<script lang="ts">
	import { browser } from '$app/environment';
	import { onDestroy } from 'svelte';
	import { beforeNavigate } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { useSession } from '$lib/auth/session.svelte';
	import {
		getAuthPolicy,
		postImportsFit,
		getImportsImportId,
		type ImportRecord
	} from '$lib/api/generated/client';
	import {
		getAuthPolicy200Response,
		postImportsFit200Response,
		getImportsImportId200Response
	} from '$lib/api/generated/schemas';
	import { ApiError, request, requestOptions, errorText } from '$lib/api/request';
	const demo = import.meta.env.MODE === 'demo';
	const session = useSession();
	const client = useQueryClient();
	const lifetime = new AbortController();
	let active = true;
	onDestroy(() => {
		active = false;
		lifetime.abort();
	});
	const policy = createQuery(() => ({
		queryKey: ['auth-policy'],
		enabled: browser && !demo,
		queryFn: ({ signal }) =>
			request(() => getAuthPolicy(requestOptions(signal)), getAuthPolicy200Response)
	}));
	let file = $state<File | null>(null);
	let busy = $state(false);
	let uncertain = $state(false);
	let validation = $state('');
	let error = $state<Error | null>(null);
	let result = $state<ImportRecord | null>(null);
	const pending = $derived(result?.status === 'pending' || result?.status === 'processing');
	beforeNavigate((navigation) => {
		if (
			(busy || uncertain) &&
			(navigation.type === 'leave' ||
				!window.confirm(
					'导入结果尚未确认，离开后可在训练列表检查，或重新上传同一文件确认结果。确定离开？'
				))
		)
			navigation.cancel();
	});
	function selectFile(event: Event & { currentTarget: HTMLInputElement }) {
		file = event.currentTarget.files?.[0] ?? null;
		result = null;
		error = null;
		validation = '';
		uncertain = false;
	}
	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (busy || !file || !policy.data) return;
		if (file.size === 0 || file.size > policy.data.maximumFitBytes) {
			validation =
				file.size === 0 ? '这个文件是空的，请重新选择。' : '文件超过大小限制，请重新选择。';
			return;
		}
		const selected = file;
		await perform((csrf, options) =>
			request(
				() => postImportsFit(selected, { 'X-CSRF-Token': csrf }, options),
				postImportsFit200Response
			)
		);
	}
	async function refresh() {
		if (busy || !result) return;
		const id = result.id;
		await perform((_csrf, options) =>
			request(() => getImportsImportId(id, undefined, options), getImportsImportId200Response)
		);
	}
	async function perform(action: (csrf: string, options: RequestInit) => Promise<ImportRecord>) {
		busy = true;
		error = null;
		validation = '';
		const owner = session.user?.id;
		try {
			const record = await session.run(async (csrf, options) => {
				// WebKit shipped AbortController before AbortSignal.any. Forward session
				// cancellation to the page lifetime and release the listener after each request.
				const abort = () => lifetime.abort(options.signal?.reason);
				options.signal?.addEventListener('abort', abort, { once: true });
				if (options.signal?.aborted) abort();
				try {
					return await action(csrf, { ...options, signal: lifetime.signal });
				} finally {
					options.signal?.removeEventListener('abort', abort);
				}
			});
			if (!active || owner !== session.user?.id) return;
			result = record;
			uncertain = false;
			if (record.status === 'succeeded')
				void client.invalidateQueries({ queryKey: ['workouts', owner] });
		} catch (cause) {
			if (
				!active ||
				owner !== session.user?.id ||
				(cause instanceof Error && cause.name === 'AbortError')
			)
				return;
			error = cause instanceof Error ? cause : new Error('Upload failed');
			if (
				!(cause instanceof ApiError) ||
				cause.status === 0 ||
				cause.status >= 500 ||
				cause.code === 'invalid_response'
			)
				uncertain = true;
		} finally {
			if (active) busy = false;
		}
	}
	function failureText(code: string | undefined) {
		switch (code) {
			case 'unsupported_fit':
				return '暂时仅支持包含单次骑行或跑步的 FIT 活动文件。';
			case 'missing_fit_time':
				return '文件缺少有效的训练时间，暂时无法导入。';
			case 'fit_resource_limit':
				return '文件中的数据量超出解析限制。';
			case 'invalid_fit':
				return '文件损坏或不是有效的 FIT 活动文件，请重新导出后再试。';
			default:
				return '文件未通过解析或数据校验，请检查来源并重新导出。';
		}
	}
</script>

<svelte:head><title>上传 FIT · AI Fitness</title></svelte:head>
<header class="page-heading">
	<div>
		<p class="eyebrow">IMPORT WORKOUT</p>
		<h1>上传 FIT 文件</h1>
		<p class="subtle">从运动设备导出的文件中导入一次骑行或跑步。</p>
	</div>
</header>
{#if demo}<div class="status">上传需要登录真实账号，演示模式仅供查看。</div>
{:else}<section class="surface upload-panel form-stack" aria-label="FIT 导入">
		<p>原始文件会私有保存，便于后续重新处理。同一账号重复上传相同文件会返回已有记录。</p>
		{#if policy.isPending}<p role="status">正在读取上传限制…</p>
		{:else if policy.isError}<p class="form-error" role="alert">{errorText(policy.error)}</p>
			<button class="button" onclick={() => policy.refetch()}>重试读取限制</button>
		{:else if policy.data}<form class="form-stack" onsubmit={submit}>
				<label
					>FIT 文件<input
						type="file"
						accept=".fit,.FIT,application/octet-stream"
						required
						disabled={busy || uncertain || pending}
						onchange={selectFile}
					/></label
				>
				<p class="small subtle">
					每次一个文件，最大 {policy.data.maximumFitBytes / 1024 / 1024} MiB。
				</p>
				{#if validation}<p class="form-error" role="alert">{validation}</p>{/if}
				{#if error}<p class="form-error" role="alert">{errorText(error)}</p>{/if}
				{#if uncertain}<p role="status">
						结果尚未确认。请重试上传同一文件，服务器会核对已有记录。
					</p>{/if}
				<div class="form-actions">
					<button
						class="button primary"
						disabled={busy || !file || pending || (!!result && !uncertain)}
						>{busy ? '正在处理…' : uncertain ? '重试上传' : '开始导入'}</button
					><a class="button" href={resolve('/workouts')}>返回训练</a>
				</div>
			</form>{/if}
		{#if result}<div class="import-result" role="status">
				{#if result.status === 'succeeded'}<h2>训练已导入</h2>
					<p>已确认保存。重复上传同一文件会显示已有训练。</p>
					{#each result.lastSuccess?.parts ?? [] as part (part.workoutId)}<a
							class="button primary"
							href={resolve(`/workouts/${part.workoutId}`)}>查看训练</a
						>{/each}
				{:else if result.status === 'suppressed'}<h2>这份文件的训练已被移除</h2>
					<p>重复上传不会恢复已删除的训练。</p>
				{:else if result.status === 'failed'}<h2>未能导入</h2>
					<p>{failureText(result.failure?.code)}</p>
				{:else}<h2>正在处理这份文件</h2>
					<p>稍后检查结果，确认训练是否已保存。</p>
					<button class="button" disabled={busy} onclick={refresh}>检查结果</button>{/if}
			</div>{/if}
	</section>{/if}

<style>
	.upload-panel {
		max-width: 760px;
	}
	.import-result {
		display: grid;
		gap: 14px;
		justify-items: start;
	}
	input[type='file'] {
		height: auto;
	}
</style>
