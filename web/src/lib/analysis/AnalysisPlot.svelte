<script lang="ts">
	import { formatLocale } from '$lib/i18n/format';
	import { onMount } from 'svelte';
	import { init, use, type EChartsType } from 'echarts/core';
	import { BarChart, ScatterChart, LineChart } from 'echarts/charts';
	import { GridComponent, TooltipComponent, LegendComponent } from 'echarts/components';
	import { SVGRenderer } from 'echarts/renderers';
	use([
		BarChart,
		ScatterChart,
		LineChart,
		GridComponent,
		TooltipComponent,
		LegendComponent,
		SVGRenderer
	]);
	let {
		kind,
		xLabel,
		yLabel,
		points = [],
		labels,
		series
	}: {
		kind: 'bar' | 'scatter' | 'line';
		xLabel: string;
		yLabel: string;
		points?: (number | null)[][];
		labels?: string[];
		series?: { name: string; values: (number | null)[] }[];
	} = $props();
	let host: HTMLDivElement;
	let chart = $state<EChartsType>();
	let textColor = $state('#647286');
	onMount(() => {
		const readTheme = () => (textColor = getComputedStyle(host).color);
		readTheme();
		const media = matchMedia('(prefers-color-scheme: dark)');
		media.addEventListener('change', readTheme);
		const theme = new MutationObserver(readTheme);
		theme.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
		const instance = init(host, undefined, { renderer: 'svg' });
		chart = instance;
		const resize = new ResizeObserver(() => instance.resize());
		resize.observe(host);
		return () => {
			resize.disconnect();
			theme.disconnect();
			media.removeEventListener('change', readTheme);
			instance.dispose();
		};
	});
	$effect(() => {
		chart?.setOption(
			{
				animation: false,
				color: ['#7350C7', '#D43A4A', '#1769D2'],
				grid: { top: 44, left: 60, right: 24, bottom: 65 },
				tooltip: {
					trigger: kind === 'line' ? 'axis' : 'item',
					confine: true,
					renderMode: 'richText',
					formatter:
						kind === 'scatter'
							? (params: unknown) => {
									if (
										!params ||
										typeof params !== 'object' ||
										!('value' in params) ||
										!Array.isArray(params.value)
									)
										return '';
									const [x, y] = params.value;
									return typeof x === 'number' && typeof y === 'number'
										? `${xLabel}: ${x.toLocaleString(formatLocale(), { maximumFractionDigits: 2 })}\n${yLabel}: ${y.toLocaleString(formatLocale(), { maximumFractionDigits: 2 })}`
										: '';
								}
							: undefined
				},
				legend: series ? { textStyle: { color: textColor } } : undefined,
				xAxis: {
					type: labels ? 'category' : 'value',
					data: labels,
					name: xLabel,
					nameLocation: 'middle',
					nameGap: 40,
					axisLabel: { color: textColor, hideOverlap: true },
					nameTextStyle: { color: textColor },
					splitLine: { show: false },
					scale: true
				},
				yAxis: {
					type: 'value',
					name: yLabel,
					nameTextStyle: { color: textColor },
					axisLabel: { color: textColor },
					splitLine: { lineStyle: { color: '#8995a633' } },
					scale: kind === 'scatter'
				},
				series: series
					? series.map((s) => ({
							name: s.name,
							type: 'line',
							data: s.values,
							connectNulls: false,
							showSymbol: false,
							smooth: false
						}))
					: [{ type: kind, data: points, symbolSize: 5, connectNulls: false }]
			},
			true
		);
	});
</script>

<div class="plot" bind:this={host} aria-hidden="true"></div>

<style>
	.plot {
		width: 100%;
		overflow: hidden;
		height: 290px;
		color: var(--muted);
		min-width: 0;
	}
	@media (max-width: 700px) {
		.plot {
			height: 250px;
		}
	}
</style>
