import { svelte } from '@sveltejs/vite-plugin-svelte';
import { defineConfig } from 'vitest/config';
import { fileURLToPath } from 'node:url';
export default defineConfig({
	plugins: [svelte()],
	ssr: { noExternal: ['@tanstack/svelte-query'] },
	resolve: { alias: { $lib: fileURLToPath(new URL('./src/lib', import.meta.url)) } },
	test: { include: ['tests/**/*.test.ts'], environment: 'node' }
});
