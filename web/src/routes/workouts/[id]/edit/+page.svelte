<script lang="ts">
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import WorkoutGate from '$lib/workouts/components/WorkoutGate.svelte';
	import WorkoutEditor from '$lib/workouts/components/WorkoutEditor.svelte';

	const demo = import.meta.env.MODE === 'demo';
	const id = $derived(page.params.id ?? '');
</script>

<svelte:head><title>编辑训练 · AI Fitness</title></svelte:head>
<nav class="breadcrumb" aria-label="面包屑">
	<a href={resolve('/workouts')}>训练</a><span>/</span>
	<a href={resolve('/workouts/[id]', { id })}>训练详情</a><span>/</span><span>编辑</span>
</nav>
<header class="page-heading">
	<div>
		<div class="eyebrow">WORKOUT DETAILS</div>
		<h1>编辑训练</h1>
	</div>
</header>
{#if demo}<div class="status">编辑与删除需要登录真实账号，演示模式仅供查看。</div>
{:else}<WorkoutGate {id} scenario="normal">
		{#snippet children(workout)}{#key id}<WorkoutEditor {workout} />{/key}{/snippet}
	</WorkoutGate>{/if}
