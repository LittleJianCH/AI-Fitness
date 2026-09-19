<script lang="ts">
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
		['resting', '静息'],
		['threshold', '阈值'],
		['maximum', '最大']
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
		>{title}阈值功率 (W)<input
			type="number"
			min="0.01"
			step="any"
			bind:value={profile.sportThresholdWatts}
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
		/>配置{title}心率参数</label
	>
	{#if enabled}
		<p class="small subtle">请填写自己的参数。负荷使用明确选择的指数，不根据身份推断。</p>
		{#each fields as [key, label] (key)}<label
				>{title}{label}心率 (bpm)<input
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
			>{title}TRIMP 指数<select
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
