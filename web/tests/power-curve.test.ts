import { afterEach, expect, it, vi } from 'vitest';
import { loadPowerCurve } from '../src/lib/api/read';
import { workouts, powerCurveFixture } from '../demo/fixtures';
import { metrics } from '../src/lib/workouts/presentation';

afterEach(() => vi.unstubAllGlobals());

it('keeps zero effort, missing coverage and string revisions distinct', async () => {
	const workout = workouts[0];
	const curve = powerCurveFixture(workout);
	curve.points[0].best = {
		averagePower: 0,
		start: '2026-09-12T00:10:00Z',
		end: '2026-09-12T00:10:01Z'
	};
	const fetch = vi.fn().mockResolvedValue(Response.json(curve));
	vi.stubGlobal('fetch', fetch);
	const signal = new AbortController().signal;
	const result = await loadPowerCurve(workout.workoutId, signal, 'normal');
	expect(result.points[0].best?.averagePower).toBe(0);
	expect(result.points.find((point) => point.durationSeconds === 120)?.best).toBeUndefined();
	expect(result.inputRevision).toBe('9007199254740993');
	expect(fetch.mock.calls[0][0]).toBe(`/api/v1/workouts/${workout.workoutId}/power-curve`);
	expect(fetch.mock.calls[0][1]).toMatchObject({
		signal,
		cache: 'no-store',
		credentials: 'same-origin'
	});
});

it('rejects malformed curves and preserves cancellation', async () => {
	vi.stubGlobal('fetch', vi.fn().mockResolvedValue(Response.json({ points: [] })));
	await expect(
		loadPowerCurve(workouts[0].workoutId, new AbortController().signal, 'normal')
	).rejects.toMatchObject({ code: 'invalid_response' });
	vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new DOMException('cancelled', 'AbortError')));
	await expect(
		loadPowerCurve(workouts[0].workoutId, new AbortController().signal, 'normal')
	).rejects.toMatchObject({ name: 'AbortError' });
});

it('summary-only power can open analysis without relabeling recorded values as calculated', () => {
	const metric = metrics(workouts[2]).find((metric) => metric.key === 'power');
	expect(metric).toBeDefined();
	expect(metric?.samples).toEqual([]);
	expect(metric?.average).toBeUndefined();
});
