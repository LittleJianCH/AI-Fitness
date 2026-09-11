import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { promisify } from 'node:util';

// Keep temporary outputs in the Web package so Orval detects the same Zod major.
const generated = resolve('../web/src/lib/api/generated');
const temporary = await mkdtemp(join(generated, '.check-'));
try {
  for (const name of ['first', 'second']) {
    const directory = join(temporary, name);
    await promisify(execFile)(process.execPath, ['node_modules/orval/dist/bin/orval.js', '--config', 'web.config.ts'],
      { env: { ...process.env, AI_FITNESS_WEB_CONTRACT_OUTPUT: directory } });
    for (const file of ['client.ts', 'schemas.ts']) {
      assert.equal(await readFile(join(directory, file), 'utf8'), await readFile(join(generated, file), 'utf8'));
    }
  }
  console.log('Web client and Zod schemas matched in two clean output directories.');
} finally { await rm(temporary, { recursive: true, force: true }); }
