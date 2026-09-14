import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import SwaggerParser from '@apidevtools/swagger-parser';
import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import { parseDocument, upgradeDocument, upgradeSchema } from './openapi.mjs';
import { getWorkouts, postImportsFit, getWorkoutsWorkoutIdExportsFit, postAuthWebLogin } from './build/javascript/build/client.js';
import { cadence, listResult, revision } from './build/javascript/consumer.js';

const readJSON = async path => JSON.parse(await readFile(path, 'utf8'));
const document = await readJSON('build/openapi.json');
await SwaggerParser.validate(structuredClone(document));
const schemas = document.components.schemas;
const ajv = new Ajv2020({ allErrors: true, strict: false });
addFormats(ajv);
for (const format of ['double', 'float', 'int32', 'int64']) {
  ajv.addFormat(format, { type: 'number', validate: Number.isFinite });
}
ajv.addFormat('binary', true);
const validate = (name, value) => {
  const check = ajv.compile({ components: { schemas }, $ref: `#/components/schemas/${name}` });
  assert.ok(check(value), `${name}: ${ajv.errorsText(check.errors)}`);
  return check;
};
const page = await readJSON('../backend/build/list-response.json');
const workout = await readJSON('../backend/build/workout-response.json');
const problem = await readJSON('../backend/build/error-response.json');
const bundle = await readJSON('../backend/build/export-response.json');
validate('Page_WorkoutCard', page);
const workoutCheck = validate('Workout', workout);
validate('Problem', problem);
validate('PowerCurve', await readJSON('../backend/build/power-curve-response.json'));
validate('CanonicalExport', bundle);
validate('Platform', 'appleHealth');
assert.equal(bundle.version, 'canonicalV1');
assert.equal(revision(workout), 9007199254740993n);
assert.deepEqual(bundle.workouts.map(w => w.workoutObservation.observationSport.type), ['cycling', 'running']);
for (const item of bundle.workouts) assert.ok(cadence(item.workoutObservation.observationSport).length > 0);
assert.ok(!('workoutNotes' in workout.workoutUserData));
assert.ok(!workoutCheck({ ...workout, workoutRevision: 9007199254740992 }));
assert.ok(!workoutCheck({ ...workout, workoutRevision: '01' }));
assert.ok(!workoutCheck({ ...workout, workoutUserData: { ...workout.workoutUserData, workoutNotes: null } }));
assert.ok(!workoutCheck({ ...workout, workoutObservation: { ...workout.workoutObservation,
  observationSport: { type: 'swimming', data: {} } } }));
assert.ok(!workoutCheck({ ...workout, workoutObservation: { ...workout.workoutObservation,
  observationRange: { rangeStart: 'yesterday', rangeEnd: 'tomorrow' } } }));

// Exercise the generated fetch function with bytes emitted by the real Servant
// fixture router. This is a transport stub, not an authentication/server test.
const originalFetch = globalThis.fetch;
try {
  const headerValues = { authorization: 'Bearer synthetic-token', 'x-csrf-token': 'override-csrf' };
  for (const headers of [headerValues, new Headers(headerValues), Object.entries(headerValues)]) {
    globalThis.fetch = async (url, options) => {
      assert.equal(url, '/api/v1/workouts');
      const sent = new Headers(options.headers);
      assert.equal(sent.get('Authorization'), headerValues.authorization);
      assert.equal(sent.get('X-CSRF-Token'), 'override-csrf');
      return new Response(JSON.stringify(page), { status: 200 });
    };
    await getWorkouts(undefined, { 'X-CSRF-Token': 'route-csrf' }, { headers });

    globalThis.fetch = async (url, options) => {
      assert.equal(url, '/api/v1/auth/web/login');
      const sent = new Headers(options.headers);
      assert.equal(sent.get('Authorization'), headerValues.authorization);
      assert.equal(sent.get('X-CSRF-Token'), 'override-csrf');
      assert.equal(sent.get('Content-Type'), 'application/json;charset=utf-8');
      return new Response(JSON.stringify(problem), { status: 403 });
    };
    await postAuthWebLogin({ username: 'fixture', password: 'not-a-real-credential' },
      { 'X-CSRF-Token': 'route-csrf' }, { headers });
  }
  globalThis.fetch = async (url, options) => {
    assert.equal(new Headers(options.headers).get('Content-Type'), 'application/json');
    return new Response(JSON.stringify(problem), { status: 403 });
  };
  await postAuthWebLogin({ username: 'fixture', password: 'not-a-real-credential' },
    { 'X-CSRF-Token': 'synthetic-csrf' }, { headers: new Headers({ 'content-type': 'application/json' }) });

  for (const [status, body] of [[200, page], [400, problem]]) {
    globalThis.fetch = async (url, options) => {
      assert.equal(url, '/api/v1/workouts?limit=50');
      assert.equal(options.method, 'GET');
      return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
    };
    const response = await getWorkouts({ limit: 50 });
    assert.equal(response.status, status);
    assert.equal(listResult(response), status === 400 ? 'invalid_query' : page.items.map(i => i.userData.workoutTitle ?? i.id).join(', '));
  }
  const bytes = new Uint8Array([0, 255, 1, 128, 70, 73, 84]);
  const file = new Blob([bytes], { type: 'application/octet-stream' });
  globalThis.fetch = async (url, options) => {
    assert.equal(url, '/api/v1/imports/fit');
    assert.equal(new Headers(options.headers).get('Content-Type'), 'application/octet-stream');
    assert.ok(options.body instanceof Blob);
    assert.deepEqual(new Uint8Array(await options.body.arrayBuffer()), bytes);
    return new Response(JSON.stringify(problem), { status: 422 });
  };
  assert.equal((await postImportsFit(file)).status, 422);
  for (const status of [200, 404]) {
    globalThis.fetch = async url => {
      assert.equal(url, `/api/v1/workouts/${workout.workoutId}/exports/fit`);
      return new Response(status === 200 ? file : JSON.stringify(problem), { status,
        headers: { 'Content-Type': status === 200 ? 'application/octet-stream' : 'application/json' } });
    };
    const response = await getWorkoutsWorkoutIdExportsFit(workout.workoutId);
    if (response.status === 200) assert.deepEqual(new Uint8Array(await response.data.arrayBuffer()), bytes);
    else assert.equal(response.data.code, problem.code);
  }
  globalThis.fetch = async (url, options) => {
    assert.equal(url, '/api/v1/auth/web/login');
    assert.equal(new Headers(options.headers).get('X-CSRF-Token'), 'synthetic-csrf');
    return new Response(JSON.stringify(problem), { status: 403 });
  };
  assert.equal((await postAuthWebLogin({ username: 'fixture', password: 'not-a-real-credential' },
    { 'X-CSRF-Token': 'synthetic-csrf' })).status, 403);
} finally { globalThis.fetch = originalFetch; }

