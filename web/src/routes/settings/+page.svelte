<script lang="ts">
	import { m as L } from '$lib/paraglide/messages.js';
	import { createQuery } from '@tanstack/svelte-query';
	import AccountSettings from '$lib/auth/components/AccountSettings.svelte';
	import { useSession } from '$lib/auth/session.svelte';
	import SettingsEditor from '$lib/settings/SettingsEditor.svelte';
	import { loadSettings, settingsKey } from '$lib/settings/api';
	import Feedback from '$lib/components/Feedback.svelte';
	const demo = import.meta.env.MODE === 'demo';
	const session = useSession();
	const query = createQuery(() => ({
		queryKey: settingsKey(session.user?.id),
		queryFn: ({ signal }) => loadSettings(signal),
		enabled: !demo && !!session.user
	}));
</script>

<svelte:head><title>{L.page_settings_title()}</title></svelte:head>
<header class="page-heading">
	<div>
		<div class="eyebrow">{L.eyebrow_your_settings()}</div>
		<h1>{L.page_settings()}</h1>
		<p class="subtle">{L.settings_intro()}</p>
	</div>
</header>
{#if demo}<div class="status">{L.settings_demo()}</div>
{:else}
	{#if query.isError}<Feedback error={query.error} retry={() => query.refetch()} />{/if}
	{#if query.data}<SettingsEditor initial={query.data} />{:else if query.isPending}<p role="status">
			{L.settings_loading()}
		</p>{/if}
	<section class="section">
		<h2>{L.settings_account()}</h2>
		<AccountSettings />
	</section>
{/if}
