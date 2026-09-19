<script lang="ts">
	import { metricValueText } from '$lib/analysis/presentation';
	import type { Workout } from '$lib/api/generated/client';
	import { metrics, metricKinds, motion, duration, valueText } from '$lib/workouts/presentation';
	import { sampleAt } from '$lib/workouts/timeline';

	let {
		workout,
		time,
		pinned = false,
		compact = false
	}: { workout: Workout; time?: string; pinned?: boolean; compact?: boolean } = $props();
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
		metrics(workout).sort((a, b) => order.indexOf(a.key) - order.indexOf(b.key))
	);
	const distance = $derived(sampleAt(motion(workout).motionDistance, time));
	const start = $derived(workout.workoutObservation.observationRange.rangeStart);
</script>

<div class="point-details">
	<div class="point-title">
		<strong>{time ? duration((Date.parse(time) - Date.parse(start)) / 1000) : '未记录'}</strong
		><span>{pinned ? '已固定' : '时间点明细'}</span>
	</div>
	<p class="point-context">
		累计 {distance ? `${valueText(distance.value, 0.001, 1)} km` : '未记录'}<br />{time
			? new Date(time).toLocaleTimeString('zh-CN', { hour12: false })
			: '未记录'} · 本地记录时间
	</p>
	<dl class:compact>
		{#each items as metric (metric.key)}{@const sample = sampleAt(metric.samples, time)}
			<div>
				<dt><i style:background={`var(--metric-${metric.key})`}></i>{metric.title}</dt>
				<dd>
					{metricValueText(
						sample?.value,
						metricKinds[metric.key],
						metric.key === 'speed' ? 1 : 0
					)}{#if sample}<small>{metric.unit}</small>{/if}
				</dd>
			</div>{/each}
	</dl>
</div>

<style>
	.point-title {
		display: flex;
		justify-content: space-between;
		gap: 12px;
		font-size: 12px;
	}
	.point-title span {
		font-size: 11px;
		color: var(--muted);
	}
	.point-context {
		font-size: 11px;
		color: var(--muted);
		margin: 8px 0 12px;
		line-height: 1.7;
		font-variant-numeric: tabular-nums;
	}
	dl {
		margin: 0;
	}
	dl div {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: 12px;
		padding: 5px 0;
		font-size: 13px;
	}
	dt {
		display: flex;
		align-items: center;
		gap: 8px;
		color: var(--muted);
	}
	dd {
		margin: 0;
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}
	small {
		font-size: 11px;
		font-weight: 400;
		color: var(--muted);
		margin-left: 4px;
	}
	i {
		width: 7px;
		height: 7px;
		border-radius: 50%;
	}
	.compact {
		display: grid;
		grid-template-columns: 1fr 1fr;
		column-gap: 14px;
	}
	.compact div {
		font-size: 12px;
		flex-wrap: wrap;
		gap: 2px 8px;
	}
</style>
