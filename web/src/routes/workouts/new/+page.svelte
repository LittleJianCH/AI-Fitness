<script lang="ts">
	import { onDestroy } from 'svelte';
	import { navigating } from '$app/state';
	import { goto, beforeNavigate } from '$app/navigation';
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
	beforeNavigate((navigation) => {
		if (
			dirty &&
			(navigation.type === 'leave' ||
				!window.confirm('这条训练尚未确认保存，离开会丢失当前填写内容。确定离开？'))
		)
			navigation.cancel();
	});
	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (busy || demo) return;
		error = null;
		validation = '';
		if (!attempt) {
			tagInput?.flush();
			const parsed = manualDraftSchema.safeParse({
				sport,
				start,
				minutes,
				seconds,
				distanceKm,
				title,
				notes,
				tags
			});
			if (!parsed.success) {
				validation = parsed.error.issues[0]?.message ?? '请检查填写内容。';
				return;
			}
			try {
				attempt = buildManualWorkout(parsed.data, crypto.randomUUID());
				uncertain = false;
			} catch {
				validation = '请检查时间、时长和距离是否有效。';
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

<svelte:head><title>手动录入 · AI Fitness</title></svelte:head>
<nav class="breadcrumb" aria-label="面包屑">
	<a href={resolve('/workouts')}>训练</a><span>/</span><span>手动录入</span>
</nav>
<header class="page-heading">
	<div>
		<div class="eyebrow">MANUAL WORKOUT</div>
		<h1>记录一次训练</h1>
		<p class="subtle">填写时间与距离，保存这次骑行或跑步。</p>
	</div>
</header>
{#if demo}<div class="status">手动录入需要登录真实账号，演示模式仅供查看。</div>
{:else}<form
		class="surface manual-form form-stack"
		onsubmit={submit}
		oninput={() => (dirty = true)}
	>
		<fieldset disabled={busy || attempt !== null}>
			<legend>训练内容</legend>
			<div class="form-stack">
				<div class="form-grid">
					<label
						>运动类型<select bind:value={sport}
							><option value="cycling">骑行</option><option value="running">跑步</option></select
						></label
					><label>标题（可选）<input bind:value={title} /></label>
				</div>
				<label>开始时间<input type="datetime-local" step="1" required bind:value={start} /></label>
				<p class="small subtle">使用本地时区：{timezone}</p>
				<div>
					<div class="form-grid">
						<label
							>经过时长（分钟）<input
								type="number"
								min="0"
								step="1"
								required
								bind:value={minutes}
							/></label
						><label
							>秒（可选）<input
								type="number"
								min="0"
								max="59"
								step="1"
								bind:value={seconds}
							/></label
						>
					</div>
					<p class="small subtle">经过时长包括暂停时间。</p>
				</div>
				<label
					>距离（km，可选）<input type="number" min="0" step="any" bind:value={distanceKm} /></label
				>
				<label>备注（可选）<textarea bind:value={notes}></textarea></label>
				<TagsInput bind:tags bind:this={tagInput} />
			</div>
		</fieldset>
		{#if validation}<p class="form-error" role="alert">{validation}</p>{/if}
		{#if error}<p class="form-error" role="alert">{errorText(error)}</p>{/if}
		{#if attempt && !busy}<p role="status">
				保存结果尚未确认。重试会核对同一次提交；刷新或离开前，请先确认列表中是否已有这条记录。
			</p>{/if}
		<div class="form-actions">
			<button class="button primary" disabled={busy}
				>{busy ? '正在保存…' : attempt ? '重试保存' : '保存训练'}</button
			><a class="button" href={resolve('/workouts')}>返回训练</a>
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
