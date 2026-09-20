<script lang="ts">
	import { m } from '$lib/paraglide/messages.js';
	import '../app.css';
	import { onMount } from 'svelte';
	import { provideSession } from '$lib/auth/session.svelte';
	import { ApiError, errorText } from '$lib/api/request';
	import AuthGate from '$lib/auth/components/AuthGate.svelte';
	import { QueryCache, QueryClient, QueryClientProvider } from '@tanstack/svelte-query';
	import { browser } from '$app/environment';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import LanguagePicker from '$lib/components/LanguagePicker.svelte';
	import ThemePicker from '$lib/components/ThemePicker.svelte';
	import Icon from '$lib/components/Icon.svelte';
	import Preferences from '$lib/settings/Preferences.svelte';
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

<svelte:head><meta name="description" content={m.app_description()} /></svelte:head>
<!-- Same-document focus navigation preserves the current route. -->
<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
<a class="skip" href="#main">{m.app_skip()}</a>
<aside class="sidebar">
	<a class="brand" href={resolve(`/workouts${suffix}`)} aria-label={m.app_brand()}
		><span class="brand-icon">↗</span><span class="brand-name">AI Fitness</span></a
	>
	<span class="workspace-label">{m.app_workspace()}</span>
	<nav aria-label={m.app_navigation()}>
		<a
			class:active={page.url.pathname.includes('/workouts')}
			aria-current={page.url.pathname.includes('/workouts') ? 'page' : undefined}
			href={resolve(`/workouts${suffix}`)}><Icon /><span>{m.nav_workouts()}</span></a
		>
		{#if !demo}<a
				href={resolve('/training-history')}
				class:active={page.url.pathname.includes('/training-history')}
				aria-current={page.url.pathname.includes('/training-history') ? 'page' : undefined}
				><span>{m.nav_trends()}</span></a
			><a
				class:active={page.url.pathname.includes('/settings')}
				aria-current={page.url.pathname.includes('/settings') ? 'page' : undefined}
				href={resolve('/settings')}><Icon kind="settings" /><span>{m.nav_settings()}</span></a
			>{/if}
	</nav>
	{#if demo}<a class="bottom-link" href={resolve('/demo')}
			><Icon kind="info" /><span>{m.nav_demo()}</span></a
		>{/if}
	<ThemePicker /><LanguagePicker />
</aside>
<QueryClientProvider {client}>
	<main class="app-content" id="main">
		<div class="page">
			{#if demo}<div class="demo-bar">
					<span
						><span class="demo-dot"></span>{m.demo_mode()}
						<span class="demo-note">{m.demo_synthetic()}</span></span
					><label
						>{m.demo_scenario()}
						<select value={scenario} onchange={changeScenario} aria-label={m.demo_select()}
							><option value="normal">{m.demo_normal()}</option><option value="slow"
								>{m.demo_slow()}</option
							><option value="empty">{m.demo_empty()}</option><option value="error"
								>{m.demo_error()}</option
							><option value="invalid">{m.demo_invalid()}</option><option value="unauthenticated"
								>{m.demo_session()}</option
							></select
						></label
					>
				</div>{/if}
			{#if !demo && session.user}<div class="account-bar">
					<span class="small subtle">{session.user.username}</span><button
						class="button"
						disabled={loggingOut}
						onclick={logout}>{loggingOut ? m.auth_signing_out() : m.auth_sign_out()}</button
					>
				</div>{/if}
			{#if logoutError && session.user}<p class="form-error" role="alert">
					{errorText(logoutError)}
				</p>{/if}
			<AuthGate
				>{#if !demo}<Preferences />{/if}{@render children()}</AuthGate
			>
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
		background: var(--panel);
		padding: 12px;
	}
	.skip:not(:focus) {
		clip-path: inset(50%);
	}
	.skip:focus {
		top: 12px;
	}
	.sidebar {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: 12px;
		padding: 10px 24px;
		border-bottom: 1px solid var(--line);
		background: var(--panel);
	}
	.brand {
		display: flex;
		align-items: center;
		gap: 10px;
		font-weight: 700;
		font-size: 16px;
	}
	.brand-icon {
		display: grid;
		place-items: center;
		color: var(--blue);
	}
	nav {
		display: flex;
		gap: 8px;
		margin-left: auto;
	}
	nav a,
	.bottom-link {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 10px 12px;
		border-radius: 6px;
		min-height: 44px;
	}
	nav .active {
		background: var(--soft);
		color: var(--blue);
	}
	.bottom-link {
		color: var(--muted);
	}
	.demo-bar {
		min-height: 44px;
		font-size: 13px;
		display: flex;
		flex-wrap: wrap;
		gap: 8px 20px;
		justify-content: space-between;
		align-items: center;
		color: var(--muted);
	}
	.demo-dot {
		width: 6px;
		height: 6px;
		display: inline-block;
		background: var(--blue);
		border-radius: 50%;
		margin-right: 7px;
	}
	.demo-bar label {
		display: flex;
		flex-wrap: wrap;
		max-width: 100%;
		align-items: center;
		gap: 8px;
	}
	.demo-bar select {
		font-size: 13px;
		min-height: 36px;
		background: transparent;
	}
	@media (max-width: 700px) {
		.sidebar {
			padding: 12px;
			gap: 8px;
		}
		.brand {
			font-size: 16px;
		}
		nav a {
			padding: 8px;
		}
		.bottom-link {
			display: none;
		}
		.demo-note {
			display: none;
		}
	}
	.brand-icon {
		width: 23px;
		height: 23px;
		border-radius: 4px;
		background: var(--blue);
		color: var(--panel);
		font-size: 18px;
		font-weight: 700;
	}
	.workspace-label {
		font-size: 11px;
		color: var(--muted);
		margin-left: 10px;
	}
	nav a,
	.bottom-link {
		font-size: 12px;
	}
	.sidebar :global(select) {
		font-size: 11px;
		min-height: 36px;
	}
	@media (max-width: 700px) {
		.workspace-label {
			display: none;
		}
	}
</style>
