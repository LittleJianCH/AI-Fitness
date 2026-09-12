import { expect, it } from 'vitest';
import { buildManualWorkout, manualDraftSchema } from '../src/lib/workouts/manual';
const input = {
	sport: 'cycling',
	start: '2026-09-11T09:00',
	minutes: 30,
	seconds: 15,
	title: '',
	notes: '',
	tags: []
};
const id = '00000000-0000-4000-8000-000000000123';
it('encodes user-supplied time and kilometres without inventing sensor data or calculated summaries', () => {
	const draft = manualDraftSchema.parse({
		...input,
		distanceKm: 12.345,
		title: 'Synthetic manual ride'
	});
	const body = buildManualWorkout(draft, id);
	expect(body.submissionId).toBe(id);
	expect(
		Date.parse(body.observation.observationRange.rangeEnd) -
			Date.parse(body.observation.observationRange.rangeStart)
	).toBe(1815000);
	const sport = body.observation.observationSport;
	if (sport.type !== 'cycling') throw new Error('Expected cycling');
	expect(sport.data.cyclingSummary.recordedSummary.cyclingCommonSummary).toMatchObject({
		summaryElapsedTime: 1815,
		summaryDistance: 12345,
		summaryHeartRate: {},
		summarySpeed: {}
	});
	expect(sport.data.cyclingMotion.motionPosition).toEqual([]);
	expect(sport.data.cyclingMotion.motionHeartRate).toEqual([]);
	expect(sport.data.cyclingSummary.calculatedSummary).toBeUndefined();
	expect(body.userData.workoutNotes).toBeUndefined();
});
it('keeps missing distance distinct from zero for both sports', () => {
	for (const sport of ['cycling', 'running']) {
		for (const distanceKm of [undefined, 0]) {
			const body = buildManualWorkout(manualDraftSchema.parse({ ...input, sport, distanceKm }), id);
			const data = body.observation.observationSport;
			const summary =
				data.type === 'cycling'
					? data.data.cyclingSummary.recordedSummary.cyclingCommonSummary
					: data.data.runningSummary.recordedSummary.runningCommonSummary;
			expect(summary.summaryDistance).toBe(distanceKm);
			expect(summary.summaryTimerTime).toBeUndefined();
			expect(summary.summaryMovingTime).toBeUndefined();
		}
	}
});
it('rejects impossible local dates, missing time, invalid seconds and overflowing conversions', () => {
	for (const change of [
		{ start: '2026-02-30T09:00' },
		{ start: '' },
		{ minutes: undefined },
		{ minutes: -1 },
		{ minutes: 0.5 },
		{ seconds: 60 },
		{ distanceKm: Number.MAX_VALUE },
		{ minutes: Number.MAX_SAFE_INTEGER }
	])
		expect(manualDraftSchema.safeParse({ ...input, ...change }).success).toBe(false);
});
