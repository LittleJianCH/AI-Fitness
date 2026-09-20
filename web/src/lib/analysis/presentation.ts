import { formatLocale } from '$lib/i18n/format';
import { m as L } from '$lib/paraglide/messages.js';
import type { MetricKind, HeartLoadStatus } from '$lib/api/generated/client';
export const metricInfo: Record<
	MetricKind,
	{ title: string; unit: string; factor: number; digits?: number }
> = {
	heartRateMetric: {
		get title() {
			return L.metric_heart_rate();
		},
		unit: 'bpm',
		factor: 1
	},
	powerMetric: {
		get title() {
			return L.metric_power();
		},
		unit: 'W',
		factor: 1
	},
	speedMetric: {
		get title() {
			return L.metric_speed();
		},
		unit: 'km/h',
		factor: 3.6
	},
	cadenceMetric: {
		get title() {
			return L.metric_cadence();
		},
		get unit() {
			return L.unit_cycles_minute();
		},
		factor: 1
	},
	altitudeMetric: {
		get title() {
			return L.metric_altitude();
		},
		unit: 'm',
		factor: 1
	},
	stepLengthMetric: {
		get title() {
			return L.metric_step_length();
		},
		unit: 'm',
		factor: 1,
		digits: 2
	},
	verticalOscillationMetric: {
		get title() {
			return L.metric_vertical_oscillation();
		},
		unit: 'cm',
		factor: 100
	},
	groundContactTimeMetric: {
		get title() {
			return L.metric_ground_contact();
		},
		unit: 'ms',
		factor: 1000
	},
	temperatureMetric: {
		get title() {
			return L.metric_temperature();
		},
		unit: '°C',
		factor: 1
	},
	gradeMetric: {
		get title() {
			return L.metric_grade();
		},
		unit: '%',
		factor: 1
	}
};
export const heartStatus: Record<HeartLoadStatus, string> = {
	get heartLoadAvailable() {
		return L.heart_status_available();
	},
	get heartProfileMissing() {
		return L.heart_status_profile_missing();
	},
	get heartCoverageInsufficient() {
		return L.heart_status_partial();
	},
	get heartNoActiveTime() {
		return L.heart_status_no_time();
	},
	get heartExcluded() {
		return L.heart_status_excluded();
	},
	get heartCalculationUnavailable() {
		return L.heart_status_unavailable();
	}
};
export function pace(speed: number | undefined) {
	if (speed === undefined || speed <= 0) return L.value_no_data();
	const seconds = Math.round(1000 / speed);
	return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')} /km`;
}

// Metric-specific precision takes precedence over the view's default precision.
export function metricValueText(value: number | undefined, kind: MetricKind, digits = 0) {
	if (value === undefined) return L.value_not_recorded();
	const info = metricInfo[kind];
	return (value * info.factor).toLocaleString(formatLocale(), {
		minimumFractionDigits: info.digits ?? 0,
		maximumFractionDigits: info.digits ?? digits
	});
}

// Display precision is one metre in this table. Sub-millimetre arithmetic noise
// at accumulated distance boundaries must not label a complete split as partial.
export const isPartialSplit = (metres: number, length: number): boolean => length - metres > 0.001;
