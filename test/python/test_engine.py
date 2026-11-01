import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import pybikes
import requests

BRIDGE = Path(__file__).parents[2] / 'lib/rubybikes/pybikes_bridge.py'
spec = importlib.util.spec_from_file_location('bridge', BRIDGE)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class EngineConformanceTest(unittest.TestCase):
    def setUp(self):
        bridge._SYSTEMS.clear()
        bridge._COOLDOWNS.clear()

    def test_catalog_is_the_upstream_catalog(self):
        expected = sorted(params['tag'] for _, params in pybikes.get_instances())
        self.assertEqual(expected, [row['tag'] for row in bridge.catalog()['networks']])

    def test_real_gbfs_parser_preserves_upstream_hash_and_fields(self):
        feeds = {'data': {'en': {'feeds': [
            {'name': name, 'url': 'https://example.org/' + name + '.json'}
            for name in ['station_information', 'station_status', 'free_bike_status']
        ]}}}
        info = {'data': {'stations': [{'station_id': '123', 'stationCode': '456',
            'name': 'École', 'lat': -22.1234567, 'lon': -43.1234567, 'capacity': 12}]}}
        status = {'data': {'stations': [{'station_id': '123', 'is_installed': 1,
            'is_renting': 0, 'is_returning': 1, 'num_bikes_available': 3,
            'num_docks_available': 9, 'last_reported': 1793550000}]}}
        vehicles = {'data': {'bikes': [{'bike_id': 'bike-1', 'lat': -22.1, 'lon': -43.1,
                                       'is_reserved': False, 'is_disabled': False}]}}
        def request(_session, method, url, **kwargs):
            self.assertTrue(kwargs['verify'])
            self.assertEqual((5, 20), kwargs['timeout'])
            if url.endswith('station_information.json'):
                payload = info
            elif url.endswith('station_status.json'):
                payload = status
            elif url.endswith('free_bike_status.json'):
                payload = vehicles
            else:
                payload = feeds
            response = requests.Response()
            response.status_code = 200
            response._content = json.dumps(payload).encode()
            response.headers['Content-Type'] = 'application/json'
            return response
        with patch.object(requests.Session, 'request', request):
            row = bridge.update({'tag': 'velib'})
        station = row['stations'][0]
        expected = hashlib.md5(b'-22123456,-43123456').hexdigest()
        self.assertEqual(expected, station['id'])
        self.assertEqual(3, station['bikes'])
        self.assertEqual(9, station['free'])
        self.assertEqual('456', station['extra']['uid'])
        self.assertEqual(0, station['extra']['renting'])
        self.assertTrue(station['extra']['last_updated'])
        self.assertEqual('bike', row['vehicles'][0]['kind'])

    def test_rate_limit_precedes_provider_json_parsing_and_never_caches_error(self):
        response = requests.Response()
        response.status_code = 429
        response._content = b'not json'
        response.headers['Retry-After'] = '120'
        with patch.object(requests.Session, 'request', return_value=response):
            with self.assertRaises(bridge.RateLimited) as error:
                bridge.update({'tag': 'velib'})
        self.assertEqual(120, error.exception.retry_after)
        self.assertFalse(bridge.scraper({}).cachedict)

    def test_provider_timeout_override_remains_bounded(self):
        response = requests.Response()
        response.status_code = 200
        response._content = b'{}'
        transport = bridge.scraper({})
        transport.requests_timeout = max(transport.requests_timeout, 600)
        with patch.object(requests.Session, 'request', return_value=response) as request:
            transport.request('https://example.org/feed', ssl_verification=False)
        self.assertEqual((5, 20), request.call_args.kwargs['timeout'])
        self.assertTrue(request.call_args.kwargs['verify'])

    def test_persisted_host_cooldown_prevents_requests(self):
        with patch.object(requests.Session, 'request') as request:
            with self.assertRaises(bridge.RateLimited):
                bridge.scraper({'cooldowns': {'example.org': 9999999999}}).request('https://example.org/feed')
        request.assert_not_called()

    def test_secrets_and_provider_output_are_not_returned(self):
        failure = bridge.failure(ValueError('https://provider/?key=private-secret'))
        self.assertNotIn('private-secret', json.dumps(failure))
        output = io.StringIO()
        def noisy(_request):
            print('private-secret')
            return {'test': 1}
        with patch.object(bridge, 'handle', noisy), patch('sys.stdin', io.StringIO('{"id":1,"op":"version"}\n')), contextlib.redirect_stdout(output):
            bridge.main()
        self.assertNotIn('private-secret', output.getvalue())
        self.assertEqual({'test': 1}, json.loads(output.getvalue())['result'])

    def test_station_detail_providers_are_updated(self):
        class Station:
            def update(self, scraper):
                self.updated = True
        class Network:
            sync = False
            stations = [Station(), Station()]
            def update(self, scraper):
                pass
            def to_dict(self):
                return {'updated': all(station.updated for station in self.stations)}
        with patch.object(bridge, 'system', return_value=Network()):
            self.assertEqual({'updated': True}, bridge.update({'tag': 'test'}))

if __name__ == '__main__':
    unittest.main()
