<script lang="ts">
	const demo = import.meta.env.MODE === 'demo';
	import type { Workout } from '$lib/api/generated/client';
	import {
		dateText,
		duration,
		valueText,
		recordedMetricSummary,
		type Metric
	} from '$lib/workouts/presentation';
	import { nearestTimeIndex } from '$lib/workouts/timeline';
	import { untrack } from 'svelte';
	import TimeChart from './TimeChart.svelte';
	let {
		workout,
		metric,
		initialTime,
		embedded = false
	}: { workout: Workout; metric: Metric; initialTime?: string; embedded?: boolean } = $props();
	let index = $state(
		untrack(() => {
			if (!initialTime) return 0;
			return nearestTimeIndex(
				metric.samples.map((s) => s.timestamp),
				Date.parse(initialTime)
			);
		})
	);
	const range = $derived(workout.workoutObservation.observationRange);
	const recorded = $derived(recordedMetricSummary(workout, metric.key));
	const average = $derived(metric.average ?? recorded.averageValue);
	const maximum = $derived(metric.maximum ?? recorded.maximumValue);
	const selected = $derived(metric.samples[index]);
</script>

<svelte:head><title>{metric.title}分析 · AI Fitness</title></svelte:head>
{#if !embedded}<header class="page-heading">
		<div>
			<div class="eyebrow">METRIC ANALYSIS</div>
			<h1>{metric.title}分析</h1>
			<p class="subtle">
				{workout.workoutUserData.workoutTitle ?? '未命名训练'} · {dateText(range.rangeStart)}
			</p>
		</div>
	</header>{/if}
<p class="small subtle">
	{#if metric.average !== undefined || metric.maximum !== undefined}计算统计包含真实零值；超过 2
		分钟的空档不计入时间加权平均。{:else}当前显示记录自带的汇总。曲线保留原始采样；缺失记录不补零。{/if}
</p>
{#if average !== undefined || maximum !== undefined}<div class="summary-strip">
		<div>
			<div class="summary-label">{metric.average !== undefined ? '计算平均' : '记录平均'}</div>
			<div class="summary-number">
				{valueText(average, metric.factor, metric.key === 'speed' ? 1 : 0)}<small
					>{average !== undefined ? metric.unit : ''}</small
				>
			</div>
		</div>
		<div>
			<div class="summary-label">{metric.maximum !== undefined ? '计算最大' : '记录最大'}</div>
			<div class="summary-number">
				{valueText(maximum, metric.factor, metric.key === 'speed' ? 1 : 0)}<small
					>{maximum !== undefined ? metric.unit : ''}</small
				>
			</div>
		</div>
	</div>
{:else}<p class="small subtle">此指标暂无汇总统计，可以查看下方真实采样。</p>{/if}
{#if selected}<section class="surface analysis-chart">
		<h2>{metric.title}时间曲线</h2>
		<p class="small subtle">横轴为经过时间 · 超过 2 分钟的采样间隔以断线显示</p>
		<TimeChart
			{metric}
			start={range.rangeStart}
			end={range.rangeEnd}
			selectedTime={selected.timestamp}
			onSelect={(i) => (index = i)}
		/>
		<div class="sample-value" aria-live="polite">
			<span>{duration((Date.parse(selected.timestamp) - Date.parse(range.rangeStart)) / 1000)}</span
			><strong style:color={`var(--metric-${metric.key})`}
				>{valueText(selected.value, metric.factor, 1)} <small>{metric.unit}</small></strong
			>
		</div>
		<label class="slider-label" for="sample"
			>选择真实样本 <span class="subtle small">{index + 1} / {metric.samples.length}</span></label
		><input
			id="sample"
			type="range"
			min="0"
			max={metric.samples.length - 1}
			step="1"
			bind:value={index}
			aria-valuetext={`${duration((Date.parse(selected.timestamp) - Date.parse(range.rangeStart)) / 1000)}，${valueText(selected.value, metric.factor, 1)} ${metric.unit}`}
		/>
		<div class="sample-buttons">
			<button class="button" disabled={index === 0} onclick={() => index--}>上一个样本</button
			><button class="button" disabled={index === metric.samples.length - 1} onclick={() => index++}
				>下一个样本</button
			>
		</div>
		<details>
			<summary>查看样本数据表</summary>
			<div class="table-scroll" role="region" aria-label="指标样本表">
				<table>
					<thead><tr><th>经过时间</th><th>{metric.title} ({metric.unit})</th></tr></thead><tbody
						>{#each metric.samples as sample (sample.timestamp)}<tr
								><td
									>{duration(
										(Date.parse(sample.timestamp) - Date.parse(range.rangeStart)) / 1000
									)}</td
								><td>{valueText(sample.value, metric.factor, 1)}</td></tr
							>{/each}</tbody
					>
				</table>
			</div>
		</details>
	</section>{:else}<div class="status">
		<h2>这次训练仅包含汇总数据</h2>
		<p>没有逐点样本，因此不展示曲线。汇总值按其实际来源标注为计算或记录。</p>
	</div>{/if}
{#if embedded && metric.key === 'cadence' && workout.workoutObservation.observationSport.type === 'running'}<p
		class="small subtle"
	>
		跑步步频使用双脚总步数（步/分钟）。
	</p>{/if}
{#if !embedded}<section class="section">
		<h2>如何阅读这些数据</h2>
		<div class="surface">
			<p>
				标为“计算”的统计来自后端对当前修订采样的计算；标为“记录”的统计直接来自训练记录。曲线按原始时间排列，保留真实零值，显示中的断线或缩放不改变统计值。
			</p>
			{#if metric.key === 'heart-rate'}<p>
					当前接口没有提供已配置的心率分区或运动后恢复计算，因此这里展示心率记录本身。
				</p>{/if}{#if metric.key === 'cadence' && workout.workoutObservation.observationSport.type === 'running'}<p
				>
					跑步步频使用双脚总步数（步/分钟）。
				</p>{/if}
			<p class="small subtle">
				数据来源：{demo ? '合成演示响应' : '当前账号的训练记录'} · 时间显示使用本地时区
			</p>
		</div>
	</section>
{/if}

<style>
	h2 {
		font-size: 20px;
	}
	.analysis-chart > p {
		margin-top: 6px;
	}
	.sample-value {
		display: flex;
		align-items: baseline;
		gap: 20px;
		font-variant-numeric: tabular-nums;
		margin: 12px 0;
	}
	.sample-value strong {
		font-size: 26px;
	}
	.sample-value small {
		font-size: 15px;
		font-weight: 400;
	}
	.slider-label {
		display: flex;
		justify-content: space-between;
		gap: 12px;
		margin-top: 20px;
	}
	input[type='range'] {
		width: 100%;
		min-height: 44px;
		accent-color: var(--blue);
	}
	.sample-buttons {
		display: flex;
		flex-wrap: wrap;
		gap: 12px;
		margin: 10px 0 20px;
	}
	summary {
		cursor: pointer;
		min-height: 44px;
		padding: 10px 0;
	}
	.section p + p {
		margin-top: 14px;
	}
	.status p {
		margin-top: 10px;
	}
</style>
