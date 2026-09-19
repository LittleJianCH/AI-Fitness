<script lang="ts">
	import { onMount } from 'svelte';
	import { init, use, type EChartsType } from 'echarts/core';
	import { LineChart } from 'echarts/charts';
	import { GridComponent, MarkLineComponent, MarkPointComponent } from 'echarts/components';
	import { SVGRenderer } from 'echarts/renderers';
	import { chartPoints, nearestIndex, sampleTimes } from '$lib/workouts/chart-data';
	import { sampleAt } from '$lib/workouts/timeline';
	import { duration, type Metric } from '$lib/workouts/presentation';

	use([LineChart, GridComponent, MarkLineComponent, MarkPointComponent, SVGRenderer]);
	let {
		metric,
		start,
		end,
		preview = false,
		compact = false,
		selectedTime,
		viewStart = 0,
		viewEnd,
		maxGapSeconds = 120,
		onSelect
	}: {
		metric: Metric;
		start: string;
		end: string;
		preview?: boolean;
		compact?: boolean;
		selectedTime?: string;
		viewStart?: number;
		viewEnd?: number;
		maxGapSeconds?: number;
		onSelect?: (index: number) => void;
	} = $props();
	const timestamps = $derived(sampleTimes(metric.samples));
	const points = $derived(chartPoints(metric.samples, start, metric.factor, maxGapSeconds));
	const startTime = $derived(Date.parse(start));
	let host: HTMLDivElement;
	let dark = $state(false);
	const color = $derived(
		dark
			? ({
					power: '#b6a0ed',
					'heart-rate': '#ec9baf',
					cadence: '#e2bc70',
					speed: '#8fc0f4',
					altitude: '#a7c7b1',
					grade: '#a7c7b1',
					temperature: '#e2bc70',
					'step-length': '#8fc0f4',
					'vertical-oscillation': '#e2bc70',
					'ground-contact-time': '#a7c7b1'
				}[metric.key] ?? metric.color)
			: metric.color
	);
	let chart = $state<EChartsType>();
	onMount(() => {
		const media = matchMedia('(prefers-color-scheme: dark)');
		const readTheme = () => {
			const choice = document.documentElement.dataset.theme;
			dark = choice === 'dark' || (choice !== 'light' && media.matches);
		};
		readTheme();
		media.addEventListener('change', readTheme);
		const themeObserver = new MutationObserver(readTheme);
		themeObserver.observe(document.documentElement, {
			attributes: true,
			attributeFilter: ['data-theme']
		});
		const instance = init(host, undefined, { renderer: 'svg' });
		chart = instance;
		let pinned = false;
		const selectAt = (event: { offsetX: number; offsetY: number }) => {
			if (preview || !onSelect || !instance.containPixel('grid', [event.offsetX, event.offsetY]))
				return;
			const position: unknown = instance.convertFromPixel('grid', [event.offsetX, event.offsetY]);
			if (!Array.isArray(position) || typeof position[0] !== 'number') return;
			const seconds = position[0];
			if (timestamps.length) onSelect(nearestIndex(timestamps, startTime + seconds * 1000));
		};
		instance.getZr().on('mousemove', (event) => {
			if (!pinned) selectAt(event);
		});
		instance.getZr().on('click', (event) => {
			selectAt(event);
			pinned = true;
		});
		const release = (event: KeyboardEvent) => {
			if (event.key === 'Escape') pinned = false;
		};
		window.addEventListener('keydown', release);
		let resizeFrame = 0;
		const observer = new ResizeObserver(() => {
			cancelAnimationFrame(resizeFrame);
			resizeFrame = requestAnimationFrame(() => instance.resize());
		});
		observer.observe(host);
		return () => {
			observer.disconnect();
			themeObserver.disconnect();
			media.removeEventListener('change', readTheme);
			cancelAnimationFrame(resizeFrame);
			window.removeEventListener('keydown', release);
			instance.dispose();
		};
	});
	$effect(() => {
		if (!chart) return;
		chart.setOption(
			{
				animation: false,
				grid: {
					outerBoundsMode: compact ? 'none' : 'auto',
					top: preview || compact ? 8 : 24,
					right: 12,
					bottom: preview ? 8 : compact ? 25 : 40,
					left: preview ? 4 : compact ? 40 : 52
				},
				xAxis: {
					type: 'value',
					min: viewStart,
					max: viewEnd ?? (Date.parse(end) - Date.parse(start)) / 1000,
					splitNumber: compact ? 3 : 5,
					show: !preview,
					axisLabel: {
						formatter: (v: number) => duration(v),
						alignMinLabel: 'left',
						alignMaxLabel: 'right',
						hideOverlap: true,
						color: dark ? '#a0afc4' : '#647286'
					},
					splitLine: { show: false }
				},
				yAxis: {
					type: 'value',
					scale: true,
					show: !preview,
					name: compact ? undefined : metric.unit,
					splitNumber: compact ? 2 : 5,
					axisLabel: { color: dark ? '#a0afc4' : '#647286' },
					splitLine: { lineStyle: { color: '#8995a633' } }
				},
				series: [
					{
						type: 'line',
						data: points,
						showSymbol: false,
						connectNulls: false,
						smooth: false,
						lineStyle: { color, width: compact || preview ? 1.6 : 2 },
						areaStyle: { color, opacity: compact ? 0.16 : 0.07 }
					}
				]
			},
			true
		);
	});
	$effect(() => {
		if (!chart) return;
		const candidate = sampleAt(metric.samples, selectedTime);
		const seconds = candidate ? (Date.parse(candidate.timestamp) - Date.parse(start)) / 1000 : 0;
		const sample =
			candidate &&
			seconds >= viewStart &&
			seconds <= (viewEnd ?? (Date.parse(end) - Date.parse(start)) / 1000)
				? candidate
				: undefined;
		chart.setOption({
			series: [
				{
					markPoint: {
						silent: true,
						symbol: 'circle',
						symbolSize: 7,
						label: { show: false },
						itemStyle: { color, borderColor: dark ? '#1a2433' : '#fff', borderWidth: 1.5 },
						data: sample
							? [
									{
										coord: [
											(Date.parse(sample.timestamp) - Date.parse(start)) / 1000,
											sample.value * metric.factor
										]
									}
								]
							: []
					},
					markLine:
						selectedTime && !preview && !compact
							? {
									silent: true,
									symbol: 'none',
									label: { show: false },
									lineStyle: { color: dark ? '#a0afc4' : '#647286' },
									data: [{ xAxis: (Date.parse(selectedTime) - Date.parse(start)) / 1000 }]
								}
							: { data: [] }
				}
			]
		});
	});
</script>

<div bind:this={host} class:preview class:compact class="time-chart" aria-hidden="true"></div>

<style>
	.time-chart {
		width: 100%;
		overflow: hidden;
		height: 340px;
		touch-action: pan-y;
	}
	.compact {
		height: 110px;
		pointer-events: none;
	}
	.preview {
		height: 116px;
		pointer-events: none;
	}
	@media (max-width: 700px) {
		.time-chart {
			height: 270px;
		}
		.compact {
			height: 112px;
		}
		.preview {
			height: 100px;
		}
	}
</style>
