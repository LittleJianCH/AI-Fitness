<script lang="ts">
	import { useSession } from '$lib/auth/session.svelte';
	import { page } from '$app/state';
	import { createFocusSnapshot, type FocusSnapshot } from '$lib/focus-snapshot.svelte';
	import type { Snapshot } from '@sveltejs/kit';
	import { untrack } from 'svelte';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { createInfiniteQuery, useQueryClient } from '@tanstack/svelte-query';
	import { browser } from '$app/environment';
	import { filtersFromUrl } from '$lib/workouts/filters';
	import { ApiError } from '$lib/api/request';
	import { loadWorkouts, readScenario } from '$lib/api/read';
	import {
		commonCard,
		groupCards,
		duration,
		timeSummary,
		valueText
	} from '$lib/workouts/presentation';
	import Icon from '$lib/components/Icon.svelte';
	import Feedback from '$lib/components/Feedback.svelte';

	const session = useSession();
	const demo = import.meta.env.MODE === 'demo';

	const focus = createFocusSnapshot();
	let restoration = $state<{ focus: FocusSnapshot; pages: number; url: string } | null>(null);
	export const snapshot: Snapshot<{ focus: FocusSnapshot; pages: number }> = {
		capture: () => ({ focus: focus.snapshot.capture(), pages: query.data?.pages.length ?? 1 }),
		restore: (saved) => {
			restoration = { ...saved, url: page.url.href };
		}
	};
	const restoreFocus = focus.restoreFocus;

	const client = useQueryClient();
	let validation = $state('');
	// Editable derived values follow URL navigation and allow an explicit draft reset.
	let fromDate = $derived(page.url.searchParams.get('from') ?? '');
	let throughDate = $derived(page.url.searchParams.get('through') ?? '');
	let tagDraft = $derived(page.url.searchParams.get('tag') ?? '');

	const filters = $derived(filtersFromUrl(page.url.searchParams));
	const selectedSport = $derived(filters.success ? filters.data.sport : undefined);
	const filterError = $derived(
		validation || (!filters.success ? filters.error.issues[0]?.message : '')
	);
	const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
	const scenario = $derived(readScenario(page.url.searchParams.get('scenario')));
	const queryKey = $derived([
		'workouts',
		session.user?.id ?? 'demo',
		filters.success ? filters.data : null,
		scenario
	]);
	const query = createInfiniteQuery(() => ({
		queryKey,
		enabled: browser && filters.success,
		queryFn: ({ signal, pageParam }) =>
			loadWorkouts(
				{ ...(filters.success ? filters.data : {}), cursor: pageParam, limit: 3 },
				signal,
				scenario
			),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (last) => last.nextCursor
	}));
	$effect(() => {
		const saved = restoration;
		if (!saved) return;
		if (page.url.href !== saved.url || query.isError) {
			restoration = null;
			return;
		}
		if (!query.data || query.isFetching) return;
		if (query.data.pages.length < saved.pages && query.hasNextPage) {
			untrack(() => {
				void query.fetchNextPage();
			});
			return;
		}
		// A removed/filtered record must not leave a deferred focus request behind.
		if (
			query.data.pages.some((p) => p.items.some((item) => `workout-${item.id}` === saved.focus.key))
		) {
			untrack(() => focus.snapshot.restore(saved.focus));
		}
		restoration = null;
	});
	const items = $derived([
		...new Map((query.data?.pages.flatMap((p) => p.items) ?? []).map((w) => [w.id, w])).values()
	]);
	const groups = $derived(groupCards(items));
	async function retry() {
		if (query.error instanceof ApiError && query.error.code === 'invalid_cursor') {
			restoration = null;
			await client.resetQueries({ queryKey, exact: true });
		} else if (query.isFetchNextPageError) await query.fetchNextPage();
		else await query.refetch();
	}
	async function applyFilters(event: SubmitEvent) {
		event.preventDefault();
		if (!(event.currentTarget instanceof HTMLFormElement)) return;
		const values = new FormData(event.currentTarget);
		const url = new URL(page.url);
		for (const key of ['from', 'through', 'tag']) {
			const value = values.get(key);
			if (typeof value === 'string' && value !== '') url.searchParams.set(key, value);
			else url.searchParams.delete(key);
		}
		const result = filtersFromUrl(url.searchParams);
		if (!result.success) {
			validation = result.error.issues[0]?.message ?? '请检查筛选条件。';
			return;
		}
		validation = '';
		await goto(resolve(`/workouts?${url.searchParams}`), { noScroll: true, keepFocus: true });
	}
	async function clearFilters() {
		fromDate = '';
		throughDate = '';
		tagDraft = '';
		const url = new URL(page.url);
		for (const key of ['sport', 'from', 'through', 'tag']) url.searchParams.delete(key);
		validation = '';
		await goto(resolve(`/workouts?${url.searchParams}`), { noScroll: true, keepFocus: true });
	}
	async function filter(value: string) {
		validation = '';
		const url = new URL(page.url);
		if (value) url.searchParams.set('sport', value);
		else url.searchParams.delete('sport');
		await goto(resolve(`/workouts?${url.searchParams}`), { noScroll: true, keepFocus: true });
	}
	const suffix: '' | `?scenario=${string}` = $derived(
		scenario !== 'normal' ? (`?scenario=${scenario}` as const) : ''
	);
