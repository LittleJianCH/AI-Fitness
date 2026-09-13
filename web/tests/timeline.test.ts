import { expect, it } from 'vitest';
import { nearestTimeIndex, sampleAt } from '../src/lib/workouts/timeline';
const times = ['2026-01-01T00:00:00Z', '2026-01-01T00:00:30Z', '2026-01-01T00:05:00Z'];
it('snaps to real timestamps across gaps and clamps at both ends', () => {
	expect(nearestTimeIndex(times, Date.parse(times[0]) - 1000)).toBe(0);
	expect(nearestTimeIndex(times, Date.parse(times[2]) + 1000)).toBe(2);
	expect(nearestTimeIndex(times, Date.parse(times[1]) + 1000)).toBe(1);
	expect(nearestTimeIndex(times, Date.parse(times[0]) + 15000)).toBe(0);
	expect(nearestTimeIndex([], 0)).toBe(0);
});
it('preserves zero and refuses to invent values between samples', () => {
	const samples = [
		{ timestamp: times[0], value: 0 },
		{ timestamp: times[2], value: 42 }
	];
	expect(sampleAt(samples, times[0])?.value).toBe(0);
	expect(sampleAt(samples, times[1])).toBeUndefined();
	expect(sampleAt(samples, undefined)).toBeUndefined();
	expect(sampleAt([], times[0])).toBeUndefined();
	expect(sampleAt(samples, '2026-01-01T08:05:00+08:00')?.value).toBe(42);
});

import { workouts } from '../demo/fixtures';
import { metrics, recordedMetricSummary } from '../src/lib/workouts/presentation';
it('exposes recorded statistics without relabeling them as calculated', () => {
	const ride = workouts[0];
	expect(recordedMetricSummary(ride, 'heart-rate').averageValue).toBe(142);
	expect(metrics(ride).find((metric) => metric.key === 'heart-rate')?.average).toBeUndefined();
	expect(recordedMetricSummary(workouts[3], 'heart-rate').averageValue).toBeUndefined();
});
