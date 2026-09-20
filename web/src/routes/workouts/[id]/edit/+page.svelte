<script lang="ts">
	import { m as L } from '$lib/paraglide/messages.js';
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import WorkoutGate from '$lib/workouts/components/WorkoutGate.svelte';
	import WorkoutEditor from '$lib/workouts/components/WorkoutEditor.svelte';

	const demo = import.meta.env.MODE === 'demo';
	const id = $derived(page.params.id ?? '');
</script>

<svelte:head><title>{L.page_edit_title()}</title></svelte:head>
<nav class="breadcrumb" aria-label={L.navigation_breadcrumb()}>
	<a href={resolve('/workouts')}>{L.navigation_workouts()}</a><span>/</span>
	<a href={resolve('/workouts/[id]', { id })}>{L.workout_details()}</a><span>/</span><span
		>{L.action_edit()}</span
	>
</nav>
<header class="page-heading">
	<div>
		<div class="eyebrow">{L.eyebrow_workout_details()}</div>
		<h1>{L.workout_edit()}</h1>
	</div>
</header>
{#if demo}<div class="status">{L.workout_edit_demo()}</div>
{:else}<WorkoutGate {id} scenario="normal">
		{#snippet children(workout)}{#key id}<WorkoutEditor {workout} />{/key}{/snippet}
	</WorkoutGate>{/if}
