<script lang="ts">
	import { createInfiniteQuery, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { z } from 'zod';
	import { useSession } from '$lib/auth/session.svelte';
	import {
		getAuthPolicy,
		getAuthSessions,
		deleteAuthSessions,
		deleteAuthSessionsSessionId,
		putAuthPassword,
		getMe,
		type Session
	} from '$lib/api/generated/client';
	import {
		getAuthPolicy200Response,
		getAuthSessions200Response,
		putAuthPasswordBody,
		getMe200Response
	} from '$lib/api/generated/schemas';
	import { ApiError, errorText, request, requestOptions } from '$lib/api/request';
	import Feedback from '$lib/components/Feedback.svelte';

	const session = useSession();
	const client = useQueryClient();
	const policy = createQuery(() => ({
		queryKey: ['auth-policy'],
		queryFn: ({ signal }) =>
			request(() => getAuthPolicy(requestOptions(signal)), getAuthPolicy200Response)
	}));
	const queryKey = $derived(['sessions', session.user?.id]);
	const sessions = createInfiniteQuery(() => ({
		queryKey,
		queryFn: ({ signal, pageParam }) =>
			request(
				() => getAuthSessions({ cursor: pageParam, limit: 5 }, undefined, requestOptions(signal)),
				getAuthSessions200Response
			),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (last) => last.nextCursor
	}));
	const items = $derived([
		...new Map(
			(sessions.data?.pages.flatMap((page) => page.items) ?? []).map((item) => [item.id, item])
		).values()
	]);
	let busy = $state(false);
	let actionError = $state<Error | null>(null);
	let passwordError = $state<Error | null>(null);
	let currentPassword = $state('');
	let newPassword = $state('');
	let confirmation = $state('');
	let validation = $state('');
	let notice = $state('');
	const time = (value: string) => new Date(value).toLocaleString('zh-CN', { hour12: false });
	async function retrySessions() {
		if (sessions.error instanceof ApiError && sessions.error.code === 'invalid_cursor')
			await client.resetQueries({ queryKey, exact: true });
		else if (sessions.isFetchNextPageError) await sessions.fetchNextPage();
		else await sessions.refetch();
	}
	async function revoke(item?: Session) {
		const message = !item
			? '退出所有设备？当前页面也会退出登录。'
			: item.current
				? '退出当前设备？当前页面会返回登录。'
				: '退出这台设备？该设备需要重新登录。';
		if (busy || !window.confirm(message)) return;
		busy = true;
		actionError = null;
		notice = '';
		try {
			await session.run((csrf, options) =>
				request(
					() =>
						item
							? deleteAuthSessionsSessionId(item.id, { 'X-CSRF-Token': csrf }, options)
							: deleteAuthSessions({ 'X-CSRF-Token': csrf }, options),
					z.void(),
					204
				)
			);
			if (!item || item.current) session.end();
			else {
				notice = '已退出这台设备。';
				await client.resetQueries({ queryKey, exact: true });
			}
		} catch (cause) {
			if (cause instanceof Error && cause.name !== 'AbortError') actionError = cause;
		} finally {
			busy = false;
		}
	}
	async function changePassword(event: SubmitEvent) {
		event.preventDefault();
		if (busy || !policy.data) return;
		validation = '';
		passwordError = null;
		const parsed = putAuthPasswordBody.safeParse({ currentPassword, newPassword });
		const length = [...newPassword].length;
		if (!parsed.success || !currentPassword) {
			validation = '请填写当前密码和新密码。';
			return;
		}
		if (length < policy.data.minimumPasswordLength || length > policy.data.maximumPasswordLength) {
			validation = `新密码需要 ${policy.data.minimumPasswordLength}–${policy.data.maximumPasswordLength} 个字符。`;
			return;
		}
		if (newPassword !== confirmation) {
			validation = '两次输入的新密码不一致。';
			return;
		}
		busy = true;
		try {
			await session.run(async (csrf, options) => {
				try {
					await request(
						() => putAuthPassword(parsed.data, { 'X-CSRF-Token': csrf }, options),
						z.void(),
						204
					);
				} catch (cause) {
					// This endpoint also uses 401 for an incorrect current password.
					// Verify the session before deciding whether the user must log in again.
					if (cause instanceof ApiError && cause.code === 'unauthenticated') {
						const user = await request(() => getMe(undefined, options), getMe200Response);
						if (user.id !== session.user?.id) {
							await session.restore();
							throw new DOMException('Account changed', 'AbortError');
						}
						throw new ApiError('invalid_current_password');
					}
					throw cause;
				}
			});
			currentPassword = '';
			newPassword = '';
			confirmation = '';
			session.end();
		} catch (cause) {
			if (cause instanceof Error && cause.name !== 'AbortError') passwordError = cause;
		} finally {
			busy = false;
		}
	}
</script>

<div class="settings-grid">
	<section class="surface form-stack">
		<div class="section-heading">
			<div>
				<h2>登录设备</h2>
				<p class="small subtle">时间按本地时区显示。</p>
			</div>
			<button
				class="button"
				disabled={busy || sessions.isFetching}
				onclick={() => client.resetQueries({ queryKey, exact: true })}>刷新设备</button
			>
		</div>
		{#if actionError}<p class="form-error" role="alert">{errorText(actionError)}</p>{/if}
		{#if notice}<p role="status">{notice}</p>{/if}
		{#if sessions.isPending}<p role="status">正在读取登录设备…</p>
		{:else if items.length}<ul class="sessions" aria-label="登录设备">
				{#each items as item (item.id)}<li class="session-card">
						<div class="section-heading">
							<h3>{item.deviceName ?? (item.transport === 'browser' ? '浏览器' : '客户端')}</h3>
							{#if item.current}<span class="tag">当前设备</span>{/if}
						</div>
						<p class="small subtle">{item.transport === 'browser' ? '浏览器会话' : '客户端会话'}</p>
						<dl class="stats-rows small">
							<div>
								<dt>登录时间</dt>
								<dd>{time(item.createdAt)}</dd>
							</div>
							<div>
								<dt>最近活动</dt>
								<dd>{time(item.lastSeenAt)}</dd>
							</div>
							<div>
								<dt>会话最晚到期</dt>
								<dd>{time(item.absoluteExpiresAt)}</dd>
							</div>
						</dl>
						<div>
							<button class="button" disabled={busy} onclick={() => revoke(item)}
								>{item.current ? '退出当前设备' : '退出这台设备'}</button
							>
						</div>
					</li>{/each}
			</ul>{:else if !sessions.isError}<p>没有可显示的登录设备。</p>{/if}
		{#if sessions.isError}<Feedback error={sessions.error} retry={retrySessions} />{/if}
		{#if sessions.hasNextPage}<button
				class="button"
				disabled={sessions.isFetching || busy}
				onclick={() =>
					sessions.error instanceof ApiError && sessions.error.code === 'invalid_cursor'
						? retrySessions()
						: sessions.fetchNextPage()}
				>{sessions.isFetchingNextPage ? '正在读取…' : '加载更多设备'}</button
			>{/if}
		<div>
			<button class="button danger" disabled={busy} onclick={() => revoke()}>退出所有设备</button>
		</div>
	</section>
	<section class="surface form-stack password-section">
		<h2>修改密码</h2>
		<p class="subtle">修改成功后会退出所有设备，请使用新密码重新登录。</p>
		<form class="form-stack" onsubmit={changePassword}>
			<label
				>当前密码<input
					type="password"
					autocomplete="current-password"
					required
					disabled={busy}
					bind:value={currentPassword}
				/></label
			>
			<label
				>新密码<input
					type="password"
					autocomplete="new-password"
					required
					disabled={busy}
					bind:value={newPassword}
				/></label
			>
			<label
				>确认新密码<input
					type="password"
					autocomplete="new-password"
					required
					disabled={busy}
					bind:value={confirmation}
				/></label
			>
			{#if policy.data}<p class="small subtle">
					新密码需要 {policy.data.minimumPasswordLength}–{policy.data.maximumPasswordLength} 个字符。
				</p>{/if}
			{#if validation}<p class="form-error" role="alert">{validation}</p>{/if}
			{#if passwordError}<p class="form-error" role="alert">{errorText(passwordError)}</p>{/if}
			<button class="button primary" disabled={busy || !policy.data}
				>{busy ? '正在处理…' : '修改密码并退出'}</button
			>
		</form>
		{#if policy.isError}<Feedback error={policy.error} retry={() => policy.refetch()} />{/if}
	</section>
</div>

<style>
	.settings-grid {
		display: grid;
		grid-template-columns: minmax(0, 1.3fr) minmax(0, 1fr);
		gap: 24px;
		align-items: start;
	}
	.section-heading {
		display: flex;
		align-items: start;
		justify-content: space-between;
		gap: 12px;
		flex-wrap: wrap;
	}
	.section-heading h3 {
		overflow-wrap: anywhere;
	}
	.sessions {
		list-style: none;
		padding: 0;
		margin: 0;
	}
	.session-card {
		padding: 20px 0;
		border-bottom: 1px solid var(--line);
		display: grid;
		gap: 12px;
	}
	.session-card:first-child {
		padding-top: 0;
	}
	@media (max-width: 1000px) {
		.settings-grid {
			grid-template-columns: 1fr;
		}
	}
</style>
