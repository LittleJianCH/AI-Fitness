<script lang="ts">
	import { onDestroy, untrack } from 'svelte';
	import { beforeNavigate, goto } from '$app/navigation';
	import { navigating } from '$app/state';
	import { resolve } from '$app/paths';
	import { useQueryClient } from '@tanstack/svelte-query';
	import { z } from 'zod';
	import { useSession } from '$lib/auth/session.svelte';
	import {
		deleteWorkoutsWorkoutId,
		putWorkoutsWorkoutIdUserData,
		type Workout
	} from '$lib/api/generated/client';
	import {
		putWorkoutsWorkoutIdUserDataBody,
		putWorkoutsWorkoutIdUserData200Response
	} from '$lib/api/generated/schemas';
	import { ApiError, errorText, request } from '$lib/api/request';
	import { loadWorkout } from '$lib/api/read';
	import TagsInput from './TagsInput.svelte';
	let { workout }: { workout: Workout } = $props();
	const session = useSession();
	const client = useQueryClient();
	// Refetches may update the query while this deliberate editing snapshot stays intact.
	let baseline = $state(untrack(() => workout));
	let title = $state(untrack(() => workout.workoutUserData.workoutTitle ?? ''));
	let notes = $state(untrack(() => workout.workoutUserData.workoutNotes ?? ''));
	let tags = $state(untrack(() => [...workout.workoutUserData.workoutTags]));
	let pendingTag = $state('');
	let tagInput = $state<{ flush: () => void }>();
	let busy = $state(false);
	let error = $state<Error | null>(null);
	let done = $state(false);
	let active = true;
	onDestroy(() => {
		active = false;
	});
	const dirty = $derived(
		!done &&
			(title !== (baseline.workoutUserData.workoutTitle ?? '') ||
				notes !== (baseline.workoutUserData.workoutNotes ?? '') ||
				JSON.stringify(tags) !== JSON.stringify(baseline.workoutUserData.workoutTags) ||
				pendingTag !== '')
	);
	const conflict = $derived(error instanceof ApiError && error.code === 'revision_conflict');
	beforeNavigate((navigation) => {
		if (
			dirty &&
			(navigation.type === 'leave' ||
				!window.confirm('修改尚未保存，离开会丢失当前填写内容。确定离开？'))
		)
			navigation.cancel();
	});
	async function reload() {
		if (
			busy ||
			(dirty && !window.confirm('重新加载会丢弃当前修改，使用服务器上的最新内容。继续？'))
		)
			return;
		busy = true;
		const owner = session.user?.id;
		try {
			const latest = await client.fetchQuery({
				queryKey: ['workout', owner, baseline.workoutId, 'normal'],
				queryFn: ({ signal }) => loadWorkout(baseline.workoutId, signal, 'normal'),
				staleTime: 0
			});
			if (!active || owner !== session.user?.id) return;
			baseline = latest;
			title = latest.workoutUserData.workoutTitle ?? '';
			notes = latest.workoutUserData.workoutNotes ?? '';
			tags = [...latest.workoutUserData.workoutTags];
			pendingTag = '';
			error = null;
		} catch (cause) {
			showError(cause);
		} finally {
			busy = false;
		}
	}
	function showError(cause: unknown) {
		if (cause instanceof Error && cause.name === 'AbortError') return;
		error = cause instanceof Error ? cause : new ApiError('network_error');
	}
	async function save(event: SubmitEvent) {
		event.preventDefault();
		if (busy || conflict) return;
		tagInput?.flush();
		const parsed = putWorkoutsWorkoutIdUserDataBody.safeParse({
			expectedRevision: baseline.workoutRevision,
			userData: {
				statisticsInclusion: baseline.workoutUserData.statisticsInclusion,
				...(title !== '' ? { workoutTitle: title } : {}),
				...(notes !== '' ? { workoutNotes: notes } : {}),
				workoutTags: tags
			}
		});
		if (!parsed.success) {
			error = new ApiError('validation_failed');
			return;
		}
		busy = true;
		error = null;
		const owner = session.user?.id;
		try {
			const saved = await session.run((csrf, options) =>
				request(
					() =>
						putWorkoutsWorkoutIdUserData(
							baseline.workoutId,
							parsed.data,
							{ 'X-CSRF-Token': csrf },
							options
						),
					putWorkoutsWorkoutIdUserData200Response
				)
			);
			await client.cancelQueries({ queryKey: ['workout', owner, saved.workoutId] });
			if (owner !== session.user?.id) return;
			client.setQueryData(['workout', owner, saved.workoutId, 'normal'], saved);
			await client.invalidateQueries({ queryKey: ['workouts', owner] });
			if (!active || navigating.to || owner !== session.user?.id) return;
			done = true;
			await goto(resolve('/workouts/[id]', { id: saved.workoutId }));
		} catch (cause) {
			showError(cause);
		} finally {
			busy = false;
		}
	}
	async function remove() {
		if (
			busy ||
			conflict ||
			!window.confirm(
				`删除“${baseline.workoutUserData.workoutTitle ?? '未命名训练'}”？此操作无法撤销，当前修改也会丢弃。`
			)
		)
			return;
		busy = true;
		error = null;
		const owner = session.user?.id;
		const id = baseline.workoutId;
		try {
			await session.run((csrf, options) =>
				request(
					() =>
						deleteWorkoutsWorkoutId(
							id,
							{ expectedRevision: baseline.workoutRevision, deleteEmptyGroups: false },
							{ 'X-CSRF-Token': csrf },
							options
						),
					z.void(),
					204
				)
			);
			await client.cancelQueries({ queryKey: ['workout', owner, id] });
			client.removeQueries({ queryKey: ['workout', owner, id] });
			await client.invalidateQueries({ queryKey: ['workouts', owner] });
			if (!active || navigating.to || owner !== session.user?.id) return;
			done = true;
			await goto(resolve('/workouts'));
		} catch (cause) {
			showError(cause);
		} finally {
			busy = false;
		}
	}
