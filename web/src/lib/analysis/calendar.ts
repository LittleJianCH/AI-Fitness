import { m as L } from '$lib/paraglide/messages.js';
import { z } from 'zod';
import type { CalendarDay, TrainingHistoryRequest } from '../api/generated/client';
import { postAnalysisTrainingHistoryBody } from '../api/generated/schemas';
import { localDay } from '../workouts/filters';
export const localDate = (date: Date) =>
	`${String(date.getFullYear()).padStart(4, '0')}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
export function calendarDays(from: string, through: string): CalendarDay[] {
	const start = localDay(from),
		end = localDay(through);
	if (!start || !end || from > through || through === '9999-12-31') return [];
	const days: CalendarDay[] = [];
	let current = start;
	while (localDate(current) <= through && days.length < 367) {
		// Construct consecutive civil midnights, including 23/25-hour DST days.
		const next = new Date(current);
		next.setHours(24, 0, 0, 0);
		if (next <= current) return [];
		days.push({
			calendarDate: localDate(current),
			calendarStart: current.toISOString(),
			calendarEnd: next.toISOString(),
			calendarRecordingComplete: false
		});
		current = next;
	}
	return days.length <= 366 ? days : [];
}
export function historyRequest(
	days: CalendarDay[],
	complete: ReadonlySet<string>,
	initial: string,
	fitness: number | undefined,
	fatigue: number | undefined
): TrainingHistoryRequest {
	if (!days.length) throw new Error(L.history_invalid_range());
	if (initial !== 'zero' && initial !== 'known') throw new Error(L.history_initial_required());
	if (
		initial === 'known' &&
		!z.tuple([z.number().nonnegative(), z.number().nonnegative()]).safeParse([fitness, fatigue])
			.success
	)
		throw new Error(L.history_initial_invalid());
	return postAnalysisTrainingHistoryBody.parse({
		historyCalendar: days.map((d) => ({
			...d,
			calendarRecordingComplete: complete.has(d.calendarDate)
		})),
		historyAssumeNoPriorLoad: initial === 'zero',
		...(initial === 'known' ? { historyPriorFitness: fitness, historyPriorFatigue: fatigue } : {})
	});
}

export function defaultHistoryRange(now = new Date()) {
	const start = new Date(now);
	start.setDate(start.getDate() - 27);
	return { from: localDate(start), through: localDate(now) };
}
