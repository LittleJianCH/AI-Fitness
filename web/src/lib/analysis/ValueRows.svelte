<script lang="ts">
	import { valueText } from '$lib/workouts/presentation';
	let { rows }: { rows: [string, number | undefined, string, number?][] } = $props();
</script>

<dl class="stats-rows">
	{#each rows as [label, value, unit, digits], i (i)}<div>
			<dt>{label}</dt>
			<dd>{value === undefined ? '无数据' : `${valueText(value, 1, digits ?? 1)} ${unit}`}</dd>
		</div>{/each}
</dl>
