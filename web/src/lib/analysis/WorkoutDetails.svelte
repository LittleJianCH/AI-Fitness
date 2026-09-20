<script lang="ts">
	import { m as L } from '$lib/paraglide/messages.js';
	import { isPartialSplit } from './presentation';
	import { resolve } from '$app/paths';
	import type { Workout } from '$lib/api/generated/client';
	import { workoutAnalysisQuery } from './query.svelte';
	import { heartStatus, pace } from './presentation';
	import { valueText, duration, dateText, common } from '$lib/workouts/presentation';
	import Feedback from '$lib/components/Feedback.svelte';
	import Zones from './Zones.svelte';
	import ValueRows from './ValueRows.svelte';
	let { workout }: { workout: Workout } = $props();
	const { query, refresh } = workoutAnalysisQuery(() => workout);
	const sport = $derived(workout.workoutObservation.observationSport);
	const running = $derived(sport.type === 'running');
	const recorded = $derived(common(workout));
	const laps = $derived(
		sport.type === 'cycling'
			? sport.data.cyclingLaps.map((l) => ({
					label: l.lapLabel,
					range: l.lapRange,
					summary: l.lapSummary.recordedSummary.cyclingCommonSummary
				}))
			: sport.data.runningLaps.map((l) => ({
					label: l.lapLabel,
					range: l.lapRange,
					summary: l.lapSummary.recordedSummary.runningCommonSummary
				}))
	);
	let length = $state(1000);
	const splits = $derived(
		query.data?.analysisSplits.find((s) => s.splitLengthMetres === length)?.distanceSplits ?? []
	);
	const speed = (value: number | undefined) =>
		running ? pace(value) : `${valueText(value, 3.6, 1)} km/h`;
</script>

