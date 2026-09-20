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

// Sort once per series. Search expands from the nearest horizontal coordinate
// and stops once its horizontal distance exceeds the best pixel distance.
export type CoordinatePoint = Readonly<{ x: number; y: number; index: number }>;
export function coordinateIndex(
	coordinates: readonly (number | undefined)[],
	values: readonly number[]
): CoordinatePoint[] {
	return coordinates
		.flatMap((x, index) => (x === undefined ? [] : [{ x, y: values[index], index }]))
		.sort((a, b) => a.x - b.x || a.index - b.index);
}
export function nearestCoordinateIndex(
	points: readonly CoordinatePoint[],
	targetX: number,
	targetY: number,
	xPerPixel = 1,
	yPerPixel = 1
): number | undefined {
	let low = 0,
		high = points.length;
	while (low < high) {
		const middle = Math.floor((low + high) / 2);
		if (points[middle].x < targetX) low = middle + 1;
		else high = middle;
	}
	let left = low - 1,
		right = low,
		best: number | undefined,
		distance = Infinity;
	const dx = (i: number) => Math.abs((points[i].x - targetX) / xPerPixel);
	while (left >= 0 || right < points.length) {
		const l = left >= 0 ? dx(left) : Infinity;
		const r = right < points.length ? dx(right) : Infinity;
		if (Math.min(l, r) ** 2 > distance) break;
		const i = l <= r ? left-- : right++;
		const point = points[i];
		const squared = dx(i) ** 2 + ((point.y - targetY) / yPerPixel) ** 2;
		if (
			squared < distance ||
			(squared === distance && (best === undefined || point.index < best))
		) {
			best = point.index;
			distance = squared;
		}
	}
	return best;
}
