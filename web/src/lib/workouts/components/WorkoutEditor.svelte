<script lang="ts">
	import { m as L } from '$lib/paraglide/messages.js';
	import { m } from '$lib/paraglide/messages.js';
	import { protectUnsavedChanges } from '$lib/i18n/guard.svelte';
	import { onDestroy, untrack } from 'svelte';
	import { goto } from '$app/navigation';
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
	import TagsInput from '$lib/workouts/components/TagsInput.svelte';

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
	protectUnsavedChanges(
		() => dirty,
		() => m.discard_edit(),
		() => busy
	);
	async function reload() {
		if (busy || (dirty && !window.confirm(L.workout_confirm_reload()))) return;
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
				L.workout_confirm_delete({
					title: baseline.workoutUserData.workoutTitle ?? L.workout_untitled()
				})
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
		<p class="subtle">{L.workout_edit_note()}</p>
		<fieldset class="form-stack" disabled={busy}>
			<legend class="sr-only">{L.workout_information()}</legend>
			<label>{L.workout_optional_title()}<input bind:value={title} /></label>
			<label>{L.workout_optional_notes()}<textarea bind:value={notes}></textarea></label>
			<TagsInput bind:tags bind:pending={pendingTag} bind:this={tagInput} />
		</fieldset>
		{#if error}<p role="alert" class="form-error">{errorText(error)}</p>{/if}
		{#if conflict}<p role="status">{L.workout_edit_conflict()}</p>{/if}
		<div class="form-actions">
			<button class="button primary" disabled={busy || conflict}
				>{busy ? L.action_processing() : L.action_save_changes()}</button
			>
			<a class="button" href={resolve('/workouts/[id]', { id: baseline.workoutId })}
				>{L.action_back_details()}</a
			>
			<button class="button" type="button" disabled={busy} onclick={reload}
				>{L.action_reload_latest()}</button
			>
		</div>
	</form>
	<section class="surface form-stack">
		<h2>{L.action_delete_workout()}</h2>
		<p class="subtle">
			{L.workout_delete_note()}
		</p>
		<div>
			<button class="button danger" disabled={busy || conflict} onclick={remove}
				>{L.action_delete_this_workout()}</button
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
