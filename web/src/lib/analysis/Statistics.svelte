<script lang="ts">
	import type { MetricAnalysis } from '$lib/api/generated/client';
	import { metricInfo, metricValueText } from './presentation';
	import { duration } from '$lib/workouts/presentation';
	import AnalysisPlot from './AnalysisPlot.svelte';
	let { metric }: { metric: MetricAnalysis } = $props();
	const info = $derived(metricInfo[metric.metricKind]);
</script>

<div class="surface">
	<dl class="stats-rows">
		{#each [['平均', metric.metricStatistics.averageValue], ['最大', metric.metricStatistics.maximumValue], ['最小', metric.metricStatistics.minimumValue], ['非零平均', metric.metricAverageExcludingZeros]] as row, index (index)}<div
			>
				<dt>{row[0]}</dt>
				<dd>
					{metricValueText(typeof row[1] === 'number' ? row[1] : undefined, metric.metricKind, 2)}
					{info.unit}
				</dd>
			</div>{/each}
		<div>
			<dt>有效覆盖</dt>
			<dd>{duration(metric.metricCoveredSeconds)}</dd>
		</div>
		<div>
			<dt>真实采样数</dt>
			<dd>{metric.metricSampleCount}</dd>
		</div>
	</dl>
	<h3>{info.title}分布</h3>
	{#if metric.metricDistribution.length}
		<AnalysisPlot
			kind="bar"
			xLabel={`${info.title} (${info.unit})`}
			yLabel="分钟"
			labels={metric.metricDistribution.map(
				(b) =>
					`${metricValueText(b.binLower, metric.metricKind, 1)}–${metricValueText(b.binUpper, metric.metricKind, 1)}`
			)}
			points={metric.metricDistribution.map((b, i) => [i, b.binSeconds / 60])}
		/>
		<details>
			<summary>查看分布数据</summary>
			<div class="table-scroll" role="region" aria-label={`${info.title}分布表`}>
				<table>
					<thead><tr><th>区间 ({info.unit})</th><th>时间</th></tr></thead><tbody
						>{#each metric.metricDistribution as bin, i (i)}<tr
								><td
									>{metricValueText(bin.binLower, metric.metricKind, 2)}–{metricValueText(
										bin.binUpper,
										metric.metricKind,
										2
									)}</td
								><td>{duration(bin.binSeconds)}</td></tr
							>{/each}</tbody
					>
				</table>
			</div>
		</details>
	{:else}<p class="subtle">没有足够的连续采样，无法计算时间分布。</p>{/if}
</div>

<style>
	h3 {
		font-size: 16px;
		margin-top: 20px;
	}
	summary {
		cursor: pointer;
		padding: 12px 0;
	}
</style>
