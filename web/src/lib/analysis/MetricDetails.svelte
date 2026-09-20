<script lang="ts">
	import { m as L } from '$lib/paraglide/messages.js';
	import type { Workout, MetricKind } from '$lib/api/generated/client';
	import { workoutAnalysisQuery } from './query.svelte';
	import { metricInfo } from './presentation';
	import { valueText } from '$lib/workouts/presentation';
	import Statistics from './Statistics.svelte';
	import AnalysisPlot from './AnalysisPlot.svelte';
	import Zones from './Zones.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	let { workout, kind }: { workout: Workout; kind: MetricKind } = $props();
	const { query, refresh } = workoutAnalysisQuery(() => workout);
	const metric = $derived(query.data?.analysisMetrics.find((m) => m.metricKind === kind));
	const relationships = $derived(
		query.data?.analysisRelationships.filter(
			(r) => r.relationshipX === kind || r.relationshipY === kind
		) ?? []
	);
</script>

<section class="section" aria-label={L.analysis_statistics_region()}>
	<h2>{L.analysis_statistics()}</h2>
	{#if query.isPending}<p role="status">{L.analysis_loading()}</p>{:else if query.isError}<Feedback
			error={query.error}
			retry={refresh}
		/>{:else if metric}<Statistics {metric} />{:else}<p>{L.analysis_metric_unavailable()}</p>{/if}
	{#if query.data && (kind === 'powerMetric' || kind === 'heartRateMetric')}<div
			class="surface section"
		>
			<Zones
				zones={kind === 'powerMetric'
					? query.data.analysisPowerZones
					: query.data.analysisHeart.heartZones}
				unit={kind === 'powerMetric' ? 'W' : 'bpm'}
				title={kind === 'powerMetric' ? L.analysis_power_zones() : L.analysis_heart_zones()}
			/>
		</div>{/if}
</section>
{#if relationships.length}<section class="section">
		<h2>{L.analysis_relationships()}</h2>
		{#each relationships as relationship, i (i)}
			{@const x = metricInfo[relationship.relationshipX]}{@const y =
				metricInfo[relationship.relationshipY]}
			<div class="surface relationship">
				<h3>{L.analysis_pair({ x: x.title, y: y.title })}</h3>
				<p class="small subtle">
					{L.analysis_correlation_summary({
						correlation: valueText(relationship.relationshipCorrelation, 1, 3),
						count: relationship.relationshipSampleCount
					})}
				</p>
				<AnalysisPlot
					kind="scatter"
					xLabel={`${x.title} (${x.unit})`}
					yLabel={`${y.title} (${y.unit})`}
					points={relationship.relationshipPoints.map((p) => [
						p.relationshipXValue * x.factor,
						p.relationshipYValue * y.factor
					])}
				/>
				<details>
					<summary>{L.analysis_aligned_samples()}</summary>
					<div
						class="table-scroll"
						role="region"
						aria-label={L.analysis_pair_table({ x: x.title, y: y.title })}
					>
						<table>
							<thead><tr><th>{x.title} ({x.unit})</th><th>{y.title} ({y.unit})</th></tr></thead
							><tbody
								>{#each relationship.relationshipPoints as point, j (j)}<tr
										><td>{valueText(point.relationshipXValue, x.factor, 2)}</td><td
											>{valueText(point.relationshipYValue, y.factor, 2)}</td
										></tr
									>{/each}</tbody
							>
						</table>
					</div>
				</details>
			</div>{/each}
		<p class="small subtle">{L.analysis_correlation_note()}</p>
	</section>{/if}

<style>
	h2 {
		margin-bottom: 12px;
	}
	h3 {
		font-size: 16px;
	}
	.relationship {
		margin-bottom: 16px;
	}
	summary {
		padding: 12px 0;
		cursor: pointer;
	}
</style>
