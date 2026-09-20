<script lang="ts">
	import { m as L } from '$lib/paraglide/messages.js';
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import WorkoutGate from '$lib/workouts/components/WorkoutGate.svelte';
	import RoutePlot from '$lib/workouts/components/RoutePlot.svelte';
	import { readScenario } from '$lib/api/read';
	import { motion, duration } from '$lib/workouts/presentation';

	const id = $derived(page.params.id ?? '');
	const scenario = $derived(readScenario(page.url.searchParams.get('scenario')));
	const suffix: '' | `?scenario=${string}` = $derived(
		scenario !== 'normal' ? (`?scenario=${scenario}` as const) : ''
	);
	let selection = $state({ id: '', index: 0 });
	const selected = $derived(selection.id === id ? selection.index : 0);
	function selectSample(event: Event) {
		if (event.currentTarget instanceof HTMLInputElement)
			selection = { id, index: event.currentTarget.valueAsNumber };
	}
</script>

<svelte:head><title>{L.page_route_title()}</title></svelte:head>
<nav class="breadcrumb" aria-label={L.navigation_breadcrumb()}>
	<a href={resolve(`/workouts${suffix}`)}>{L.navigation_workouts()}</a><span>/</span><a
		href={resolve(`/workouts/[id]${suffix}`, { id })}>{L.workout_details()}</a
	><span>/</span><span>{L.route_title()}</span>
</nav>
<WorkoutGate {id} {scenario}>
	{#snippet children(workout)}{@const samples = motion(workout).motionPosition}{@const sample =
			samples[selected]}
		<header class="page-heading">
			<div>
				<div class="eyebrow">{L.eyebrow_route_review()}</div>
				<h1>{L.route_heading()}</h1>
				<p class="subtle">{workout.workoutUserData.workoutTitle}</p>
			</div>
		</header>
		{#if samples.length && sample}<section class="surface">
				<RoutePlot {samples} {selected} />
				<p class="subtle small">
					{L.route_basemap_note({
						kind: import.meta.env.MODE === 'demo' ? L.route_synthetic() : L.route_diagram()
					})}
				</p>
				<label for="route-sample"
					>{L.point_elapsed_value({
						time: duration(
							(Date.parse(sample.timestamp) -
								Date.parse(workout.workoutObservation.observationRange.rangeStart)) /
								1000
						)
					})}</label
				><input
					id="route-sample"
					aria-label={L.route_sample_picker()}
					type="range"
					min="0"
					max={samples.length - 1}
					step="1"
					value={selected}
					oninput={selectSample}
				/>
				<p class="small subtle">{L.route_help()}</p>
			</section>{:else}<div class="status">{L.route_missing()}</div>{/if}
	{/snippet}
</WorkoutGate>

<style>
	section > p {
		margin-top: 12px;
	}
	label {
		display: block;
		margin-top: 24px;
	}
	input {
		width: 100%;
		min-height: 44px;
		accent-color: var(--blue);
	}
</style>
