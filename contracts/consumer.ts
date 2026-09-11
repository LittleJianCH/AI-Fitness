import { getWorkouts, type Sport, type Workout, type getWorkoutsResponse } from './build/client.js';

// Compile against generated unions, optional fields and string revisions. No
// duplicate response interfaces or casts are needed at the consumer boundary.
export const loadWorkouts = () => getWorkouts({ sport: 'cycling', limit: 50 });

export function listResult(response: getWorkoutsResponse): string {
  if (response.status === 200) {
    return response.data.items.map(item => item.userData.workoutTitle ?? item.id).join(', ');
  }
  return response.data.code;
}

export function revision(workout: Workout): bigint {
  return BigInt(workout.workoutRevision);
}

export function cadence(sport: Sport): readonly number[] {
  switch (sport.type) {
    case 'cycling': return sport.data.cyclingCadence.map(sample => sample.value);
    case 'running': return sport.data.runningCadence.map(sample => sample.value);
  }
}
