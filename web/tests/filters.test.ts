import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { filtersFromUrl } from '../src/lib/workouts/filters';
describe('local calendar workout filters', () => {
	const original = process.env.TZ;
	beforeAll(() => {
		process.env.TZ = 'America/New_York';
	});
	afterAll(() => {
		if (original === undefined) delete process.env.TZ;
		else process.env.TZ = original;
	});
	it('uses inclusive local start and the next calendar midnight as the exclusive end', () => {
		const result = filtersFromUrl(
			new URLSearchParams({
				sport: 'running',
				from: '2026-03-08',
				through: '2026-03-08',
				tag: ' exact tag '
			})
		);
		expect(result.success && result.data).toEqual({
			sport: 'running',
			from: '2026-03-08T05:00:00.000Z',
			before: '2026-03-09T04:00:00.000Z',
			tag: ' exact tag '
		});
	});
	it('includes all 25 hours of a fall daylight-saving day', () => {
		const result = filtersFromUrl(
			new URLSearchParams({ from: '2026-11-01', through: '2026-11-01' })
		);
		expect(result.success && result.data).toEqual({
			from: '2026-11-01T04:00:00.000Z',
			before: '2026-11-02T05:00:00.000Z'
		});
	});
	it('rejects invalid, impossible and reversed URL filters', () => {
		const invalid: Record<string, string>[] = [
			{ from: '2026-02-30' },
			{ from: '0000-01-01' },
			{ from: 'yesterday' },
			{ sport: 'swimming' },
			{ from: '2026-09-12', through: '2026-09-11' },
			{ through: '9999-12-31' }
		];
		for (const input of invalid)
			expect(filtersFromUrl(new URLSearchParams(input)).success).toBe(false);
	});
	it('ends a day with a midnight DST gap at the next midnight', () => {
		process.env.TZ = 'America/Santiago';
		try {
			const result = filtersFromUrl(
				new URLSearchParams({ from: '2026-09-06', through: '2026-09-06' })
			);
			expect(result.success && result.data).toEqual({
				from: '2026-09-06T04:00:00.000Z',
				before: '2026-09-07T03:00:00.000Z'
			});
		} finally {
			process.env.TZ = 'America/New_York';
		}
	});
	it('omits empty filters', () => {
		const result = filtersFromUrl(new URLSearchParams());
		expect(result.success && result.data).toEqual({});
	});
});
