<script lang="ts">
	import type { ZoneDuration } from '$lib/api/generated/client';
	import { valueText, duration } from '$lib/workouts/presentation';
	let { zones, unit, title }: { zones: ZoneDuration[]; unit: string; title: string } = $props();
	// Only scale display bars; the backend owns the ranges and durations.
	const maximum = $derived(Math.max(1, ...zones.map((z) => z.zoneSeconds)));
</script>

<h3>{title}</h3>
{#if zones.length}<div class="table-scroll" role="region" aria-label={title}>
		<table>
			<thead><tr><th>分区</th><th>范围 ({unit})</th><th>时间</th></tr></thead><tbody
				>{#each zones as zone (zone.zoneIndex)}<tr
						><td>Z{zone.zoneIndex}</td><td
							>{valueText(zone.zoneLower, 1, 1)}–{zone.zoneUpper === undefined
								? '以上'
								: valueText(zone.zoneUpper, 1, 1)}</td
						><td
							>{duration(zone.zoneSeconds)}
							<div class="bar" style:width={`${(zone.zoneSeconds / maximum) * 100}%`}></div></td
						></tr
					>{/each}</tbody
			>
		</table>
	</div>{:else}<p class="subtle">缺少有效参数或连续采样，分区暂不可用。</p>{/if}

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
