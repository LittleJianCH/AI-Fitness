import { spawn, type ChildProcess } from 'node:child_process';
import { setTimeout } from 'node:timers/promises';
import { test as base } from '@playwright/test';

// A fresh runtime per test isolates process-local rate windows while the private
// PostgreSQL cluster survives restarts. No rate-limit relaxation in product code.
export const test = base.extend<{
	restartBackend: (options?: { registrationOpen?: boolean }) => Promise<void>;
}>({
	restartBackend: [
		// Playwright requires a destructured fixture argument even without dependencies.
		// eslint-disable-next-line no-empty-pattern
		async ({}, use) => {
			if (
				!process.env.AI_FITNESS_WEB_TEST_DATABASE_URL ||
				process.env.DATABASE_URL !== process.env.AI_FITNESS_WEB_TEST_DATABASE_URL ||
				!process.env.DATABASE_URL.startsWith('host=/tmp/ai-fitness-web.')
			)
				throw new Error('Run connected tests through scripts/web_integration_test');
			let backend: ChildProcess | undefined;
			let registrationOpen = process.env.REGISTRATION_OPEN ?? 'true';
			const stop = async () => {
				if (!backend || backend.exitCode !== null || backend.signalCode !== null) return;
				const processToStop = backend;
				const closed = new Promise<void>((resolve) => processToStop.once('exit', () => resolve()));
				processToStop.kill('SIGTERM');
				const timer = globalThis.setTimeout(() => processToStop.kill('SIGKILL'), 3000);
				await closed;
				clearTimeout(timer);
			};
			const start = async () => {
				backend = spawn('./build/backend', [], {
					cwd: '../backend',
					env: { ...process.env, REGISTRATION_OPEN: registrationOpen },
					stdio: 'ignore'
				});
				let spawnError: Error | undefined;
				backend.on('error', (error) => {
					spawnError = error;
				});
				for (let attempt = 0; attempt < 100; attempt++) {
					if (spawnError || backend.exitCode !== null)
						throw new Error('Isolated test backend failed to start');
					try {
						const response = await fetch('http://127.0.0.1:8181/api/v1/hello', {
							signal: AbortSignal.timeout(200)
						});
						if (response.ok) {
							await response.text();
							return;
						}
					} catch {
						/* Wait for this process to bind the loopback listener. */
					}
					await setTimeout(100);
				}
				throw new Error('Isolated test backend did not become ready');
			};
			const onExit = () => backend?.kill('SIGTERM');
			process.once('exit', onExit);
			try {
				await start();
				await use(async (options) => {
					if (options?.registrationOpen !== undefined)
						registrationOpen = String(options.registrationOpen);
					await stop();
					await start();
				});
			} finally {
				await stop();
				process.off('exit', onExit);
			}
		},
		{ auto: true }
	]
});
