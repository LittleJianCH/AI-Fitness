<script lang="ts">
	import { m as L } from '$lib/paraglide/messages.js';
	import type { ZoneDuration } from '$lib/api/generated/client';
	import { valueText, duration } from '$lib/workouts/presentation';
	let { zones, unit, title }: { zones: ZoneDuration[]; unit: string; title: string } = $props();
	// Only scale display bars; the backend owns the ranges and durations.
	const maximum = $derived(Math.max(1, ...zones.map((z) => z.zoneSeconds)));
</script>

<h3>{title}</h3>
{#if zones.length}<div class="table-scroll" role="region" aria-label={title}>
		<table>
			<thead
				><tr
					><th>{L.zone_label()}</th><th>{L.zone_range_unit({ unit })}</th><th>{L.label_time()}</th
					></tr
				></thead
			><tbody
				>{#each zones as zone (zone.zoneIndex)}<tr
						><td>Z{zone.zoneIndex}</td><td
							>{valueText(zone.zoneLower, 1, 1)}–{zone.zoneUpper === undefined
								? L.zone_above()
								: valueText(zone.zoneUpper, 1, 1)}</td
						><td
							>{duration(zone.zoneSeconds)}
							<div class="bar" style:width={`${(zone.zoneSeconds / maximum) * 100}%`}></div></td
						></tr
					>{/each}</tbody
			>
		</table>
	</div>{:else}<p class="subtle">{L.zone_missing()}</p>{/if}

<style>
	h3 {
		font-size: 16px;
		margin: 20px 0 12px;
	}
	.bar {
		height: 4px;
		background: var(--blue);
		margin-top: 6px;
	}
	td:last-child {
		min-width: 110px;
	}
</style>
