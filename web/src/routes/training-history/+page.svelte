<script lang="ts">
	import { m as L } from '$lib/paraglide/messages.js';
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
			validation = cause instanceof Error ? cause.message : L.validation_check_inputs();
		}
	}
	const rows = $derived(query.data?.trainingDays ?? []);
</script>

<svelte:head><title>{L.page_history_title()}</title></svelte:head>
<header class="page-heading">
	<div>
		<div class="eyebrow">{L.eyebrow_training_history()}</div>
		<h1>{L.page_history()}</h1>
		<p class="subtle">{L.history_subtitle()} {zone}</p>
	</div>
</header>
{#if demo}<p>{L.history_sign_in()}</p>{:else}
	<form
		class="surface"
		onsubmit={(event) => {
			event.preventDefault();
			calculate();
		}}
	>
		<h2>{L.history_inputs()}</h2>
		<div class="fields">
			<label>{L.label_start_date()}<input type="date" required bind:value={from} /></label><label
				>{L.label_end_date()}<input type="date" required bind:value={through} /></label
			>
			<label
				>{L.history_initial_load()}<select required bind:value={initial}
					><option value="" disabled>{L.action_select()}</option><option value="zero"
						>{L.history_assume_zero()}</option
					><option value="known">{L.history_enter_initial()}</option></select
				></label
			>
			{#if initial === 'known'}<label
					>{L.history_initial_ctl()}<input
						type="number"
						required
						min="0"
						step="any"
						bind:value={fitness}
					/></label
				><label
					>{L.history_initial_atl()}<input
						type="number"
						required
						min="0"
						step="any"
						bind:value={fatigue}
					/></label
				>{/if}
		</div>
		<h3>{L.history_completeness()}</h3>
		<p class="small subtle">
			{L.history_completeness_note()}
		</p>
		<label
			><input
				type="checkbox"
				checked={days.length > 0 && days.every((d) => complete.includes(d.calendarDate))}
				onchange={(e) =>
					(complete = e.currentTarget.checked ? days.map((d) => d.calendarDate) : [])}
			/>{L.history_confirm_all()}</label
		>
		<details>
			<summary>{L.history_confirm_days({ count: days.length })}</summary>
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
		<button class="button primary" disabled={query.isFetching}>{L.history_calculate()}</button>
	</form>
	{#if submitted}<section class="section" aria-label={L.history_results()}>
			<h2>{L.history_results()}</h2>
			<p class="small subtle">
				{L.history_submitted({
					start: submitted.historyCalendar[0].calendarDate,
					end: submitted.historyCalendar.at(-1)?.calendarDate ?? '',
					initial: submitted.historyAssumeNoPriorLoad
						? L.history_zero_assumption()
						: `CTL ${submitted.historyPriorFitness} / ATL ${submitted.historyPriorFatigue}`
				})}
			</p>
			{#if query.isPending}<p role="status">
					{L.history_calculating()}
				</p>{:else if query.isError}<Feedback
					error={query.error}
					retry={() => query.refetch()}
				/>{:else if query.data}<div class="surface">
					<AnalysisPlot
						kind="line"
						xLabel={L.history_local_date()}
						yLabel={L.history_hrss()}
						labels={rows.map((d) => d.trainingCalendar.calendarDate)}
						series={[
							{ name: L.history_ctl(), values: rows.map((d) => d.trainingFitness ?? null) },
							{ name: L.history_atl(), values: rows.map((d) => d.trainingFatigue ?? null) },
							{ name: L.history_balance(), values: rows.map((d) => d.trainingBalance ?? null) }
						]}
					/>
					<div class="table-scroll" role="region" aria-label={L.history_table()}>
						<table>
							<thead
								><tr
									><th>{L.label_date()}</th><th>{L.history_completeness_column()}</th><th
										>{L.history_workouts()}</th
									><th>{L.history_known_hrss()}</th><th>{L.history_daily_hrss()}</th><th>CTL</th><th
										>ATL</th
									><th>{L.label_balance()}</th><th>{L.history_initial_weight()}</th></tr
								></thead
							><tbody
								>{#each rows as row (row.trainingCalendar.calendarDate)}<tr
										><td>{row.trainingCalendar.calendarDate}</td><td
											>{row.trainingCalendar.calendarRecordingComplete
												? L.status_confirmed()
												: L.status_unknown()}</td
										><td>{row.trainingWorkoutCount}</td><td
											>{valueText(row.trainingKnownLoad, 1, 2)}</td
										><td
											>{row.trainingTotalLoad === undefined
												? L.status_unknown()
												: valueText(row.trainingTotalLoad, 1, 2)}</td
										><td
											>{row.trainingFitness === undefined
												? L.status_unknown()
												: valueText(row.trainingFitness, 1, 2)}</td
										><td
											>{row.trainingFatigue === undefined
												? L.status_unknown()
												: valueText(row.trainingFatigue, 1, 2)}</td
										><td
											>{row.trainingBalance === undefined
												? L.status_unknown()
												: valueText(row.trainingBalance, 1, 2)}</td
										><td>{valueText(row.trainingInitialFitnessWeight, 100, 1)}%</td></tr
									>{/each}</tbody
							>
						</table>
					</div>
					<p class="small subtle">
						{L.history_method_note({
							method: query.data.trainingMethod,
							revision: query.data.trainingSettingsRevision
						})}
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
