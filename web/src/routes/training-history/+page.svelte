<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { useSession } from '$lib/auth/session.svelte';
	import {
		postAnalysisTrainingHistory,
		type TrainingHistoryRequest
	} from '$lib/api/generated/client';
	import { postAnalysisTrainingHistory200Response } from '$lib/api/generated/schemas';
	import { request } from '$lib/api/request';
	import { calendarDays, defaultHistoryRange, historyRequest } from '$lib/analysis/calendar';
	import { valueText } from '$lib/workouts/presentation';
	import Feedback from '$lib/components/Feedback.svelte';
	import AnalysisPlot from '$lib/analysis/AnalysisPlot.svelte';
	const session = useSession();
	const demo = import.meta.env.MODE === 'demo';
	const range = defaultHistoryRange();
	let from = $state(range.from),
		through = $state(range.through);
	const days = $derived(calendarDays(from, through));
	let complete = $state<string[]>([]);
	let initial = $state('');
	let fitness = $state<number | undefined>(),
		fatigue = $state<number | undefined>();
	let validation = $state('');
	let submitted = $state<TrainingHistoryRequest>();
	const zone = Intl.DateTimeFormat().resolvedOptions().timeZone;
	const query = createQuery(() => ({
		queryKey: ['training-history', session.user?.id, submitted],
		enabled: !!submitted && !!session.user && !demo,
		queryFn: ({ signal }) => {
			if (!submitted) throw new Error('No submitted calendar');
			const input = submitted;
			return session.run((csrf, options) =>
				request(
					() =>
						postAnalysisTrainingHistory(
							input,
							{ 'X-CSRF-Token': csrf },
							{
								...options,
								// Session clear also cancels Query requests; session.run rejects late results.
								signal
							}
						),
					postAnalysisTrainingHistory200Response
				)
			);
		}
	}));
	function calculate() {
		validation = '';
		try {
			const next = historyRequest(days, new Set(complete), initial, fitness, fatigue);
			if (JSON.stringify(next) === JSON.stringify(submitted)) void query.refetch();
			else submitted = next;
		} catch (cause) {
			validation = cause instanceof Error ? cause.message : '请检查输入。';
		}
	}
	const rows = $derived(query.data?.trainingDays ?? []);
</script>

<svelte:head><title>体能与疲劳趋势 · AI Fitness</title></svelte:head>
<header class="page-heading">
	<div>
		<div class="eyebrow">TRAINING HISTORY</div>
		<h1>体能与疲劳趋势</h1>
		<p class="subtle">HRSS · CTL / ATL · 本地日历 {zone}</p>
	</div>
