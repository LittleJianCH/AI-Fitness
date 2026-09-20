<script lang="ts">
	import { m } from '$lib/paraglide/messages.js';
	import { protectUnsavedChanges } from '$lib/i18n/guard.svelte';
	import { browser } from '$app/environment';
	import { createQuery } from '@tanstack/svelte-query';
	import { useSession } from '$lib/auth/session.svelte';
	import { getAuthPolicy } from '$lib/api/generated/client';
	import {
		getAuthPolicy200Response,
		postAuthRegisterBody,
		postAuthWebLoginBody
	} from '$lib/api/generated/schemas';
	import { errorText, request, requestOptions, ApiError } from '$lib/api/request';
	import Feedback from '$lib/components/Feedback.svelte';

	const demo = import.meta.env.MODE === 'demo';

	const session = useSession();
	const policy = createQuery(() => ({
		queryKey: ['auth-policy'],
		enabled: browser && !demo,
		queryFn: ({ signal }) =>
			request(() => getAuthPolicy(requestOptions(signal)), getAuthPolicy200Response)
	}));
	let registering = $state(false);
	let username = $state('');
	let password = $state('');
	let busy = $state(false);
	let error = $state<Error | null>(null);
	let notice = $state('');
	protectUnsavedChanges(
		() => !session.user && (!!username || !!password),
		() => m.discard_login(),
		() => busy
	);
	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (busy || demo) return;
		error = null;
		notice = '';
		const input = { username, password };
		const parsed = (registering ? postAuthRegisterBody : postAuthWebLoginBody).safeParse(input);
		if (!parsed.success || !username || !password) {
			notice = m.auth_required();
			return;
		}
		if (registering && policy.data) {
			const length = [...password].length;
			if (
				length < policy.data.minimumPasswordLength ||
				length > policy.data.maximumPasswordLength
			) {
				notice = m.auth_password_length({
					minimum: policy.data.minimumPasswordLength,
					maximum: policy.data.maximumPasswordLength
				});
				return;
			}
		}
		busy = true;
		try {
			if (registering) {
				await session.register(input);
				registering = false;
				password = '';
				notice = m.auth_created();
			} else {
				await session.login(input);
				password = '';
			}
		} catch (cause) {
			if (!(cause instanceof Error && cause.name === 'AbortError'))
				error = cause instanceof Error ? cause : new ApiError('network_error');
			if (cause instanceof ApiError && cause.code === 'registration_closed') {
				registering = false;
				void policy.refetch();
			}
		} finally {
			busy = false;
		}
	}
</script>

<svelte:head
	><title>{registering ? m.auth_register() : m.auth_login()} · AI Fitness</title></svelte:head
>
<div class="auth-page">
	{#if demo}<div class="status">{m.auth_demo()}</div>{:else}
		<div>
			<div class="eyebrow">{m.auth_eyebrow()}</div>
			<h1>{registering ? m.auth_create_heading() : m.auth_welcome()}</h1>
			<p class="subtle">{m.auth_intro()}</p>
		</div>
		<form class="surface form-stack" onsubmit={submit}>
			<label
				>{m.auth_username()}<input
					name="username"
					autocomplete="username"
					bind:value={username}
					required
					disabled={busy}
				/></label
			>
			{#if registering}<p class="small subtle">
					{m.auth_username_hint()}
				</p>{/if}
			<label
				>{m.auth_password()}<input
					name="password"
					type="password"
					autocomplete={registering ? 'new-password' : 'current-password'}
					bind:value={password}
					required
					disabled={busy}
				/></label
			>
			{#if registering && policy.data}<p class="small subtle">
					{m.auth_password_length({
						minimum: policy.data.minimumPasswordLength,
						maximum: policy.data.maximumPasswordLength
					})}
				</p>{/if}
			{#if notice}<p role="status">{notice}</p>{/if}
			{#if error}<p class="form-error" role="alert">{errorText(error)}</p>{/if}
			<button
				class="button primary"
				disabled={busy || (registering && policy.data?.registration !== 'openRegistration')}
				>{busy ? m.auth_working() : registering ? m.auth_create() : m.auth_login()}</button
			>
			{#if policy.data?.registration === 'openRegistration'}<button
					class="button"
					type="button"
					disabled={busy}
					onclick={() => {
						registering = !registering;
						error = null;
						notice = '';
						password = '';
					}}>{registering ? m.auth_back_login() : m.auth_new_account()}</button
				>
			{:else if policy.data}<p class="small subtle">{m.auth_existing_only()}</p>{/if}
		</form>
		{#if policy.isError}<Feedback error={policy.error} retry={() => policy.refetch()} />{/if}
	{/if}
</div>

<style>
	.auth-page {
		max-width: 480px;
		margin: 64px auto;
		display: grid;
		gap: 28px;
	}
	.auth-page h1 {
		margin-bottom: 12px;
	}
	@media (max-width: 700px) {
		.auth-page {
			margin: 32px auto;
		}
	}
</style>
