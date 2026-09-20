<script lang="ts">
	import { m as L } from '$lib/paraglide/messages.js';
	import { m } from '$lib/paraglide/messages.js';
	import { protectUnsavedChanges } from '$lib/i18n/guard.svelte';
	import { onDestroy } from 'svelte';
	import { navigating } from '$app/state';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { useQueryClient } from '@tanstack/svelte-query';
	import { useSession } from '$lib/auth/session.svelte';
	import { postWorkouts, type ManualWorkout } from '$lib/api/generated/client';
	import { postWorkouts200Response } from '$lib/api/generated/schemas';
	import { ApiError, errorText, request } from '$lib/api/request';
	import { buildManualWorkout, manualDraftSchema } from '$lib/workouts/manual';
	import TagsInput from '$lib/workouts/components/TagsInput.svelte';

	const session = useSession();
	const client = useQueryClient();
	const demo = import.meta.env.MODE === 'demo';
	let sport = $state<'cycling' | 'running'>('cycling');
	let start = $state('');
	let minutes = $state<number | undefined>();
	let seconds = $state<number | undefined>(0);
	let distanceKm = $state<number | undefined>();
	let title = $state('');
	let notes = $state('');
	let tags = $state<string[]>([]);
	let tagInput = $state<{ flush: () => void }>();
	let busy = $state(false);
	let attempt = $state<ManualWorkout | null>(null);
	let error = $state<Error | null>(null);
	let validation = $state('');
	let dirty = $state(false);
	let active = true;
	let uncertain = false;
	onDestroy(() => {
		active = false;
	});
	const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
	protectUnsavedChanges(
		() => dirty,
		() => m.discard_workout(),
		() => busy
	);
	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (busy || demo) return;
		error = null;
		validation = '';
		if (!attempt) {
			tagInput?.flush();
			const parsed = manualDraftSchema.safeParse(
				{
					sport,
					start,
					minutes,
					seconds,
					distanceKm,
					title,
					notes,
					tags
				},
				{ error: () => L.manual_check_fields() }
			);
			if (!parsed.success) {
				validation = parsed.error.issues[0]?.message ?? L.manual_check_fields();
				return;
			}
			try {
				attempt = buildManualWorkout(parsed.data, crypto.randomUUID());
				uncertain = false;
			} catch {
				validation = L.manual_check_values();
				return;
			}
		}
		busy = true;
		const body = attempt;
		const owner = session.user?.id;
		try {
			const saved = await session.run((csrf, options) =>
				request(
					() => postWorkouts(body, { 'X-CSRF-Token': csrf }, options),
					postWorkouts200Response
				)
			);
			client.setQueryData(['workout', owner, saved.workoutId, 'normal'], saved);
			await client.invalidateQueries({ queryKey: ['workouts', owner] });
			if (!active || navigating.to || session.user?.id !== owner) return;
			dirty = false;
			await goto(resolve('/workouts/[id]', { id: saved.workoutId }));
		} catch (cause) {
			if (cause instanceof Error && cause.name === 'AbortError') return;
			error = cause instanceof Error ? cause : new ApiError('network_error');
			// After any uncertain publication, even a later definitive rejection cannot
			// prove the original attempt was not saved. Keep its identity and body.
			const rejected =
				cause instanceof ApiError && [400, 403, 413, 422, 429].includes(cause.status);
			if (rejected && !uncertain) attempt = null;
			else uncertain = true;
		} finally {
			busy = false;
		}
	}
</script>

<svelte:head><title>{L.page_manual_title()}</title></svelte:head>
<nav class="breadcrumb" aria-label={L.navigation_breadcrumb()}>
	<a href={resolve('/workouts')}>{L.navigation_workouts()}</a><span>/</span><span
		>{L.action_manual_workout()}</span
	>
</nav>
<header class="page-heading">
	<div>
		<div class="eyebrow">{L.eyebrow_manual_workout()}</div>
		<h1>{L.manual_heading()}</h1>
		<p class="subtle">{L.manual_intro()}</p>
	</div>
</header>
{#if demo}<div class="status">{L.manual_demo()}</div>
{:else}<form
		class="surface manual-form form-stack"
		onsubmit={submit}
		oninput={() => (dirty = true)}
	>
		<fieldset disabled={busy || attempt !== null}>
			<legend>{L.manual_content()}</legend>
			<div class="form-stack">
				<div class="form-grid">
					<label
						>{L.label_sport()}<select bind:value={sport}
							><option value="cycling">{L.sport_cycling()}</option><option value="running"
								>{L.sport_running()}</option
							></select
						></label
					><label>{L.workout_optional_title()}<input bind:value={title} /></label>
				</div>
				<label
					>{L.label_start_time()}<input
						type="datetime-local"
						step="1"
						required
						bind:value={start}
					/></label
				>
				<p class="small subtle">{L.label_local_zone({ zone: timezone })}</p>
				<div>
					<div class="form-grid">
						<label
							>{L.manual_minutes()}<input
								type="number"
								min="0"
								step="1"
								required
								bind:value={minutes}
							/></label
						><label
							>{L.manual_seconds()}<input
								type="number"
								min="0"
								max="59"
								step="1"
								bind:value={seconds}
							/></label
						>
					</div>
					<p class="small subtle">{L.manual_elapsed_note()}</p>
				</div>
				<label
					>{L.manual_distance()}<input
						type="number"
						min="0"
						step="any"
						bind:value={distanceKm}
					/></label
				>
				<label>{L.workout_optional_notes()}<textarea bind:value={notes}></textarea></label>
				<TagsInput bind:tags bind:this={tagInput} />
			</div>
		</fieldset>
		{#if validation}<p class="form-error" role="alert">{validation}</p>{/if}
		{#if error}<p class="form-error" role="alert">{errorText(error)}</p>{/if}
		{#if attempt && !busy}<p role="status">
				{L.manual_uncertain()}
			</p>{/if}
		<div class="form-actions">
			<button class="button primary" disabled={busy}
				>{busy ? L.action_saving() : attempt ? L.manual_retry() : L.manual_save()}</button
			><a class="button" href={resolve('/workouts')}>{L.action_back_workouts()}</a>
		</div>
	</form>{/if}

<style>
	.manual-form {
		max-width: 760px;
	}
	fieldset {
		border: 0;
		padding: 0;
		margin: 0;
		min-width: 0;
	}
	legend {
		padding: 0;
		margin-bottom: 20px;
		font-weight: 600;
	}
	.form-grid {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 18px;
	}
	@media (max-width: 700px) {
		.form-grid {
			grid-template-columns: 1fr;
		}
	}
</style>
