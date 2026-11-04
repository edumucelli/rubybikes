import contextlib
import copy
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

    def test_all_schema_clients_and_uncatalogued_clients_are_available(self):
        clients = {(row['module'], row['class']): row for row in bridge.providers()['providers']}
        for schema in pybikes.get_schemas():
            data = pybikes.get_data(schema)
            names = data['class'] if isinstance(data['class'], dict) else [data['class']]
            for name in names:
                with self.subTest(schema=schema, client=name):
                    entry = clients[(data['system'], name)]
                    expected = sorted(params['tag'] for cls, params in pybikes.get_instances(schema) if cls == name)
                    self.assertEqual(expected, entry['tags'])
        for identity in [('keolis', 'KeolisIlevia'), ('keolis', 'VCub'), ('otp', 'OTP'),
                         ('nextbike_gbfs', 'NextbikeGbfs')]:
            self.assertEqual([], clients[identity]['tags'])

    def test_every_client_can_be_constructed_with_upstream_parameters(self):
        examples = {}
        for schema in pybikes.get_schemas():
            module = pybikes.get_data(schema)['system']
            for cls, params in pybikes.get_instances(schema):
                examples.setdefault((module, cls), params)
        meta = {'name': 'Fixture', 'system': 'Fixture'}
        examples.update({
            ('nextbike_gbfs', 'NextbikeGbfs'): {'meta': meta, 'domain': 'bs'},
            ('keolis', 'KeolisIlevia'): {'meta': meta, 'dataset': 'fixture'},
            ('keolis', 'VCub'): {'meta': meta, 'feed_url': 'https://example.org/feed'},
            ('otp', 'OTP'): {'meta': meta, 'feed_url': 'https://example.org/feed'},
        })
        keys = {
            'bicimad': {'clientid': 'fixture', 'passkey': 'fixture'},
            'deutschebahn': {'client_id': 'fixture', 'client_secret': 'fixture'},
            'weelo': {'client_id': 'fixture', 'client_secret': 'fixture'},
        }
        for entry in bridge.providers()['providers']:
            with self.subTest(module=entry['module'], client=entry['class']):
                params = copy.deepcopy(examples[(entry['module'], entry['class'])])
                tag = params.pop('tag', 'custom-' + entry['class'])
                definition = {'module': entry['module'], 'class': entry['class'], 'parameters': params}
                key = keys.get(entry['module'], 'fixture-token-1234567890')
                network = bridge.system(tag, key, definition)
                self.assertEqual(tag, network.tag)
                self.assertEqual(entry['class'], type(network).__name__)
                self.assertEqual(entry['authed'], network.authed)
                self.assertEqual(entry['sync'], network.sync)
                self.assertEqual(entry['unifeed'], network.unifeed)

    def test_custom_definitions_cannot_import_non_provider_classes(self):
        with self.assertRaises(ValueError):
            bridge.system('custom', None, {'module': 'base', 'class': 'BikeShareSystem', 'parameters': {}})

    def test_real_nextbike_xml_parser_preserves_stations_and_vehicles(self):
        xml = b'''<markers><country><city uid="1">
            <place uid="station-1" name="Station" lat="48.85" lng="2.35"
                   spot="1" bikes="5+" bike_racks="12" free_racks="6" />
            <place uid="vehicle-1" lat="48.86" lng="2.36" bike="1">
                <bike number="bike-1" active="1" />
            </place>
        </city></country></markers>'''
        response = requests.Response()
        response.status_code = 200
        response._content = xml
        definition = {'module': 'nextbike', 'class': 'Nextbike',
                      'parameters': {'meta': {'name': 'Fixture'}, 'domain': 'fixture'}}
        with patch.object(requests.Session, 'request', return_value=response):
            row = bridge.update({'tag': 'custom-nextbike', 'definition': definition})
        self.assertEqual(5, row['stations'][0]['bikes'])
        self.assertEqual(6, row['stations'][0]['free'])
        self.assertTrue(row['stations'][0]['extra']['bikes_approximate'])
        self.assertEqual('bike-1', row['vehicles'][0]['extra']['uid'])

    def test_real_bicimad_authentication_and_structured_keys(self):
        from pybikes.bicimad import AUTH_URL, FEED_URL
        calls = []
        def request(session, method, url, **kwargs):
            calls.append(url)
            response = requests.Response()
            response.status_code = 200
            if url == AUTH_URL:
                self.assertEqual('fixture-pass', kwargs['headers']['passkey'])
                self.assertEqual('fixture-client', kwargs['headers']['x-clientid'])
                payload = {'data': [{'accessToken': 'fixture-token'}]}
            elif 'accesstoken' not in kwargs['headers']:
                response.status_code = 401
                payload = {}
            else:
                self.assertEqual('fixture-token', kwargs['headers']['accesstoken'])
                payload = {'data': [{'id': 1, 'name': 'Madrid', 'number': '001',
                    'geometry': {'coordinates': [-3.7, 40.4]}, 'dock_bikes': 3,
                    'free_bases': 9, 'address': 'Address', 'activate': 1,
                    'no_available': 0, 'total_bases': 12, 'light': 0}]}
            response._content = json.dumps(payload).encode()
            return response
        with patch.object(requests.Session, 'request', request):
            row = bridge.update({'tag': 'bicimad', 'key': {'clientid': 'fixture-client', 'passkey': 'fixture-pass'}})
        self.assertEqual([FEED_URL, AUTH_URL, FEED_URL], calls)
        self.assertEqual(3, row['stations'][0]['bikes'])
        self.assertTrue(row['stations'][0]['extra']['online'])

    def test_real_fsm_station_details_are_included_in_snapshot(self):
        from pybikes.fsm import STATIONS_URL
        def request(session, method, url, **kwargs):
            if url == STATIONS_URL:
                payload = {'stations': [{'name': 'Tel Aviv', 'id': '1', 'stationNumber': '01',
                    'location': {'lat': 32.08, 'lng': 34.78}, 'novatechBikes': 3,
                    'omniBikes': 2, 'isShabbatStation': True}]}
            else:
                self.assertTrue(url.endswith('/station/1'))
                payload = {'availableOmniPoles': 4, 'availableNovatechPoles': 5, 'address': 'Address'}
            response = requests.Response()
            response.status_code = 200
            response._content = json.dumps(payload).encode()
            return response
        definition = {'module': 'fsm', 'class': 'FSMSystem', 'parameters': {'meta': {'name': 'Fixture'}}}
        with patch.object(requests.Session, 'request', request):
            row = bridge.update({'tag': 'custom-fsm', 'definition': definition})
        self.assertEqual(5, row['stations'][0]['bikes'])
        self.assertEqual(9, row['stations'][0]['free'])
        self.assertEqual('Address', row['stations'][0]['extra']['address'])

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