</script>

<svelte:head><title>训练 · AI Fitness</title></svelte:head>
<header class="page-heading">
	<div>
		<div class="eyebrow">TRAINING LOG</div>
		<h1>每一次训练，都值得回看</h1>
		<p class="subtle">记录你的节奏，读懂每一段努力。</p>
	</div>
	{#if demo}<a class="button" href={resolve('/demo')}>演示说明 <Icon kind="arrow" size={16} /></a
		>{:else}<div class="form-actions">
			<a class="button primary" href={resolve('/workouts/import')}>上传 FIT</a><a
				class="button"
				href={resolve('/workouts/new')}>手动录入</a
			>
		</div>{/if}
</header>
<div class="list-toolbar">
	<div class="filters" aria-label="运动类型">
		<button class:chosen={!selectedSport} aria-pressed={!selectedSport} onclick={() => filter('')}
			>全部训练</button
		><button
			class:chosen={selectedSport === 'cycling'}
			aria-pressed={selectedSport === 'cycling'}
			onclick={() => filter('cycling')}>骑行</button
		><button
			class:chosen={selectedSport === 'running'}
			aria-pressed={selectedSport === 'running'}
			onclick={() => filter('running')}>跑步</button
		>
	</div>
	<span class="small subtle">按开始时间排序 · 本地时区</span>
</div>
<form class="surface form-stack filter-form" onsubmit={applyFilters}>
	<div class="filter-fields">
		<label>开始日期<input type="date" name="from" bind:value={fromDate} /></label>
		<label>结束日期（含当天）<input type="date" name="through" bind:value={throughDate} /></label>
		<label>标签（精确匹配）<input name="tag" bind:value={tagDraft} /></label>
	</div>
	<div class="form-actions">
		<button class="button primary">应用筛选</button><button
			type="button"
			class="button"
			onclick={clearFilters}>清除筛选</button
		>
	</div>
	<p class="small subtle">按训练开始时间筛选 · {timezone}</p>
	{#if filterError}<p class="form-error" role="alert">{filterError}</p>{/if}
</form>
{#if !filters.success}<div class="status">请修正筛选条件后再查看训练。</div>
{:else if query.isPending}<div class="status" role="status">正在读取训练记录…</div>
{:else if query.isError && !query.data}<Feedback error={query.error} {retry} />
{:else if !items.length}<div class="feedback">
		<Icon size={32} />
		<h2>还没有训练记录</h2>
		<p>
			{demo
				? '当前筛选下没有训练。可以切换运动类型，或在演示场景中选择正常数据。'
				: '当前筛选下没有训练记录。可以切换运动类型，或手动录入一次训练。'}
		</p>
		<button class="button" onclick={clearFilters}>查看全部训练</button>
	</div>
{:else}
	{#each groups as [day, activities] (day)}<section class="activity-group">
			<h2>{day}</h2>
			<div class="activity-list">
				{#each activities as activity (activity.id)}{@const summary =
						commonCard(activity)}{@const timing = timeSummary(summary)}{@const kind =
						activity.summary.type === 'cyclingSummary' ? 'cycling' : 'running'}
					<a
						data-return-focus={`workout-${activity.id}`}
						use:restoreFocus
						class="activity-row"
						href={resolve(`/workouts/[id]${suffix}`, { id: activity.id })}
					>
						<span class="sport-icon"><Icon {kind} size={26} /></span>
						<div class="activity-identity">
							<span class="activity-type"
								>{kind === 'cycling' ? '骑行' : '跑步'} · {new Date(
									activity.range.rangeStart
								).toLocaleTimeString('zh-CN', {
									hour: '2-digit',
									minute: '2-digit',
									hour12: false
								})}</span
							>
							<h3>{activity.userData.workoutTitle ?? '未命名训练'}</h3>
							<div class="tags">
								{#each activity.userData.workoutTags as tag, i (i)}<span class="tag">{tag}</span
									>{/each}
							</div>
						</div>
						<div class="activity-numbers">
							<div>
								<strong>{valueText(summary.summaryDistance, 0.001, 1)} <small>km</small></strong
								><span>距离</span>
							</div>
							<div><strong>{duration(timing.seconds)}</strong><span>{timing.label}</span></div>
						</div>
						<span class="row-arrow"><Icon kind="arrow" size={18} /></span>
					</a>
				{/each}
			</div>
		</section>{/each}
	{#if query.isError}<Feedback error={query.error} {retry} />{/if}
	<div class="list-footer">
		{#if query.hasNextPage}<button
				class="button"
				disabled={query.isFetching}
				onclick={() =>
					query.error instanceof ApiError && query.error.code === 'invalid_cursor'
						? retry()
						: query.fetchNextPage()}
				>{query.isFetchingNextPage ? '正在读取…' : '加载更多训练'}</button
			>{:else}<span class="small subtle">已显示全部 {items.length} 条训练</span>{/if}
	</div>
{/if}

<style>
	.filter-form {
		margin-bottom: 28px;
	}
	.filter-fields {
		display: grid;
		grid-template-columns: 1fr 1fr 1.2fr;
		gap: 16px;
	}
	@media (max-width: 850px) {
		.filter-fields {
			grid-template-columns: 1fr;
		}
	}
	.list-toolbar {
		display: flex;
		justify-content: space-between;
		align-items: center;
		flex-wrap: wrap;
		gap: 16px;
		margin: 30px 0 34px;
	}
	.filters {
		display: flex;
		padding: 4px;
		background: var(--soft);
		border-radius: 11px;
	}
	.filters button {
		padding: 9px 18px;
		min-height: 44px;
		border: 0;
		background: transparent;
		color: var(--muted);
		border-radius: 8px;
		font-size: 14px;
	}
	.filters .chosen {
		background: var(--panel);
		color: var(--text);
		font-weight: 600;
	}
	.activity-group {
		margin-bottom: 28px;
	}
	.activity-group h2 {
		font-size: 15px;
		color: var(--muted);
		margin-bottom: 12px;
		font-weight: 500;
	}
	.activity-list {
		background: var(--panel);
		border-radius: 18px;
		overflow: clip;
	}
	.activity-row {
		display: flex;
		align-items: center;
		gap: 20px;
		padding: 26px;
		border-bottom: 1px solid var(--line);
	}
	.activity-row:last-child {
		border: 0;
	}
	.activity-row:hover {
		background: var(--soft);
		color: inherit;
	}
	.activity-row:focus-visible {
		outline-offset: -4px;
	}
	.sport-icon {
		display: grid;
		place-items: center;
		width: 52px;
		height: 52px;
		background: var(--soft);
		color: var(--blue);
		border-radius: 14px;
		flex-shrink: 0;
	}
	.activity-identity {
		flex: 1;
		min-width: 0;
	}
	.activity-identity h3 {
		margin: 5px 0 9px;
		overflow-wrap: anywhere;
	}
	.activity-type {
		font-size: 13px;
		color: var(--muted);
	}
	.tags {
		display: flex;
		gap: 6px;
		flex-wrap: wrap;
	}
	.activity-numbers {
		display: flex;
		gap: 40px;
	}
	.activity-numbers strong {
		display: block;
		font-size: 20px;
		font-weight: 550;
		font-variant-numeric: tabular-nums;
	}
	.activity-numbers small {
		font-size: 13px;
		font-weight: 400;
	}
	.activity-numbers span {
		font-size: 13px;
		color: var(--muted);
	}
	.row-arrow {
		color: var(--muted);
		margin-left: 12px;
	}
	.list-footer {
		display: flex;
		justify-content: center;
		padding: 12px;
	}
	@media (max-width: 950px) {
		.activity-numbers {
			gap: 20px;
		}
	}
	@media (max-width: 700px) {
		.activity-row {
			position: relative;
			flex-wrap: wrap;
			padding: 20px;
			gap: 12px;
		}
		.sport-icon {
			width: 44px;
			height: 44px;
		}
		.activity-identity {
			width: calc(100% - 70px);
			flex: auto;
			padding-right: 12px;
		}
		.activity-numbers {
			width: 100%;
			padding-top: 12px;
			border-top: 1px solid #f1f2f5;
			gap: 32px;
		}
		.row-arrow {
			position: absolute;
			right: 15px;
			top: 40px;
		}
		.filters button {
			font-size: 15px;
			padding: 8px 14px;
		}
		.activity-group h2 {
			font-size: 15px;
		}
	}
</style>
