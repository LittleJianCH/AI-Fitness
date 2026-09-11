import { defineConfig } from 'orval';
import { fetchClient } from './fetch-client';

export default defineConfig({
  fitness: {
    input: './build/openapi.json',
    output: {
      target: process.env.AI_FITNESS_CONTRACT_OUTPUT ?? './build/client.ts',
      client: fetchClient,
      headers: true,
      mode: 'single',
      override: { fetch: { includeHttpResponseReturnType: true } },
    },
  },
});
