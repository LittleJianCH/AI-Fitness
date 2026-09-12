import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { createServer as httpServer } from 'node:http';
import { request } from 'node:https';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'vite';
import { expect, it } from 'vitest';
import { developmentServer } from '../dev/server';

it('preserves browser credentials, Origin and secure cookies through the HTTPS proxy', async () => {
	const temporary = mkdtempSync(join(tmpdir(), 'fitness-web-tls-'));
	const cert = join(temporary, 'cert.pem');
	const key = join(temporary, 'key.pem');
	execFileSync(
		'openssl',
		[
			'req',
			'-x509',
			'-newkey',
			'rsa:2048',
			'-nodes',
			'-days',
			'1',
			'-subj',
			'/CN=localhost',
			'-keyout',
			key,
			'-out',
			cert
		],
		{ stdio: 'ignore' }
	);
	const received: { origin?: string; cookie?: string; csrf?: string | string[]; url?: string } = {};
	const backend = httpServer((req, res) => {
		received.origin = req.headers.origin;
		received.cookie = req.headers.cookie;
		received.csrf = req.headers['x-csrf-token'];
		received.url = req.url;
		res.setHeader(
			'Set-Cookie',
			'__Host-ai-fitness-session=synthetic; Secure; HttpOnly; SameSite=Lax; Path=/'
		);
		res.setHeader('Cache-Control', 'no-store');
		res.end('{}');
	});
	await new Promise<void>((resolve) => backend.listen(0, '127.0.0.1', resolve));
	const address = backend.address();
	if (!address || typeof address === 'string') throw new Error('Missing test backend address');
	const vite = await createServer({
		configFile: false,
		appType: 'custom',
		server: {
			...developmentServer({
				AI_FITNESS_TLS_CERT: cert,
				AI_FITNESS_TLS_KEY: key,
				AI_FITNESS_API_TARGET: `http://127.0.0.1:${address.port}`
			}),
			port: 0
		}
	});
	try {
		await vite.listen();
		const proxyAddress = vite.httpServer?.address();
		if (!proxyAddress || typeof proxyAddress === 'string')
			throw new Error('Missing test proxy address');
		const origin = `https://localhost:${proxyAddress.port}`;
		const headers = await new Promise<import('node:http').IncomingHttpHeaders>(
			(resolve, reject) => {
				const req = request(
					`${origin}/api/v1/auth/web/login`,
					{
						method: 'POST',
						rejectUnauthorized: false,
						headers: {
							Origin: origin,
							Cookie: '__Host-ai-fitness-session=synthetic',
							'X-CSRF-Token': 'synthetic-csrf'
						}
					},
					(res) => {
						res.resume();
						res.on('end', () => resolve(res.headers));
					}
				);
				req.on('error', reject);
				req.end();
			}
		);
		expect(received).toEqual({
			origin,
			cookie: '__Host-ai-fitness-session=synthetic',
			csrf: 'synthetic-csrf',
			url: '/api/v1/auth/web/login'
		});
		expect(headers['set-cookie']).toEqual([
			'__Host-ai-fitness-session=synthetic; Secure; HttpOnly; SameSite=Lax; Path=/'
		]);
		expect(headers['cache-control']).toBe('no-store');
	} finally {
		await vite.close();
		await new Promise<void>((resolve, reject) =>
			backend.close((error) => (error ? reject(error) : resolve()))
		);
		rmSync(temporary, { recursive: true, force: true });
	}
});
