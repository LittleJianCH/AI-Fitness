<script lang="ts">
	const demo = import.meta.env.MODE === 'demo';
	import type { Workout } from '$lib/api/generated/client';
	import { dateText, duration, valueText, type Metric } from '$lib/workouts/presentation';
	import TimeChart from './TimeChart.svelte';
	let { workout, metric }: { workout: Workout; metric: Metric } = $props();
	let index = $state(0);
	const range = $derived(workout.workoutObservation.observationRange);
	const selected = $derived(metric.samples[index]);
</script>

<svelte:head><title>{metric.title}分析 · AI Fitness</title></svelte:head>
<header class="page-heading">
	<div>
		<div class="eyebrow">METRIC ANALYSIS</div>
		<h1>{metric.title}分析</h1>
		<p class="subtle">
			{workout.workoutUserData.workoutTitle ?? '未命名训练'} · {dateText(range.rangeStart)}
		</p>
	</div>
</header>
<p class="small subtle">
	平均值包含真实零值，按相邻样本线性变化做时间加权；超过 2 分钟的空档不计入。最大值取所有真实样本。
</p>
<div class="summary-strip">
	<div>
		<div class="summary-label">计算平均</div>
		<div class="summary-number">
			{valueText(metric.average, metric.factor, metric.key === 'speed' ? 1 : 0)}<small
				>{metric.unit}</small
			>
		</div>
	</div>
	<div>
		<div class="summary-label">计算最大</div>
		<div class="summary-number">
			{valueText(metric.maximum, metric.factor, metric.key === 'speed' ? 1 : 0)}<small
				>{metric.unit}</small
			>
		</div>
	</div>
</div>
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
			><strong style:color={metric.color}
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
		<p>没有逐点样本，因此不展示曲线。上方统计值来自后端计算结果。</p>
	</div>{/if}
<section class="section">
	<h2>如何阅读这些数据</h2>
	<div class="surface">
		<p>
			平均与最大值由后端根据当前修订的完整采样计算。曲线按原始采样时间排列，保留真实零值；显示中的断线与抽样不会参与统计计算。
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
		accent-color: #1769d2;
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
