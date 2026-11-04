"""Offline operator responses for Ruby-to-real-PyBikes integration tests."""
import importlib.util
import json
from pathlib import Path
from unittest.mock import patch

import requests

source = Path(__file__).parents[2] / 'lib/rubybikes/pybikes_bridge.py'
spec = importlib.util.spec_from_file_location('bridge', source)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


def request(session, method, url, **kwargs):
    if url.endswith('station_information.json'):
        payload = {'data': {'stations': [{'station_id': '1', 'name': 'Fixture Station',
                                        'lat': 48.85, 'lon': 2.35, 'capacity': 12}]}}
    elif url.endswith('station_status.json'):
        payload = {'data': {'stations': [{'station_id': '1', 'num_bikes_available': 3,
                                        'num_docks_available': 9, 'is_installed': 1,
                                        'is_renting': 1, 'is_returning': 1}]}}
    elif url.endswith('free_bike_status.json'):
        payload = {'data': {'bikes': [{'bike_id': 'bike-1', 'lat': 48.86, 'lon': 2.36,
                                     'is_reserved': False, 'is_disabled': False}]}}
    else:
        payload = {'data': {'en': {'feeds': [
            {'name': name, 'url': 'https://example.org/' + name + '.json'}
            for name in ('station_information', 'station_status', 'free_bike_status')
        ]}}}
    response = requests.Response()
    response.status_code = 200
    response._content = json.dumps(payload).encode()
    response.headers['Content-Type'] = 'application/json'
    return response


if __name__ == '__main__':
    with patch.object(requests.Session, 'request', request):
        bridge.main()
