import { expect, it } from 'vitest';
import { chartPoints, nearestIndex, sampleTimes } from '../src/lib/workouts/chart-data';

it('selects recorded samples with stable ties, endpoint clamping and empty input', () => {
	expect(nearestIndex([], 10)).toBe(0);
	const times = [100, 200, 500];
	for (const [target, index] of [
		[0, 0],
		[100, 0],
		[150, 0],
		[151, 1],
		[200, 1],
		[351, 2],
		[900, 2]
	]) {
		expect(nearestIndex(times, target)).toBe(index);
	}
});

it('keeps nearest-sample lookup logarithmic for long activities', () => {
	let reads = 0;
	const times = new Proxy(
		Array.from({ length: 100000 }, (_, i) => i * 1000),
		{
			get(target, key, receiver) {
				if (typeof key === 'string' && /^\d+$/.test(key)) reads++;
				return Reflect.get(target, key, receiver);
			}
		}
	);
	expect(nearestIndex(times, 65789321)).toBe(65789);
	expect(reads).toBeLessThan(25);
});

it('prepares numeric times and display gaps without changing recorded samples', () => {
	const samples = Object.freeze([
		Object.freeze({ timestamp: '2026-01-01T08:00:00+08:00', value: 2 }),
		Object.freeze({ timestamp: '2026-01-01T00:02:00Z', value: 3 }),
		Object.freeze({ timestamp: '2026-01-01T00:04:01Z', value: 4 })
	]);
	expect(sampleTimes(samples).map((t) => t - Date.parse(samples[0].timestamp))).toEqual([
		0, 120000, 241000
	]);
	expect(chartPoints(samples, samples[0].timestamp, 3.6)).toEqual([
		[0, 7.2],
		[120, 10.8],
		[240.999, null],
		[241, 14.4]
	]);
});
