<script lang="ts">
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

{#if query.isPending}<p role="status">正在读取训练分析…</p>{:else if query.isError}<Feedback
		error={query.error}
		retry={refresh}
	/>{:else if query.data}
	{@const analysis = query.data}{@const power = analysis.analysisPower}{@const heart =
		analysis.analysisHeart}
	<section class="section" aria-label="功率分析">
		<h2>功率分析</h2>
		<div class="surface">
			<ValueRows
				rows={[
					['标准化功率', power.powerNormalized, 'W'],
					['变异指数', power.powerVariabilityIndex, '', 2],
					['强度因子', power.powerIntensityFactor, '', 2],
					['功率训练压力', power.powerStressScore, ''],
					['平均功率 / 体重', power.powerWattsPerKilogram, 'W/kg', 2],
					[
						'观测机械功',
						power.powerWorkJoules === undefined ? undefined : power.powerWorkJoules / 1000,
						'kJ'
					],
					['效率因子', power.powerEfficiency, 'W/bpm', 2],
					['前后半程功率 / 心率解耦', power.powerDecouplingPercent, '%'],
					['使用的阈值功率', power.powerThresholdWatts, 'W'],
					['使用的体重', power.powerAthleteKilograms, 'kg']
				]}
			/>
			<p class="small subtle">
				功率仅连接相邻 5 秒内的采样。标准化功率需要完整 30 秒滚动窗口；归一化时长 {duration(
					power.powerNormalizationSeconds
				)}。训练压力、效率与解耦需要完整覆盖。短时或非稳态训练应谨慎解读。
			</p>
			<Zones zones={analysis.analysisPowerZones} title="功率分区" unit="W" />
			<p class="small subtle">FTP 边界：55 / 75 / 90 / 105 / 120 / 150%。</p>
		</div>
	</section>
	{#if analysis.analysisRunning}{@const r = analysis.analysisRunning}
		<section class="section" aria-label="跑姿">
			<h2>跑姿</h2>
			<div class="surface">
				<ValueRows
					rows={[
						['步数（完整步频积分）', r.runningSteps, '步', 0],
						[
							'腾空时间',
							r.runningFlightSeconds === undefined ? undefined : r.runningFlightSeconds * 1000,
							'ms'
						],
						['垂直比', r.runningVerticalRatioPercent, '%'],
						['腾空比', r.runningFlightRatioPercent, '%'],
						['跑步效率', r.runningEffectiveness, '', 2]
					]}
				/>
				<p class="small subtle">
					由后端根据有效的步频、触地时间、垂直振幅、步长、速度和功率计算；缺失输入不补零。
				</p>
			</div>
		</section>{/if}
	<section class="section" aria-label="心率与训练负荷">
		<h2>心率与训练负荷</h2>
		<div class="surface">
			<p>{heartStatus[heart.heartLoadStatus]}</p>
			<ValueRows
				rows={[
					['HRSS', heart.heartHrss, ''],
					['TRIMPexp', heart.heartTrimp, ''],
					[
						'心率覆盖率',
						heart.heartCoverageFraction === undefined
							? undefined
							: heart.heartCoverageFraction * 100,
						'%'
					]
				]}
			/>
			<p class="small subtle">
				计时依据：{heart.heartUsesRecordedTimer ? '记录中的计时事件' : '经过时间（缺少计时事件）'} · 有效时间
				{duration(heart.heartActiveSeconds)} · 覆盖时间 {duration(heart.heartCoveredSeconds)}
			</p>
			<Zones zones={heart.heartZones} title="心率分区" unit="bpm" />
			<p class="small subtle">
				按心率储备 50 / 60 / 70 / 80 / 90% 分区；Z0 低于 50%，Z6
				达到或超过最大心率。超出最大心率的读数不计入负荷。
			</p>
			<a class="button" href={resolve('/training-history')}>体能与疲劳趋势 →</a>
		</div>
	</section>
	<section class="section" aria-label="距离分段">
		<h2>距离分段</h2>
		<div class="surface">
			<label
				>分段长度<select bind:value={length}
					><option value={1000}>1 km</option><option value={5000}>5 km</option></select
				></label
			>
			{#if splits.length}<div class="table-scroll" role="region" aria-label="距离分段表">
					<table>
						<thead
							><tr
								><th>分段</th><th>距离 (km)</th><th>用时</th><th
									>{running ? '配速 (/km)' : '速度 (km/h)'}</th
								><th>心率 (bpm)</th><th>功率 (W)</th><th
									>{running ? '步频 (步/分钟)' : '踏频 (rpm)'}</th
								><th>净海拔变化 (m)</th></tr
							></thead
						><tbody
							>{#each splits as split (split.splitIndex)}<tr
									><td>{split.splitIndex}</td><td
										>{valueText(split.splitDistanceMetres, 0.001, 3)}{split.splitDistanceMetres <
										length
											? '（末段）'
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
				</div>{:else}<p>需要连续、非递减的距离采样；缺失或距离重置时不推算。</p>{/if}
			{#if analysis.analysisHalves}<dl class="stats-rows">
					<div>
						<dt>前半程</dt>
						<dd>{speed(analysis.analysisHalves.firstHalfSpeed)}</dd>
					</div>
					<div>
						<dt>后半程</dt>
						<dd>{speed(analysis.analysisHalves.secondHalfSpeed)}</dd>
					</div>
					<div>
						<dt>后半程速度变化</dt>
						<dd>{valueText(analysis.analysisHalves.secondHalfChangePercent, 1, 1)}%</dd>
					</div>
				</dl>{/if}
			<p class="small subtle">
				包含停止时间，末段保留实际距离。半程按等距离比较；不是设备记录的计圈。
			</p>
		</div>
	</section>
	<section class="section">
		<h2>来源计圈</h2>
		<div class="surface">
			{#if laps.length}<div class="table-scroll" role="region" aria-label="来源计圈表">
					<table>
						<thead
							><tr
								><th>计圈</th><th>开始时间</th><th>距离 (km)</th><th>经过时长</th><th
									>记录平均心率 (bpm)</th
								><th>记录平均功率 (W)</th></tr
							></thead
						><tbody
							>{#each laps as lap, i (i)}<tr
									><td>{lap.label ?? `第 ${i + 1} 圈`}</td><td>{dateText(lap.range.rangeStart)}</td
									><td>{valueText(lap.summary.summaryDistance, 0.001, 2)}</td><td
										>{duration(lap.summary.summaryElapsedTime)}</td
									><td>{valueText(lap.summary.summaryHeartRate.averageValue)}</td><td
										>{valueText(lap.summary.summaryPower.averageValue)}</td
									></tr
								>{/each}</tbody
						>
					</table>
				</div>{:else}<p class="subtle">来源未记录计圈。</p>{/if}
		</div>
	</section>
	<section class="section">
		<h2>来源与分析依据</h2>
		<div class="surface">
			<h3>记录汇总与器材</h3>
			<ValueRows
				rows={[
					['记录爬升', recorded.summaryAscent, 'm'],
					['记录下降', recorded.summaryDescent, 'm'],
					['记录平均海拔', recorded.summaryAltitude.averageValue, 'm'],
					[
						'记录机械功',
						recorded.summaryMechanicalWork === undefined
							? undefined
							: recorded.summaryMechanicalWork / 1000,
						'kJ'
					],
					[
						'记录代谢能量',
						recorded.summaryMetabolicEnergy === undefined
							? undefined
							: recorded.summaryMetabolicEnergy / 1000,
						'kJ'
					]
				]}
			/>
			{#if sport.type === 'cycling'}<p>
					记录自行车：{sport.data.cyclingContext.bicycleName ?? '未记录'} · {valueText(
						sport.data.cyclingContext.bicycleMass,
						1,
						2
					)} kg
				</p>{/if}
			<p class="small subtle">以上为来源记录，不替代后端重新计算的分析。</p>
			<details>
				<summary>分析方法与个人参数</summary>
				<dl class="stats-rows">
					<div>
						<dt>算法</dt>
						<dd>{analysis.analysisMethod}</dd>
					</div>
					<div>
						<dt>训练版本</dt>
						<dd>{analysis.analysisRevision}</dd>
					</div>
					<div>
						<dt>参数版本</dt>
						<dd>{analysis.analysisSettingsRevision}</dd>
					</div>
					<div>
						<dt>参数生效时间</dt>
						<dd>
							{analysis.analysisBodyProfile
								? dateText(analysis.analysisBodyProfile.bodyEffectiveFrom)
								: '训练开始时没有生效的个人参数'}
						</dd>
					</div>
				</dl>
				<p>
					传感器统计和分布按时间加权，最大连接间隔 {analysis.analysisMaxGapSeconds} 秒。零值保留；没有外推或补零。缺失结果显示无数据。
				</p>
				{#each analysis.analysisNotes as note, i (i)}<p class="small subtle">{note}</p>{/each}
			</details>
			<button class="button" onclick={refresh} disabled={query.isFetching}>刷新分析</button>
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
