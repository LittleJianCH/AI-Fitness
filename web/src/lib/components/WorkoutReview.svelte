<script lang="ts">
	import { nearestTimeIndex, sampleAt } from '$lib/workouts/timeline';
	import type { Workout } from '$lib/api/generated/client';
	import {
		metrics,
		motion,
		duration,
		valueText,
		common,
		recordedMetricSummary
	} from '$lib/workouts/presentation';
	import TimePointDetails from './TimePointDetails.svelte';
	import TimeChart from './TimeChart.svelte';
	import RoutePlot from './RoutePlot.svelte';
	import DetailDialog from './DetailDialog.svelte';
	import MetricAnalysis from './MetricAnalysis.svelte';
	import { resolve } from '$app/paths';
	let {
		workout,
		restoreFocus,
		suffix = ''
	}: {
		workout: Workout;
		restoreFocus: (node: HTMLElement) => void;
		suffix?: '' | `?scenario=${string}`;
	} = $props();
	const range = $derived(workout.workoutObservation.observationRange);
	const order = ['speed', 'power', 'cadence', 'heart-rate', 'altitude'];
	const items = $derived(
		metrics(workout).sort((a, b) => order.indexOf(a.key) - order.indexOf(b.key))
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

	const elapsed = $derived((Date.parse(range.rangeEnd) - Date.parse(range.rangeStart)) / 1000);
	const windowLength = $derived(elapsed / zoom);
	const windowEnd = $derived(windowStart + windowLength);
	const selectedSeconds = $derived(
		selectedTime ? (Date.parse(selectedTime) - Date.parse(range.rangeStart)) / 1000 : 0
	);
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

	const positionIndex = $derived(
		positions.findIndex((p) => Date.parse(p.timestamp) === Date.parse(selectedTime))
	);
	const selectedMetric = $derived(items.find((m) => m.key === opened));
	function move(event: PointerEvent) {
		if (pinned || event.pointerType === 'touch' || !(event.currentTarget instanceof HTMLElement))
			return;
		const rect = event.currentTarget.getBoundingClientRect();
		const fraction = Math.max(
			0,
			Math.min(1, (event.clientX - rect.left - 40) / Math.max(1, rect.width - 52))
		);
		const target = Date.parse(range.rangeStart) + (windowStart + fraction * windowLength) * 1000;
		index = nearestTimeIndex(times, target);
		tip = true;
		tipY = Math.max(8, Math.min(rect.height - 260, event.clientY - rect.top + 16));
	}
	function openRoute() {
		routeIndex =
			positionIndex >= 0
				? positionIndex
				: nearestTimeIndex(
						positions.map((p) => p.timestamp),
						Date.parse(selectedTime)
					);
		opened = 'route';
	}
</script>

<svelte:window onkeydown={release} />
<div class="series-caption"><span>时间序列</span><span>横轴：经过时间</span></div>
<div class="review-grid" class:has-route={positions.length > 0}>
	{#if positions.length}<aside class="surface route-card">
			<div class="review-heading">
				<h2>轨迹</h2>
				<span class="small subtle">点击放大 ↗</span>
			</div>
			<button class="map-open" onclick={openRoute} aria-label="放大轨迹地图"
				><RoutePlot samples={positions} selected={positionIndex} /></button
			>
			<p class="small subtle">轨迹示意 · 无地图底图</p>
			<div class="route-position">
				<strong>{duration(selectedSeconds)}</strong><span
					>累计 {valueText(sampleAt(motion(workout).motionDistance, selectedTime)?.value, 0.001, 1)} km</span
				>
			</div>
			<p class="small subtle">
				{positionIndex >= 0 ? '标记与图表时间点同步' : '此时间点未记录位置'}
			</p>
			<a
				data-return-focus="route"
				use:restoreFocus
				href={resolve(`/workouts/[id]/route${suffix}`, { id: workout.workoutId })}>查看完整轨迹 →</a
			>
		</aside>{/if}
	<section class="surface linked-panel" aria-label="联动训练图表">
		<div class="review-heading">
			<div>
				<h2>同一时刻，一起看</h2>
				<p>移动查看 · 点击图表放大 · Esc 解除固定</p>
			</div>
			<div class="zoom-actions">
				<button
					class="button"
					aria-label="缩小时间范围"
					disabled={zoom === 1}
					onclick={() => changeZoom(zoom / 2)}>−</button
				><button
					class="button"
					aria-label="放大时间范围"
					disabled={zoom === 16}
					onclick={() => changeZoom(zoom * 2)}>＋</button
				><button class="button" onclick={() => changeZoom(1)}>全程</button>
			</div>
		</div>
		{#if selectedTime}<div class="time-controls">
				<label for="review-time">经过时间 <strong>{duration(selectedSeconds)}</strong></label
				><button
					class="button"
					aria-label="上一个时间点"
					onclick={() => step(-1)}
					disabled={index === 0}>←</button
				><input
					id="review-time"
					aria-label="选择时间点"
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
					aria-label="下一个时间点"
					onclick={() => step(1)}
					disabled={index === times.length - 1}>→</button
				><button class="button" onclick={() => (pinned = !pinned)} aria-pressed={pinned}
					>{pinned ? '解除固定' : '固定时间点'}</button
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
			aria-label="按时间对齐的指标"
			onpointermove={move}
		>
			{#each items as metric (metric.key)}
				{@const sample = sampleAt(metric.samples, selectedTime)}
				{@const recorded = recordedMetricSummary(workout, metric.key)}
				{@const statistic =
					metric.average ?? metric.maximum ?? recorded.averageValue ?? recorded.maximumValue}
				{@const statisticLabel =
					metric.average !== undefined
						? '计算平均'
						: metric.maximum !== undefined
							? '计算最大'
							: recorded.averageValue !== undefined
								? '记录平均'
								: recorded.maximumValue !== undefined
									? '记录最大'
									: '统计暂不可用'}
				<button
					class="metric-open"
					data-return-focus={`metric-${metric.key}`}
					use:restoreFocus
					onclick={() => (opened = metric.key)}
					aria-label={`放大${metric.title}图表`}
				>
					<div class="metric-heading">
						<h3>{metric.title}</h3>
						<span class="subtle"
							>{#if statistic !== undefined}{valueText(
									statistic,
									metric.factor,
									metric.key === 'speed' ? 1 : 0
								)}
								{metric.unit} ·
							{/if}{statisticLabel}</span
						><strong class="current"
							>此刻 {valueText(sample?.value, metric.factor, metric.key === 'speed' ? 1 : 0)}
							{sample ? metric.unit : ''}</strong
						>
					</div>
					{#if metric.samples.length}<TimeChart
							{metric}
							start={range.rangeStart}
							end={range.rangeEnd}
							{selectedTime}
							compact
							viewStart={windowStart}
							viewEnd={windowEnd}
						/>{:else}<p class="subtle">仅记录汇总 · 无逐点曲线</p>{/if}
				</button>
			{:else}<p class="subtle">这条训练缺少逐点采样，暂时无法计算指标平均值或最大值。</p>{/each}
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
		<p class="chart-foot">横轴：经过时间（时:分:秒）。缺失样本保留断线，不补零。</p>
	</section>
	<section class="surface training-summary">
		<h2>训练摘要</h2>
		<dl>
			<div>
				<dt>运动类型</dt>
				<dd>
					{workout.workoutObservation.observationSport.type === 'cycling' ? '骑行' : '跑步'}
				</dd>
			</div>
			<div>
				<dt>平均速度 · 记录</dt>
				<dd>{valueText(common(workout).summarySpeed.averageValue, 3.6, 1)} km/h</dd>
			</div>
			<div>
				<dt>数据来源</dt>
				<dd>{import.meta.env.MODE === 'demo' ? '合成训练' : '训练记录'}</dd>
			</div>
		</dl>
		<h3>我的备注</h3>
		<p class="notes">{workout.workoutUserData.workoutNotes ?? '暂无备注'}</p>
		<div class="tags">
			{#each workout.workoutUserData.workoutTags as tag, i (i)}<span class="tag">{tag}</span>{/each}
		</div>
	</section>
</div>
{#if opened === 'route'}
	<DetailDialog title="轨迹详情" onclose={() => (opened = null)}>
		<div class="route-modal-grid">
			<div>
				<RoutePlot samples={positions} selected={routeIndex} onSelect={(i) => (routeIndex = i)} />
				<p class="small subtle">点击路线选择样本</p>
			</div>
			<TimePointDetails {workout} time={positions[routeIndex]?.timestamp} pinned />
		</div>
		<p class="subtle">轨迹示意 · 无地图底图</p>
		<p>
			{duration(
				(Date.parse(positions[routeIndex].timestamp) - Date.parse(range.rangeStart)) / 1000
			)} · 经过时间
		</p>
		<label
			>选择轨迹样本<input
				type="range"
				min="0"
				max={positions.length - 1}
				bind:value={routeIndex}
			/></label
		>
	</DetailDialog>
{:else if selectedMetric}
	<DetailDialog title={`${selectedMetric.title}详情`} onclose={() => (opened = null)}>
		<MetricAnalysis {workout} metric={selectedMetric} initialTime={selectedTime} embedded />
		<a
			data-return-focus={`metric-${selectedMetric.key}`}
			href={resolve(`/workouts/[id]/metrics/[metric]${suffix}`, {
				id: workout.workoutId,
				metric: selectedMetric.key
			})}>独立页面查看</a
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
