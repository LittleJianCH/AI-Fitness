import type {
	CommonSummary,
	PowerCurve,
	MotionData,
	Sport,
	Workout,
	WorkoutCard
} from '../src/lib/api/generated/client.ts';

// Deterministic synthetic data only. This module is loaded by the demo server,
// never by the application bundle. Summary values represent supplied fixtures.
const samples = (start: string, count: number, step: number, value: (i: number) => number) =>
	Array.from({ length: count }, (_, i) => ({
		timestamp: new Date(Date.parse(start) + i * step * 1000).toISOString(),
		value: value(i)
	}));
const emptyMotion = (): MotionData => ({
	motionHeartRate: [],
	motionPower: [],
	motionSpeed: [],
	motionDistance: [],
	motionPosition: [],
	motionAltitude: [],
	motionGrade: [],
	motionEnergy: [],
	motionEnvironment: { ambientTemperature: [], windSpeed: [], windFrom: [], relativeHumidity: [] }
});
const commonSummary = (cycling: boolean): CommonSummary => ({
	summaryElapsedTime: cycling ? 5400 : 2700,
	summaryTimerTime: cycling ? 5220 : 2700,
	summaryDistance: cycling ? 42600 : 8200,
	summaryHeartRate: {
		averageValue: cycling ? 142 : 151,
		maximumValue: cycling ? 171 : 172,
		minimumValue: 95
	},
	summaryPower: cycling ? { averageValue: 186, maximumValue: 520 } : {},
	summarySpeed: { averageValue: cycling ? 8.16 : 3.04, maximumValue: cycling ? 14.2 : 4.1 },
	summaryAltitude: { minimumValue: 12, maximumValue: cycling ? 142 : 46 },
	summaryAscent: cycling ? 386 : 62,
	summaryDescent: cycling ? 382 : 61,
	summaryGrade: {},
	summaryTemperature: {}
});

function makeWorkout(id: number, title: string, start: string, cycling: boolean): Workout {
	const n = 181;
	const step = cycling ? 30 : 15;
	const wave = (i: number) => Math.sin(i / 11) + Math.sin(i / 3) * 0.3;
	const motion: MotionData = {
		...emptyMotion(),
		motionHeartRate: samples(start, n, step, (i) => Math.round(135 + i / 15 + wave(i) * 10)).filter(
			(_, i) => i < 70 || i > 78
		),
		motionPower: cycling
			? samples(start, n, step, (i) =>
					i >= 110 && i <= 115 ? 0 : Math.round(185 + wave(i) * 55 + (i === 140 ? 270 : 0))
				)
			: [],
		motionSpeed: samples(start, n, step, (i) =>
			Math.max(0, (cycling ? 8 : 3) + wave(i) * (cycling ? 2 : 0.4))
		),
		motionDistance: samples(start, n, step, (i) => ((cycling ? 42600 : 8200) * i) / (n - 1)),
		motionAltitude: samples(
			start,
			n,
			step,
			(i) => 40 + (cycling ? 50 : 6) * Math.sin((i / n) * Math.PI) + wave(i) * 7
		),
		motionPosition: Array.from({ length: n }, (_, i) => ({
			timestamp: new Date(Date.parse(start) + i * step * 1000).toISOString(),
			value: {
				latitude:
					31 +
					Math.sin((i / 180) * Math.PI * 2) * 0.035 +
					Math.sin((i / 180) * Math.PI * 8) * 0.002,
				longitude:
					121 + Math.cos((i / 180) * Math.PI * 2) * 0.06 + Math.sin((i / 180) * Math.PI * 6) * 0.007
			}
		}))
	};
	const cadence = samples(start, n, step, (i) =>
		cycling && i >= 110 && i <= 115 ? 0 : Math.round((cycling ? 85 : 173) + wave(i) * 5)
	);
	const sport: Sport = cycling
		? {
				type: 'cycling',
				data: {
					cyclingMotion: motion,
					cyclingCadence: cadence,
					cyclingPedaling: {
						leftPowerShare: [],
						leftSmoothness: [],
						rightSmoothness: [],
						leftTorqueEffectiveness: [],
						rightTorqueEffectiveness: []
					},
					cyclingGearChanges: [],
					cyclingLaps: [],
					cyclingContext: { bicycleName: '演示公路车' },
					cyclingSummary: {
						recordedSummary: {
							cyclingCommonSummary: commonSummary(true),
							summaryCyclingCadence: { averageValue: 84, maximumValue: 98 }
						}
					}
				}
			}
		: {
				type: 'running',
				data: {
					runningMotion: motion,
					runningCadence: cadence,
					runningDynamics: { stepLength: [], verticalOscillation: [], groundContactTime: [] },
					runningLaps: [],
					runningSummary: {
						recordedSummary: {
							runningCommonSummary: commonSummary(false),
							summaryRunningCadence: { averageValue: 174, maximumValue: 188 },
							summaryStepLength: {},
							summaryVerticalOscillation: {},
							summaryGroundContactTime: {}
						}
					}
				}
			};
	return {
		workoutId: `00000000-0000-4000-8000-${String(id).padStart(12, '0')}`,
		workoutRevision: '9007199254740993',
		workoutUserData: {
			workoutTitle: title,
			workoutNotes: '这是一条合成训练记录，用于体验训练复盘。数据不代表真实运动。',
			workoutTags: [cycling ? '耐力' : '轻松跑'],
			statisticsInclusion: 'includeInStatistics'
		},
		workoutObservation: {
			observationRange: {
				rangeStart: start,
				rangeEnd: new Date(Date.parse(start) + (n - 1) * step * 1000).toISOString()
			},
			observationSport: sport,
			observationEvents: [],
			observationCoursePoints: [],
			observationAthlete: {},
			observationExtensions: [],
			observationDataIssues: [
				{
					issueField: 'heartRate',
					issueDescription: '演示传感器采样缺口；未补零。',
					issueRange: {
						rangeStart: new Date(Date.parse(start) + 70 * step * 1000).toISOString(),
						rangeEnd: new Date(Date.parse(start) + 79 * step * 1000).toISOString()
					}
				}
			]
		}
	};
}

