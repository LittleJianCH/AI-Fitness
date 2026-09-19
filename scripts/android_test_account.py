#!/usr/bin/env python3
"""Provision synthetic data only for android_integration_test's disposable cluster."""
import copy
import http.cookies
import json
import os
from pathlib import Path
import time
import urllib.request
import uuid
from datetime import datetime, timedelta

assert os.environ.get('AI_FITNESS_ANDROID_DISPOSABLE') == '1', 'Use android_integration_test'
base = 'http://127.0.0.1:' + str(int(os.environ['PORT'])) + '/api/v1'
for _ in range(150):
    try:
        with urllib.request.urlopen(base + '/hello', timeout=1) as response:
            if response.status == 200: break
    except OSError:
        time.sleep(.1)
else: raise SystemExit('Disposable backend did not start')

with urllib.request.urlopen(base + '/auth/web/csrf', timeout=5) as response:
    csrf = json.load(response)['csrfToken']
    cookies = http.cookies.SimpleCookie(response.headers['Set-Cookie'])
    cookie = '; '.join(f'{name}={item.value}' for name, item in cookies.items())

def request(method, path, body=None, token=None, headers=None):
    headers = dict(headers or {})
    if body is not None: headers['Content-Type'] = 'application/json'
    if token: headers['Authorization'] = 'Bearer ' + token
    req = urllib.request.Request(base + path, data=json.dumps(body).encode() if body is not None else None, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=20) as response:
        return None if response.status == 204 else json.load(response)

username = 'android_fixture_user'
password = 'synthetic android fixture password'
request('POST', '/auth/register', {'username': username, 'password': password}, headers={
    'Origin': os.environ['APP_ORIGIN'], 'Cookie': cookie, 'X-CSRF-Token': csrf,
})
token = request('POST', '/auth/native/login', {'username': username, 'password': password, 'deviceName': 'Android fixture provisioner'})['token']
root = Path(__file__).resolve().parent.parent
fixtures = json.loads((root / 'backend/build/export-response.json').read_text())['workouts']
for index in range(23):
    workout = copy.deepcopy(fixtures[index % 2])
    observation = workout['workoutObservation']
    sport = observation['observationSport']['type']
    # Retain the canonical synthetic record; add coherent dense sensor streams
    # inside its recorded range without importing personal HealthFit observations.
    start = datetime.fromisoformat(observation['observationRange']['rangeStart'].replace('Z', '+00:00'))
    data = observation['observationSport']['data']
    motion = data[sport + 'Motion']
    def samples(value):
        return [{'timestamp': (start + timedelta(seconds=s)).isoformat(), 'value': value(s)} for s in range(301)]
    motion['motionPower'] = samples(lambda s: 200 + s % 40)
    motion['motionHeartRate'] = samples(lambda s: 120 + s % 20)
    motion['motionSpeed'] = samples(lambda s: 5 + (s % 10) / 10)
    motion['motionDistance'] = samples(lambda s: s * 5)
    motion['motionAltitude'] = samples(lambda s: 50 + s / 100)
    motion['motionGrade'] = samples(lambda s: 1 + (s % 3))
    motion['motionEnvironment']['ambientTemperature'] = samples(lambda s: 22 + s / 100)
    motion['motionPosition'] = samples(lambda s: {'latitude': 30 + s / 100000, 'longitude': 120 + s / 100000})
    data[sport + 'Cadence'] = samples(lambda s: 160 + s % 10 if sport == 'running' else 80 + s % 5)
    if sport == 'running':
        data['runningDynamics'] = {'stepLength': samples(lambda s: 1.1), 'verticalOscillation': samples(lambda s: .08), 'groundContactTime': samples(lambda s: .25)}
    workout['workoutUserData']['statisticsInclusion'] = 'includeInStatistics'
    workout['workoutUserData']['workoutTitle'] = f'Android synthetic {sport} {index:02}'
    request('POST', '/workouts', {'submissionId': str(uuid.uuid4()), 'observation': observation, 'userData': workout['workoutUserData']}, token)
request('POST', '/auth/logout', token=token)
print('Created disposable Android account and 23 synthetic workouts.')
