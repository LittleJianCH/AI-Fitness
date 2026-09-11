<script lang="ts">
	import { page } from '$app/state';
	import { createFocusSnapshot, type FocusSnapshot } from '$lib/focus-snapshot.svelte';
	import type { Snapshot } from '@sveltejs/kit';
	import { untrack } from 'svelte';
	const focus = createFocusSnapshot();
	let restoration = $state<{ focus: FocusSnapshot; pages: number; url: string } | null>(null);
	export const snapshot: Snapshot<{ focus: FocusSnapshot; pages: number }> = {
		capture: () => ({ focus: focus.snapshot.capture(), pages: query.data?.pages.length ?? 1 }),
		restore: (saved) => {
			restoration = { ...saved, url: page.url.href };
		}
	};
	const restoreFocus = focus.restoreFocus;
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { createInfiniteQuery } from '@tanstack/svelte-query';
	import { loadWorkouts, readScenario, sportSchema } from '$lib/api/read';
	import {
		commonCard,
		groupCards,
		duration,
		timeSummary,
		valueText
	} from '$lib/workouts/presentation';
	import Icon from '$lib/components/Icon.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	const sport = $derived(sportSchema.safeParse(page.url.searchParams.get('sport')));
	const selectedSport = $derived(sport.success ? sport.data : undefined);
	const scenario = $derived(readScenario(page.url.searchParams.get('scenario')));
	const query = createInfiniteQuery(() => ({
		queryKey: ['workouts', selectedSport, scenario],
		queryFn: ({ signal, pageParam }) =>
			loadWorkouts({ sport: selectedSport, cursor: pageParam, limit: 3 }, signal, scenario),
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
	async function filter(value: string) {
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
	<a class="button" href={resolve('/demo')}>演示说明 <Icon kind="arrow" size={16} /></a>
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
{#if query.isPending}<div class="status" role="status">正在读取训练记录…</div>
{:else if query.isError && !query.data}<Feedback
		error={query.error}
		retry={() => query.refetch()}
	/>
{:else if !items.length}<div class="feedback">
		<Icon size={32} />
		<h2>还没有训练记录</h2>
		<p>当前筛选下没有训练。可以切换运动类型，或在演示场景中选择正常数据。</p>
		<button class="button" onclick={() => filter('')}>查看全部训练</button>
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
	{#if query.isError}<Feedback
			error={query.error}
			retry={() => (query.isFetchNextPageError ? query.fetchNextPage() : query.refetch())}
		/>{/if}
	<div class="list-footer">
		{#if query.hasNextPage}<button
				class="button"
				disabled={query.isFetchingNextPage}
				onclick={() => query.fetchNextPage()}
				>{query.isFetchingNextPage ? '正在读取…' : '加载更多训练'}</button
			>{:else}<span class="small subtle">已显示全部 {items.length} 条训练</span>{/if}
	</div>
{/if}

<style>
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
		background: #e9ebf1;
		border-radius: 11px;
	}
	.filters button {
		padding: 9px 18px;
		min-height: 44px;
		border: 0;
		background: transparent;
		color: #606672;
		border-radius: 8px;
		font-size: 14px;
	}
	.filters .chosen {
		background: #fff;
		color: #171923;
		font-weight: 600;
	}
	.activity-group {
		margin-bottom: 28px;
	}
	.activity-group h2 {
		font-size: 15px;
		color: #606672;
		margin-bottom: 12px;
		font-weight: 500;
	}
	.activity-list {
		background: #fff;
		border-radius: 18px;
		overflow: clip;
	}
	.activity-row {
		display: flex;
		align-items: center;
		gap: 20px;
		padding: 26px;
		border-bottom: 1px solid #e6e8ee;
	}
	.activity-row:last-child {
		border: 0;
	}
	.activity-row:hover {
		background: #fafbfe;
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
		background: #f0f4fc;
		color: #1769d2;
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
		color: #606672;
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
		color: #606672;
	}
	.row-arrow {
		color: #606672;
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
