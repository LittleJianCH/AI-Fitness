<script lang="ts">
	import { m as L } from '$lib/paraglide/messages.js';
	import type { TimedPosition } from '$lib/api/generated/client';

	let {
		samples,
		selected = 0,
		onSelect
	}: { samples: TimedPosition[]; selected?: number; onSelect?: (index: number) => void } = $props();
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
	const finish = $derived(points.at(-1));
	function choose(event: MouseEvent) {
		if (!onSelect || !(event.currentTarget instanceof HTMLElement)) return;
		if (event.detail === 0) {
			onSelect(Math.min(samples.length - 1, Math.max(0, selected) + 1));
			return;
		}
		const rect = event.currentTarget.querySelector('svg')?.getBoundingClientRect();
		if (!rect) return;
		const scale = Math.min(rect.width / 360, rect.height / 280);
		const x = (event.clientX - rect.left - (rect.width - 360 * scale) / 2) / scale;
		const y = (event.clientY - rect.top - (rect.height - 280 * scale) / 2) / scale;
		let best = Math.max(0, selected);
		points.forEach((p, i) => {
			if (Math.hypot(p.x - x, p.y - y) < Math.hypot(points[best].x - x, points[best].y - y))
				best = i;
		});
		onSelect(best);
	}
</script>

{#snippet graphic()}
	<svg
		viewBox="0 0 360 280"
		role="img"
		aria-label={import.meta.env.MODE === 'demo'
			? L.route_synthetic_description()
			: L.route_description()}
		class="route-plot"
	>
		<rect width="360" height="280" fill="var(--map-land)" />
		<path
			d="M0 70H360M0 140H360M0 210H360M90 0V280M180 0V280M270 0V280"
			stroke="var(--line)"
			stroke-width=".6"
		/>
		<text x="337" y="27" text-anchor="middle" fill="var(--muted)" font-size="12">↑</text><text
			x="337"
			y="42"
			text-anchor="middle"
			fill="var(--muted)"
			font-size="9">N</text
		>

		<polyline
			points={points.map((p) => `${p.x},${p.y}`).join(' ')}
			fill="none"
			stroke="var(--route-full)"
			stroke-width="3"
			stroke-linejoin="round"
		/>
		{#if selected >= 0}<polyline
				points={points
					.slice(0, selected + 1)
					.map((p) => `${p.x},${p.y}`)
					.join(' ')}
				fill="none"
				stroke="var(--metric-speed)"
				stroke-width="3"
				stroke-linejoin="round"
				stroke-linecap="round"
			/>{/if}
		{#if finish}<rect
				x={finish.x - 4}
				y={finish.y - 4}
				width="8"
				height="8"
				fill="var(--panel)"
				stroke="var(--text)"
				stroke-width="2"
			/>{/if}

		{#if points[0]}<circle
				cx={points[0].x}
				cy={points[0].y}
				r="6"
				fill="var(--panel)"
				stroke="var(--route-start)"
				stroke-width="3"
			/>{/if}
		{#if active}<circle
				cx={active.x}
				cy={active.y}
				r="10"
				fill="var(--metric-speed)"
				opacity=".2"
			/><circle
				cx={active.x}
				cy={active.y}
				r="5"
				fill="var(--metric-speed)"
				stroke="var(--panel)"
				stroke-width="2"
			/>{/if}
	</svg>
{/snippet}
{#if onSelect}<button class="interactive-route" onclick={choose} aria-label={L.route_choose_time()}
		>{@render graphic()}</button
	>{:else}{@render graphic()}{/if}
<div class="route-legend">
	<span>{L.route_start_legend()}</span><span>{L.route_end_legend()}</span><span
		>{L.route_current_legend()}</span
	>
</div>

<style>
	.route-plot {
		display: block;
		width: 100%;
		max-height: 520px;
		border-radius: 4px;
	}
	.interactive-route {
		display: block;
		width: 100%;
		padding: 0;
		border: 0;
		background: transparent;
		cursor: crosshair;
	}
	.route-legend {
		display: flex;
		flex-wrap: wrap;
		gap: 12px;
		margin-top: 10px;
		color: var(--muted);
		font-size: 10px;
	}
</style>
