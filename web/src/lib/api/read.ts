import { z } from 'zod';
import {
	getWorkouts,
	getWorkoutsWorkoutId,
	getWorkoutsWorkoutIdPowerCurve,
	type GetWorkoutsParams,
	type PageWorkoutCard,
	type Workout
} from './generated/client';
import {
	getWorkouts200Response,
	getWorkoutsWorkoutId200Response,
	getWorkoutsWorkoutIdPowerCurve200Response
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
import { ApiError, request } from './request';
export { ApiError, errorText } from './request';
function options(signal: AbortSignal, scenario: Scenario): RequestInit {
	return {
		signal,
		credentials: 'same-origin',
		cache: 'no-store',
		...(import.meta.env.MODE === 'demo' ? { headers: { 'X-Demo-Scenario': scenario } } : {})
	};
}
export const loadWorkouts = (
	params: GetWorkoutsParams,
	signal: AbortSignal,
	scenario: Scenario
): Promise<PageWorkoutCard> =>
	request(() => getWorkouts(params, undefined, options(signal, scenario)), getWorkouts200Response);
export const loadWorkout = (
	id: string,
	signal: AbortSignal,
	scenario: Scenario
): Promise<Workout> => {
	if (!z.guid().safeParse(id).success) return Promise.reject(new ApiError('not_found'));
	return request(
		() => getWorkoutsWorkoutId(id, undefined, options(signal, scenario)),
		getWorkoutsWorkoutId200Response
	);
};

export const loadPowerCurve = (id: string, signal: AbortSignal, scenario: Scenario) =>
	request(
		() => getWorkoutsWorkoutIdPowerCurve(id, undefined, options(signal, scenario)),
		getWorkoutsWorkoutIdPowerCurve200Response
	);
