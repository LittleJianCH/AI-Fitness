// Input timestamps are chronological. Selection never manufactures a sample.
export function nearestTimeIndex(times: string[], target: number): number {
	if (!times.length) return 0;
	let low = 0,
		high = times.length;
	while (low < high) {
		const middle = Math.floor((low + high) / 2);
		if (Date.parse(times[middle]) < target) low = middle + 1;
		else high = middle;
	}
	if (!low) return 0;
	if (low === times.length) return low - 1;
	return target - Date.parse(times[low - 1]) <= Date.parse(times[low]) - target ? low - 1 : low;
}
export function sampleAt<T extends { timestamp: string }>(
	samples: T[],
	time: string | undefined
): T | undefined {
	if (!time) return undefined;
	const target = Date.parse(time);
	let low = 0,
		high = samples.length;
	while (low < high) {
		const middle = Math.floor((low + high) / 2);
		if (Date.parse(samples[middle].timestamp) < target) low = middle + 1;
		else high = middle;
	}
	return samples[low] && Date.parse(samples[low].timestamp) === target ? samples[low] : undefined;
}
