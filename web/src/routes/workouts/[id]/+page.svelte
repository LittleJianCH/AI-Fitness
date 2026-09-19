<script lang="ts">
	import { page } from '$app/state';
	import { createFocusSnapshot } from '$lib/focus-snapshot.svelte';
	import { resolve } from '$app/paths';
	import RecentWorkouts from '$lib/workouts/components/RecentWorkouts.svelte';
	import WorkoutReview from '$lib/workouts/components/WorkoutReview.svelte';
	import WorkoutDetails from '$lib/analysis/WorkoutDetails.svelte';
	import WorkoutGate from '$lib/workouts/components/WorkoutGate.svelte';
	import Icon from '$lib/components/Icon.svelte';
	import { readScenario } from '$lib/api/read';
	import { common, valueText, duration, timeSummary, dateText } from '$lib/workouts/presentation';

	const demo = import.meta.env.MODE === 'demo';

	const focus = createFocusSnapshot();
	const restoreFocus = focus.restoreFocus;
	export const snapshot = focus.snapshot;

	const id = $derived(page.params.id ?? '');
	const scenario = $derived(readScenario(page.url.searchParams.get('scenario')));
	const suffix: '' | `?scenario=${string}` = $derived(
		scenario !== 'normal' ? (`?scenario=${scenario}` as const) : ''
	);
</script>

<svelte:head><title>训练详情 · AI Fitness</title></svelte:head>

<div>
	<WorkoutGate {id} {scenario}>
		{#snippet children(workout)}{@const summary = common(workout)}{@const timing =
				timeSummary(summary)}
			<div class="workspace">
				<div class="recent-column"><RecentWorkouts {id} {scenario} /></div>
				<div class="workout-content">
					<nav class="breadcrumb" aria-label="面包屑">
						<a href={resolve(`/workouts${suffix}`)}><Icon kind="back" size={16} /> 训练</a><span
							>/</span
						><span>训练详情</span>
					</nav>
					<header class="page-heading">
						<div>
							<h1>{workout.workoutUserData.workoutTitle ?? '未命名训练'}</h1>
							<p class="subtle">
								{dateText(workout.workoutObservation.observationRange.rangeStart)} · 本地时区
							</p>
						</div>
						{#if demo}<span class="tag">合成训练</span>{:else}<a
								class="button"
								href={resolve('/workouts/[id]/edit', { id })}>编辑训练</a
							>{/if}
					</header>
					<div class="summary-strip">
						<div>
							<div class="summary-label">距离</div>
							<div class="summary-number">
								{valueText(summary.summaryDistance, 0.001, 1)}<small>km</small>
							</div>
						</div>
						<div>
							<div class="summary-label">{timing.label}</div>
							<div class="summary-number">{duration(timing.seconds)}</div>
						</div>
						<div>
							<div class="summary-label">累计爬升</div>
							<div class="summary-number">{valueText(summary.summaryAscent)}<small>m</small></div>
						</div>
						<div>
							<div class="summary-label">平均功率 · 记录</div>
							<div class="summary-number">
								{valueText(summary.summaryPower.averageValue)}<small>W</small>
							</div>
						</div>
						<div>
							<div class="summary-label">平均心率 · 记录</div>
							<div class="summary-number">
								{valueText(summary.summaryHeartRate.averageValue)}<small>bpm</small>
							</div>
						</div>
					</div>
					{#key `${id}-${workout.workoutRevision}-${scenario}`}<WorkoutReview
							{restoreFocus}
							{workout}
							{suffix}
						/>{/key}
					{#if !demo}<WorkoutDetails {workout} />{/if}
					<section class="source-details">
						<details>
							<summary>查看来源与统计口径</summary>
							<dl class="stats-rows">
								<div>
									<dt>数据来源</dt>
									<dd>{demo ? '合成演示响应' : '当前账号的训练记录'}</dd>
								</div>
								<div>
									<dt>统计口径</dt>
									<dd>记录汇总，未重新计算</dd>
								</div>
								<div>
									<dt>修订号</dt>
									<dd>{workout.workoutRevision}</dd>
								</div>
								<div>
									<dt>经过时长</dt>
									<dd>{duration(summary.summaryElapsedTime)}</dd>
								</div>
								<div>
									<dt>累计爬升</dt>
									<dd>{valueText(summary.summaryAscent)} m</dd>
								</div>
							</dl>
							{#each workout.workoutObservation.observationDataIssues as issue, i (i)}<p
									class="small subtle"
								>
									{issue.issueDescription}
								</p>{/each}
						</details>
					</section>
				</div>
			</div>
		{/snippet}
	</WorkoutGate>
</div>

<style>
	.workspace {
		display: grid;
		grid-template-columns: 157px minmax(0, 1fr);
		min-height: calc(100vh - 100px);
	}
	.recent-column {
		background: var(--sidebar);
		border-right: 1px solid var(--line);
		padding: 16px 13px;
	}
	.workout-content {
		min-width: 0;
		padding: 18px 26px 28px;
	}
	.breadcrumb {
		font-size: 11px;
		margin: 0;
		min-height: 28px;
	}
	.breadcrumb a {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		min-height: 28px;
	}
	.page-heading {
		margin: 14px 0 20px;
		align-items: center;
	}
	.page-heading h1 {
		font-size: 23px;
		line-height: 1.4;
		font-weight: 650;
	}
	.page-heading p {
		font-size: 11px;
		margin-top: 4px;
	}
	.page-heading .button {
		font-size: 11px;
		min-height: 36px;
		padding: 6px 10px;
	}
	.summary-strip {
		display: grid;
		grid-template-columns: 1.15fr 1.35fr 1fr 1fr 1fr;
		padding: 0;
		gap: 0;
		border-radius: 4px;
		margin-bottom: 18px;
	}
	.summary-strip > div {
		padding: 13px 14px;
		border-right: 1px solid var(--line);
		min-width: 0;
	}
	.summary-strip > div:last-child {
		border-right: 0;
	}
	.summary-label {
		font-size: 11px;
		margin-bottom: 5px;
	}
	.summary-number {
		font:
			500 23px/1.4 'SFMono-Regular',
			Consolas,
			monospace;
		letter-spacing: -1px;
		overflow-wrap: anywhere;
	}
	.summary-number small {
		font-size: 10px;
		margin-left: 3px;
		color: var(--muted);
	}
	.source-details {
		margin-top: 16px;
		font-size: 11px;
		color: var(--muted);
	}
	.source-details summary {
		cursor: pointer;
		min-height: 36px;
		padding: 8px 0;
	}
	.source-details .stats-rows {
		max-width: 600px;
	}
	.source-details p {
		margin-top: 8px;
	}
	@media (max-width: 900px) {
		.workspace {
			display: block;
		}
		.recent-column {
			display: none;
		}
		.workout-content {
			padding: 18px 14px;
		}
		.summary-strip {
			grid-template-columns: 1fr 1.2fr;
		}
		.summary-strip > div {
			border-bottom: 1px solid var(--line);
			padding: 12px;
		}
		.summary-strip > div:nth-child(2n) {
			border-right: 0;
		}
		.summary-strip > div:last-child {
			grid-column: 1/-1;
			border-bottom: 0;
			display: flex;
			align-items: baseline;
			gap: 14px;
		}
		.page-heading {
			align-items: start;
			gap: 12px;
		}
		.page-heading h1 {
			font-size: 23px;
		}
	}
</style>
