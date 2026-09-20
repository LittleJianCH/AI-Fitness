import { m as L } from '$lib/paraglide/messages.js';
import { z } from 'zod';
import type { CommonSummary, ManualWorkout, MotionData, Sport } from '../api/generated/client';
import { postWorkoutsBody } from '../api/generated/schemas';

function localStart(value: string): Date | undefined {
	if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/.test(value)) return;
	const date = new Date(value);
	if (!Number.isFinite(date.getTime())) return;
	const pad = (n: number) => String(n).padStart(2, '0');
	const local = `${String(date.getFullYear()).padStart(4, '0')}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
	// Reject impossible dates and nonexistent local times instead of silently shifting them.
	return local.slice(0, value.length) === value ? date : undefined;
}
export const manualDraftSchema = z
	.object({
		sport: z.enum(['cycling', 'running']),
		start: z
			.string()
			.refine((value) => !!localStart(value), { error: () => L.manual_invalid_start() }),
		minutes: z
			.number()
			.int()
			.nonnegative({ error: () => L.manual_invalid_minutes() }),
		seconds: z.number().int().min(0).max(59).default(0),
		distanceKm: z
			.number()
			.nonnegative()
			.max(Number.MAX_VALUE / 1000)
			.optional(),
		title: z.string(),
		notes: z.string(),
		tags: z.array(z.string())
	})
	.superRefine((draft, context) => {
		const start = localStart(draft.start);
		const end = start
			? new Date(start.getTime() + (draft.minutes * 60 + draft.seconds) * 1000)
			: undefined;
		if (start && (!end || !Number.isFinite(end.getTime()) || end.getUTCFullYear() > 9999))
			context.addIssue({
				code: 'custom',
				path: ['minutes'],
				message: L.manual_duration_overflow()
			});
	});
export type ManualDraft = z.output<typeof manualDraftSchema>;
export function buildManualWorkout(draft: ManualDraft, submissionId: string): ManualWorkout {
	const start = new Date(draft.start);
	const elapsed = draft.minutes * 60 + draft.seconds;
	const motion: MotionData = {
		motionHeartRate: [],
		motionPower: [],
		motionSpeed: [],
		motionDistance: [],
		motionPosition: [],
		motionAltitude: [],
		motionGrade: [],
		motionEnergy: [],
		motionEnvironment: { ambientTemperature: [], windSpeed: [], windFrom: [], relativeHumidity: [] }
	};
	const summary: CommonSummary = {
		summaryElapsedTime: elapsed,
		...(draft.distanceKm === undefined ? {} : { summaryDistance: draft.distanceKm * 1000 }),
		summaryHeartRate: {},
		summaryPower: {},
		summarySpeed: {},
		summaryAltitude: {},
		summaryGrade: {},
		summaryTemperature: {}
	};
	const sport: Sport =
		draft.sport === 'cycling'
			? {
					type: 'cycling',
					data: {
						cyclingMotion: motion,
						cyclingCadence: [],
						cyclingPedaling: {
							leftPowerShare: [],
							leftSmoothness: [],
							rightSmoothness: [],
							leftTorqueEffectiveness: [],
							rightTorqueEffectiveness: []
						},
						cyclingGearChanges: [],
						cyclingLaps: [],
						cyclingContext: {},
						cyclingSummary: {
							recordedSummary: { cyclingCommonSummary: summary, summaryCyclingCadence: {} }
						}
					}
				}
			: {
					type: 'running',
					data: {
						runningMotion: motion,
						runningCadence: [],
						runningDynamics: { stepLength: [], verticalOscillation: [], groundContactTime: [] },
						runningLaps: [],
						runningSummary: {
							recordedSummary: {
								runningCommonSummary: summary,
								summaryRunningCadence: {},
								summaryStepLength: {},
								summaryVerticalOscillation: {},
								summaryGroundContactTime: {}
							}
						}
					}
				};
	return postWorkoutsBody.parse({
		submissionId,
		observation: {
			observationRange: {
				rangeStart: start.toISOString(),
				rangeEnd: new Date(start.getTime() + elapsed * 1000).toISOString()
			},
			observationSport: sport,
			observationEvents: [],
			observationCoursePoints: [],
			observationAthlete: {},
			observationExtensions: [],
			observationDataIssues: []
		},
		userData: {
			...(draft.title === '' ? {} : { workoutTitle: draft.title }),
			...(draft.notes === '' ? {} : { workoutNotes: draft.notes }),
			workoutTags: [...draft.tags],
			statisticsInclusion: 'includeInStatistics'
		}
	} satisfies ManualWorkout);
}
