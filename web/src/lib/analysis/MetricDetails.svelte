<script lang="ts">
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

<section class="section" aria-label="指标统计与分布">
	<h2>统计与分布</h2>
	{#if query.isPending}<p role="status">正在读取分析…</p>{:else if query.isError}<Feedback
			error={query.error}
			retry={refresh}
		/>{:else if metric}<Statistics {metric} />{:else}<p>此指标暂无可用分析。</p>{/if}
	{#if query.data && (kind === 'powerMetric' || kind === 'heartRateMetric')}<div
			class="surface section"
		>
			<Zones
				zones={kind === 'powerMetric'
					? query.data.analysisPowerZones
					: query.data.analysisHeart.heartZones}
				unit={kind === 'powerMetric' ? 'W' : 'bpm'}
				title={kind === 'powerMetric' ? '功率分区' : '心率分区'}
			/>
		</div>{/if}
</section>
{#if relationships.length}<section class="section">
		<h2>相关分析</h2>
		{#each relationships as relationship, i (i)}
			{@const x = metricInfo[relationship.relationshipX]}{@const y =
				metricInfo[relationship.relationshipY]}
			<div class="surface relationship">
				<h3>{x.title}与{y.title}</h3>
				<p class="small subtle">
					样本相关系数 {valueText(relationship.relationshipCorrelation, 1, 3)} · 对齐样本 {relationship.relationshipSampleCount}
					· 图中最多 600 点
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
					<summary>查看对齐样本</summary>
					<div class="table-scroll" role="region" aria-label={`${x.title}与${y.title}样本表`}>
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
		<p class="small subtle">由后端按真实时间对齐，不跨空档外推；相关性不表示因果关系。</p>
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
