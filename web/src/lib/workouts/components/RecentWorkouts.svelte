<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { browser } from '$app/environment';
	import { resolve } from '$app/paths';
	import { useSession } from '$lib/auth/session.svelte';
	import { loadWorkouts, type Scenario } from '$lib/api/read';
	import {
		dateText,
		commonCard,
		timeSummary,
		duration,
		valueText
	} from '$lib/workouts/presentation';

	let { id, scenario }: { id: string; scenario: Scenario } = $props();
	const session = useSession();
	const suffix = $derived(scenario === 'normal' ? '' : (`?scenario=${scenario}` as const));
	const query = createQuery(() => ({
		queryKey: ['workouts', session.user?.id ?? 'demo', 'recent', scenario],
		enabled: browser,
		queryFn: ({ signal }) => loadWorkouts({ limit: 5 }, signal, scenario)
	}));
</script>

<aside aria-label="近期训练" class="recent">
	<h2>近期训练</h2>
	{#each query.data?.items ?? [] as item (item.id)}<a
			class:active={item.id === id}
			aria-current={item.id === id ? 'page' : undefined}
			href={resolve(`/workouts/[id]${suffix}`, { id: item.id })}
			><small>{dateText(item.range.rangeStart)}</small><strong
				>{item.userData.workoutTitle ?? '未命名训练'}</strong
			><small
				>{valueText(commonCard(item).summaryDistance, 0.001, 1)} km · {duration(
					timeSummary(commonCard(item)).seconds
				)}</small
			></a
		>{/each}
	{#if query.isPending}<p class="small subtle">正在加载…</p>{:else if query.isError}<p
			class="small subtle"
		>
			暂时无法读取近期训练
		</p>{/if}
</aside>

<style>
	.recent {
		display: grid;
		align-content: start;
		gap: 8px;
	}
	h2 {
		font-size: 11px;
		color: var(--muted);
		margin: 12px 8px;
	}
	a {
		padding: 12px 10px;
		border-radius: 0;
		font-size: 11px;
		overflow-wrap: anywhere;
	}
	a:hover,
	a.active {
		background: var(--soft);
		color: var(--blue);
	}
	small {
		display: block;
		margin-top: 4px;
		color: var(--muted);
		font-size: 11px;
	}
	a.active {
		border-left: 3px solid var(--blue);
		padding-left: 7px;
	}
	strong {
		display: block;
		font-size: 12px;
		font-weight: 550;
	}
</style>
