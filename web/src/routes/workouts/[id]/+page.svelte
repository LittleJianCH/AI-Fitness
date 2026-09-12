<script lang="ts">
	const demo = import.meta.env.MODE === 'demo';
	import { page } from '$app/state';
	import { createFocusSnapshot } from '$lib/focus-snapshot.svelte';
	const focus = createFocusSnapshot();
	export const snapshot = focus.snapshot;
	const restoreFocus = focus.restoreFocus;
	import { resolve } from '$app/paths';
	import { onMount } from 'svelte';
	import WorkoutGate from '$lib/components/WorkoutGate.svelte';
	import TimeChart from '$lib/components/TimeChart.svelte';
	import RoutePlot from '$lib/components/RoutePlot.svelte';
	import Icon from '$lib/components/Icon.svelte';
	import { readScenario } from '$lib/api/read';
	import {
		common,
		motion,
		metrics,
		valueText,
		duration,
		timeSummary,
		dateText
	} from '$lib/workouts/presentation';
	import type { Workout } from '$lib/api/generated/client';
	const id = $derived(page.params.id ?? '');
	const scenario = $derived(readScenario(page.url.searchParams.get('scenario')));
	const suffix: '' | `?scenario=${string}` = $derived(
		scenario !== 'normal' ? (`?scenario=${scenario}` as const) : ''
	);
	let region: HTMLDivElement;
	let wide = $state(false);
	onMount(() => {
		wide = region.getBoundingClientRect().width >= 924;
		let resizeFrame = 0;
		const observer = new ResizeObserver((entries) => {
			const next = entries[0].contentRect.width >= 924;
			cancelAnimationFrame(resizeFrame);
			resizeFrame = requestAnimationFrame(() => {
				wide = next;
			});
		});
		observer.observe(region);
		return () => {
			observer.disconnect();
			cancelAnimationFrame(resizeFrame);
		};
	});
</script>

<svelte:head><title>训练详情 · AI Fitness</title></svelte:head>
<nav class="breadcrumb" aria-label="面包屑">
	<a href={resolve(`/workouts${suffix}`)}><Icon kind="back" size={16} /> 训练</a><span>/</span><span
		>训练详情</span
	>
