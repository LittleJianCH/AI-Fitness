import { expect, it } from 'vitest';
import {
	chartPoints,
	distanceCoordinates,
	nearestCoordinateIndex,
	nearestIndex,
	sampleTimes
} from '../src/lib/workouts/chart-data';

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

it('aligns distance display without extrapolating over missing coverage or resets', () => {
	const at = (seconds: number, value = 0) => ({
		timestamp: new Date(seconds * 1000).toISOString(),
		value
	});
	const distances = [at(10, 0), at(20, 1000), at(200, 2000), at(210, 100)];
	expect(
		distanceCoordinates(
			[at(0), at(10), at(15), at(20), at(100), at(205), at(210), at(211)],
			distances
		)
	).toEqual([undefined, 0, 0.5, 1, undefined, undefined, 0.1, undefined]);
	expect(distanceCoordinates([at(60)], [at(0, 0), at(120, 1000)])).toEqual([0.5]);
	expect(distanceCoordinates([at(60)], [at(0, 0), at(121, 1000)])).toEqual([undefined]);
});

it('breaks distance plots at unaligned samples, time gaps and distance resets while retaining zero', () => {
	const samples = [0, 1, 2, 3, 200].map((seconds) => ({
		timestamp: new Date(seconds * 1000).toISOString(),
		value: 0
	}));
	expect(chartPoints(samples, samples[0].timestamp, 1, 120, [0, undefined, 2, 1, 3])).toEqual([
		[0, 0],
		[0, null],
		[2, 0],
		[1, null],
		[1, 0],
		[3, null],
		[3, 0]
	]);
	expect(nearestCoordinateIndex([undefined, 3, 1, 1, 4], 1)).toBe(2);
	expect(nearestCoordinateIndex([undefined, 3, 1], 2)).toBe(1);
	expect(nearestCoordinateIndex([undefined], 2)).toBeUndefined();
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