</header>
{#if demo}<p>训练历史需要登录真实账号。</p>{:else}
	<form
		class="surface"
		onsubmit={(event) => {
			event.preventDefault();
			calculate();
		}}
	>
		<h2>分析输入</h2>
		<div class="fields">
			<label>开始日期<input type="date" required bind:value={from} /></label><label
				>结束日期<input type="date" required bind:value={through} /></label
			>
			<label
				>开始前的训练负荷<select required bind:value={initial}
					><option value="" disabled>请选择</option><option value="zero"
						>明确假设此前无训练负荷</option
					><option value="known">填写已知 CTL / ATL</option></select
				></label
			>
			{#if initial === 'known'}<label
					>初始 CTL<input type="number" required min="0" step="any" bind:value={fitness} /></label
				><label
					>初始 ATL<input type="number" required min="0" step="any" bind:value={fatigue} /></label
				>{/if}
		</div>
		<h3>每日记录完整性</h3>
		<p class="small subtle">
			仅确认已完整记录的日期。完整且无训练的日期视为休息；未确认或心率覆盖不足的日期为未知，之后的
			CTL / ATL 也保持未知。不会用功率或配速负荷补足。
		</p>
		<label
			><input
				type="checkbox"
				checked={days.length > 0 && days.every((d) => complete.includes(d.calendarDate))}
				onchange={(e) =>
					(complete = e.currentTarget.checked ? days.map((d) => d.calendarDate) : [])}
			/>确认所选日期全部记录完整</label
		>
		<details>
			<summary>逐日确认（{days.length} 天）</summary>
			<div class="days">
				{#each days as day (day.calendarDate)}<label
						><input
							type="checkbox"
							value={day.calendarDate}
							bind:group={complete}
						/>{day.calendarDate}</label
					>{/each}
			</div>
		</details>
		{#if validation}<p class="form-error" role="alert">{validation}</p>{/if}
		<button class="button primary" disabled={query.isFetching}>计算训练历史</button>
	</form>
	{#if submitted}<section class="section" aria-label="训练历史结果">
			<h2>训练历史结果</h2>
			<p class="small subtle">
				已提交日期：{submitted.historyCalendar[0].calendarDate} — {submitted.historyCalendar.at(-1)
					?.calendarDate} · 初始状态：{submitted.historyAssumeNoPriorLoad
					? '明确假设零负荷'
					: `CTL ${submitted.historyPriorFitness} / ATL ${submitted.historyPriorFatigue}`}。修改输入后请重新计算。
			</p>
			{#if query.isPending}<p role="status">正在计算训练历史…</p>{:else if query.isError}<Feedback
					error={query.error}
					retry={() => query.refetch()}
				/>{:else if query.data}<div class="surface">
					<AnalysisPlot
						kind="line"
						xLabel="本地日期"
						yLabel="HRSS 负荷"
						labels={rows.map((d) => d.trainingCalendar.calendarDate)}
						series={[
							{ name: 'CTL 体能', values: rows.map((d) => d.trainingFitness ?? null) },
							{ name: 'ATL 疲劳', values: rows.map((d) => d.trainingFatigue ?? null) },
							{ name: '负荷平衡', values: rows.map((d) => d.trainingBalance ?? null) }
						]}
					/>
					<div class="table-scroll" role="region" aria-label="训练历史表">
						<table>
							<thead
								><tr
									><th>日期</th><th>完整性</th><th>训练数</th><th>已知部分 HRSS</th><th
										>全天 HRSS</th
									><th>CTL</th><th>ATL</th><th>平衡</th><th>初始 CTL 剩余权重</th></tr
								></thead
							><tbody
								>{#each rows as row (row.trainingCalendar.calendarDate)}<tr
										><td>{row.trainingCalendar.calendarDate}</td><td
											>{row.trainingCalendar.calendarRecordingComplete ? '已确认' : '未知'}</td
										><td>{row.trainingWorkoutCount}</td><td
											>{valueText(row.trainingKnownLoad, 1, 2)}</td
										><td
											>{row.trainingTotalLoad === undefined
												? '未知'
												: valueText(row.trainingTotalLoad, 1, 2)}</td
										><td
											>{row.trainingFitness === undefined
												? '未知'
												: valueText(row.trainingFitness, 1, 2)}</td
										><td
											>{row.trainingFatigue === undefined
												? '未知'
												: valueText(row.trainingFatigue, 1, 2)}</td
										><td
											>{row.trainingBalance === undefined
												? '未知'
												: valueText(row.trainingBalance, 1, 2)}</td
										><td>{valueText(row.trainingInitialFitnessWeight, 100, 1)}%</td></tr
									>{/each}</tbody
							>
						</table>
					</div>
					<p class="small subtle">
						算法 {query.data.trainingMethod} · 参数版本 {query.data.trainingSettingsRevision} · 所有负荷与衰减由后端计算；不用于判断健康风险。
					</p>
				</div>{/if}
		</section>{/if}
{/if}

<style>
	h2 {
		font-size: 20px;
		margin-bottom: 16px;
	}
	h3 {
		font-size: 16px;
	}
	p {
		margin: 12px 0;
	}
	.fields {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(min(220px, 100%), 1fr));
		gap: 16px;
		margin-bottom: 20px;
	}
	.fields input,
	.fields select {
		display: block;
		width: 100%;
		margin-top: 6px;
	}
	.days {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
		gap: 8px;
		margin: 12px 0;
	}
	summary {
		padding: 12px 0;
		cursor: pointer;
	}
	input[type='checkbox'] {
		margin-right: 8px;
	}
</style>
