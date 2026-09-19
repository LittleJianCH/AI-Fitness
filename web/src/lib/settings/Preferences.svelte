<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { useSession } from '$lib/auth/session.svelte';
	import { loadSettings, settingsKey } from './api';
	const session = useSession();
	const query = createQuery(() => ({
		queryKey: settingsKey(session.user?.id),
		queryFn: ({ signal }) => loadSettings(signal),
		enabled: !!session.user
	}));
	$effect(() => {
		if (!query.data) return;
		const theme = { systemAppearance: 'system', lightAppearance: 'light', darkAppearance: 'dark' }[
			query.data.settingsSoftware.softwareAppearance
		];
		document.documentElement.dataset.theme = theme;
		window.dispatchEvent(new Event('fitness-theme-changed'));
	});
</script>
