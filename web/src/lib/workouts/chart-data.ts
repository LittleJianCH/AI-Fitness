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
	maxGapSeconds = 120,
	coordinates?: readonly (number | undefined)[]
): [number, number | null][] {
	const points: [number, number | null][] = [];
	const origin = Date.parse(start);
	let previous: number | undefined;
	let previousX: number | undefined;
	for (const [index, sample] of samples.entries()) {
		const timestamp = Date.parse(sample.timestamp);
		const seconds = (timestamp - origin) / 1000;
		const x = coordinates ? coordinates[index] : seconds;
		if (x === undefined) {
			points.push([previousX ?? 0, null]);
			continue;
		}
		if (
			previous !== undefined &&
			(timestamp - previous > maxGapSeconds * 1000 || (previousX !== undefined && x < previousX))
		)
			points.push([coordinates ? x : seconds - 0.001, null]);
		points.push([x, sample.value * factor]);
		previous = timestamp;
		previousX = x;
	}
	return points;
}

// Horizontal display coordinates only; metric values and backend statistics
// are untouched. Never extrapolate, cross a long gap, or interpolate a reset.
export function distanceCoordinates(
	samples: readonly NumericSample[],
	distances: readonly NumericSample[],
	maxGapSeconds = 120
): (number | undefined)[] {
	const times = sampleTimes(distances);
	return samples.map((sample) => {
		const target = Date.parse(sample.timestamp);
		let low = 0,
			high = times.length;
		while (low < high) {
			const middle = Math.floor((low + high) / 2);
			if (times[middle] < target) low = middle + 1;
			else high = middle;
		}
		if (times[low] === target) return distances[low].value / 1000;
		if (!low || low === times.length) return undefined;
		const gap = times[low] - times[low - 1];
		const before = distances[low - 1].value,
			after = distances[low].value;
		if (gap <= 0 || gap > maxGapSeconds * 1000 || after < before) return undefined;
		return (before + (after - before) * ((target - times[low - 1]) / gap)) / 1000;
	});
}

// Distance may pause or reset, so binary search is not valid for this axis.
export function nearestCoordinateIndex(
	coordinates: readonly (number | undefined)[],
	target: number
): number | undefined {
	let best: number | undefined;
	let difference = Infinity;
	coordinates.forEach((x, index) => {
		if (x !== undefined && Math.abs(x - target) < difference) {
			best = index;
			difference = Math.abs(x - target);
		}
	});
	return best;
}
