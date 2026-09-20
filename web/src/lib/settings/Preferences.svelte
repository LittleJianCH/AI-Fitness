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
		// An explicit header choice belongs to this browser, including "system".
		try {
			const local = localStorage.getItem('fitness-theme');
			if (local === 'system' || local === 'light' || local === 'dark') return;
		} catch {
			/* Account appearance still works when storage is unavailable. */
		}
		if (document.documentElement.dataset.themeOverride === 'true') return;
		const theme = { systemAppearance: 'system', lightAppearance: 'light', darkAppearance: 'dark' }[
			query.data.settingsSoftware.softwareAppearance
		];
		document.documentElement.dataset.theme = theme;
		window.dispatchEvent(new Event('fitness-theme-changed'));
	});
</script>
