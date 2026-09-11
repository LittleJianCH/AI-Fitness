import { z } from 'zod';
import {
	getWorkouts,
	getWorkoutsWorkoutId,
	type GetWorkoutsParams,
	type PageWorkoutCard,
	type Workout
} from './generated/client';
import {
	getWorkouts200Response,
	getWorkoutsWorkoutId200Response,
	getWorkoutsDefaultResponse
} from './generated/schemas';

export const scenarioSchema = z.enum([
	'normal',
	'slow',
	'empty',
	'error',
	'invalid',
	'unauthenticated'
]);
export type Scenario = z.infer<typeof scenarioSchema>;
export function readScenario(value: string | null): Scenario {
	return scenarioSchema.catch('normal').parse(value ?? 'normal');
}
export const sportSchema = z.enum(['cycling', 'running']);
export class ApiError extends Error {
	constructor(public code: string) {
		super(code);
		this.name = 'ApiError';
	}
}
function options(signal: AbortSignal, scenario: Scenario): RequestInit {
	return {
		signal,
		credentials: 'same-origin',
		cache: 'no-store',
		...(import.meta.env.MODE === 'demo' ? { headers: { 'X-Demo-Scenario': scenario } } : {})
	};
}
function validated<T>(response: { status: number; data: unknown }, schema: z.ZodType<T>): T {
	if (response.status !== 200) {
		const error = getWorkoutsDefaultResponse.safeParse(response.data);
		throw new ApiError(error.success ? error.data.code : 'invalid_response');
	}
	const parsed = schema.safeParse(response.data);
	if (!parsed.success) throw new ApiError('invalid_response');
	return parsed.data;
}
async function request<T>(action: () => Promise<T>): Promise<T> {
	try {
		return await action();
	} catch (error) {
		if (error instanceof ApiError || (error instanceof Error && error.name === 'AbortError'))
			throw error;
		throw new ApiError(error instanceof SyntaxError ? 'invalid_response' : 'network_error');
	}
}
export const loadWorkouts = (
	params: GetWorkoutsParams,
	signal: AbortSignal,
	scenario: Scenario
): Promise<PageWorkoutCard> =>
	request(async () =>
		validated(
			await getWorkouts(params, undefined, options(signal, scenario)),
			getWorkouts200Response
		)
	);
export const loadWorkout = (
	id: string,
	signal: AbortSignal,
	scenario: Scenario
): Promise<Workout> =>
	request(async () => {
		if (!z.guid().safeParse(id).success) throw new ApiError('not_found');
		return validated(
			await getWorkoutsWorkoutId(id, undefined, options(signal, scenario)),
			getWorkoutsWorkoutId200Response
		);
	});
export function errorText(error: Error | null): string {
	const code = error instanceof ApiError ? error.code : 'network_error';
	switch (code) {
		case 'not_found':
			return '没有找到这条训练记录。';
		case 'unauthenticated':
			return '当前会话不可用，请重新登录。演示模式可切回正常场景继续体验。';
		case 'invalid_response':
			return '收到的数据不符合接口约定，暂时无法展示。';
		case 'internal_error':
			return '服务暂时无法完成请求，请稍后重试。';
		default:
			return '连接失败，请检查网络后重试。';
	}
}
