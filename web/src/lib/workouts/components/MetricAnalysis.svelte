<script lang="ts">
	import { formatNumber } from '$lib/i18n/format';
	import { m as L } from '$lib/paraglide/messages.js';
	import { metricValueText, pace } from '$lib/analysis/presentation';
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
	const calculatedAverage = $derived(
		(demo ? undefined : statistics?.averageValue) ?? metric.average
	);
	const calculatedMaximum = $derived(
		(demo ? undefined : statistics?.maximumValue) ?? metric.maximum
	);
	const average = $derived(calculatedAverage ?? recorded.averageValue);
	const maximum = $derived(calculatedMaximum ?? recorded.maximumValue);
	const selected = $derived(metric.samples[index]);
	const runningSpeed = $derived(
		metric.key === 'speed' && workout.workoutObservation.observationSport.type === 'running'
	);
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
		value === undefined ? L.value_distance_missing() : `${formatNumber(value, 2)} km`;
</script>

<svelte:head><title>{L.metric_analysis_document({ metric: metric.title })}</title></svelte:head>
{#if !embedded}<header class="page-heading">
		<div>
			<div class="eyebrow">{L.eyebrow_metric_analysis()}</div>
			<h1>{L.metric_analysis_heading({ metric: metric.title })}</h1>
			<p class="subtle">
				{workout.workoutUserData.workoutTitle ?? L.workout_untitled()} · {dateText(
					range.rangeStart
				)}
			</p>
		</div>
	</header>{/if}
<p class="small subtle">
	{#if calculatedAverage !== undefined || calculatedMaximum !== undefined}{L.metric_calculated_note()}{:else}{L.metric_recorded_note()}{/if}
</p>
{#if average !== undefined || maximum !== undefined}<div class="summary-strip">
		<div>
			<div class="summary-label">
				{calculatedAverage !== undefined ? L.stat_calculated_average() : L.stat_recorded_average()}
			</div>
			<div class="summary-number">
				{metricValueText(average, metricKinds[metric.key], metric.key === 'speed' ? 1 : 0)}<small
					>{average !== undefined ? metric.unit : ''}</small
				>
			</div>
		</div>
		<div>
			<div class="summary-label">
				{calculatedMaximum !== undefined ? L.stat_calculated_maximum() : L.stat_recorded_maximum()}
			</div>
			<div class="summary-number">
				{metricValueText(maximum, metricKinds[metric.key], metric.key === 'speed' ? 1 : 0)}<small
					>{maximum !== undefined ? metric.unit : ''}</small
				>
			</div>
		</div>
		{#if runningSpeed}
			<div>
				<div class="summary-label">
					{calculatedAverage !== undefined ? L.stat_average_pace() : L.stat_recorded_average_pace()}
				</div>
				<div class="summary-number">{pace(average)}</div>
			</div>
			<div>
				<div class="summary-label">
					{calculatedMaximum !== undefined
						? L.stat_fastest_sample_pace()
						: L.stat_recorded_fastest_pace()}
				</div>
				<div class="summary-number">{pace(maximum)}</div>
			</div>
		{/if}
	</div>
{:else}<p class="small subtle">{L.metric_summary_missing()}</p>{/if}
{#if runningSpeed}<p class="small subtle">
		{L.metric_pace_note()}
	</p>{/if}
{#if selected}<section class="surface analysis-chart">
		<h2>
			{L.metric_chart_heading({
				metric: metric.title,
				axis: axis === 'time' ? L.label_time() : L.label_distance()
			})}
		</h2>
		<label
			>{L.metric_axis()}
			<select bind:value={axis}>
				<option value="time">{L.label_time()}</option>
				<option value="distance">{L.label_distance()}</option>
			</select>
		</label>
		<p class="small subtle">
			{L.metric_axis_note({ axis: axis === 'time' ? L.label_elapsed() : L.label_cumulative_km() })}
		</p>
		{#if axis === 'distance'}<p class="small subtle">
				{L.metric_distance_note()}
			</p>{/if}
		{#if axis === 'distance' && !hasDistance}<p role="status">
				{L.metric_distance_missing()}
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
		{#if runningSpeed}<p class="selected-pace" aria-live="polite">
				{L.metric_current_pace({ pace: pace(selected.value) })}
			</p>{/if}
		<label class="slider-label" for="sample"
			>{L.metric_select_sample()}
			<span class="subtle small">{index + 1} / {metric.samples.length}</span></label
		><input
			id="sample"
			type="range"
			min="0"
			max={metric.samples.length - 1}
			step="1"
			bind:value={index}
			aria-valuetext={runningSpeed
				? L.metric_running_sample_value({
						time: duration((Date.parse(selected.timestamp) - Date.parse(range.rangeStart)) / 1000),
						value: metricValueText(selected.value, metricKinds[metric.key], 1),
						unit: metric.unit,
						pace: pace(selected.value)
					})
				: L.metric_sample_value({
						time: duration((Date.parse(selected.timestamp) - Date.parse(range.rangeStart)) / 1000),
						value: metricValueText(selected.value, metricKinds[metric.key], 1),
						unit: metric.unit
					})}
		/>
		<div class="sample-buttons">
			<button class="button" disabled={index === 0} onclick={() => index--}
				>{L.action_previous_sample()}</button
			><button class="button" disabled={index === metric.samples.length - 1} onclick={() => index++}
				>{L.action_next_sample()}</button
			>
		</div>
		<details>
			<summary>{L.metric_sample_table_show()}</summary>
			<div class="table-scroll" role="region" aria-label={L.metric_sample_table()}>
				<table>
					<thead
						><tr
							><th>{L.label_elapsed()}</th>{#if axis === 'distance'}<th
									>{L.label_cumulative_distance()}</th
								>{/if}<th>{metric.title} ({metric.unit})</th></tr
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
		<h2>{L.metric_summary_only_title()}</h2>
		<p>{L.metric_summary_only()}</p>
	</div>{/if}
{#if !demo}<MetricDetails {workout} kind={metricKinds[metric.key]} />{/if}
{#if metric.key === 'power'}
	{#if metric.samples.length > 0}<PowerCurveAnalysis {workout} />
	{:else}<section class="section" aria-label={L.power_best_sustained()}>
			<h2>{L.power_best_sustained()}</h2>
			<p>{L.power_curve_missing()}</p>
		</section>{/if}
{/if}
{#if embedded && metric.key === 'cadence' && workout.workoutObservation.observationSport.type === 'running'}<p
		class="small subtle"
	>
		{L.running_cadence_note()}
	</p>{/if}
{#if !embedded}<section class="section">
		<h2>{L.metric_reading_guide()}</h2>
		<div class="surface">
			<p>
				{L.metric_provenance_note()}
			</p>
			{#if metric.key === 'heart-rate'}<p>
					{L.metric_heart_note()}
				</p>{/if}{#if metric.key === 'cadence' && workout.workoutObservation.observationSport.type === 'running'}<p
				>
					{L.running_cadence_note()}
				</p>{/if}
			<p class="small subtle">
				{L.metric_source_note({
					source: demo ? L.data_synthetic_response() : L.data_account_workout()
				})}
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
