<script lang="ts">
	import { m } from '$lib/paraglide/messages.js';
	import { onMount } from 'svelte';

	let theme = $state('system');
	let ready = $state(false);
	function apply() {
		document.documentElement.dataset.themeOverride = 'true';
		document.documentElement.dataset.theme = theme;
		try {
			localStorage.setItem('fitness-theme', theme);
		} catch {
			/* Storage is optional. */
		}
	}
	onMount(() => {
		try {
			const saved = localStorage.getItem('fitness-theme');
			if (saved === 'system' || saved === 'light' || saved === 'dark') {
				theme = saved;
				apply();
			}
		} catch {
			/* Use the system theme. */
		}
		theme = document.documentElement.dataset.theme ?? 'system';
		ready = true;
		const sync = () => {
			theme = document.documentElement.dataset.theme ?? 'system';
		};
		window.addEventListener('fitness-theme-changed', sync);
		return () => window.removeEventListener('fitness-theme-changed', sync);
	});
</script>

<select
	aria-label={m.theme_label()}
	value={theme}
	disabled={!ready}
	onchange={(event) => {
		theme = event.currentTarget.value;
		apply();
	}}
	><option value="system">{m.theme_system()}</option><option value="light">{m.theme_light()}</option
	><option value="dark">{m.theme_dark()}</option></select
>
