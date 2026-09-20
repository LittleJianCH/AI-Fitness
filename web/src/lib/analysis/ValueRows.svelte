<script lang="ts">
	import { m as L } from '$lib/paraglide/messages.js';
	import { valueText } from '$lib/workouts/presentation';
	let { rows }: { rows: [string, number | undefined, string, number?][] } = $props();
</script>

<dl class="stats-rows">
	{#each rows as [label, value, unit, digits], i (i)}<div>
			<dt>{label}</dt>
			<dd>
				{value === undefined ? L.value_no_data() : `${valueText(value, 1, digits ?? 1)} ${unit}`}
			</dd>
		</div>{/each}
</dl>
