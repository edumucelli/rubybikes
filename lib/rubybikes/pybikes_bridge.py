#!/usr/bin/env python3
"""Private JSON-lines adapter to the maintained pybikes provider engine.

No HTTP server is exposed. Requests and provider keys arrive on stdin; provider
output is discarded and only structured results are written to stdout.
"""
import asyncio
import contextlib
import importlib.metadata
import inspect
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from email.utils import parsedate_to_datetime
from urllib.parse import urlsplit

# Several upstream parsers produce naive dates via datetime.fromtimestamp.
# Keep their interpretation independent of the Ruby host's local timezone.
os.environ['TZ'] = 'UTC'
if hasattr(time, 'tzset'):
    time.tzset()

PROTOCOL = 1
_SYSTEMS = {}
_CATALOG = None
_COOLDOWNS = {}


class Quiet:
    def write(self, text):
        return len(text)
    def flush(self):
        pass


class MissingKey(Exception):
    pass


class RateLimited(Exception):
    def __init__(self, host, retry_after):
        self.host = host
        self.retry_after = retry_after


class ResponseCache(dict):
    def __contains__(self, key):
        return key in self.keys() and time.monotonic() - dict.__getitem__(self, key)[0] < 60
    def __getitem__(self, key):
        return dict.__getitem__(self, key)[1]
    def __setitem__(self, key, value):
        now = time.monotonic()
        for expired in [k for k, (created, _) in self.items() if now - created >= 60]:
            dict.__delitem__(self, expired)
        if value.status_code < 400:
            dict.__setitem__(self, key, (now, value))


def engine_info():
    revision = None
    try:
        distribution = importlib.metadata.distribution('pybikes')
        direct = json.loads(distribution.read_text('direct_url.json') or '{}')
        revision = direct.get('vcs_info', {}).get('commit_id')
        version = distribution.version
    except importlib.metadata.PackageNotFoundError:
        version = 'unknown'
    return {'protocol': PROTOCOL, 'version': version, 'revision': revision}


def catalog():
    global _CATALOG
    if _CATALOG is None:
        import pybikes
        rows = []
        for schema in sorted(pybikes.get_schemas()):
            data = pybikes.get_data(schema)
            for class_name, params in pybikes.get_instances(schema):
                meta = dict(params['meta'])
                meta.setdefault('system', class_name)
                endpoint = params.get('feed_url') or params.get('endpoint') or ''
                rows.append({'tag': params['tag'], 'class': class_name,
                             'module': data['system'], 'label': data.get('label') or class_name,
                             'endpoint_host': urlsplit(endpoint).hostname, 'meta': meta})
        _CATALOG = sorted(rows, key=lambda row: row['tag'])
    return {'engine': engine_info(), 'networks': _CATALOG}


def system(tag, key):
    import pybikes
    from pybikes import data
    identity = (tag, json.dumps(key, sort_keys=True))
    if identity not in _SYSTEMS:
        module, class_name, _ = data.find(tag)
        cls = getattr(__import__('pybikes.' + module, fromlist=[class_name]), class_name)
        if cls.authed and not key:
            raise MissingKey()
        _SYSTEMS[identity] = pybikes.get(tag, key=key)
    return _SYSTEMS[identity]


