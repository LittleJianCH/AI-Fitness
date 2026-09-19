<script lang="ts">
	import { untrack } from 'svelte';
	import { beforeNavigate } from '$app/navigation';
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
	beforeNavigate(({ cancel }) => {
		if (dirty && !window.confirm('离开会丢弃未保存的设置，仍要离开？')) cancel();
	});
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
				error = '请填写有效的本地生效时间。';
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
			error = '请检查设置中的数值和必填项。';
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
			notice = '设置已保存到当前账号。';
		} catch (cause) {
			if (cause instanceof Error && cause.name !== 'AbortError') {
				conflict = cause instanceof ApiError && cause.status === 409;
				error = conflict ? '设置已被其他会话更新。请重新加载最新设置后再编辑。' : errorText(cause);
			}
		} finally {
			busy = false;
		}
	}
	async function reload() {
		if (busy || (dirty && !window.confirm('重新加载会丢弃未保存的设置，继续？'))) return;
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

<svelte:window
	onbeforeunload={(event) => {
		if (dirty) event.preventDefault();
	}}
/>
<form
	onsubmit={(event) => {
		event.preventDefault();
		void save();
	}}
>
	<fieldset disabled={busy || conflict} class="editor">
		<section class="section">
			<h2>软件设置</h2>
			<div class="surface">
				<label
					>账号外观<select bind:value={draft.settingsSoftware.softwareAppearance}
						><option value="systemAppearance">跟随系统</option><option value="lightAppearance"
							>亮色</option
						><option value="darkAppearance">暗色</option></select
					></label
				>
				<p class="small subtle">公制 · km / kg / W · 时间使用浏览器本地时区</p>
			</div>
		</section>
		<section class="section">
			<h2>个人身体参数</h2>
			<div class="surface">
				<p>
					每次更新新增完整参数记录。生效时间之前的训练使用旧参数；选择过去的时间会影响该时间之后的训练分析。训练记录中的体重和阈值优先。
				</p>
				{#each draft.settingsBodyProfiles as profile (profile.bodyProfileId)}<details>
						<summary
							>{dateText(profile.bodyEffectiveFrom)} · {valueText(profile.bodyMassKilograms, 1, 1)} kg</summary
						>
						<dl class="stats-rows">
							<div>
								<dt>身高</dt>
								<dd>{valueText(profile.bodyHeightMetres, 100, 1)} cm</dd>
							</div>
							{#each [['骑行', profile.bodyCycling], ['跑步', profile.bodyRunning]] as entry, i (i)}
								{@const sport = i === 0 ? profile.bodyCycling : profile.bodyRunning}
								<div>
									<dt>{entry[0]}阈值功率</dt>
									<dd>{valueText(sport.sportThresholdWatts)} W</dd>
								</div>
								<div>
									<dt>{entry[0]}静息 / 阈值 / 最大心率</dt>
									<dd>
										{valueText(sport.sportHeartRate?.heartRateResting)} / {valueText(
											sport.sportHeartRate?.heartRateThreshold
										)} / {valueText(sport.sportHeartRate?.heartRateMaximum)} bpm
									</dd>
								</div>
							{/each}
						</dl>
					</details>{:else}<p class="subtle">尚未配置身体参数。</p>{/each}
				{#if body}
					<div class="fields">
						<label
							>生效时间（本地）<input
								type="datetime-local"
								required
								bind:value={effective}
							/></label
						>
						<label
							>体重 (kg)<input
								type="number"
								min="0.01"
								step="any"
								bind:value={body.bodyMassKilograms}
							/></label
						>
						<label
							>身高 (m)<input
								type="number"
								min="0.01"
								step="any"
								bind:value={body.bodyHeightMetres}
							/></label
						>
					</div>
					<div class="fields">
						<SportFields title="骑行" bind:profile={body.bodyCycling} /><SportFields
							title="跑步"
							bind:profile={body.bodyRunning}
						/>
					</div>
					<button type="button" class="button" onclick={() => (body = undefined)}
						>取消参数更新</button
					>
				{:else}<button type="button" class="button" onclick={addBody}>更新个人参数</button>{/if}
			</div>
		</section>
		<section class="section">
			<h2>器材</h2>
			<div class="surface">
				<p class="small subtle">管理自行车和跑鞋；目录修改不会重写已记录的训练器材。</p>
				<ul>
					{#each draft.settingsEquipment as entry (entry.equipmentId)}<li>
							<button
								type="button"
								class="button"
								onclick={() => (equipment = structuredClone($state.snapshot(entry)))}
								>{entry.equipmentName} · {entry.equipmentKind === 'bicycle'
									? '自行车'
									: '跑鞋'}{entry.equipmentRetired ? ' · 已停用' : ''}</button
							>
						</li>{:else}<li>尚未添加器材。</li>{/each}
				</ul>
				{#if equipment}<div class="fields">
						<label
							>器材名称<input
								required
								maxlength="120"
								bind:value={equipment.equipmentName}
							/></label
						>
						<label
							>器材类型<select
								disabled={draft.settingsEquipment.some(
									(e) => e.equipmentId === equipment?.equipmentId
								)}
								bind:value={equipment.equipmentKind}
								><option value="bicycle">自行车</option><option value="runningShoes">跑鞋</option
								></select
							></label
						>
						<label
							>器材重量 (kg)<input
								type="number"
								min="0.01"
								step="any"
								bind:value={equipment.equipmentMassKilograms}
							/></label
						>
						<label
							><input type="checkbox" bind:checked={equipment.equipmentRetired} />停用器材</label
						>
					</div>
					<button type="button" class="button" onclick={() => (equipment = undefined)}
						>取消器材编辑</button
					>
				{:else}<button type="button" class="button" onclick={addEquipment}>添加器材</button>{/if}
			</div>
		</section>
	</fieldset>
	{#if error}<p role="alert" class="form-error">{error}</p>{/if}
	{#if notice}<p role="status">{notice}</p>{/if}
	<div class="form-actions">
		<button class="button primary" disabled={busy || conflict || !dirty}
			>{busy ? '正在保存…' : '保存设置'}</button
		><button type="button" class="button" disabled={busy} onclick={reload}>重新加载设置</button>
	</div>
	<p class="small subtle">当前账号 · 参数版本 {saved.settingsRevision}</p>
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
