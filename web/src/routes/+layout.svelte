<script lang="ts">
	import '../app.css';
	import { onMount } from 'svelte';
	import { provideSession } from '$lib/auth/session.svelte';
	import { ApiError, errorText } from '$lib/api/request';
	import AuthGate from '$lib/components/AuthGate.svelte';
	import { QueryCache, QueryClient, QueryClientProvider } from '@tanstack/svelte-query';
	import { browser } from '$app/environment';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import Icon from '$lib/components/Icon.svelte';
	import { readScenario } from '$lib/api/read';
	let { children } = $props();
	const demo = import.meta.env.MODE === 'demo';
	const client = new QueryClient({
		queryCache: new QueryCache({
			onError: (error) => {
				if (!demo && error instanceof ApiError && error.status === 401) session.expire();
			}
		}),
		defaultOptions: {
			queries: { enabled: browser, retry: false, staleTime: 30_000, refetchOnWindowFocus: false }
		}
	});
	const session = provideSession(client);
	onMount(() => {
		if (!demo) return session.mount();
	});
	let logoutError = $state<Error | null>(null);
	let loggingOut = $state(false);
	async function logout() {
		if (loggingOut) return;
		loggingOut = true;
		logoutError = null;
		try {
			await session.logout();
		} catch (error) {
			if (error instanceof Error && error.name !== 'AbortError') logoutError = error;
		} finally {
			loggingOut = false;
		}
	}
	const scenario = $derived(readScenario(page.url.searchParams.get('scenario')));
	const suffix: '' | `?scenario=${string}` = $derived(
		demo && scenario !== 'normal' ? (`?scenario=${scenario}` as const) : ''
	);
	async function changeScenario(event: Event) {
		if (!(event.currentTarget instanceof HTMLSelectElement)) return;
		const url = new URL(page.url);
		const next = readScenario(event.currentTarget.value);
		if (next === 'normal') url.searchParams.delete('scenario');
		else url.searchParams.set('scenario', next);
		// The URL comes from the current page and already includes the configured base.
		// eslint-disable-next-line svelte/no-navigation-without-resolve
		await goto(url, { noScroll: true, keepFocus: true });
	}
</script>

