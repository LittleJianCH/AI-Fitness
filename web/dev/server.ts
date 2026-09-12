import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { ServerOptions } from 'vite';

export function developmentServer(env: Record<string, string | undefined>): ServerOptions {
	return {
		host: 'localhost',
		port: 5173,
		strictPort: true,
		forwardConsole: false,
		https: {
			cert: readFileSync(
				env.AI_FITNESS_TLS_CERT ??
					fileURLToPath(new URL('../.certs/localhost.pem', import.meta.url))
			),
			key: readFileSync(
				env.AI_FITNESS_TLS_KEY ??
					fileURLToPath(new URL('../.certs/localhost-key.pem', import.meta.url))
			)
		},
		proxy: {
			'/api/': {
				target: env.AI_FITNESS_API_TARGET ?? 'http://127.0.0.1:8000',
				// Preserve browser Origin and Cookie for the backend's authentication checks.
				changeOrigin: false
			}
		}
	};
}