const cycling = makeWorkout(1, '周末环湖 · 耐力骑行', '2026-09-12T00:10:00Z', true);
const running = makeWorkout(2, '清晨轻松跑', '2026-09-11T22:30:00Z', false);
const indoor = makeWorkout(3, '室内骑行 · 仅汇总', '2026-09-10T11:00:00Z', true);
if (indoor.workoutObservation.observationSport.type === 'cycling') {
	const data = indoor.workoutObservation.observationSport.data;
	data.cyclingMotion = emptyMotion();
	data.cyclingCadence = [];
	indoor.workoutObservation.observationDataIssues = [];
	indoor.workoutUserData.workoutTags = ['室内', '仅汇总'];
}
const noHeartRate = makeWorkout(4, '午后慢跑 · 无心率', '2026-09-09T09:30:00Z', false);
if (noHeartRate.workoutObservation.observationSport.type === 'running') {
	const data = noHeartRate.workoutObservation.observationSport.data;
	data.runningMotion.motionHeartRate = [];
	data.runningSummary.recordedSummary.runningCommonSummary.summaryHeartRate = {};
	noHeartRate.workoutObservation.observationDataIssues = [];
}
// A known 60-second, 200 W effort exercises the new analysis without a second
// implementation of the backend algorithm. Later cycling samples remain sparse.
for (const workout of [cycling, running]) {
	const sport = workout.workoutObservation.observationSport;
	const motion = sport.type === 'cycling' ? sport.data.cyclingMotion : sport.data.runningMotion;
	const start = workout.workoutObservation.observationRange.rangeStart;
	motion.motionPower = [
		...samples(start, 61, 1, () => 200),
		...motion.motionPower.filter(
			(sample) => Date.parse(sample.timestamp) > Date.parse(start) + 60000
		)
	];
}
export function powerCurveFixture(workout: Workout): PowerCurve {
	const start = workout.workoutObservation.observationRange.rangeStart;
	const hasEffort = workout === cycling || workout === running;
	return {
		curveWorkoutId: workout.workoutId,
		inputRevision: workout.workoutRevision,
		method: 'linear-best-duration-v1',
		maxGapSeconds: 5,
		points: [
			1, 5, 10, 15, 30, 60, 120, 180, 300, 600, 900, 1200, 1800, 2700, 3600, 5400, 7200, 10800,
			14400
		].map((durationSeconds) => ({
			durationSeconds,
			...(hasEffort && durationSeconds <= 60
				? {
						best: {
							averagePower: 200,
							start,
							end: new Date(Date.parse(start) + durationSeconds * 1000).toISOString()
						}
					}
				: {})
		}))
	};
}
export const workouts: readonly Workout[] = [cycling, running, indoor, noHeartRate];
export function card(workout: Workout): WorkoutCard {
	const sport = workout.workoutObservation.observationSport;
	return {
		id: workout.workoutId,
		revision: workout.workoutRevision,
		range: workout.workoutObservation.observationRange,
		userData: workout.workoutUserData,
		summary:
			sport.type === 'cycling'
				? { type: 'cyclingSummary', data: sport.data.cyclingSummary }
				: { type: 'runningSummary', data: sport.data.runningSummary }
	};
}
