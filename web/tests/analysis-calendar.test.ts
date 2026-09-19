import { describe, it, expect, afterEach } from 'vitest';
import { calendarDays, historyRequest } from '../src/lib/analysis/calendar';
import { chartPoints } from '../src/lib/workouts/chart-data';
const zone = process.env.TZ;
afterEach(() => {
	if (zone === undefined) delete process.env.TZ;
	else process.env.TZ = zone;
});
describe('training calendar inputs', () => {
	it('uses true DST civil-day boundaries without changing date labels', () => {
		process.env.TZ = 'America/New_York';
		const spring = calendarDays('2026-03-07', '2026-03-09');
		expect(spring.map((d) => d.calendarDate)).toEqual(['2026-03-07', '2026-03-08', '2026-03-09']);
		expect(
			spring.map((d) => (Date.parse(d.calendarEnd) - Date.parse(d.calendarStart)) / 3600000)
		).toEqual([24, 23, 24]);
		expect(spring[0].calendarEnd).toBe(spring[1].calendarStart);
		const fall = calendarDays('2026-10-31', '2026-11-02');
		expect(
			fall.map((d) => (Date.parse(d.calendarEnd) - Date.parse(d.calendarStart)) / 3600000)
		).toEqual([24, 25, 24]);
	});
	it('rejects invalid or excessive date ranges and preserves explicit completeness', () => {
		expect(calendarDays('2026-02-30', '2026-03-02')).toEqual([]);
		expect(calendarDays('2025-01-01', '2026-01-02')).toEqual([]);
		const days = calendarDays('2026-01-01', '2026-01-02');
		expect(() => historyRequest(days, new Set(), ' ', undefined, undefined)).toThrow();
		expect(() => historyRequest(days, new Set(), 'known', NaN, 7)).toThrow();
		const input = historyRequest(days, new Set(['2026-01-01']), 'zero', undefined, undefined);
		expect(input.historyCalendar.map((d) => d.calendarRecordingComplete)).toEqual([true, false]);
		expect(input.historyPriorFitness).toBeUndefined();
		expect(historyRequest(days, new Set(), 'known', 42, 7).historyPriorFatigue).toBe(7);
	});
});
it('preserves gaps using the backend analysis gap limit before rendering', () => {
	const start = '2026-01-01T00:00:00Z';
	const samples = [0, 10, 60, 65].map((seconds) => ({
		timestamp: new Date(Date.parse(start) + seconds * 1000).toISOString(),
		value: seconds
	}));
	expect(chartPoints(samples, start, 1, 30)).toEqual([
		[0, 0],
		[10, 10],
		[59.999, null],
		[60, 60],
		[65, 65]
	]);
	expect(chartPoints(samples, start, 1, 120)).toHaveLength(4);
});
