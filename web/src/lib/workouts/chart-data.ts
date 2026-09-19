export type NumericSample = Readonly<{ timestamp: string; value: number }>;
export const sampleTimes = (samples: readonly NumericSample[]): number[] =>
	samples.map((sample) => Date.parse(sample.timestamp));
// Chronological numeric timestamps; ties select the earlier recorded sample.
export function nearestIndex(times: readonly number[], target: number): number {
	if (!times.length) return 0;
	let low = 0,
		high = times.length;
	while (low < high) {
		const middle = Math.floor((low + high) / 2);
		if (times[middle] < target) low = middle + 1;
		else high = middle;
	}
	if (!low) return 0;
	if (low === times.length) return low - 1;
	return target - times[low - 1] <= times[low] - target ? low - 1 : low;
}
// Display rule only: separate samples more than two minutes apart. The points
// and all reported statistics remain unchanged, and the rule is stated in UI.
export function chartPoints(
	samples: readonly NumericSample[],
	start: string,
	factor: number,
	maxGapSeconds = 120
): [number, number | null][] {
	const points: [number, number | null][] = [];
	const origin = Date.parse(start);
	let previous: number | undefined;
	for (const sample of samples) {
		const timestamp = Date.parse(sample.timestamp);
		const seconds = (timestamp - origin) / 1000;
		if (previous !== undefined && timestamp - previous > maxGapSeconds * 1000)
			points.push([seconds - 0.001, null]);
		points.push([seconds, sample.value * factor]);
		previous = timestamp;
	}
	return points;
}
