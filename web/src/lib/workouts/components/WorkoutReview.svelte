<script lang="ts">
	import { m as L } from '$lib/paraglide/messages.js';
	import { metricValueText } from '$lib/analysis/presentation';
	import { sampleAt } from '$lib/workouts/timeline';
	import { nearestIndex } from '$lib/workouts/chart-data';
	import type { Workout } from '$lib/api/generated/client';
	import {
		metrics,
		metricKinds,
		motion,
		duration,
		valueText,
		common,
		recordedMetricSummary
	} from '$lib/workouts/presentation';
	import TimePointDetails from '$lib/workouts/components/TimePointDetails.svelte';
	import TimeChart from '$lib/workouts/components/TimeChart.svelte';
	import RoutePlot from '$lib/workouts/components/RoutePlot.svelte';
	import DetailDialog from '$lib/components/DetailDialog.svelte';
	import MetricAnalysis from '$lib/workouts/components/MetricAnalysis.svelte';
	import { resolve } from '$app/paths';
	import { workoutAnalysisQuery } from '$lib/analysis/query.svelte';

	let {
		workout,
		restoreFocus,
		suffix = ''
	}: {
		workout: Workout;
		restoreFocus: (node: HTMLElement) => void;
		suffix?: '' | `?scenario=${string}`;
	} = $props();
	const { query: analysis } = workoutAnalysisQuery(() => workout);
	const range = $derived(workout.workoutObservation.observationRange);
	const order = [
		'power',
		'heart-rate',
		'cadence',
		'speed',
		'altitude',
		'grade',
		'temperature',
		'step-length',
		'vertical-oscillation',
		'ground-contact-time'
	];
	const items = $derived(
		metrics(workout)
			.map((metric) => {
				if (import.meta.env.MODE === 'demo') return metric;
				const stats = analysis.data?.analysisMetrics.find(
					(m) => m.metricKind === metricKinds[metric.key]
				)?.metricStatistics;
				return {
					...metric,
					average: stats?.averageValue ?? metric.average,
					maximum: stats?.maximumValue ?? metric.maximum
				};
			})
			.sort((a, b) => order.indexOf(a.key) - order.indexOf(b.key))
	);
	const positions = $derived(motion(workout).motionPosition);
	const times = $derived(
		[
			...new Set([
				...items.flatMap((m) => m.samples.map((s) => s.timestamp)),
				...positions.map((s) => s.timestamp)
			])
		].sort((a, b) => Date.parse(a) - Date.parse(b))
	);
	const timestamps = $derived(times.map((time) => Date.parse(time)));
	const positionTimes = $derived(positions.map((sample) => Date.parse(sample.timestamp)));
	const startTime = $derived(Date.parse(range.rangeStart));
	let index = $state(0);
	let pinned = $state(false);
	let opened = $state<string | null>(null);
	let routeIndex = $state(0);
	const selectedTime = $derived(times[index]);
	let zoom = $state(1);
	let windowStart = $state(0);
	let tip = $state(false);
	let tipY = $state(0);
	let plotWidth = $state(0);

	const elapsed = $derived((Date.parse(range.rangeEnd) - startTime) / 1000);
	const windowLength = $derived(elapsed / zoom);
	const windowEnd = $derived(windowStart + windowLength);
	const selectedSeconds = $derived(selectedTime ? (timestamps[index] - startTime) / 1000 : 0);
	const cursorX = $derived(
		40 +
			Math.max(0, Math.min(1, (selectedSeconds - windowStart) / (windowLength || 1))) *
				Math.max(0, plotWidth - 52)
	);
	const cursorVisible = $derived(selectedSeconds >= windowStart && selectedSeconds <= windowEnd);
	const tipX = $derived(
		Math.max(8, Math.min(plotWidth - 232, cursorX + 242 < plotWidth ? cursorX + 16 : cursorX - 240))
	);
	function changeZoom(next: number) {
		zoom = Math.max(1, Math.min(16, next));
		windowStart = Math.max(
			0,
			Math.min(elapsed - elapsed / zoom, selectedSeconds - elapsed / zoom / 2)
		);
	}
	function step(delta: number) {
		index = Math.max(0, Math.min(times.length - 1, index + delta));
		pinned = true;
		reveal();
	}
	function reveal() {
		if (selectedSeconds < windowStart || selectedSeconds > windowEnd)
			windowStart = Math.max(
				0,
				Math.min(elapsed - windowLength, selectedSeconds - windowLength / 2)
			);
	}
	function release(event: KeyboardEvent) {
		if (event.key === 'Escape' && !opened) {
			pinned = false;
			tip = false;
		}
	}

	const positionIndex = $derived.by(() => {
		if (!selectedTime || !positionTimes.length) return -1;
		const nearest = nearestIndex(positionTimes, timestamps[index]);
		return positionTimes[nearest] === timestamps[index] ? nearest : -1;
	});
	const selectedMetric = $derived(items.find((m) => m.key === opened));
	function move(event: PointerEvent) {
		if (pinned || event.pointerType === 'touch' || !(event.currentTarget instanceof HTMLElement))
			return;
		const rect = event.currentTarget.getBoundingClientRect();
		const fraction = Math.max(
			0,
			Math.min(1, (event.clientX - rect.left - 40) / Math.max(1, rect.width - 52))
		);
		const target = startTime + (windowStart + fraction * windowLength) * 1000;
		index = nearestIndex(timestamps, target);
		tip = true;
		tipY = Math.max(8, Math.min(rect.height - 260, event.clientY - rect.top + 16));
	}
	function openRoute() {
		routeIndex =
			positionIndex >= 0 ? positionIndex : nearestIndex(positionTimes, timestamps[index]);
		opened = 'route';
	}
