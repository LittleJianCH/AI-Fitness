<script lang="ts">
	import { onMount } from 'svelte';
	import { init, use, type EChartsType } from 'echarts/core';
	import { LineChart } from 'echarts/charts';
	import { GridComponent, MarkPointComponent } from 'echarts/components';
	import { SVGRenderer } from 'echarts/renderers';
	import type { PowerCurvePoint } from '$lib/api/generated/client';
	import { duration } from '$lib/workouts/presentation';
	use([LineChart, GridComponent, MarkPointComponent, SVGRenderer]);
	let {
		points,
		selectedDuration,
		onSelect
	}: { points: PowerCurvePoint[]; selectedDuration: number; onSelect: (seconds: number) => void } =
		$props();
	let host: HTMLDivElement;
	let chart = $state<EChartsType>();
	let color = $state('#7658bd');
	let textColor = $state('#647286');
	onMount(() => {
		const instance = init(host, undefined, { renderer: 'svg' });
		chart = instance;
		const theme = () => {
			color = getComputedStyle(host).getPropertyValue('--metric-power').trim();
			textColor = getComputedStyle(host).color;
		};
		theme();
		const media = matchMedia('(prefers-color-scheme: dark)');
		media.addEventListener('change', theme);
		const themeObserver = new MutationObserver(theme);
		themeObserver.observe(document.documentElement, {
			attributes: true,
			attributeFilter: ['data-theme']
		});
		const resize = new ResizeObserver(() => instance.resize());
		resize.observe(host);
		let pinned = false;
		const selectAt = (event: { offsetX: number; offsetY: number }) => {
			if (!instance.containPixel('grid', [event.offsetX, event.offsetY])) return;
			const position: unknown = instance.convertFromPixel('grid', [event.offsetX, event.offsetY]);
			if (!Array.isArray(position) || typeof position[0] !== 'number') return;
			const seconds = position[0];
			let nearest: PowerCurvePoint | undefined;
			for (const point of points) {
				if (
					!nearest ||
					Math.abs(Math.log(point.durationSeconds / seconds)) <
						Math.abs(Math.log(nearest.durationSeconds / seconds))
				)
					nearest = point;
			}
			if (nearest) onSelect(nearest.durationSeconds);
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
		return () => {
			resize.disconnect();
			themeObserver.disconnect();
			media.removeEventListener('change', theme);
			window.removeEventListener('keydown', release);
			instance.dispose();
		};
	});
	$effect(() => {
		const selected = points.find((point) => point.durationSeconds === selectedDuration);
		chart?.setOption(
			{
				animation: false,
				grid: { top: 30, right: 20, bottom: 40, left: 55 },
				xAxis: {
					type: 'log',
					min: 1,
					max: Math.max(5, ...points.map((point) => point.durationSeconds)),
					axisLabel: { formatter: duration, color: textColor, hideOverlap: true },
					splitLine: { show: false }
				},
				yAxis: {
					type: 'value',
					name: 'W',
					min: 0,
					axisLabel: { color: textColor },
					splitLine: { lineStyle: { color: '#8995a633' } }
				},
				series: [
					{
						type: 'line',
						smooth: false,
						symbol: 'circle',
						symbolSize: 6,
						data: points.map((point) => [point.durationSeconds, point.best?.averagePower ?? null]),
						lineStyle: { color, width: 2 },
						itemStyle: { color },
						markPoint: {
							symbol: 'circle',
							symbolSize: 11,
							label: { show: false },
							data: selected?.best
								? [{ coord: [selected.durationSeconds, selected.best.averagePower] }]
								: []
						}
					}
				]
			},
			true
		);
	});
</script>

<div bind:this={host} class="chart subtle" aria-hidden="true"></div>

<style>
	.chart {
		width: 100%;
		height: 340px;
		touch-action: pan-y;
	}
	@media (max-width: 700px) {
		.chart {
			height: 270px;
		}
	}
</style>