const operations = Object.values(document.paths).flatMap(path => Object.entries(path)
  .filter(([method]) => ['get', 'post', 'put', 'patch', 'delete'].includes(method)).map(([, operation]) => operation));
assert.equal(new Set(operations.map(operation => operation.operationId)).size, operations.length);
const login = document.paths['/api/v1/auth/web/login'].post;
assert.deepEqual(Object.keys(login.responses['200'].headers).sort(), ['Cache-Control', 'Set-Cookie']);
assert.ok(login.parameters.find(p => p.name === 'X-CSRF-Token')?.required);
for (const [path, item] of Object.entries(document.paths)) {
  for (const operation of Object.values(item)) {
    if (!operation.operationId) continue;
    const isPublic = ['/auth/policy', '/auth/web/csrf', '/auth/web/login', '/auth/native/login', '/auth/register']
      .some(suffix => path === `/api/v1${suffix}`);
    if (isPublic) assert.ok(!operation.security?.length);
    else assert.deepEqual(operation.security, [{ sessionCookie: [] }, { sessionBearer: [] }]);
    if (operation.responses['204']) assert.ok(!operation.responses['204'].content);
    if (operation.responses['429']) assert.equal(operation.responses['429'].headers['Retry-After'].schema.type, 'integer');
    assert.equal(operation.responses.default.content['application/json'].schema.$ref, '#/components/schemas/Problem');
  }
}
assert.equal(document.components.securitySchemes.sessionCookie.name, '__Host-ai-fitness-session');
assert.equal(document.components.securitySchemes.sessionBearer.scheme, 'bearer');

// Regression cases for the explicit 3.0 -> 3.1 compatibility bridge.
assert.deepEqual(upgradeSchema({ type: 'number', minimum: 1, exclusiveMinimum: true, maximum: 9, exclusiveMaximum: false }),
  { type: 'number', exclusiveMinimum: 1, maximum: 9 });
assert.deepEqual(upgradeSchema({ type: 'string', nullable: true, enum: ['x'] }), { type: ['string', 'null'], enum: ['x'] });
assert.throws(() => upgradeSchema({ nullable: true }), /explicit type/);
assert.throws(() => upgradeSchema({ items: [{ type: 'string' }] }), /Tuple schemas/);
const example = { nullable: true, exclusiveMinimum: true, schema: { type: 'string' } };
assert.deepEqual(upgradeSchema({ type: 'object', properties: { nullable: { type: 'boolean' } }, example }).example, example);
assert.equal(upgradeSchema({ type: 'string', format: 'yyyy-mm-ddThh:MM:ssZ' }).format, 'date-time');
assert.equal(JSON.stringify(parseDocument('{"minimum":-9223372036854775808,"maximum":9223372036854775807}')),
  '{"minimum":-9223372036854775808,"maximum":9223372036854775807}');
assert.throws(() => upgradeDocument({ openapi: '3.1.0' }), /3.0 output/);
console.log(`OpenAPI validation, Servant payloads, generated TypeScript fetch and ${operations.length} operation contracts passed.`);
