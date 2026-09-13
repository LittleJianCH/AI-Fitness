<script lang="ts">
	import { onMount } from 'svelte';
	let theme = $state('system');
	let ready = $state(false);
	function apply() {
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
			if (saved === 'light' || saved === 'dark') theme = saved;
		} catch {
			/* Use the system theme. */
		}
		apply();
		ready = true;
	});
</script>

<select
	aria-label="外观主题"
	value={theme}
	disabled={!ready}
	onchange={(event) => {
		theme = event.currentTarget.value;
		apply();
	}}
	><option value="system">跟随系统</option><option value="light">亮色</option><option value="dark"
		>暗色</option
	></select
>
