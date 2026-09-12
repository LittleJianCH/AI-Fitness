<script lang="ts">
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import type { Snippet } from 'svelte';
	import { useSession } from '$lib/auth/session.svelte';
	import { loginDestination } from '$lib/auth/navigation';
	import Feedback from './Feedback.svelte';
	let { children }: { children: Snippet } = $props();
	const session = useSession();
	const demo = import.meta.env.MODE === 'demo';
	$effect(() => {
		if (demo) return;
		if (session.state.type === 'anonymous' && page.url.pathname !== resolve('/login')) {
			void goto(resolve(`/login?next=${encodeURIComponent(page.url.pathname + page.url.search)}`), {
				replaceState: true
			});
		} else if (session.user && page.url.pathname === resolve('/login')) {
			// The return destination is validated as a local application path.
			// eslint-disable-next-line svelte/no-navigation-without-resolve
			void goto(loginDestination(page.url.searchParams.get('next')), {
				replaceState: true
			});
		}
	});
</script>

{#if demo || page.url.pathname === resolve('/login')}
	{@render children()}
{:else if session.user}
	{#key session.user.id}{@render children()}{/key}
{:else if session.state.type === 'error'}
	<Feedback error={session.state.error} retry={() => session.restore()} />
{:else}<div class="status" role="status">正在确认登录状态…</div>{/if}
