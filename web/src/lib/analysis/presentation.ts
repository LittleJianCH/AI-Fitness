import type { MetricKind, HeartLoadStatus } from '$lib/api/generated/client';
export const metricInfo: Record<
	MetricKind,
	{ title: string; unit: string; factor: number; digits?: number }
> = {
	heartRateMetric: { title: '心率', unit: 'bpm', factor: 1 },
	powerMetric: { title: '功率', unit: 'W', factor: 1 },
	speedMetric: { title: '速度', unit: 'km/h', factor: 3.6 },
	cadenceMetric: { title: '踏频 / 步频', unit: '次/分钟', factor: 1 },
	altitudeMetric: { title: '海拔', unit: 'm', factor: 1 },
	stepLengthMetric: { title: '步长', unit: 'm', factor: 1, digits: 2 },
	verticalOscillationMetric: { title: '垂直振幅', unit: 'cm', factor: 100 },
	groundContactTimeMetric: { title: '触地时间', unit: 'ms', factor: 1000 },
	temperatureMetric: { title: '温度', unit: '°C', factor: 1 },
	gradeMetric: { title: '坡度', unit: '%', factor: 1 }
};
export const heartStatus: Record<HeartLoadStatus, string> = {
	heartLoadAvailable: '采样覆盖满足要求',
	heartProfileMissing: '请在设置中补充训练开始时生效的心率参数。',
	heartCoverageInsufficient: '心率覆盖不足 95%，以下仅为已观测部分的负荷。',
	heartNoActiveTime: '没有有效计时时间',
	heartExcluded: '此训练不计入统计',
	heartCalculationUnavailable: '当前数据无法计算心率负荷'
};
export function pace(speed: number | undefined) {
	if (speed === undefined || speed <= 0) return '无数据';
	const seconds = Math.round(1000 / speed);
	return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')} /km`;
}

// Metric-specific precision takes precedence over the view's default precision.
export function metricValueText(value: number | undefined, kind: MetricKind, digits = 0) {
	if (value === undefined) return '未记录';
	const info = metricInfo[kind];
	return (value * info.factor).toLocaleString('zh-CN', {
		minimumFractionDigits: info.digits ?? 0,
		maximumFractionDigits: info.digits ?? digits
	});
}
