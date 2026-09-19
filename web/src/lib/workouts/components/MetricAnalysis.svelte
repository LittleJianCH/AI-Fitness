<script lang="ts">
	import { metricValueText } from '$lib/analysis/presentation';
	import type { Workout } from '$lib/api/generated/client';
	import {
		metricKinds,
		motion,
		dateText,
		duration,
		recordedMetricSummary,
		type Metric
	} from '$lib/workouts/presentation';
	import { distanceCoordinates, nearestIndex, sampleTimes } from '$lib/workouts/chart-data';
	import { untrack } from 'svelte';
	import MetricDetails from '$lib/analysis/MetricDetails.svelte';
	import { workoutAnalysisQuery } from '$lib/analysis/query.svelte';
	import PowerCurveAnalysis from '$lib/workouts/components/PowerCurveAnalysis.svelte';
	import TimeChart from '$lib/workouts/components/TimeChart.svelte';

	const demo = import.meta.env.MODE === 'demo';

	let {
		workout,
		metric,
		initialTime,
		embedded = false
	}: { workout: Workout; metric: Metric; initialTime?: string; embedded?: boolean } = $props();
	let index = $state(
		untrack(() => {
			if (!initialTime) return 0;
			return nearestIndex(sampleTimes(metric.samples), Date.parse(initialTime));
		})
	);
	const { query: analysis } = workoutAnalysisQuery(() => workout);
	const statistics = $derived(
		analysis.data?.analysisMetrics.find((m) => m.metricKind === metricKinds[metric.key])
			?.metricStatistics
	);
	const range = $derived(workout.workoutObservation.observationRange);
	const recorded = $derived(recordedMetricSummary(workout, metric.key));
	const average = $derived(
		(demo ? metric.average : statistics?.averageValue) ?? recorded.averageValue
	);
	const maximum = $derived(
		(demo ? metric.maximum : statistics?.maximumValue) ?? recorded.maximumValue
	);
	const selected = $derived(metric.samples[index]);
	let axis = $state<'time' | 'distance'>('time');
	const distances = $derived(
		distanceCoordinates(
			metric.samples,
			motion(workout).motionDistance,
			analysis.data?.analysisMaxGapSeconds ?? 120
		)
	);
	const hasDistance = $derived(distances.some((value) => value !== undefined));
	const distanceText = (value: number | undefined) =>
		value === undefined ? '距离未记录' : `${value.toFixed(2)} km`;
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
	{#if (demo ? metric.average : statistics?.averageValue) !== undefined || (demo ? metric.maximum : statistics?.maximumValue) !== undefined}计算统计包含真实零值；超过
		2 分钟的空档不计入时间加权平均。{:else}当前显示记录自带的汇总。曲线保留原始采样；缺失记录不补零。{/if}
</p>
{#if average !== undefined || maximum !== undefined}<div class="summary-strip">
		<div>
			<div class="summary-label">
				{(demo ? metric.average : statistics?.averageValue) !== undefined ? '计算平均' : '记录平均'}
			</div>
			<div class="summary-number">
				{metricValueText(average, metricKinds[metric.key], metric.key === 'speed' ? 1 : 0)}<small
					>{average !== undefined ? metric.unit : ''}</small
				>
			</div>
		</div>
		<div>
			<div class="summary-label">
				{(demo ? metric.maximum : statistics?.maximumValue) !== undefined ? '计算最大' : '记录最大'}
			</div>
			<div class="summary-number">
				{metricValueText(maximum, metricKinds[metric.key], metric.key === 'speed' ? 1 : 0)}<small
					>{maximum !== undefined ? metric.unit : ''}</small
				>
			</div>
		</div>
	</div>
{:else}<p class="small subtle">此指标暂无汇总统计，可以查看下方真实采样。</p>{/if}
{#if selected}<section class="surface analysis-chart">
		<h2>{metric.title}{axis === 'time' ? '时间' : '距离'}曲线</h2>
		<label
			>图表横轴
			<select bind:value={axis}>
				<option value="time">时间</option>
				<option value="distance">距离</option>
			</select>
		</label>
		<p class="small subtle">
			横轴为{axis === 'time' ? '经过时间' : '累计距离（km）'} · 超过 2 分钟的采样间隔以断线显示
		</p>
		{#if axis === 'distance'}<p class="small subtle">
				距离按记录时间对齐；仅在相邻距离记录间插值，不跨空档或距离重置外推。指标数值仍为原始样本。
			</p>{/if}
		{#if axis === 'distance' && !hasDistance}<p role="status">
				没有可对齐的距离采样，请切换时间轴查看原始曲线。
			</p>{:else}
			<TimeChart
				{metric}
				distanceCoordinates={axis === 'distance' ? distances : undefined}
				maxGapSeconds={analysis.data?.analysisMaxGapSeconds ?? 120}
				start={range.rangeStart}
				end={range.rangeEnd}
				selectedTime={selected.timestamp}
				onSelect={(i) => (index = i)}
			/>
		{/if}
		<div class="sample-value" aria-live="polite">
			<span>{duration((Date.parse(selected.timestamp) - Date.parse(range.rangeStart)) / 1000)}</span
			>{#if axis === 'distance'}<span>{distanceText(distances[index])}</span>{/if}<strong
				style:color={`var(--metric-${metric.key})`}
				>{metricValueText(selected.value, metricKinds[metric.key], 1)}
				<small>{metric.unit}</small></strong
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
			aria-valuetext={`${duration((Date.parse(selected.timestamp) - Date.parse(range.rangeStart)) / 1000)}，${metricValueText(selected.value, metricKinds[metric.key], 1)} ${metric.unit}`}
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
					<thead
						><tr
							><th>经过时间</th>{#if axis === 'distance'}<th>累计距离</th>{/if}<th
								>{metric.title} ({metric.unit})</th
							></tr
						></thead
					><tbody
						>{#each metric.samples as sample, sampleIndex (sample.timestamp)}<tr
								><td
									>{duration(
										(Date.parse(sample.timestamp) - Date.parse(range.rangeStart)) / 1000
									)}</td
								>{#if axis === 'distance'}<td>{distanceText(distances[sampleIndex])}</td>{/if}<td
									>{metricValueText(sample.value, metricKinds[metric.key], 1)}</td
								></tr
							>{/each}</tbody
					>
				</table>
			</div>
		</details>
	</section>{:else}<div class="status">
		<h2>这次训练仅包含汇总数据</h2>
		<p>没有逐点样本，因此不展示曲线。汇总值按其实际来源标注为计算或记录。</p>
	</div>{/if}
{#if !demo}<MetricDetails {workout} kind={metricKinds[metric.key]} />{/if}
{#if metric.key === 'power'}
	{#if metric.samples.length > 0}<PowerCurveAnalysis {workout} />
	{:else}<section class="section" aria-label="最佳持续功率">
			<h2>最佳持续功率</h2>
			<p>没有足够的连续功率采样，无法计算最佳持续功率。</p>
		</section>{/if}
{/if}
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
					心率分区使用训练开始时生效的个人参数。运动后恢复读数暂不在当前模型范围内。
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
		flex-wrap: wrap;
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