</script>

<div class="editor">
	<form class="surface form-stack" onsubmit={save}>
		<p class="subtle">修改标题、备注与标签。训练的时间、距离和测量数据保持原样。</p>
		<fieldset class="form-stack" disabled={busy}>
			<legend class="sr-only">训练信息</legend>
			<label>标题（可选）<input bind:value={title} /></label>
			<label>备注（可选）<textarea bind:value={notes}></textarea></label>
			<TagsInput bind:tags bind:pending={pendingTag} bind:this={tagInput} />
		</fieldset>
		{#if error}<p role="alert" class="form-error">{errorText(error)}</p>{/if}
		{#if conflict}<p role="status">当前填写内容已保留。载入最新版本后，可以重新修改并保存。</p>{/if}
		<div class="form-actions">
			<button class="button primary" disabled={busy || conflict}
				>{busy ? '正在处理…' : '保存修改'}</button
			>
			<a class="button" href={resolve('/workouts/[id]', { id: baseline.workoutId })}>返回详情</a>
			<button class="button" type="button" disabled={busy} onclick={reload}>重新加载最新版本</button
			>
		</div>
	</form>
	<section class="surface form-stack">
		<h2>删除训练</h2>
		<p class="subtle">
			删除后无法恢复。从文件或 Apple Health 导入的训练，删除后重复导入也不会自动恢复。
		</p>
		<div>
			<button class="button danger" disabled={busy || conflict} onclick={remove}
				>删除这条训练</button
			>
		</div>
	</section>
</div>

<style>
	.editor {
		max-width: 760px;
		display: grid;
		gap: 24px;
	}
	fieldset {
		border: 0;
		padding: 0;
		margin: 0;
		min-width: 0;
	}
</style>
