import { getSettings, putSettings, type UserSettings } from '$lib/api/generated/client';
import { getSettings200Response, putSettings200Response } from '$lib/api/generated/schemas';
import { request, requestOptions } from '$lib/api/request';
import type { BrowserSession } from '$lib/auth/session.svelte';
import type { QueryClient } from '@tanstack/svelte-query';

export const settingsKey = (owner: string | undefined) => ['settings', owner];
export const loadSettings = (signal?: AbortSignal) =>
	request(() => getSettings(undefined, requestOptions(signal)), getSettings200Response);
export async function saveSettings(
	session: BrowserSession,
	client: QueryClient,
	value: UserSettings
) {
	const owner = session.user?.id;
	const saved = await session.run((csrf, options) =>
		request(() => putSettings(value, { 'X-CSRF-Token': csrf }, options), putSettings200Response)
	);
	client.setQueryData(settingsKey(owner), saved);
	await client.invalidateQueries({
		predicate: (q) => q.queryKey[0] === 'workout-analysis' || q.queryKey[0] === 'training-history'
	});
	return saved;
}
