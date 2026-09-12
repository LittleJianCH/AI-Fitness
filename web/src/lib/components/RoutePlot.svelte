<script lang="ts">
	import type { TimedPosition } from '$lib/api/generated/client';
	let { samples, selected = 0 }: { samples: TimedPosition[]; selected?: number } = $props();
	const points = $derived.by(() => {
		if (!samples.length) return [];
		const lat = samples.map((s) => s.value.latitude),
			lon = samples.map((s) => s.value.longitude);
		const minLat = Math.min(...lat),
			maxLat = Math.max(...lat),
			minLon = Math.min(...lon),
			maxLon = Math.max(...lon);
		const scale = Math.min(300 / (maxLon - minLon || 1), 200 / (maxLat - minLat || 1));
		return samples.map((s) => ({
			x: 180 + (s.value.longitude - (minLon + maxLon) / 2) * scale,
			y: 140 - (s.value.latitude - (minLat + maxLat) / 2) * scale
		}));
	});
	const active = $derived(points[selected]);
</script>

<svg
	viewBox="0 0 360 280"
	role="img"
	aria-label={import.meta.env.MODE === 'demo' ? '合成轨迹示意，无地图底图' : '轨迹示意，无地图底图'}
	class="route-plot"
>
	<rect width="360" height="280" fill="#f2f5f3" />
	<path
		d="M0 70H360M0 140H360M0 210H360M90 0V280M180 0V280M270 0V280"
		stroke="#e4eae6"
		stroke-width="1"
	/>
	<polyline
		points={points.map((p) => `${p.x},${p.y}`).join(' ')}
		fill="none"
		stroke="#1769D2"
		stroke-width="3"
		stroke-linejoin="round"
	/>
	{#if points[0]}<circle
			cx={points[0].x}
			cy={points[0].y}
			r="6"
			fill="#fff"
			stroke="#1769D2"
			stroke-width="3"
		/>{/if}
	{#if active}<circle
			cx={active.x}
			cy={active.y}
			r="5"
			fill="#171923"
			stroke="#fff"
			stroke-width="2"
		/>{/if}
</svg>

<style>
	.route-plot {
		display: block;
		width: 100%;
		max-height: 520px;
		border-radius: 12px;
	}
</style>
