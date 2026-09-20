<script lang="ts">
	import { m as L } from '$lib/paraglide/messages.js';
	import { untrack } from 'svelte';
	import type { SportProfile, LoadWeighting } from '$lib/api/generated/client';
	let { title, profile = $bindable() }: { title: string; profile: SportProfile } = $props();
	const previous = untrack(() => profile.sportHeartRate);
	let enabled = $state(!!previous);
	let draft = $state<{
		resting?: number;
		threshold?: number;
		maximum?: number;
		weighting: LoadWeighting;
	}>({
		resting: previous?.heartRateResting,
		threshold: previous?.heartRateThreshold,
		maximum: previous?.heartRateMaximum,
		weighting: previous?.heartRateWeighting ?? 'exponent192'
	});
	const fields = [
		['resting', L.label_resting()],
		['threshold', L.label_threshold()],
		['maximum', L.stat_maximum()]
	] as const;
	function update() {
		profile.sportHeartRate =
			enabled &&
			draft.resting !== undefined &&
			draft.threshold !== undefined &&
			draft.maximum !== undefined
				? {
						heartRateResting: draft.resting,
						heartRateThreshold: draft.threshold,
						heartRateMaximum: draft.maximum,
						heartRateWeighting: draft.weighting
					}
				: undefined;
	}
</script>

<fieldset>
	<legend>{title}</legend>
	<label
		>{L.settings_sport_ftp({ sport: title })}<input
			type="number"
			min="0.01"
			step="any"
			value={profile.sportThresholdWatts ?? ''}
			oninput={(event) => {
				profile.sportThresholdWatts =
					event.currentTarget.value === '' ? undefined : event.currentTarget.valueAsNumber;
			}}
		/></label
	>
	<label
		><input
			type="checkbox"
			checked={enabled}
			onchange={(e) => {
				enabled = e.currentTarget.checked;
				update();
			}}
		/>{L.settings_sport_enable_heart({ sport: title })}</label
	>
	{#if enabled}
		<p class="small subtle">{L.settings_heart_note()}</p>
		{#each fields as [key, label] (key)}<label
				>{L.settings_sport_heart_value({ sport: title, kind: label })}<input
					type="number"
					required
					min="1"
					step="any"
					value={draft[key] ?? ''}
					oninput={(e) => {
						draft[key] = e.currentTarget.value === '' ? undefined : e.currentTarget.valueAsNumber;
						update();
					}}
				/></label
			>{/each}
		<label
			>{L.settings_sport_trimp({ sport: title })}<select
				value={draft.weighting}
				onchange={(e) => {
					draft.weighting = e.currentTarget.value === 'exponent167' ? 'exponent167' : 'exponent192';
					update();
				}}
				><option value="exponent192">1.92</option><option value="exponent167">1.67</option></select
			></label
		>
	{/if}
</fieldset>

<style>
	fieldset {
		min-width: 0;
		border: 1px solid var(--line);
		border-radius: 6px;
		padding: 16px;
	}
	label {
		display: block;
		margin: 12px 0;
	}
	input:not([type='checkbox']),
	select {
		display: block;
		width: 100%;
		margin-top: 6px;
	}
</style>