</nav>
<div bind:this={region}>
	<WorkoutGate {id} {scenario}>
		{#snippet children(workout)}{@const summary = common(workout)}{@const timing =
				timeSummary(summary)}{@const sport = workout.workoutObservation.observationSport}
			<header class="page-heading">
				<div>
					<div class="eyebrow">{sport.type === 'cycling' ? '骑行复盘' : '跑步复盘'}</div>
					<h1>{workout.workoutUserData.workoutTitle ?? '未命名训练'}</h1>
					<p class="subtle">
						{dateText(workout.workoutObservation.observationRange.rangeStart)} · 本地时区
					</p>
				</div>
				{#if demo}<span class="tag">合成训练</span>{/if}
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
			</div>
			<div
				class:two-columns={wide && motion(workout).motionPosition.length > 0}
				class="overview-grid"
			>
				{#if wide}{@render previews(workout)}{@render route(workout)}{:else}{@render route(
						workout
					)}{@render previews(workout)}{/if}
			</div>
			<section class="section">
				<h2>备注与数据说明</h2>
				<div class="surface">
					<p class="notes">{workout.workoutUserData.workoutNotes ?? '暂无备注'}</p>
					<div class="tags">
						{#each workout.workoutUserData.workoutTags as tag, i (i)}<span class="tag">{tag}</span
							>{/each}
					</div>
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
				</div>
			</section>
		{/snippet}
	</WorkoutGate>
</div>
{#snippet previews(workout: Workout)}
	<div class="metric-stack">
		{#if !metrics(workout).length}<div class="surface subtle">
				这条训练暂无可分析的指标汇总或曲线。
			</div>{/if}
		{#each metrics(workout) as metric (metric.key)}{@const range =
				workout.workoutObservation.observationRange}
			<a
				class="surface metric-card"
				data-return-focus={`metric-${metric.key}`}
				use:restoreFocus
				href={resolve(`/workouts/[id]/metrics/[metric]${suffix}`, { id, metric: metric.key })}
			>
				<div class="metric-heading">
					<h2 style:color={metric.color}>{metric.title}</h2>
					<Icon kind="arrow" size={17} />
				</div>
				<div class="metric-number">
					{valueText(
						metric.average ?? metric.maximum,
						metric.factor,
						metric.key === 'speed' ? 1 : 0
					)}<span>{metric.unit} · {metric.average !== undefined ? '记录平均' : '记录最大'}</span>
				</div>
				{#if metric.samples.length}<TimeChart
						{metric}
						start={range.rangeStart}
						end={range.rangeEnd}
						preview
					/>
					<div class="chart-caption">
						<span>开始</span><span
							>{duration((Date.parse(range.rangeEnd) - Date.parse(range.rangeStart)) / 1000)}</span
						>
					</div>{:else}<p class="summary-only">仅记录汇总 · 无逐点曲线</p>{/if}
			</a>
		{/each}
	</div>
{/snippet}
{#snippet route(workout: Workout)}
	{#if motion(workout).motionPosition.length}<aside class="surface route-card">
			<div class="metric-heading">
				<h2>轨迹</h2>
				<Icon kind="route" size={18} />
			</div>
			<RoutePlot samples={motion(workout).motionPosition} />
			<p class="small subtle">{demo ? '合成轨迹示意' : '轨迹示意'} · 无地图底图</p>
			<a
				class="route-link"
				data-return-focus="route"
				use:restoreFocus
				href={resolve(`/workouts/[id]/route${suffix}`, { id })}
				>查看完整轨迹 <Icon kind="arrow" size={16} /></a
			>
		</aside>{/if}
{/snippet}

<style>
	.breadcrumb a {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		min-height: 44px;
	}
	.overview-grid {
		display: grid;
		gap: 24px;
		align-items: start;
	}
	.two-columns {
		grid-template-columns: minmax(600px, 1fr) minmax(300px, 360px);
	}
	.metric-stack {
		display: grid;
		gap: 20px;
		min-width: 0;
	}
	.metric-card {
		display: block;
	}
	.metric-card:hover {
		box-shadow: inset 0 0 0 1px #cbd5e7;
		color: inherit;
	}
	.metric-heading {
		display: flex;
		align-items: center;
		justify-content: space-between;
		color: #606672;
		margin-bottom: 12px;
	}
	.metric-heading h2 {
		font-size: 17px;
		color: #171923;
	}
	.metric-number {
		font-size: 30px;
		font-variant-numeric: tabular-nums;
		margin-bottom: 8px;
	}
	.metric-number span {
		font-size: 14px;
		color: #606672;
		margin-left: 8px;
	}
	.chart-caption {
		display: flex;
		justify-content: space-between;
		color: #606672;
		font-size: 12px;
		margin-top: 4px;
	}
	.route-card {
		display: grid;
		gap: 12px;
	}
	.route-card .metric-heading {
		margin-bottom: 0;
	}
	.route-link {
		display: flex;
		align-items: center;
		justify-content: space-between;
		min-height: 44px;
		color: #1769d2;
	}
	.summary-only {
		font-size: 14px;
		color: #606672;
		padding: 22px 0 8px;
	}
	.notes {
		white-space: pre-wrap;
		overflow-wrap: anywhere;
	}
	.tags {
		display: flex;
		gap: 8px;
		margin: 18px 0;
	}
	details {
		border-top: 1px solid #e6e8ee;
		margin-top: 20px;
		padding-top: 8px;
	}
	summary {
		min-height: 44px;
		padding: 10px 0;
		cursor: pointer;
	}
	@media (max-width: 700px) {
		.metric-heading h2 {
			font-size: 18px;
		}
		.metric-number span,
		.summary-only {
			font-size: 15px;
		}
		.metric-stack,
		.overview-grid {
			gap: 16px;
		}
	}
</style>
