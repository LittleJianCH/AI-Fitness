export function sampleAt<T extends { timestamp: string }>(
	samples: readonly T[],
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
