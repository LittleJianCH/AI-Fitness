<script lang="ts">
	import { onMount } from 'svelte';
	import { init, use, type EChartsType } from 'echarts/core';
	import { LineChart } from 'echarts/charts';
	import { GridComponent, MarkLineComponent } from 'echarts/components';
	import { SVGRenderer } from 'echarts/renderers';
	import { chartPoints, duration, type Metric } from '$lib/workouts/presentation';
	use([LineChart, GridComponent, MarkLineComponent, SVGRenderer]);
	let {
		metric,
		start,
		end,
		preview = false,
		selectedTime,
		onSelect
	}: {
		metric: Metric;
		start: string;
		end: string;
		preview?: boolean;
		selectedTime?: string;
		onSelect?: (index: number) => void;
	} = $props();
	let host: HTMLDivElement;
	let chart = $state<EChartsType>();
	onMount(() => {
		const instance = init(host, undefined, { renderer: 'svg' });
		chart = instance;
		let pinned = false;
		const selectAt = (event: { offsetX: number; offsetY: number }) => {
			if (preview || !onSelect || !instance.containPixel('grid', [event.offsetX, event.offsetY]))
				return;
			const position: unknown = instance.convertFromPixel('grid', [event.offsetX, event.offsetY]);
			if (!Array.isArray(position) || typeof position[0] !== 'number') return;
			const seconds = position[0];
			let nearest = 0;
			metric.samples.forEach((sample, i) => {
				if (
					Math.abs((Date.parse(sample.timestamp) - Date.parse(start)) / 1000 - seconds) <
					Math.abs(
						(Date.parse(metric.samples[nearest].timestamp) - Date.parse(start)) / 1000 - seconds
					)
				)
					nearest = i;
			});
			if (metric.samples.length) onSelect(nearest);
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
					top: preview ? 8 : 24,
					right: 12,
					bottom: preview ? 8 : 40,
					left: preview ? 4 : 52
				},
				xAxis: {
					type: 'value',
					min: 0,
					max: (Date.parse(end) - Date.parse(start)) / 1000,
					show: !preview,
					axisLabel: {
						formatter: (v: number) => duration(v).replace(/^00:/, ''),
						hideOverlap: true,
						color: '#606672'
					},
					splitLine: { show: false }
				},
				yAxis: {
					type: 'value',
					scale: true,
					show: !preview,
					name: metric.unit,
					axisLabel: { color: '#606672' },
					splitLine: { lineStyle: { color: '#ECEEF3' } }
				},
				series: [
					{
						type: 'line',
						data: chartPoints(metric.samples, start, metric.factor),
						showSymbol: false,
						connectNulls: false,
						smooth: false,
						lineStyle: { color: metric.color, width: preview ? 1.7 : 2 },
						areaStyle: preview ? { color: metric.color, opacity: 0.05 } : undefined,
						markLine:
							selectedTime && !preview
								? {
										silent: true,
										symbol: 'none',
										label: { show: false },
										lineStyle: { color: '#606672' },
										data: [{ xAxis: (Date.parse(selectedTime) - Date.parse(start)) / 1000 }]
									}
								: { data: [] }
					}
				]
			},
			true
		);
	});
</script>

<div bind:this={host} class:preview class="time-chart" aria-hidden="true"></div>

<style>
	.time-chart {
		width: 100%;
		height: 340px;
		touch-action: pan-y;
	}
	.preview {
		height: 116px;
		pointer-events: none;
	}
	@media (max-width: 700px) {
		.time-chart {
			height: 270px;
		}
		.preview {
			height: 100px;
		}
	}
</style>
