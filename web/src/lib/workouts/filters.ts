import { z } from 'zod';
import type { GetWorkoutsParams } from '../api/generated/client';
export function localDay(value: string): Date | undefined {
	if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(value) || value.startsWith('0000')) return;
	const date = new Date(`${value}T00:00:00`);
	if (!Number.isFinite(date.getTime())) return;
	const [year, month, day] = value.split('-').map(Number);
	if (date.getFullYear() !== year || date.getMonth() + 1 !== month || date.getDate() !== day)
		return;
	return date;
}
const day = z
	.string()
	.refine((value) => value === '' || localDay(value) !== undefined, '请使用有效的本地日期。');
export const workoutFilters = z
	.object({
		sport: z.enum(['', 'cycling', 'running']),
		from: day,
		through: day,
		tag: z.string()
	})
	.superRefine((value, context) => {
		if (value.from && value.through && value.from > value.through)
			context.addIssue({ code: 'custom', message: '结束日期应不早于开始日期。' });
		if (value.through === '9999-12-31')
			context.addIssue({ code: 'custom', message: '结束日期超出支持范围。' });
	})
	.transform((value): GetWorkoutsParams => {
		const from = value.from ? localDay(value.from) : undefined;
		const before = value.through ? localDay(value.through) : undefined;
		// A midnight DST gap can normalize the selected day to 01:00.
		// Construct the next calendar midnight without inheriting that hour.
		if (before) before.setHours(24, 0, 0, 0);
		return {
			...(value.sport ? { sport: value.sport } : {}),
			...(from ? { from: from.toISOString() } : {}),
			...(before ? { before: before.toISOString() } : {}),
			...(value.tag !== '' ? { tag: value.tag } : {})
		};
	});
export function filtersFromUrl(params: URLSearchParams) {
	return workoutFilters.safeParse({
		sport: params.get('sport') ?? '',
		from: params.get('from') ?? '',
		through: params.get('through') ?? '',
		tag: params.get('tag') ?? ''
	});
}
