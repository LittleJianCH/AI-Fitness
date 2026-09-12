"""Provision only the disposable account owned by ios_integration_test."""
import http.cookies
import json
import os
from pathlib import Path
import time
import urllib.error
import urllib.request
import uuid

base = f"http://127.0.0.1:{int(os.environ['PORT'])}/api/v1"
for attempt in range(100):
    try:
        with urllib.request.urlopen(base + '/hello', timeout=1) as response:
            if response.status == 200:
                break
    except (OSError, urllib.error.URLError):
        time.sleep(0.1)
else:
    raise SystemExit('Temporary API did not start')

with urllib.request.urlopen(base + '/auth/web/csrf', timeout=5) as response:
    csrf = json.load(response)['csrfToken']
    cookie = http.cookies.SimpleCookie()
    cookie.load(response.headers['Set-Cookie'])
    cookie_header = '; '.join(f'{key}={morsel.value}' for key, morsel in cookie.items())

request = urllib.request.Request(
    base + '/auth/register',
    data=json.dumps({'username': 'ios_fixture_user', 'password': 'synthetic ios fixture password'}).encode(),
    headers={'Content-Type': 'application/json', 'Origin': 'https://localhost:5173',
             'Cookie': cookie_header, 'X-CSRF-Token': csrf},
    method='POST',
)
with urllib.request.urlopen(request, timeout=10) as response:
    assert response.status == 201
request = urllib.request.Request(
    base + '/auth/native/login',
    data=json.dumps({'username': 'ios_fixture_user', 'password': 'synthetic ios fixture password',
                     'deviceName': 'Fixture setup'}).encode(),
    headers={'Content-Type': 'application/json'}, method='POST',
)
with urllib.request.urlopen(request, timeout=10) as response:
    token = json.load(response)['token']
with (Path(__file__).resolve().parent.parent / 'backend/build/export-response.json').open() as source:
    workouts = json.load(source)['workouts']
for workout in workouts:
    sport = workout['workoutObservation']['observationSport']['type']
    workout['workoutUserData']['workoutTitle'] = 'Synthetic ' + sport
    request = urllib.request.Request(
        base + '/workouts',
        data=json.dumps({'submissionId': str(uuid.uuid4()), 'observation': workout['workoutObservation'],
                         'userData': workout['workoutUserData']}).encode(),
        headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token}, method='POST',
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        assert response.status == 200
request = urllib.request.Request(base + '/auth/logout',
                                 headers={'Authorization': 'Bearer ' + token}, method='POST')
with urllib.request.urlopen(request, timeout=10) as response:
    assert response.status == 204
print('Disposable iOS account and synthetic cycling/running fixtures created.')
