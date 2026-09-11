import type { OutputClientFunc } from 'orval';

// Orval 7.13's fetch renderer JSON-stringifies all non-form bodies and JSON-parses
// every response, and object-spreads HeadersInit. Adapt these branches at
// generation time; keep its types, parameters and URL generation. Fail loudly
// if an upgrade changes the template.
export const fetchClient: OutputClientFunc = clients => ({
  ...clients.fetch,
  client: async (operation, options, outputClient, output) => {
    const generated = await clients.fetch.client(operation, options, outputClient, output);
    let implementation = generated.implementation;
    if (/headers:\s*\{/.test(implementation)) {
      implementation = replaceOnce(implementation,
        /headers: \{ ([^\n]*?)\.\.\.options\?\.headers \}/,
        `headers: (() => {
      const merged = new Headers({ $1 });
      new Headers(options?.headers).forEach((value, name) => merged.set(name, value));
      return merged;
    })()`);
    }
    if (operation.body.contentType === 'application/octet-stream') {
      implementation = replaceOnce(implementation, /body: JSON\.stringify\(([\s\S]*?)\)/, 'body: $1');
    }
    if (operation.response.types.success.some(response => response.contentType === 'application/octet-stream')) {
      implementation = replaceOnce(implementation,
        /const body = \[204, 205, 304\].includes\(res.status\) \? null : await res.text\(\);/,
        "const body = res.ok ? await res.blob() : await res.text();");
      implementation = replaceOnce(implementation, /body \? JSON.parse\(body\) : \{\}/,
        "body instanceof Blob ? body : JSON.parse(body)");
    }
    return { ...generated, implementation };
  },
});

function replaceOnce(source: string, pattern: RegExp, replacement: string): string {
  if ([...source.matchAll(new RegExp(pattern, 'g'))].length !== 1) {
    throw new Error(`Pinned Orval fetch template changed: ${pattern}`);
  }
  return source.replace(pattern, replacement);
}
