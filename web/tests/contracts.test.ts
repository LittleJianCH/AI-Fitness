import { chartPoints } from '../src/lib/workouts/chart-data';
import { describe, it, expect, vi, afterEach } from 'vitest';
import { readFile } from 'node:fs/promises';
import { workouts, card } from '../demo/fixtures';
import {
	getWorkouts200Response,
	getWorkoutsWorkoutId200Response,
	getWorkoutsWorkoutIdPowerCurve200Response,
	getSettings200Response,
	getWorkoutsWorkoutIdAnalysis200Response
} from '../src/lib/api/generated/schemas';
import { loadWorkouts, loadWorkout, readScenario, ApiError } from '../src/lib/api/read';
import { metrics, duration, common, timeSummary } from '../src/lib/workouts/presentation';

afterEach(() => vi.unstubAllGlobals());
describe('generated runtime contract', () => {
	it('accepts the actual Servant list and detail responses', async () => {
		for (const [file, schema] of [
			['list-response.json', getWorkouts200Response],
			['workout-response.json', getWorkoutsWorkoutId200Response],
			['power-curve-response.json', getWorkoutsWorkoutIdPowerCurve200Response],
			['settings-response.json', getSettings200Response],
			['analysis-response.json', getWorkoutsWorkoutIdAnalysis200Response]
		] as const) {
			const raw: unknown = JSON.parse(
				await readFile(new URL(`../../backend/build/${file}`, import.meta.url), 'utf8')
			);
			expect(schema.safeParse(raw).success).toBe(true);
		}
	});
	it('validates every synthetic sport and its list card', () => {
		workouts.forEach((workout) =>
			expect(getWorkoutsWorkoutId200Response.safeParse(workout).success).toBe(true)
		);
		expect(getWorkouts200Response.safeParse({ items: workouts.map(card) }).success).toBe(true);
	});
	it('retains large revisions and rejects null, numeric revisions, and unknown sports', () => {
		const original = workouts[0];
		expect(getWorkoutsWorkoutId200Response.parse(original).workoutRevision).toBe(
			'9007199254740993'
		);
		for (const bad of [
			{ ...original, workoutRevision: 9007199254740992 },
			{ ...original, workoutUserData: { ...original.workoutUserData, workoutNotes: null } },
			{
				...original,
				workoutObservation: {
					...original.workoutObservation,
					observationSport: { type: 'swimming', data: {} }
				}
			}
		])
			expect(getWorkoutsWorkoutId200Response.safeParse(bad).success).toBe(false);
		expect(
			getWorkoutsWorkoutId200Response.safeParse({ ...original, futureField: true }).success
		).toBe(true);
	});
});
describe('read boundary', () => {
	it('uses generated URL filters and passes cancellation through', async () => {
		const fetch = vi.fn().mockResolvedValue(Response.json({ items: workouts.map(card) }));
		vi.stubGlobal('fetch', fetch);
		const signal = new AbortController().signal;
		const result = await loadWorkouts({ sport: 'running', limit: 3 }, signal, 'normal');
		expect(result.items).toHaveLength(4);
		expect(fetch.mock.calls[0][0]).toContain('sport=running');
		expect(fetch.mock.calls[0][1]).toMatchObject({
			signal,
			credentials: 'same-origin',
			cache: 'no-store'
		});
	});
	it('rejects malformed success data instead of rendering it', async () => {
		vi.stubGlobal('fetch', vi.fn().mockResolvedValue(Response.json({ items: [{ id: 123 }] })));
		await expect(loadWorkouts({}, new AbortController().signal, 'normal')).rejects.toMatchObject({
			code: 'invalid_response'
		});
	});
	it('handles non-JSON errors and preserves API codes', async () => {
		vi.stubGlobal(
			'fetch',
			vi.fn().mockResolvedValue(new Response('<html>failure</html>', { status: 502 }))
		);
		await expect(
			loadWorkout(workouts[0].workoutId, new AbortController().signal, 'normal')
		).rejects.toMatchObject({ code: 'invalid_response' });
		vi.stubGlobal(
			'fetch',
			vi
				.fn()
				.mockResolvedValue(
					Response.json(
						{ code: 'not_found', message: 'x', fields: [], requestId: 'test' },
						{ status: 404 }
					)
				)
		);
		await expect(
			loadWorkout(workouts[0].workoutId, new AbortController().signal, 'normal')
		).rejects.toMatchObject({ code: 'not_found' });
	});
	it('preserves AbortError and avoids requests for invalid IDs', async () => {
		const fetch = vi.fn().mockRejectedValue(new DOMException('Aborted', 'AbortError'));
		vi.stubGlobal('fetch', fetch);
		await expect(loadWorkouts({}, new AbortController().signal, 'normal')).rejects.toMatchObject({
			name: 'AbortError'
		});
		fetch.mockClear();
		await expect(
			loadWorkout('bad-id', new AbortController().signal, 'normal')
		).rejects.toBeInstanceOf(ApiError);
		expect(fetch).not.toHaveBeenCalled();
	});
});
describe('presentation semantics', () => {
	it('uses only current backend calculations, never recorded statistics or chart samples', () => {
		const workout = structuredClone(workouts[0]);
		const sport = workout.workoutObservation.observationSport;
		if (sport.type !== 'cycling') throw new Error('Expected cycling fixture');
		sport.data.cyclingSummary.calculatedSummary = undefined;
		const missing = metrics(workout).find((m) => m.key === 'heart-rate');
		expect(missing?.average).toBeUndefined();
		expect(missing?.maximum).toBeUndefined();
		const calculated = structuredClone(sport.data.cyclingSummary.recordedSummary);
		calculated.cyclingCommonSummary.summaryHeartRate = { averageValue: 80, maximumValue: 120 };
		sport.data.cyclingSummary.calculatedSummary = {
			calculationInputRevision: workout.workoutRevision,
			calculationConfig: 'synthetic-test',
			calculationMethod: 'synthetic-test',
			calculatedAt: '2026-09-12T00:00:00Z',
			calculationValue: calculated
		};
		expect(metrics(workout).find((m) => m.key === 'heart-rate')).toMatchObject({
			average: 80,
			maximum: 120
		});
		calculated.cyclingCommonSummary.summaryHeartRate = { averageValue: 0, maximumValue: 0 };
		expect(metrics(workout).find((m) => m.key === 'heart-rate')).toMatchObject({
			average: 0,
			maximum: 0
		});
		sport.data.cyclingSummary.calculatedSummary.calculationInputRevision = '999999';
		expect(metrics(workout).find((m) => m.key === 'heart-rate')?.maximum).toBeUndefined();
	});
	it('distinguishes sensor absence, summary-only records and sport cadences', () => {
		expect(metrics(workouts[3]).find((m) => m.key === 'heart-rate')).toBeUndefined();
		expect(metrics(workouts[2]).find((m) => m.key === 'power')?.samples).toEqual([]);
		expect(metrics(workouts[0]).find((m) => m.key === 'cadence')?.unit).toBe('rpm');
		expect(metrics(workouts[1]).find((m) => m.key === 'cadence')?.unit).toBe('步/分钟');
		expect(timeSummary(common(workouts[0])).label).toBe('计时时长');
	});
	it('keeps zeros and irregular timestamps; gaps never become zeros', () => {
		const points = chartPoints(
			[
				{ timestamp: '2026-09-12T00:00:00Z', value: 0 },
				{ timestamp: '2026-09-12T00:00:30Z', value: 2 },
				{ timestamp: '2026-09-12T00:05:00Z', value: 3 }
			],
			'2026-09-12T00:00:00Z',
			3.6
		);
		expect(points[0]).toEqual([0, 0]);
		expect(points[1]).toEqual([30, 7.2]);
		expect(points[2][1]).toBeNull();
		expect(points[3][0]).toBe(300);
	});
	it('uses explicit empty values and validates URL scenario input', () => {
		expect(duration(0)).toBe('00:00:00');
		expect(duration(undefined)).toBe('未记录');
		expect(readScenario('unknown')).toBe('normal');
	});
});
