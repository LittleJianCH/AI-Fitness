<script lang="ts">
	import { m as L } from '$lib/paraglide/messages.js';
	import { m } from '$lib/paraglide/messages.js';
	import { protectUnsavedChanges } from '$lib/i18n/guard.svelte';
	import { browser } from '$app/environment';
	import { onDestroy } from 'svelte';
	import { resolve } from '$app/paths';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { useSession } from '$lib/auth/session.svelte';
	import {
		getAuthPolicy,
		postImportsFit,
		getImportsImportId,
		type ImportRecord
	} from '$lib/api/generated/client';
	import {
		getAuthPolicy200Response,
		postImportsFit200Response,
		getImportsImportId200Response
	} from '$lib/api/generated/schemas';
	import { ApiError, request, requestOptions, errorText } from '$lib/api/request';

	const demo = import.meta.env.MODE === 'demo';
	const session = useSession();
	const client = useQueryClient();
	const lifetime = new AbortController();
	let active = true;
	onDestroy(() => {
		active = false;
		lifetime.abort();
	});
	const policy = createQuery(() => ({
		queryKey: ['auth-policy'],
		enabled: browser && !demo,
		queryFn: ({ signal }) =>
			request(() => getAuthPolicy(requestOptions(signal)), getAuthPolicy200Response)
	}));
	let file = $state<File | null>(null);
	let busy = $state(false);
	let uncertain = $state(false);
	let validation = $state('');
	let error = $state<Error | null>(null);
	let result = $state<ImportRecord | null>(null);
	const pending = $derived(result?.status === 'pending' || result?.status === 'processing');
	protectUnsavedChanges(
		() => busy || uncertain,
		() => m.discard_import(),
		() => busy
	);
	function selectFile(event: Event & { currentTarget: HTMLInputElement }) {
		file = event.currentTarget.files?.[0] ?? null;
		result = null;
		error = null;
		validation = '';
		uncertain = false;
	}
	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (busy || !file || !policy.data) return;
		if (file.size === 0 || file.size > policy.data.maximumFitBytes) {
			validation = file.size === 0 ? L.import_empty_file() : L.import_file_too_large();
			return;
		}
		const selected = file;
		await perform((csrf, options) =>
			request(
				() => postImportsFit(selected, { 'X-CSRF-Token': csrf }, options),
				postImportsFit200Response
			)
		);
	}
	async function refresh() {
		if (busy || !result) return;
		const id = result.id;
		await perform((_csrf, options) =>
			request(() => getImportsImportId(id, undefined, options), getImportsImportId200Response)
		);
	}
	async function perform(action: (csrf: string, options: RequestInit) => Promise<ImportRecord>) {
		busy = true;
		error = null;
		validation = '';
		const owner = session.user?.id;
		try {
			const record = await session.run(async (csrf, options) => {
				// WebKit shipped AbortController before AbortSignal.any. Forward session
				// cancellation to the page lifetime and release the listener after each request.
				const abort = () => lifetime.abort(options.signal?.reason);
				options.signal?.addEventListener('abort', abort, { once: true });
				if (options.signal?.aborted) abort();
				try {
					return await action(csrf, { ...options, signal: lifetime.signal });
				} finally {
					options.signal?.removeEventListener('abort', abort);
				}
			});
			if (!active || owner !== session.user?.id) return;
			result = record;
			uncertain = false;
			if (record.status === 'succeeded')
				void client.invalidateQueries({ queryKey: ['workouts', owner] });
		} catch (cause) {
			if (
				!active ||
				owner !== session.user?.id ||
				(cause instanceof Error && cause.name === 'AbortError')
			)
				return;
			error = cause instanceof Error ? cause : new Error('Upload failed');
			if (
				!(cause instanceof ApiError) ||
				cause.status === 0 ||
				cause.status >= 500 ||
				cause.code === 'invalid_response'
			)
				uncertain = true;
		} finally {
			if (active) busy = false;
		}
	}
	function failureText(code: string | undefined) {
		switch (code) {
			case 'unsupported_fit':
				return L.import_unsupported();
			case 'missing_fit_time':
				return L.import_missing_time();
			case 'fit_resource_limit':
				return L.import_limit_exceeded();
			case 'invalid_fit':
				return L.import_invalid_file();
			default:
				return L.import_invalid_data();
		}
	}
</script>

<svelte:head><title>{L.page_upload_title()}</title></svelte:head>
<header class="page-heading">
	<div>
		<p class="eyebrow">{L.eyebrow_import_workout()}</p>
		<h1>{L.import_heading()}</h1>
		<p class="subtle">{L.import_intro()}</p>
	</div>
</header>
{#if demo}<div class="status">{L.import_demo()}</div>
{:else}<section class="surface upload-panel form-stack" aria-label={L.import_region()}>
		<p>{L.import_privacy_note()}</p>
		{#if policy.isPending}<p role="status">{L.import_policy_loading()}</p>
		{:else if policy.isError}<p class="form-error" role="alert">{errorText(policy.error)}</p>
			<button class="button" onclick={() => policy.refetch()}>{L.import_policy_retry()}</button>
		{:else if policy.data}<form class="form-stack" onsubmit={submit}>
				<label
					>{L.import_file()}<input
						type="file"
						accept=".fit,.FIT,application/octet-stream"
						required
						disabled={busy || uncertain || pending}
						onchange={selectFile}
					/></label
				>
				<p class="small subtle">
					{L.import_maximum({ size: policy.data.maximumFitBytes / 1024 / 1024 })}
				</p>
				{#if validation}<p class="form-error" role="alert">{validation}</p>{/if}
				{#if error}<p class="form-error" role="alert">{errorText(error)}</p>{/if}
				{#if uncertain}<p role="status">
						{L.import_uncertain()}
					</p>{/if}
				<div class="form-actions">
					<button
						class="button primary"
						disabled={busy || !file || pending || (!!result && !uncertain)}
						>{busy
							? L.action_processing()
							: uncertain
								? L.import_retry()
								: L.import_start()}</button
					><a class="button" href={resolve('/workouts')}>{L.action_back_workouts()}</a>
				</div>
			</form>{/if}
		{#if result}<div class="import-result" role="status">
				{#if result.status === 'succeeded'}<h2>{L.import_success_title()}</h2>
					<p>{L.import_success_note()}</p>
					{#each result.lastSuccess?.parts ?? [] as part (part.workoutId)}<a
							class="button primary"
							href={resolve(`/workouts/${part.workoutId}`)}>{L.action_view_workout()}</a
						>{/each}
				{:else if result.status === 'suppressed'}<h2>{L.import_removed_title()}</h2>
					<p>{L.import_removed_note()}</p>
				{:else if result.status === 'failed'}<h2>{L.import_failed_title()}</h2>
					<p>{failureText(result.failure?.code)}</p>
				{:else}<h2>{L.import_pending_title()}</h2>
					<p>{L.import_pending_note()}</p>
					<button class="button" disabled={busy} onclick={refresh}>{L.import_check_result()}</button
					>{/if}
			</div>{/if}
	</section>{/if}

<style>
	.upload-panel {
		max-width: 760px;
	}
	.import-result {
		display: grid;
		gap: 14px;
		justify-items: start;
	}
	input[type='file'] {
		height: auto;
	}
</style>