def scraper(options):
    import requests
    from pybikes.utils import PyBikesScraper
    class BoundedSession(requests.Session):
        def request(self, *args, **kwargs):
            kwargs['timeout'] = (5, 20)
            kwargs['verify'] = True
            return super().request(*args, **kwargs)
    class VerifiedScraper(PyBikesScraper):
        def request(self, url, *args, **kwargs):
            # Own retry/deadline handling lives in the Ruby caller. Providers may
            # opt into retries or disable verification; neither overrides this.
            host = urlsplit(url).hostname
            until = max(_COOLDOWNS.get(host, 0), options.get('cooldowns', {}).get(host, 0))
            if until > time.time():
                raise RateLimited(host, until - time.time())
            self.retry = False
            self.ssl_verification = True
            self.requests_timeout = 20
            if len(args) >= 8:
                args = (*args[:7], True, *args[8:])
            else:
                kwargs['ssl_verification'] = True
            cache = self.cachedict
            # Upstream caches by URL only. Authenticated or parameterized
            # requests must not share responses under that incomplete key.
            if args or any(kwargs.get(key) for key in ('params', 'data', 'headers')) or kwargs.get('method', 'GET') != 'GET':
                self.cachedict = None
            try:
                result = super().request(url, *args, **kwargs)
            finally:
                self.cachedict = cache
            if self.last_request.status_code == 429:
                value = self.last_request.headers.get('Retry-After', '300')
                try:
                    delay = float(value)
                except ValueError:
                    try:
                        delay = parsedate_to_datetime(value).timestamp() - time.time()
                    except (TypeError, ValueError):
                        delay = 300
                delay = max(1, min(delay, 86400))
                _COOLDOWNS[host] = time.time() + delay
                raise RateLimited(host, delay)
            return result
    proxy = options.get('proxy')
    return VerifiedScraper(cachedict=ResponseCache(), headers=options.get('headers'),
                          requests_timeout=20, session=BoundedSession(), ssl_verification=True,
                          proxy_enabled=bool(proxy), proxies={'http': proxy, 'https': proxy} if proxy else {})


def update(request):
    network = system(request['tag'], request.get('key'))
    options = request.get('scraper') or {}
    transport = scraper(options)
    result = network.update(transport)
    if inspect.isawaitable(result):
        asyncio.run(result)
    # In pybikes, sync=False means station detail requests are required; it
    # does not mean that network.update is an async function.
    if not network.sync:
        def detail(station):
            station.update(scraper(options))
        with ThreadPoolExecutor(max_workers=4) as workers:
            list(workers.map(detail, network.stations))
    return network.to_dict()


def handle(request):
    operation = request.get('op')
    if operation == 'catalog':
        return catalog()
    if operation == 'describe':
        network = system(request['tag'], request.get('key'))
        return {'tag': network.tag, 'meta': network.meta, 'authed': network.authed, 'sync': network.sync}
    if operation == 'update':
        return update(request)
    if operation == 'version':
        return engine_info()
    raise ValueError('Unknown bridge operation')


def failure(error):
    from_name = type(error).__name__
    if isinstance(error, ModuleNotFoundError):
        code, message = 'dependency_missing', 'Install the pinned pybikes engine and its dependencies'
    elif isinstance(error, MissingKey):
        code, message = 'missing_key', 'This provider requires an API key'
    elif isinstance(error, RateLimited):
        return {'code': 'rate_limited', 'type': from_name, 'message': 'Provider rate limit reached',
                'host': error.host, 'retry_after': error.retry_after}
    elif from_name == 'BikeShareSystemNotFound':
        code, message = 'not_found', 'Unknown system tag'
    else:
        # Provider exceptions can contain credentials, request URLs or response
        # bodies. Return their type, never those potentially sensitive details.
        code, message = 'provider_error', 'Provider update failed (' + from_name + ')'
    return {'code': code, 'type': from_name, 'message': message}


def main():
    from datetime import datetime, timezone
    def encode(value):
        if isinstance(value, datetime):
            return (value if value.tzinfo else value.replace(tzinfo=timezone.utc)).isoformat()
        if hasattr(value, 'to_dict'):
            return value.to_dict()
        raise TypeError('Unsupported provider value')
    for line in sys.stdin:
        request = {}
        try:
            if len(line) > 2 * 1024 * 1024:
                raise ValueError('Bridge request is too large')
            request = json.loads(line)
            if not isinstance(request, dict):
                request = {}
                raise ValueError('Expected a bridge request object')
            with contextlib.redirect_stdout(Quiet()), contextlib.redirect_stderr(Quiet()):
                result = handle(request)
            response = {'protocol': PROTOCOL, 'id': request.get('id'), 'ok': True, 'result': result}
            output = json.dumps(response, default=encode, allow_nan=False)
        except Exception as error:
            output = json.dumps({'protocol': PROTOCOL, 'id': request.get('id'), 'ok': False, 'error': failure(error)})
        try:
            sys.stdout.write(output + '\n')
            sys.stdout.flush()
        except BrokenPipeError:
            return


if __name__ == '__main__':
    main()
