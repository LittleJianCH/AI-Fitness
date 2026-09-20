<script lang="ts">
	import { m as L } from '$lib/paraglide/messages.js';
	import { m } from '$lib/paraglide/messages.js';
	import { protectUnsavedChanges } from '$lib/i18n/guard.svelte';
	import { untrack } from 'svelte';
	import { useQueryClient } from '@tanstack/svelte-query';
	import { useSession } from '$lib/auth/session.svelte';
	import type { UserSettings, BodyProfile, Equipment } from '$lib/api/generated/client';
	import { putSettingsBody } from '$lib/api/generated/schemas';
	import { ApiError, errorText } from '$lib/api/request';
	import { loadSettings, saveSettings, settingsKey } from './api';
	import { dateText, valueText } from '$lib/workouts/presentation';
	import SportFields from './SportFields.svelte';
	let { initial }: { initial: UserSettings } = $props();
	const session = useSession();
	const client = useQueryClient();
	let saved = $state(untrack(() => structuredClone(initial)));
	let draft = $state(untrack(() => structuredClone(initial)));
	let body = $state<BodyProfile>();
	let effective = $state('');
	let equipment = $state<Equipment>();
	let busy = $state(false);
	let conflict = $state(false);
	let error = $state('');
	let notice = $state('');
	const dirty = $derived(JSON.stringify(draft) !== JSON.stringify(saved) || !!body || !!equipment);
	protectUnsavedChanges(
		() => dirty,
		() => m.discard_settings(),
		() => busy
	);
	function localTime(date: Date) {
		const pad = (n: number) => String(n).padStart(2, '0');
		return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
	}
	function addBody() {
		const previous = draft.settingsBodyProfiles.at(-1);
		body = previous
			? structuredClone($state.snapshot(previous))
			: { bodyProfileId: '', bodyEffectiveFrom: '', bodyCycling: {}, bodyRunning: {} };
		body.bodyProfileId = crypto.randomUUID();
		effective = localTime(new Date());
		notice = '';
	}
	function addEquipment() {
		equipment = {
			equipmentId: crypto.randomUUID(),
			equipmentKind: 'bicycle',
			equipmentName: '',
			equipmentRetired: false
		};
		notice = '';
	}
	async function save() {
		if (busy || conflict) return;
		error = '';
		notice = '';
		let value = structuredClone($state.snapshot(draft));
		if (body) {
			const date = new Date(effective);
			if (!Number.isFinite(date.getTime()) || localTime(date) !== effective) {
				error = L.settings_invalid_time();
				return;
			}
			value.settingsBodyProfiles.push({
				...$state.snapshot(body),
				bodyEffectiveFrom: date.toISOString()
			});
		}
		if (equipment) {
			const entry = {
				...$state.snapshot(equipment),
				equipmentName: equipment.equipmentName.trim()
			};
			const index = value.settingsEquipment.findIndex((e) => e.equipmentId === entry.equipmentId);
			if (index < 0) value.settingsEquipment.push(entry);
			else value.settingsEquipment[index] = entry;
		}
		const parsed = putSettingsBody.safeParse(value);
		if (!parsed.success) {
			error = L.settings_invalid_values();
			return;
		}
		value = parsed.data;
		busy = true;
		try {
			const result = await saveSettings(session, client, value);
			saved = structuredClone(result);
			draft = structuredClone(result);
			body = undefined;
			equipment = undefined;
			notice = L.settings_saved();
		} catch (cause) {
			if (cause instanceof Error && cause.name !== 'AbortError') {
				conflict = cause instanceof ApiError && cause.status === 409;
				error = conflict ? L.settings_conflict() : errorText(cause);
			}
		} finally {
			busy = false;
		}
	}
	async function reload() {
		if (busy || (dirty && !window.confirm(L.settings_discard_reload()))) return;
		busy = true;
		error = '';
		notice = '';
		try {
			const result = await session.run((_csrf, options) =>
				loadSettings(options.signal ?? undefined)
			);
			client.setQueryData(settingsKey(session.user?.id), result);
			saved = structuredClone(result);
			draft = structuredClone(result);
			body = undefined;
			equipment = undefined;
			conflict = false;
		} catch (cause) {
			if (cause instanceof Error && cause.name !== 'AbortError') error = errorText(cause);
		} finally {
			busy = false;
		}
	}
</script>

<form
	onsubmit={(event) => {
		event.preventDefault();
		void save();
	}}
