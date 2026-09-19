import { createQuery, useQueryClient } from '@tanstack/svelte-query';
import { useSession } from '$lib/auth/session.svelte';
import { getWorkoutsWorkoutIdAnalysis, type Workout } from '$lib/api/generated/client';
import { getWorkoutsWorkoutIdAnalysis200Response } from '$lib/api/generated/schemas';
import { request, requestOptions, ApiError } from '$lib/api/request';

export function workoutAnalysisQuery(workout: () => Workout) {
	const session = useSession();
	const client = useQueryClient();
	const query = createQuery(() => ({
		queryKey: [
			'workout-analysis',
			session.user?.id,
			workout().workoutId,
			workout().workoutRevision
		],
		enabled: import.meta.env.MODE !== 'demo' && !!session.user,
		staleTime: 0,
		queryFn: async ({ signal }) => {
			const { workoutId, workoutRevision } = workout();
			const result = await request(
				() => getWorkoutsWorkoutIdAnalysis(workoutId, undefined, requestOptions(signal)),
				getWorkoutsWorkoutIdAnalysis200Response
			);
			if (result.analysisWorkoutId !== workoutId || result.analysisRevision !== workoutRevision)
				throw new ApiError('analysis_revision_conflict');
			return result;
		}
	}));
	async function refresh() {
		await client.invalidateQueries({
			queryKey: ['workout', session.user?.id, workout().workoutId]
		});
		await query.refetch();
	}
	return { query, refresh };
}
