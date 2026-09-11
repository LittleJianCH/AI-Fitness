import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { parseDocument, upgradeDocument } from './openapi.mjs';

const temporary = await mkdtemp(join(tmpdir(), 'fitness-contract-'));
try {
  const clients = [];
  for (const name of ['first', 'second']) {
    const target = join(temporary, name, 'client.ts');
    await promisify(execFile)(process.execPath, ['node_modules/orval/dist/bin/orval.js', '--config', 'orval.config.ts'],
      { env: { ...process.env, AI_FITNESS_CONTRACT_OUTPUT: target } });
    clients.push(await readFile(target, 'utf8'));
    const input = parseDocument(await readFile('../backend/build/openapi-3.0.json', 'utf8'));
    const schema = `${JSON.stringify(upgradeDocument(input), null, 2)}\n`;
    await writeFile(join(temporary, name, 'openapi.json'), schema);
    assert.equal(schema, await readFile('build/openapi.json', 'utf8'));
  }
  assert.equal(clients[0], clients[1]);
  assert.equal(clients[0], await readFile('build/client.ts', 'utf8'));
  console.log('OpenAPI and TypeScript generation matched in two clean output directories.');
} finally { await rm(temporary, { recursive: true, force: true }); }
