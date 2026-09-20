<script lang="ts">
	import { m as L } from '$lib/paraglide/messages.js';
	import { page } from '$app/state';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { useSession } from '$lib/auth/session.svelte';
	import { loadPowerCurve, readScenario } from '$lib/api/read';
	import type { Workout } from '$lib/api/generated/client';
	import Feedback from '$lib/components/Feedback.svelte';
	import { duration, valueText } from '$lib/workouts/presentation';
	import PowerCurveChart from './PowerCurveChart.svelte';

	let { workout }: { workout: Workout } = $props();
	const session = useSession();
	const client = useQueryClient();
	const scenario = $derived(readScenario(page.url.searchParams.get('scenario')));
	const query = createQuery(() => ({
		queryKey: [
			'power-curve',
			session.user?.id ?? 'demo',
			workout.workoutId,
			workout.workoutRevision,
			scenario
		],
		queryFn: ({ signal }) => loadPowerCurve(workout.workoutId, signal, scenario)
	}));
	const current = $derived(
		query.data?.inputRevision === workout.workoutRevision &&
			query.data?.curveWorkoutId === workout.workoutId
	);
	const points = $derived(current ? (query.data?.points ?? []) : []);
	const available = $derived(points.filter((point) => point.best !== undefined));
	let selectedDuration = $state(60);
	const selected = $derived(
		available.find((point) => point.durationSeconds === selectedDuration) ?? available[0]
	);
	const offset = (time: string) =>
		duration(
			(Date.parse(time) - Date.parse(workout.workoutObservation.observationRange.rangeStart)) / 1000
		);
	async function refreshWorkout() {
		await client.invalidateQueries({
			queryKey: ['workout', session.user?.id ?? 'demo', workout.workoutId]
		});
		await query.refetch();
	}
</script>

<section class="power-curve section" aria-label={L.power_best_sustained()}>
	<h2>{L.power_best_sustained()}</h2>
	<p class="small subtle">{L.power_curve_intro()}</p>
	<div class="surface">
		{#if query.isPending}<p role="status">{L.power_curve_loading()}</p>
		{:else if query.isError}<Feedback error={query.error} retry={() => query.refetch()} />
		{:else if !current}<p role="status">{L.power_curve_stale()}</p>
			<button class="button" onclick={refreshWorkout}>{L.workout_refresh()}</button>
		{:else}
			{#if selected?.best}
				<PowerCurveChart
					points={available}
					selectedDuration={selected.durationSeconds}
					onSelect={(seconds) => (selectedDuration = seconds)}
				/>
				<div class="selection" aria-live="polite">
					<strong
						>{duration(selected.durationSeconds)} · {valueText(selected.best.averagePower, 1, 1)} W</strong
					>
					<span class="small subtle"
						>{L.power_interval_value({
							start: offset(selected.best.start),
							end: offset(selected.best.end)
						})}</span
					>
				</div>
				<label
					>{L.power_curve_select_duration()}
					<select
						value={selected.durationSeconds}
						onchange={(event) => (selectedDuration = Number(event.currentTarget.value))}
					>
						{#each available as point (point.durationSeconds)}<option value={point.durationSeconds}
								>{duration(point.durationSeconds)}</option
							>{/each}
					</select></label
				>
			{:else}<p>{L.power_curve_missing()}</p>{/if}
			<details>
				<summary>{L.power_curve_table_show()}</summary>
				<div class="table-scroll" role="region" aria-label={L.power_curve_table()}>
					<table>
						<thead
							><tr
								><th>{L.label_sustained_duration()}</th><th>{L.label_average_power()}</th><th
									>{L.power_best_interval()}</th
								></tr
							></thead
						>
						<tbody
							>{#each points as point (point.durationSeconds)}<tr>
									<td>{duration(point.durationSeconds)}</td><td
										>{point.best
											? `${valueText(point.best.averagePower, 1, 1)} W`
											: L.power_insufficient_samples()}</td
									>
									<td
										>{point.best
											? `${offset(point.best.start)} – ${offset(point.best.end)}`
											: '—'}</td
									>
								</tr>{/each}</tbody
						>
					</table>
				</div>
			</details>
		{/if}
	</div>
	{#if current && query.data}<p class="small subtle">
			{L.power_curve_method({ seconds: query.data.maxGapSeconds })}
		</p>{/if}
</section>

<style>
	h2 {
		font-size: 20px;
	}
	section > p {
		margin: 8px 0 16px;
	}
	.selection {
		display: flex;
		flex-direction: column;
		gap: 6px;
		margin: 12px 0 20px;
		font-variant-numeric: tabular-nums;
	}
	strong {
		color: var(--metric-power);
		font-size: 24px;
	}
	label {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: 12px;
	}
	select {
		min-height: 44px;
	}
	details {
		margin-top: 16px;
	}
	summary {
		cursor: pointer;
		min-height: 44px;
		padding: 10px 0;
	}
</style>
