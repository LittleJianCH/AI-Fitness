<script lang="ts">
	import IconActivity from '@tabler/icons-svelte/icons/activity';
	import IconArrowLeft from '@tabler/icons-svelte/icons/arrow-left';
	import IconBike from '@tabler/icons-svelte/icons/bike';
	import IconChevronRight from '@tabler/icons-svelte/icons/chevron-right';
	import IconInfoCircle from '@tabler/icons-svelte/icons/info-circle';
	import IconRoute from '@tabler/icons-svelte/icons/route';
	import IconRun from '@tabler/icons-svelte/icons/run';
	import IconSettings from '@tabler/icons-svelte/icons/settings';

	const icons = {
		activity: IconActivity,
		arrow: IconChevronRight,
		back: IconArrowLeft,
		cycling: IconBike,
		running: IconRun,
		info: IconInfoCircle,
		route: IconRoute,
		settings: IconSettings
	};
	let { kind = 'activity', size = 20 }: { kind?: keyof typeof icons; size?: number } = $props();
	const Glyph = $derived(icons[kind]);
</script>

<Glyph {size} stroke={1.8} aria-hidden="true" focusable="false" />
