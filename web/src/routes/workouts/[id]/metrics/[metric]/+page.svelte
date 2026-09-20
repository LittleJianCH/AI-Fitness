<script lang="ts">
	import { m as L } from '$lib/paraglide/messages.js';
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import WorkoutGate from '$lib/workouts/components/WorkoutGate.svelte';
	import MetricAnalysis from '$lib/workouts/components/MetricAnalysis.svelte';
	import { readScenario } from '$lib/api/read';
	import { metrics } from '$lib/workouts/presentation';

	const id = $derived(page.params.id ?? '');
	const scenario = $derived(readScenario(page.url.searchParams.get('scenario')));
	const suffix: '' | `?scenario=${string}` = $derived(
		scenario !== 'normal' ? (`?scenario=${scenario}` as const) : ''
	);
</script>

<svelte:head><title>{L.page_metric_title()}</title></svelte:head>
<nav class="breadcrumb" aria-label={L.navigation_breadcrumb()}>
	<a href={resolve(`/workouts${suffix}`)}>{L.navigation_workouts()}</a><span>/</span><a
		href={resolve(`/workouts/[id]${suffix}`, { id })}>{L.workout_details()}</a
	><span>/</span><span>{L.metric_analysis()}</span>
</nav>
<WorkoutGate {id} {scenario}>
	{#snippet children(workout)}{@const metric = metrics(workout).find(
			(m) => m.key === page.params.metric
		)}
		{#if metric}{#key `${id}/${metric.key}/${scenario}`}<MetricAnalysis {workout} {metric} />{/key}
		{:else}<div class="feedback">
				<h1>{L.metric_empty_title()}</h1>
				<p>{L.metric_empty_note()}</p>
				<a class="button" href={resolve(`/workouts/[id]${suffix}`, { id })}
					>{L.action_return_details()}</a
				>
			</div>{/if}
	{/snippet}
</WorkoutGate>