>
	<fieldset disabled={busy || conflict} class="editor">
		<section class="section">
			<h2>{L.settings_software()}</h2>
			<div class="surface">
				<label
					>{L.settings_appearance()}<select bind:value={draft.settingsSoftware.softwareAppearance}
						><option value="systemAppearance">{L.theme_system()}</option><option
							value="lightAppearance">{L.theme_light()}</option
						><option value="darkAppearance">{L.theme_dark()}</option></select
					></label
				>
				<p class="small subtle">{L.settings_units_note()}</p>
			</div>
		</section>
		<section class="section">
			<h2>{L.settings_body()}</h2>
			<div class="surface">
				<p>
					{L.settings_body_note()}
				</p>
				{#each draft.settingsBodyProfiles as profile (profile.bodyProfileId)}<details>
						<summary
							>{dateText(profile.bodyEffectiveFrom)} · {valueText(profile.bodyMassKilograms, 1, 1)} kg</summary
						>
						<dl class="stats-rows">
							<div>
								<dt>{L.label_height()}</dt>
								<dd>{valueText(profile.bodyHeightMetres, 100, 1)} cm</dd>
							</div>
							{#each [[L.sport_cycling(), profile.bodyCycling], [L.sport_running(), profile.bodyRunning]] as entry, i (i)}
								{@const sport = i === 0 ? profile.bodyCycling : profile.bodyRunning}
								<div>
									<dt>{L.settings_sport_power_label({ sport: String(entry[0]) })}</dt>
									<dd>{valueText(sport.sportThresholdWatts)} W</dd>
								</div>
								<div>
									<dt>{L.settings_sport_heart_label({ sport: String(entry[0]) })}</dt>
									<dd>
										{valueText(sport.sportHeartRate?.heartRateResting)} / {valueText(
											sport.sportHeartRate?.heartRateThreshold
										)} / {valueText(sport.sportHeartRate?.heartRateMaximum)} bpm
									</dd>
								</div>
							{/each}
						</dl>
					</details>{:else}<p class="subtle">{L.settings_body_empty()}</p>{/each}
				{#if body}
					<div class="fields">
						<label
							>{L.settings_effective_time()}<input
								type="datetime-local"
								required
								bind:value={effective}
							/></label
						>
						<label
							>{L.settings_weight()}<input
								type="number"
								min="0.01"
								step="any"
								value={body.bodyMassKilograms ?? ''}
								oninput={(event) => {
									if (body)
										body.bodyMassKilograms =
											event.currentTarget.value === ''
												? undefined
												: event.currentTarget.valueAsNumber;
								}}
							/></label
						>
						<label
							>{L.settings_height()}<input
								type="number"
								min="0.01"
								step="any"
								value={body.bodyHeightMetres ?? ''}
								oninput={(event) => {
									if (body)
										body.bodyHeightMetres =
											event.currentTarget.value === ''
												? undefined
												: event.currentTarget.valueAsNumber;
								}}
							/></label
						>
					</div>
					<div class="fields">
						<SportFields title={L.sport_cycling()} bind:profile={body.bodyCycling} /><SportFields
							title={L.sport_running()}
							bind:profile={body.bodyRunning}
						/>
					</div>
					<button type="button" class="button" onclick={() => (body = undefined)}
						>{L.settings_cancel_body()}</button
					>
				{:else}<button type="button" class="button" onclick={addBody}
						>{L.settings_update_body()}</button
					>{/if}
			</div>
		</section>
		<section class="section">
			<h2>{L.settings_equipment()}</h2>
			<div class="surface">
				<p class="small subtle">{L.settings_equipment_note()}</p>
				<ul>
					{#each draft.settingsEquipment as entry (entry.equipmentId)}<li>
							<button
								type="button"
								class="button"
								onclick={() => (equipment = structuredClone($state.snapshot(entry)))}
								>{entry.equipmentName} · {entry.equipmentKind === 'bicycle'
									? L.equipment_bike()
									: L.equipment_shoes()}{entry.equipmentRetired
									? L.equipment_retired_suffix()
									: ''}</button
							>
						</li>{:else}<li>{L.equipment_empty()}</li>{/each}
				</ul>
				{#if equipment}<div class="fields">
						<label
							>{L.equipment_name()}<input
								required
								maxlength="120"
								bind:value={equipment.equipmentName}
							/></label
						>
						<label
							>{L.equipment_type()}<select
								disabled={draft.settingsEquipment.some(
									(e) => e.equipmentId === equipment?.equipmentId
								)}
								bind:value={equipment.equipmentKind}
								><option value="bicycle">{L.equipment_bike()}</option><option value="runningShoes"
									>{L.equipment_shoes()}</option
								></select
							></label
						>
						<label
							>{L.equipment_weight()}<input
								type="number"
								min="0.01"
								step="any"
								value={equipment.equipmentMassKilograms ?? ''}
								oninput={(event) => {
									if (equipment)
										equipment.equipmentMassKilograms =
											event.currentTarget.value === ''
												? undefined
												: event.currentTarget.valueAsNumber;
								}}
							/></label
						>
						<label
							><input
								type="checkbox"
								bind:checked={equipment.equipmentRetired}
							/>{L.equipment_retire()}</label
						>
					</div>
					<button type="button" class="button" onclick={() => (equipment = undefined)}
						>{L.equipment_cancel()}</button
					>
				{:else}<button type="button" class="button" onclick={addEquipment}
						>{L.equipment_add()}</button
					>{/if}
			</div>
		</section>
	</fieldset>
	{#if error}<p role="alert" class="form-error">{error}</p>{/if}
	{#if notice}<p role="status">{notice}</p>{/if}
	<div class="form-actions">
		<button class="button primary" disabled={busy || conflict || !dirty}
			>{busy ? L.action_saving() : L.settings_save()}</button
		><button type="button" class="button" disabled={busy} onclick={reload}
			>{L.settings_reload()}</button
		>
	</div>
	<p class="small subtle">{L.settings_revision({ revision: saved.settingsRevision })}</p>
</form>

<style>
	.editor {
		border: 0;
		padding: 0;
		min-width: 0;
	}
	h2 {
		margin-bottom: 12px;
	}
	.fields {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(min(240px, 100%), 1fr));
		gap: 16px;
		margin: 16px 0;
	}
	label {
		display: block;
	}
	input:not([type='checkbox']),
	select {
		display: block;
		width: 100%;
		margin: 6px 0 12px;
	}
	p {
		margin: 12px 0;
	}
	li {
		margin: 8px 0;
	}
	summary {
		cursor: pointer;
		padding: 12px 0;
	}
	.form-actions {
		margin-top: 20px;
	}
</style>