</script>

<svelte:window onkeydown={release} />
<div class="series-caption">
	<span>{L.chart_time_series()}</span><span>{L.chart_elapsed_axis()}</span>
</div>
<div class="review-grid" class:has-route={positions.length > 0}>
	{#if positions.length}<aside class="surface route-card">
			<div class="review-heading">
				<h2>{L.route_title()}</h2>
				<span class="small subtle">{L.action_expand()}</span>
			</div>
			<button class="map-open" onclick={openRoute} aria-label={L.route_expand()}
				><RoutePlot samples={positions} selected={positionIndex} /></button
			>
			<p class="small subtle">{L.route_no_basemap()}</p>
			<div class="route-position">
				<strong>{duration(selectedSeconds)}</strong><span
					>{L.point_cumulative({
						distance: `${valueText(sampleAt(motion(workout).motionDistance, selectedTime)?.value, 0.001, 1)} km`
					})}</span
				>
			</div>
			<p class="small subtle">
				{positionIndex >= 0 ? L.route_synced() : L.route_point_missing()}
			</p>
			<a
				data-return-focus="route"
				use:restoreFocus
				href={resolve(`/workouts/[id]/route${suffix}`, { id: workout.workoutId })}
				>{L.route_view_full()}</a
			>
		</aside>{/if}
	<section class="surface linked-panel" aria-label={L.chart_linked_region()}>
		<div class="review-heading">
			<div>
				<h2>{L.chart_linked_heading()}</h2>
				<p>{L.chart_interaction_hint()}</p>
			</div>
			<div class="zoom-actions">
				<button
					class="button"
					aria-label={L.chart_zoom_in()}
					disabled={zoom === 1}
					onclick={() => changeZoom(zoom / 2)}>−</button
				><button
					class="button"
					aria-label={L.chart_zoom_out()}
					disabled={zoom === 16}
					onclick={() => changeZoom(zoom * 2)}>＋</button
				><button class="button" onclick={() => changeZoom(1)}>{L.chart_full_range()}</button>
			</div>
		</div>
		{#if selectedTime}<div class="time-controls">
				<label for="review-time"
					>{L.label_elapsed()} <strong>{duration(selectedSeconds)}</strong></label
				><button
					class="button"
					aria-label={L.point_previous()}
					onclick={() => step(-1)}
					disabled={index === 0}>←</button
				><input
					id="review-time"
					aria-label={L.point_choose()}
					type="range"
					min="0"
					max={times.length - 1}
					value={index}
					oninput={(event) => {
						index = Number(event.currentTarget.value);
						pinned = true;
						reveal();
					}}
					aria-valuetext={duration(selectedSeconds)}
				/><button
					class="button"
					aria-label={L.point_next()}
					onclick={() => step(1)}
					disabled={index === times.length - 1}>→</button
				><button class="button" onclick={() => (pinned = !pinned)} aria-pressed={pinned}
					>{pinned ? L.point_unpin() : L.point_pin()}</button
				>
			</div>
			<div class="mobile-details">
				<TimePointDetails {workout} time={selectedTime} {pinned} compact />
			</div>{/if}
		<div class="accessible-details" aria-live={pinned ? 'polite' : 'off'}>
			<TimePointDetails {workout} time={selectedTime} {pinned} />
		</div>
		<div
			bind:clientWidth={plotWidth}
			class="linked-plots"
			onpointerleave={() => (tip = false)}
			role="group"
			aria-label={L.chart_aligned_metrics()}
			onpointermove={move}
		>
			{#each items as metric (metric.key)}
				{@const sample = sampleAt(metric.samples, selectedTime)}
				{@const recorded = recordedMetricSummary(workout, metric.key)}
				{@const statistic =
					metric.average ?? metric.maximum ?? recorded.averageValue ?? recorded.maximumValue}
				{@const statisticLabel =
					metric.average !== undefined
						? L.stat_calculated_average()
						: metric.maximum !== undefined
							? L.stat_calculated_maximum()
							: recorded.averageValue !== undefined
								? L.stat_recorded_average()
								: recorded.maximumValue !== undefined
									? L.stat_recorded_maximum()
									: L.stat_unavailable()}
				<button
					class="metric-open"
					data-return-focus={`metric-${metric.key}`}
					use:restoreFocus
					onclick={() => (opened = metric.key)}
					aria-label={L.metric_expand({ metric: metric.title })}
				>
					<div class="metric-heading">
						<h3>{metric.title}</h3>
						<span class="subtle"
							>{#if statistic !== undefined}{metricValueText(
									statistic,
									metricKinds[metric.key],
									metric.key === 'speed' ? 1 : 0
								)}
								{metric.unit} ·
							{/if}{statisticLabel}</span
						><strong class="current"
							>{L.metric_current_value({
								value: metricValueText(
									sample?.value,
									metricKinds[metric.key],
									metric.key === 'speed' ? 1 : 0
								),
								unit: sample ? metric.unit : ''
							})}</strong
						>
					</div>
					{#if metric.samples.length}<TimeChart
							{metric}
							maxGapSeconds={analysis.data?.analysisMaxGapSeconds ?? 120}
							start={range.rangeStart}
							end={range.rangeEnd}
							{selectedTime}
							compact
							viewStart={windowStart}
							viewEnd={windowEnd}
						/>{:else}<p class="subtle">{L.metric_recorded_only()}</p>{/if}
				</button>
			{:else}<p class="subtle">{L.metric_missing_samples()}</p>{/each}
			{#if selectedTime && cursorVisible}<div
					class="linked-guide"
					style:left={`${cursorX}px`}
				></div>{/if}
			{#if selectedTime && cursorVisible && (tip || pinned)}<div
					class="linked-tooltip"
					style:left={`${tipX}px`}
					style:top={`${tipY}px`}
					aria-hidden="true"
				>
					<TimePointDetails {workout} time={selectedTime} {pinned} />
				</div>{/if}
		</div>
		<p class="chart-foot">{L.chart_gap_note()}</p>
	</section>
	<section class="surface training-summary">
		<h2>{L.workout_summary()}</h2>
		<dl>
			<div>
				<dt>{L.label_sport()}</dt>
				<dd>
					{workout.workoutObservation.observationSport.type === 'cycling'
						? L.sport_cycling()
						: L.sport_running()}
				</dd>
			</div>
			<div>
				<dt>{L.stat_recorded_speed()}</dt>
				<dd>{valueText(common(workout).summarySpeed.averageValue, 3.6, 1)} km/h</dd>
			</div>
			<div>
				<dt>{L.data_source()}</dt>
				<dd>
					{import.meta.env.MODE === 'demo' ? L.data_synthetic_workout() : L.data_workout_record()}
				</dd>
			</div>
		</dl>
		<h3>{L.workout_notes()}</h3>
		<p class="notes">{workout.workoutUserData.workoutNotes ?? L.workout_notes_empty()}</p>
		<div class="tags">
			{#each workout.workoutUserData.workoutTags as tag, i (i)}<span class="tag">{tag}</span>{/each}
		</div>
	</section>
</div>
{#if opened === 'route'}
	<DetailDialog title={L.route_details()} onclose={() => (opened = null)}>
		<div class="route-modal-grid">
			<div>
				<RoutePlot samples={positions} selected={routeIndex} onSelect={(i) => (routeIndex = i)} />
				<p class="small subtle">{L.route_select_sample()}</p>
			</div>
			<TimePointDetails {workout} time={positions[routeIndex]?.timestamp} pinned />
		</div>
		<p class="subtle">{L.route_no_basemap()}</p>
		<p>
			{L.point_elapsed_value({
				time: duration((Date.parse(positions[routeIndex].timestamp) - startTime) / 1000)
			})}
		</p>
		<label
			>{L.route_sample_picker()}<input
				type="range"
				min="0"
				max={positions.length - 1}
				bind:value={routeIndex}
			/></label
		>
	</DetailDialog>
{:else if selectedMetric}
	<DetailDialog
		title={L.metric_details_title({ metric: selectedMetric.title })}
		onclose={() => (opened = null)}
	>
		<MetricAnalysis {workout} metric={selectedMetric} initialTime={selectedTime} embedded />
		<a
			data-return-focus={`metric-${selectedMetric.key}`}
			href={resolve(`/workouts/[id]/metrics/[metric]${suffix}`, {
				id: workout.workoutId,
				metric: selectedMetric.key
			})}>{L.action_standalone_page()}</a
		>
	</DetailDialog>
{/if}

<style>
	.series-caption {
		display: flex;
		justify-content: space-between;
		font-size: 11px;
		color: var(--muted);
		margin: 0 0 12px;
	}
	.review-grid {
		display: grid;
		gap: 16px;
		align-items: start;
	}
	.review-heading {
		display: flex;
		align-items: start;
		justify-content: space-between;
		gap: 12px;
		margin-bottom: 16px;
	}
	.review-heading h2 {
		font-size: 14px;
		font-weight: 600;
	}
	.review-heading p {
		font-size: 11px;
		color: var(--muted);
		margin: 5px 0 0;
	}
	.zoom-actions {
		display: flex;
		gap: 5px;
	}
	.linked-panel {
		min-width: 0;
		padding: 16px;
		border-radius: 4px;
	}
	.button {
		font-size: 11px;
		min-height: 36px;
		padding: 6px 9px;
		border-radius: 4px;
	}
	.time-controls {
		display: flex;
		align-items: center;
		gap: 8px;
		flex-wrap: wrap;
		padding-bottom: 16px;
		border-bottom: 1px solid var(--line);
		margin-bottom: 18px;
	}
	.time-controls label {
		display: flex;
		gap: 8px;
		font-size: 11px;
		color: var(--muted);
	}
	.time-controls strong {
		color: var(--text);
		font-variant-numeric: tabular-nums;
	}
	.time-controls input {
		flex: 1;
		min-width: 80px;
		width: 0;
	}
	.linked-plots {
		position: relative;
		min-width: 0;
		touch-action: pan-y;
	}
	.metric-open {
		display: block;
		width: 100%;
		padding: 10px 0 16px;
		margin-bottom: 12px;
		background: transparent;
		border: 0;
		border-radius: 0;
		color: inherit;
		text-align: left;
		cursor: zoom-in;
	}
	.metric-open + .metric-open {
		border-top: 1px solid var(--line);
	}
	.metric-open:hover h3 {
		color: var(--blue);
	}
	.metric-heading {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: 6px 10px;
		font-variant-numeric: tabular-nums;
		margin-bottom: 4px;
	}
	.metric-heading h3 {
		font-size: 13px;
		font-weight: 600;
	}
	.metric-heading > span {
		font-size: 11px;
	}
	.current {
		margin-left: auto;
		font-size: 12px;
		font-weight: 500;
	}
	.linked-guide {
		position: absolute;
		top: 0;
		bottom: 30px;
		width: 1px;
		background: var(--muted);
		opacity: 0.8;
		pointer-events: none;
		z-index: 1;
	}
	.linked-tooltip {
		position: absolute;
		width: 224px;
		max-width: calc(100% - 16px);
		padding: 15px 16px;
		background: var(--panel);
		border: 1px solid var(--line);
		border-radius: 8px;
		box-shadow: 0 9px 30px #0002;
		pointer-events: none;
		z-index: 2;
	}
	.mobile-details {
		display: none;
	}
	.chart-foot {
		font-size: 10px;
		color: var(--muted);
		margin: 8px 0 0;
		line-height: 1.8;
	}
	input[type='range'] {
		min-height: 36px;
		accent-color: var(--blue);
	}
	.map-open {
		display: block;
		width: 100%;
		padding: 0;
		border: 0;
		background: transparent;
		cursor: zoom-in;
	}
	.route-card {
		display: grid;
		gap: 10px;
		padding: 16px;
		border-radius: 4px;
	}
	.route-card .review-heading {
		margin-bottom: 0;
	}
	.route-card p,
	.route-card a {
		font-size: 11px;
	}
	.route-card a {
		display: flex;
		align-items: center;
		min-height: 36px;
		border: 1px solid var(--line);
		border-radius: 4px;
		padding: 6px 10px;
	}
	.route-position {
		display: flex;
		justify-content: space-between;
		gap: 8px;
		flex-wrap: wrap;
		border-top: 1px solid var(--line);
		padding-top: 12px;
		font-size: 11px;
		font-variant-numeric: tabular-nums;
	}
	.route-position strong {
		font-size: 13px;
	}
	.training-summary {
		padding: 16px;
		border-radius: 4px;
	}
	.training-summary h2 {
		font-size: 13px;
	}
	.training-summary dl {
		margin: 12px 0;
	}
	.training-summary dl div {
		display: flex;
		justify-content: space-between;
		gap: 10px;
		font-size: 11px;
		border-bottom: 1px solid var(--line);
		padding: 10px 0;
	}
	.training-summary dt,
	.training-summary h3 {
		color: var(--muted);
	}
	.training-summary dd {
		margin: 0;
		font-variant-numeric: tabular-nums;
	}
	.training-summary h3 {
		font-size: 11px;
		font-weight: 400;
		margin: 22px 0 8px;
	}
	.notes {
		font-size: 12px;
		line-height: 1.9;
		white-space: pre-wrap;
		overflow-wrap: anywhere;
	}
	.tags {
		display: flex;
		flex-wrap: wrap;
		gap: 6px;
		margin-top: 12px;
	}
	.tags .tag {
		font-size: 10px;
		padding: 2px 5px;
	}
	.route-modal-grid {
		display: grid;
		grid-template-columns: minmax(0, 1fr) 230px;
		gap: 24px;
		align-items: start;
	}
	.route-modal-grid + p {
		font-size: 11px;
		color: var(--muted);
	}
	@media (min-width: 1100px) {
		.has-route > .linked-panel {
			grid-column: 1;
			grid-row: 1 / span 2;
		}
		.has-route > .route-card {
			grid-column: 2;
			grid-row: 1;
		}
		.has-route > .training-summary {
			grid-column: 2;
			grid-row: 2;
		}
		.has-route {
			grid-template-columns: minmax(0, 1fr) 310px;
			grid-template-rows: min-content 1fr;
		}
	}
	@media (max-width: 1099px) {
		.route-card {
			grid-row: 1;
		}
		.training-summary {
			grid-row: 3;
		}
		.route-card {
			max-width: none;
		}
	}
	@media (max-width: 700px) {
		.linked-panel {
			padding: 14px 10px;
		}
		.time-controls input {
			order: 5;
			flex-basis: 100%;
		}
		.time-controls label {
			flex-basis: 100%;
		}
		.button {
			min-height: 44px;
		}
		.mobile-details {
			display: block;
			padding: 14px;
			background: var(--soft);
			border-radius: 4px;
			margin-bottom: 16px;
		}
		.linked-tooltip {
			display: none;
		}
		.metric-heading .current {
			font-size: 11px;
		}
		.route-modal-grid {
			grid-template-columns: 1fr;
		}
		.review-heading {
			flex-wrap: wrap;
		}
		.route-card {
			padding: 14px;
		}
		.metric-open {
			padding: 10px 0 12px;
		}
	}
	.accessible-details {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
	}
	@media (max-width: 700px) {
		.accessible-details {
			display: none;
		}
	}
</style>