<svelte:head><meta name="description" content="AI Fitness 训练复盘与数据分析" /></svelte:head>
<!-- Same-document focus navigation preserves the current route. -->
<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
<a class="skip" href="#main">跳到主要内容</a>
<aside class="sidebar">
	<a class="brand" href={resolve(`/workouts${suffix}`)} aria-label="AI Fitness 训练"
		><span class="brand-icon"><Icon /></span><span class="brand-name">AI Fitness</span></a
	>
	<div class="nav-caption">个人训练空间</div>
	<nav aria-label="主导航">
		<a
			class:active={page.url.pathname.includes('/workouts')}
			aria-current={page.url.pathname.includes('/workouts') ? 'page' : undefined}
			href={resolve(`/workouts${suffix}`)}><Icon /><span>训练</span></a
		>
		{#if !demo}<a
				class:active={page.url.pathname.includes('/settings')}
				aria-current={page.url.pathname.includes('/settings') ? 'page' : undefined}
				href={resolve('/settings')}><Icon kind="settings" /><span>账号</span></a
			>{/if}
	</nav>
	{#if demo}<a class="bottom-link" href={resolve('/demo')}
			><Icon kind="info" /><span>关于演示</span></a
		>{/if}
</aside>
<QueryClientProvider {client}>
	<main class="app-content" id="main">
		<div class="page">
			{#if demo}<div class="demo-bar">
					<span
						><span class="demo-dot"></span>演示模式
						<span class="demo-note">· 全部为合成数据</span></span
					><label
						>场景 <select value={scenario} onchange={changeScenario} aria-label="演示场景"
							><option value="normal">正常数据</option><option value="slow">慢速加载</option><option
								value="empty">空列表</option
							><option value="error">服务失败</option><option value="invalid">无效响应</option
							><option value="unauthenticated">会话失效</option></select
						></label
					>
				</div>{/if}
			{#if !demo && session.user}<div class="account-bar">
					<span class="small subtle">{session.user.username}</span><button
						class="button"
						disabled={loggingOut}
						onclick={logout}>{loggingOut ? '正在退出…' : '退出登录'}</button
					>
				</div>{/if}
			{#if logoutError && session.user}<p class="form-error" role="alert">
					{errorText(logoutError)}
				</p>{/if}
			<AuthGate>{@render children()}</AuthGate>
		</div>
	</main>
</QueryClientProvider>

<style>
	.account-bar {
		display: flex;
		justify-content: flex-end;
		align-items: center;
		flex-wrap: wrap;
		gap: 12px;
		margin-bottom: 16px;
		overflow-wrap: anywhere;
	}
	.skip {
		position: fixed;
		top: -80px;
		left: 16px;
		z-index: 10;
		background: #fff;
		padding: 12px;
	}
	.skip:not(:focus) {
		clip-path: inset(50%);
	}
	.skip:focus {
		top: 12px;
	}
	.sidebar {
		position: fixed;
		inset: 0 auto 0 0;
		width: 208px;
		padding: 32px 20px;
		border-right: 1px solid #e6e8ee;
		background: #fafafd;
		display: flex;
		flex-direction: column;
		z-index: 5;
	}
	.brand {
		display: flex;
		align-items: center;
		gap: 10px;
		font-weight: 700;
		font-size: 19px;
		white-space: nowrap;
	}
	.brand-icon {
		display: grid;
		place-items: center;
		width: 32px;
		height: 32px;
		background: #1769d2;
		color: #fff;
		border-radius: 9px;
	}
	.nav-caption {
		margin: 48px 12px 12px;
		font-size: 12px;
		color: #606672;
	}
	nav a,
	.bottom-link {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 13px;
		border-radius: 9px;
		font-size: 15px;
		min-height: 48px;
	}
	nav .active {
		color: #1769d2;
		background: #e8eef9;
		font-weight: 600;
	}
	.bottom-link {
		margin-top: auto;
		color: #606672;
	}
	.demo-bar {
		min-height: 44px;
		font-size: 13px;
		display: flex;
		flex-wrap: wrap;
		gap: 8px 20px;
		justify-content: space-between;
		align-items: center;
		color: #606672;
	}
	.demo-dot {
		width: 6px;
		height: 6px;
		display: inline-block;
		background: #1769d2;
		border-radius: 50%;
		margin-right: 7px;
	}
	.demo-bar label {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.demo-bar select {
		font-size: 13px;
		min-height: 36px;
		background: transparent;
	}
	@media (max-width: 1100px) and (min-width: 701px) {
		.sidebar {
			width: 76px;
			padding: 28px 12px;
		}
		.brand {
			justify-content: center;
		}
		.brand-name,
		.nav-caption {
			display: none;
		}
		nav {
			margin-top: 40px;
		}
		nav a,
		.bottom-link {
			flex-direction: column;
			gap: 4px;
			padding: 10px 0;
			font-size: 11px;
		}
	}
	@media (max-width: 700px) {
		.sidebar {
			top: auto;
			right: 0;
			width: auto;
			height: calc(68px + env(safe-area-inset-bottom));
			padding: 4px 20px env(safe-area-inset-bottom);
			border-right: 0;
			border-top: 1px solid #e6e8ee;
			flex-direction: row;
			align-items: center;
			justify-content: space-around;
			background: #fff;
		}
		nav {
			display: flex;
			gap: 24px;
		}
		.brand,
		.nav-caption {
			display: none;
		}
		nav a,
		.bottom-link {
			margin: 0;
			flex-direction: column;
			padding: 6px 20px;
			gap: 2px;
			font-size: 12px;
			background: transparent;
		}
		.demo-bar select {
			min-height: 44px;
		}
		.demo-note {
			display: none;
		}
	}
</style>
