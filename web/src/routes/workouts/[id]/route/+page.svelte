<script lang="ts">
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import WorkoutGate from '$lib/components/WorkoutGate.svelte';
	import RoutePlot from '$lib/components/RoutePlot.svelte';
	import { readScenario } from '$lib/api/read';
	import { motion, duration } from '$lib/workouts/presentation';
	const id = $derived(page.params.id ?? '');
	const scenario = $derived(readScenario(page.url.searchParams.get('scenario')));
	const suffix: '' | `?scenario=${string}` = $derived(
		scenario !== 'normal' ? (`?scenario=${scenario}` as const) : ''
	);
	let selection = $state({ id: '', index: 0 });
	const selected = $derived(selection.id === id ? selection.index : 0);
	function selectSample(event: Event) {
		if (event.currentTarget instanceof HTMLInputElement)
			selection = { id, index: event.currentTarget.valueAsNumber };
	}
</script>

<svelte:head><title>轨迹 · AI Fitness</title></svelte:head>
<nav class="breadcrumb" aria-label="面包屑">
	<a href={resolve(`/workouts${suffix}`)}>训练</a><span>/</span><a
		href={resolve(`/workouts/[id]${suffix}`, { id })}>训练详情</a
	><span>/</span><span>轨迹</span>
</nav>
<WorkoutGate {id} {scenario}>
	{#snippet children(workout)}{@const samples = motion(workout).motionPosition}{@const sample =
			samples[selected]}
		<header class="page-heading">
			<div>
				<div class="eyebrow">ROUTE REVIEW</div>
				<h1>沿着轨迹，再看一次</h1>
				<p class="subtle">{workout.workoutUserData.workoutTitle}</p>
			</div>
		</header>
		{#if samples.length && sample}<section class="surface">
				<RoutePlot {samples} {selected} />
				<p class="subtle small">合成轨迹示意 · 无地图底图 · WGS84</p>
				<label for="route-sample"
					>经过时间：{duration(
						(Date.parse(sample.timestamp) -
							Date.parse(workout.workoutObservation.observationRange.rangeStart)) /
							1000
					)}</label
				><input
					id="route-sample"
					aria-label="选择轨迹样本"
					type="range"
					min="0"
					max={samples.length - 1}
					step="1"
					value={selected}
					oninput={selectSample}
				/>
				<p class="small subtle">起点为空心圆，当前选中位置为深色圆点。选择的是实际记录时间点。</p>
			</section>{:else}<div class="status">这次训练没有记录 GPS 轨迹。</div>{/if}
	{/snippet}
</WorkoutGate>

<style>
	section > p {
		margin-top: 12px;
	}
	label {
		display: block;
		margin-top: 24px;
	}
	input {
		width: 100%;
		min-height: 44px;
		accent-color: #1769d2;
	}
</style>