{#if query.isPending}<p role="status">
		{L.analysis_workout_loading()}
	</p>{:else if query.isError}<Feedback error={query.error} retry={refresh} />{:else if query.data}
	{@const analysis = query.data}{@const power = analysis.analysisPower}{@const heart =
		analysis.analysisHeart}
	<section class="section" aria-label={L.analysis_power()}>
		<h2>{L.analysis_power()}</h2>
		<div class="surface">
			<ValueRows
				rows={[
					[L.power_normalized(), power.powerNormalized, 'W'],
					[L.power_variability(), power.powerVariabilityIndex, '', 2],
					[L.power_intensity(), power.powerIntensityFactor, '', 2],
					[L.power_stress(), power.powerStressScore, ''],
					[L.power_per_weight(), power.powerWattsPerKilogram, 'W/kg', 2],
					[
						L.power_work(),
						power.powerWorkJoules === undefined ? undefined : power.powerWorkJoules / 1000,
						'kJ'
					],
					[L.power_efficiency(), power.powerEfficiency, 'W/bpm', 2],
					[L.power_decoupling(), power.powerDecouplingPercent, '%'],
					[L.power_threshold_used(), power.powerThresholdWatts, 'W'],
					[L.power_weight_used(), power.powerAthleteKilograms, 'kg']
				]}
			/>
			<p class="small subtle">
				{L.power_analysis_note({ duration: duration(power.powerNormalizationSeconds) })}
			</p>
			<Zones zones={analysis.analysisPowerZones} title={L.analysis_power_zones()} unit="W" />
			<p class="small subtle">{L.power_zone_boundaries()}</p>
		</div>
	</section>
	{#if analysis.analysisRunning}{@const r = analysis.analysisRunning}
		<section class="section" aria-label={L.running_dynamics()}>
			<h2>{L.running_dynamics()}</h2>
			<div class="surface">
				<ValueRows
					rows={[
						[L.running_steps(), r.runningSteps, L.unit_steps(), 0],
						[
							L.running_flight_time(),
							r.runningFlightSeconds === undefined ? undefined : r.runningFlightSeconds * 1000,
							'ms'
						],
						[L.running_vertical_ratio(), r.runningVerticalRatioPercent, '%'],
						[L.running_flight_ratio(), r.runningFlightRatioPercent, '%'],
						[L.running_effectiveness(), r.runningEffectiveness, '', 2]
					]}
				/>
				<p class="small subtle">
					{L.running_dynamics_note()}
				</p>
			</div>
		</section>{/if}
	<section class="section" aria-label={L.analysis_heart_load()}>
		<h2>{L.analysis_heart_load()}</h2>
		<div class="surface">
			<p>{heartStatus[heart.heartLoadStatus]}</p>
			<ValueRows
				rows={[
					['HRSS', heart.heartHrss, ''],
					['TRIMPexp', heart.heartTrimp, ''],
					[
						L.heart_coverage(),
						heart.heartCoverageFraction === undefined
							? undefined
							: heart.heartCoverageFraction * 100,
						'%'
					]
				]}
			/>
			<p class="small subtle">
				{L.heart_timing_basis({
					basis: heart.heartUsesRecordedTimer ? L.heart_recorded_timer() : L.heart_elapsed_timer(),
					active: duration(heart.heartActiveSeconds),
					covered: duration(heart.heartCoveredSeconds)
				})}
			</p>
			<Zones zones={heart.heartZones} title={L.analysis_heart_zones()} unit="bpm" />
			<p class="small subtle">
				{L.heart_zone_note()}
			</p>
			<a class="button" href={resolve('/training-history')}>{L.history_link()}</a>
		</div>
	</section>
	<section class="section" aria-label={L.splits_distance()}>
		<h2>{L.splits_distance()}</h2>
		<div class="surface">
			<label
				>{L.splits_length()}<select bind:value={length}
					><option value={1000}>1 km</option><option value={5000}>5 km</option></select
				></label
			>
			{#if splits.length}<div class="table-scroll" role="region" aria-label={L.splits_table()}>
					<table>
						<thead
							><tr
								><th>{L.splits_split()}</th><th>{L.label_distance_km()}</th><th
									>{L.label_duration()}</th
								><th>{running ? L.label_pace_km() : L.label_speed_kmh()}</th><th
									>{L.label_heart_bpm()}</th
								><th>{L.label_power_watts()}</th><th
									>{running ? L.label_running_cadence() : L.label_cycling_cadence()}</th
								><th>{L.label_elevation_change()}</th></tr
							></thead
						><tbody
							>{#each splits as split (split.splitIndex)}<tr
									><td>{split.splitIndex}</td><td
										>{valueText(split.splitDistanceMetres, 0.001, 3)}{isPartialSplit(
											split.splitDistanceMetres,
											length
										)
											? L.splits_partial()
											: ''}</td
									><td>{duration(split.splitEndSeconds - split.splitStartSeconds)}</td><td
										>{speed(split.splitAverageSpeed)}</td
									><td>{valueText(split.splitHeartRate)}</td><td>{valueText(split.splitPower)}</td
									><td>{valueText(split.splitCadence)}</td><td
										>{valueText(split.splitElevationChange, 1, 1)}</td
									></tr
								>{/each}</tbody
						>
					</table>
				</div>{:else}<p>{L.splits_missing()}</p>{/if}
			{#if analysis.analysisHalves}<dl class="stats-rows">
					<div>
						<dt>{L.splits_first_half()}</dt>
						<dd>{speed(analysis.analysisHalves.firstHalfSpeed)}</dd>
					</div>
					<div>
						<dt>{L.splits_second_half()}</dt>
						<dd>{speed(analysis.analysisHalves.secondHalfSpeed)}</dd>
					</div>
					<div>
						<dt>{L.splits_speed_change()}</dt>
						<dd>{valueText(analysis.analysisHalves.secondHalfChangePercent, 1, 1)}%</dd>
					</div>
				</dl>{/if}
			<p class="small subtle">
				{L.splits_note()}
			</p>
		</div>
	</section>
	<section class="section">
		<h2>{L.laps_source()}</h2>
		<div class="surface">
			{#if laps.length}<div class="table-scroll" role="region" aria-label={L.laps_table()}>
					<table>
						<thead
							><tr
								><th>{L.laps_lap()}</th><th>{L.label_start_time()}</th><th
									>{L.label_distance_km()}</th
								><th>{L.label_elapsed_time()}</th><th>{L.label_recorded_heart()}</th><th
									>{L.label_recorded_power()}</th
								></tr
							></thead
						><tbody
							>{#each laps as lap, i (i)}<tr
									><td>{lap.label ?? L.lap_number({ number: i + 1 })}</td><td
										>{dateText(lap.range.rangeStart)}</td
									><td>{valueText(lap.summary.summaryDistance, 0.001, 2)}</td><td
										>{duration(lap.summary.summaryElapsedTime)}</td
									><td>{valueText(lap.summary.summaryHeartRate.averageValue)}</td><td
										>{valueText(lap.summary.summaryPower.averageValue)}</td
									></tr
								>{/each}</tbody
						>
					</table>
				</div>{:else}<p class="subtle">{L.laps_missing()}</p>{/if}
		</div>
	</section>
	<section class="section">
		<h2>{L.analysis_provenance()}</h2>
		<div class="surface">
			<h3>{L.recorded_summary_equipment()}</h3>
			<ValueRows
				rows={[
					[L.recorded_ascent(), recorded.summaryAscent, 'm'],
					[L.recorded_descent(), recorded.summaryDescent, 'm'],
					[L.recorded_altitude(), recorded.summaryAltitude.averageValue, 'm'],
					[
						L.recorded_work(),
						recorded.summaryMechanicalWork === undefined
							? undefined
							: recorded.summaryMechanicalWork / 1000,
						'kJ'
					],
					[
						L.recorded_energy(),
						recorded.summaryMetabolicEnergy === undefined
							? undefined
							: recorded.summaryMetabolicEnergy / 1000,
						'kJ'
					]
				]}
			/>
			{#if sport.type === 'cycling'}<p>
					{L.recorded_bicycle({
						name: sport.data.cyclingContext.bicycleName ?? L.value_not_recorded(),
						weight: valueText(sport.data.cyclingContext.bicycleMass, 1, 2)
					})}
				</p>{/if}
			<p class="small subtle">{L.recorded_note()}</p>
			<details>
				<summary>{L.analysis_method_profile()}</summary>
				<dl class="stats-rows">
					<div>
						<dt>{L.analysis_algorithm()}</dt>
						<dd>{analysis.analysisMethod}</dd>
					</div>
					<div>
						<dt>{L.analysis_workout_revision()}</dt>
						<dd>{analysis.analysisRevision}</dd>
					</div>
					<div>
						<dt>{L.analysis_profile_revision()}</dt>
						<dd>{analysis.analysisSettingsRevision}</dd>
					</div>
					<div>
						<dt>{L.analysis_profile_effective()}</dt>
						<dd>
							{analysis.analysisBodyProfile
								? dateText(analysis.analysisBodyProfile.bodyEffectiveFrom)
								: L.analysis_profile_absent()}
						</dd>
					</div>
				</dl>
				<p>
					{L.analysis_sampling_note({ seconds: analysis.analysisMaxGapSeconds })}
				</p>
				{#each analysis.analysisNotes as note, i (i)}<p class="small subtle">{note}</p>{/each}
			</details>
			<button class="button" onclick={refresh} disabled={query.isFetching}
				>{L.analysis_refresh()}</button
			>
		</div>
	</section>
{/if}

<style>
	h2 {
		font-size: 20px;
		margin-bottom: 12px;
	}
	h3 {
		font-size: 16px;
	}
	p {
		margin: 12px 0;
	}
	label {
		display: flex;
		align-items: center;
		gap: 12px;
		flex-wrap: wrap;
	}
	summary {
		padding: 12px 0;
		cursor: pointer;
	}
	.stats-rows dd {
		overflow-wrap: anywhere;
	}
</style>
