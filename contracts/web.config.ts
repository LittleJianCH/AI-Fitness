import { join } from 'node:path';
import { defineConfig } from 'orval';
import { webZodClient } from './web-zod-client';
import { fetchClient } from './fetch-client';

const directory = process.env.AI_FITNESS_WEB_CONTRACT_OUTPUT ?? '../web/src/lib/api/generated';

const input = {
  target: './build/openapi.json',
  override: { transformer: './web-input.cjs' },
};

export default defineConfig({
  webClient: {
    input,
    output: {
      target: join(directory, 'client.ts'),
      client: fetchClient,
      headers: true,
      mode: 'single',
      override: { fetch: { includeHttpResponseReturnType: true } },
    },
  },
  webValidation: {
    input,
    output: {
      target: join(directory, 'schemas.ts'),
      client: webZodClient,
      mode: 'single',
      override: {
        zod: {
          generateEachHttpStatus: true,
          coerce: { response: false },
          strict: { response: false },
          dateTimeOptions: { offset: true },
        },
      },
    },
  },
});
