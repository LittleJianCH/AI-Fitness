<script lang="ts">
	import { browser } from '$app/environment';
	const demo = import.meta.env.MODE === 'demo';
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
	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (busy || demo) return;
		error = null;
		notice = '';
		const input = { username, password };
		const parsed = (registering ? postAuthRegisterBody : postAuthWebLoginBody).safeParse(input);
		if (!parsed.success || !username || !password) {
			notice = '请填写用户名和密码。';
			return;
		}
		if (registering && policy.data) {
			const length = [...password].length;
			if (
				length < policy.data.minimumPasswordLength ||
				length > policy.data.maximumPasswordLength
			) {
				notice = `密码需要 ${policy.data.minimumPasswordLength}–${policy.data.maximumPasswordLength} 个字符。`;
				return;
			}
		}
		busy = true;
		try {
			if (registering) {
				await session.register(input);
				registering = false;
				password = '';
				notice = '账号已创建，请登录。';
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

<svelte:head><title>{registering ? '注册' : '登录'} · AI Fitness</title></svelte:head>
<div class="auth-page">
	{#if demo}<div class="status">登录需要使用真实接入模式，演示模式仅供查看。</div>{:else}
		<div>
			<div class="eyebrow">YOUR TRAINING SPACE</div>
			<h1>{registering ? '创建你的账号' : '欢迎回来'}</h1>
			<p class="subtle">登录后，继续回看每一次训练。</p>
		</div>
		<form class="surface form-stack" onsubmit={submit}>
			<label
				>用户名<input
					name="username"
					autocomplete="username"
					bind:value={username}
					required
					disabled={busy}
				/></label
			>
			{#if registering}<p class="small subtle">
					使用 3–64 位英文字母、数字或 _ . -，区分大小写。
				</p>{/if}
			<label
				>密码<input
					name="password"
					type="password"
					autocomplete={registering ? 'new-password' : 'current-password'}
					bind:value={password}
					required
					disabled={busy}
				/></label
			>
			{#if registering && policy.data}<p class="small subtle">
					密码需要 {policy.data.minimumPasswordLength}–{policy.data.maximumPasswordLength} 个字符。
				</p>{/if}
			{#if notice}<p role="status">{notice}</p>{/if}
			{#if error}<p class="form-error" role="alert">{errorText(error)}</p>{/if}
			<button
				class="button primary"
				disabled={busy || (registering && policy.data?.registration !== 'openRegistration')}
				>{busy ? '正在处理…' : registering ? '创建账号' : '登录'}</button
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
					}}>{registering ? '已有账号，返回登录' : '注册新账号'}</button
				>
			{:else if policy.data}<p class="small subtle">当前仅开放已有账号登录。</p>{/if}
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
