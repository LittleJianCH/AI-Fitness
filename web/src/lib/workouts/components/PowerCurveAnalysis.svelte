<script lang="ts">
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

<section class="power-curve section" aria-label="最佳持续功率">
	<h2>最佳持续功率</h2>
	<p class="small subtle">每个持续时长的最高平均功率 · 单次训练 · W</p>
	<div class="surface">
		{#if query.isPending}<p role="status">正在计算最佳持续功率…</p>
		{:else if query.isError}<Feedback error={query.error} retry={() => query.refetch()} />
		{:else if !current}<p role="status">训练已更新，请刷新后查看对应的功率曲线。</p>
			<button class="button" onclick={refreshWorkout}>刷新训练</button>
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
						>最佳区间：{offset(selected.best.start)} – {offset(selected.best.end)}</span
					>
				</div>
				<label
					>选择持续时长 <select
						value={selected.durationSeconds}
						onchange={(event) => (selectedDuration = Number(event.currentTarget.value))}
					>
						{#each available as point (point.durationSeconds)}<option value={point.durationSeconds}
								>{duration(point.durationSeconds)}</option
							>{/each}
					</select></label
				>
			{:else}<p>没有足够的连续功率采样，无法计算最佳持续功率。</p>{/if}
			<details>
				<summary>查看最佳功率数据表</summary>
				<div class="table-scroll" role="region" aria-label="最佳功率数据表">
					<table>
						<thead><tr><th>持续时长</th><th>平均功率</th><th>最佳区间</th></tr></thead>
						<tbody
							>{#each points as point (point.durationSeconds)}<tr>
									<td>{duration(point.durationSeconds)}</td><td
										>{point.best
											? `${valueText(point.best.averagePower, 1, 1)} W`
											: '连续采样不足'}</td
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
			按经过时间计算，包含真实零值；相邻采样间隔最多 {query.data.maxGapSeconds}
			秒时线性插值，更长缺口切断区间，不补零、不向首尾外推。横轴按对数显示持续时长，关键时长间连线仅辅助阅读。最佳区间时间相对训练开始。
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
