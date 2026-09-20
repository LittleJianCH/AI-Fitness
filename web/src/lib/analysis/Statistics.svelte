<script lang="ts">
	import { m as L } from '$lib/paraglide/messages.js';
	import type { MetricAnalysis } from '$lib/api/generated/client';
	import { metricInfo, metricValueText } from './presentation';
	import { duration } from '$lib/workouts/presentation';
	import AnalysisPlot from './AnalysisPlot.svelte';
	let { metric }: { metric: MetricAnalysis } = $props();
	const info = $derived(metricInfo[metric.metricKind]);
</script>

<div class="surface">
	<dl class="stats-rows">
		{#each [[L.stat_average(), metric.metricStatistics.averageValue], [L.stat_maximum(), metric.metricStatistics.maximumValue], [L.stat_minimum(), metric.metricStatistics.minimumValue], [L.stat_nonzero_average(), metric.metricAverageExcludingZeros]] as row, index (index)}<div
			>
				<dt>{row[0]}</dt>
				<dd>
					{metricValueText(typeof row[1] === 'number' ? row[1] : undefined, metric.metricKind, 2)}
					{info.unit}
				</dd>
			</div>{/each}
		<div>
			<dt>{L.stat_coverage()}</dt>
			<dd>{duration(metric.metricCoveredSeconds)}</dd>
		</div>
		<div>
			<dt>{L.stat_sample_count()}</dt>
			<dd>{metric.metricSampleCount}</dd>
		</div>
	</dl>
	<h3>{L.stat_distribution({ metric: info.title })}</h3>
	{#if metric.metricDistribution.length}
		<AnalysisPlot
			kind="bar"
			xLabel={`${info.title} (${info.unit})`}
			yLabel={L.unit_minutes()}
			labels={metric.metricDistribution.map(
				(b) =>
					`${metricValueText(b.binLower, metric.metricKind, 1)}–${metricValueText(b.binUpper, metric.metricKind, 1)}`
			)}
			points={metric.metricDistribution.map((b, i) => [i, b.binSeconds / 60])}
		/>
		<details>
			<summary>{L.stat_distribution_data()}</summary>
			<div
				class="table-scroll"
				role="region"
				aria-label={L.stat_distribution_table({ metric: info.title })}
			>
				<table>
					<thead
						><tr><th>{L.stat_interval_unit({ unit: info.unit })}</th><th>{L.label_time()}</th></tr
						></thead
					><tbody
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
	{:else}<p class="subtle">{L.stat_distribution_missing()}</p>{/if}
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
