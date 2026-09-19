import { afterEach, expect, it, vi } from 'vitest';
import { QueryClient } from '@tanstack/svelte-query';
import { loadSettings, saveSettings, settingsKey } from '../src/lib/settings/api';
import type { BrowserSession } from '../src/lib/auth/session.svelte';
import type { UserSettings } from '../src/lib/api/generated/client';

const initial: UserSettings = {
	settingsRevision: '9007199254740993',
	settingsSoftware: { softwareAppearance: 'lightAppearance' },
	settingsBodyProfiles: [],
	settingsEquipment: []
};
const saved: UserSettings = {
	...initial,
	settingsRevision: '9007199254740994',
	settingsSoftware: { softwareAppearance: 'darkAppearance' }
};
const session: Pick<BrowserSession, 'user' | 'run'> = {
	user: { id: 'synthetic-owner', username: 'synthetic', createdAt: '2026-01-01T00:00:00Z' },
	run: (action) => action('synthetic-csrf', {})
};
afterEach(() => vi.unstubAllGlobals());

it.each(['before', 'during'] as const)(
	'keeps the saved revision when a GET started %s PUT finishes last',
	async (timing) => {
		const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
		const oldResponse = Promise.withResolvers<Response>();
		const putResponse = Promise.withResolvers<Response>();
		const readFinished = Promise.withResolvers<void>();
		let readSignal: AbortSignal | null | undefined;
		vi.stubGlobal(
			'fetch',
			vi.fn((_url: string, options: RequestInit) => {
				if (options.method === 'PUT') return putResponse.promise;
				readSignal = options.signal;
				// Deliberately complete even after abort: cancellation must also protect Query's cache.
				return oldResponse.promise;
			})
		);
		client.setQueryData(settingsKey(session.user?.id), initial);
		client.setQueryData(settingsKey('another-owner'), initial);
		client.setQueryData(['workout-analysis', session.user?.id], 'old analysis');
		client.setQueryData(['training-history', session.user?.id], 'old history');
		const read = () =>
			client
				.fetchQuery({
					queryKey: settingsKey(session.user?.id),
					queryFn: async ({ signal }) => {
						try {
							return await loadSettings(signal);
						} finally {
							readFinished.resolve();
						}
					}
				})
				.catch(() => undefined);
		try {
			const pendingRead = timing === 'before' ? read() : undefined;
			const pendingSave = saveSettings(session, client, initial);
			const duringRead = timing === 'during' ? read() : undefined;
			putResponse.resolve(Response.json(saved));
			await expect(pendingSave).resolves.toEqual(saved);
			oldResponse.resolve(Response.json(initial));
			await readFinished.promise;
			await Promise.all([pendingRead, duringRead]);
			expect(client.getQueryData(settingsKey(session.user?.id))).toEqual(saved);
			expect(readSignal?.aborted).toBe(true);
			expect(client.getQueryData(settingsKey('another-owner'))).toEqual(initial);
			expect(client.getQueryState(['workout-analysis', session.user?.id])?.isInvalidated).toBe(
				true
			);
			expect(client.getQueryState(['training-history', session.user?.id])?.isInvalidated).toBe(
				true
			);
		} finally {
			client.clear();
		}
	}
);
