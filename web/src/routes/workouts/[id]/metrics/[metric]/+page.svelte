<script lang="ts">
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import WorkoutGate from '$lib/components/WorkoutGate.svelte';
	import MetricAnalysis from '$lib/components/MetricAnalysis.svelte';
	import { readScenario } from '$lib/api/read';
	import { metrics } from '$lib/workouts/presentation';
	const id = $derived(page.params.id ?? '');
	const scenario = $derived(readScenario(page.url.searchParams.get('scenario')));
	const suffix: '' | `?scenario=${string}` = $derived(
		scenario !== 'normal' ? (`?scenario=${scenario}` as const) : ''
	);
</script>

<svelte:head><title>指标分析 · AI Fitness</title></svelte:head>
<nav class="breadcrumb" aria-label="面包屑">
	<a href={resolve(`/workouts${suffix}`)}>训练</a><span>/</span><a
		href={resolve(`/workouts/[id]${suffix}`, { id })}>训练详情</a
	><span>/</span><span>指标分析</span>
</nav>
<WorkoutGate {id} {scenario}>
	{#snippet children(workout)}{@const metric = metrics(workout).find(
			(m) => m.key === page.params.metric
		)}
		{#if metric}{#key `${id}/${metric.key}/${scenario}`}<MetricAnalysis {workout} {metric} />{/key}
		{:else}<div class="feedback">
				<h1>这项指标没有可用数据</h1>
				<p>可以返回训练详情，查看其他已记录的指标。</p>
				<a class="button" href={resolve(`/workouts/[id]${suffix}`, { id })}>返回训练详情</a>
			</div>{/if}
	{/snippet}
</WorkoutGate>
