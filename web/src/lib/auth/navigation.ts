import { z } from 'zod';
// Only implemented private destinations can be a post-login return target.
export function loginDestination(value: string | null): string {
	const parsed = z.string().max(2048).safeParse(value);
	if (
		!parsed.success ||
		!/^\/(workouts|settings)(\/|\?|$)/.test(parsed.data) ||
		/[\\\r\n]/.test(parsed.data)
	)
		return '/workouts';
	const url = new URL(parsed.data, 'https://fitness.invalid');
	return url.origin === 'https://fitness.invalid' &&
		/^\/(workouts|settings)(\/|$)/.test(url.pathname)
		? `${url.pathname}${url.search}`
		: '/workouts';
}
