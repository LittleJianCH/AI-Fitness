import type { OutputClientFunc } from 'orval';

// Haskell's UUID codec accepts canonical hex groups without restricting version
// or variant bits. Zod 4 uuid() is narrower and rejects actual Servant fixtures.
// guid() retains format validation while matching that codec. Fail on template
// drift rather than editing generated output or redefining API schemas.
export const webZodClient: OutputClientFunc = clients => ({
  ...clients.zod,
  client: async (operation, options, outputClient, output) => {
    const generated = await clients.zod.client(operation, options, outputClient, output);
    if (operation.operationName === 'getWorkouts' && !generated.implementation.includes('zod.string().uuid()')) {
      throw new Error('Pinned Web Zod UUID template changed');
    }
    return { ...generated, implementation: generated.implementation.replaceAll('zod.string().uuid()', 'zod.guid()') };
  },
});
