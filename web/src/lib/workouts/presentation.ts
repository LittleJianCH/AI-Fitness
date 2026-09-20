import { dayKey, formatLocale, browserTimeZone } from '$lib/i18n/format';
import { m as L } from '$lib/paraglide/messages.js';
import type { Workout, WorkoutCard, CommonSummary, MetricKind } from '../api/generated/client';

import type { NumericSample } from './chart-data';
export type MetricKey =
	| 'power'
	| 'heart-rate'
	| 'cadence'
	| 'speed'
	| 'altitude'
	| 'grade'
	| 'temperature'
	| 'step-length'
	| 'vertical-oscillation'
	| 'ground-contact-time';
export const metricKinds: Record<MetricKey, MetricKind> = {
	power: 'powerMetric',
	'heart-rate': 'heartRateMetric',
	cadence: 'cadenceMetric',
	speed: 'speedMetric',
	altitude: 'altitudeMetric',
	grade: 'gradeMetric',
	temperature: 'temperatureMetric',
	'step-length': 'stepLengthMetric',
	'vertical-oscillation': 'verticalOscillationMetric',
	'ground-contact-time': 'groundContactTimeMetric'
};
export type Metric = {
	key: MetricKey;
	title: string;
	unit: string;
	color: string;
	average?: number;
	maximum?: number;
	samples: readonly NumericSample[];
	factor: number;
};
export function commonCard(card: WorkoutCard): CommonSummary {
	return card.summary.type === 'cyclingSummary'
		? card.summary.data.recordedSummary.cyclingCommonSummary
		: card.summary.data.recordedSummary.runningCommonSummary;
}
export function common(workout: Workout): CommonSummary {
	const sport = workout.workoutObservation.observationSport;
	return sport.type === 'cycling'
		? sport.data.cyclingSummary.recordedSummary.cyclingCommonSummary
		: sport.data.runningSummary.recordedSummary.runningCommonSummary;
}
export function motion(workout: Workout) {
	const sport = workout.workoutObservation.observationSport;
	return sport.type === 'cycling' ? sport.data.cyclingMotion : sport.data.runningMotion;
}
export function metrics(workout: Workout): Metric[] {
	const m = motion(workout),
		sport = workout.workoutObservation.observationSport;
	const cycling =
		sport.type === 'cycling' ? sport.data.cyclingSummary.calculatedSummary : undefined;
	const running =
		sport.type === 'running' ? sport.data.runningSummary.calculatedSummary : undefined;
	const currentCycling =
		cycling?.calculationInputRevision === workout.workoutRevision
			? cycling.calculationValue
			: undefined;
	const currentRunning =
		running?.calculationInputRevision === workout.workoutRevision
			? running.calculationValue
			: undefined;
	const s = currentCycling?.cyclingCommonSummary ?? currentRunning?.runningCommonSummary;
	const cadence = currentCycling?.summaryCyclingCadence ?? currentRunning?.summaryRunningCadence;
	const result: Metric[] = [
		{
			key: 'power',
			title: L.metric_power(),
			unit: 'W',
			color: '#7350C7',
			average: s?.summaryPower.averageValue,
			maximum: s?.summaryPower.maximumValue,
			samples: m.motionPower,
			factor: 1
		},
		{
			key: 'heart-rate',
			title: L.metric_heart_rate(),
			unit: 'bpm',
			color: '#D43A4A',
			average: s?.summaryHeartRate.averageValue,
			maximum: s?.summaryHeartRate.maximumValue,
			samples: m.motionHeartRate,
			factor: 1
		},
		{
			key: 'cadence',
			title: sport.type === 'cycling' ? L.metric_cycling_cadence() : L.metric_running_cadence(),
			unit: sport.type === 'cycling' ? 'rpm' : L.unit_steps_minute(),
			color: '#9A6300',
			average: cadence?.averageValue,
			maximum: cadence?.maximumValue,
			samples: sport.type === 'cycling' ? sport.data.cyclingCadence : sport.data.runningCadence,
			factor: 1
		},
		{
			key: 'speed',
			title: L.metric_speed(),
			unit: 'km/h',
			color: '#1769D2',
			average: s?.summarySpeed.averageValue,
			maximum: s?.summarySpeed.maximumValue,
			samples: m.motionSpeed,
			factor: 3.6
		},
		{
			key: 'altitude',
			title: L.metric_altitude(),
			unit: 'm',
			color: '#586B63',
			average: s?.summaryAltitude.averageValue,
			maximum: s?.summaryAltitude.maximumValue,
			samples: m.motionAltitude,
			factor: 1
		}
	];
	result.push(
		{
			key: 'grade',
			title: L.metric_grade(),
			unit: '%',
			color: '#586B63',
			samples: m.motionGrade,
			factor: 1,
			average: s?.summaryGrade.averageValue,
			maximum: s?.summaryGrade.maximumValue
		},
		{
			key: 'temperature',
			title: L.metric_temperature(),
			unit: '°C',
			color: '#9A6300',
			samples: m.motionEnvironment.ambientTemperature,
			factor: 1,
			average: s?.summaryTemperature.averageValue,
			maximum: s?.summaryTemperature.maximumValue
		}
	);
	if (sport.type === 'running')
		result.push(
			{
				key: 'step-length',
				title: L.metric_step_length(),
				unit: 'm',
				color: '#1769D2',
				samples: sport.data.runningDynamics.stepLength,
				factor: 1
			},
			{
				key: 'vertical-oscillation',
				title: L.metric_vertical_oscillation(),
				unit: 'cm',
				color: '#9A6300',
				samples: sport.data.runningDynamics.verticalOscillation,
				factor: 100
			},
			{
				key: 'ground-contact-time',
				title: L.metric_ground_contact(),
				unit: 'ms',
				color: '#586B63',
				samples: sport.data.runningDynamics.groundContactTime,
				factor: 1000
			}
		);
	return result.filter((item) => {
		const recorded = recordedMetricSummary(workout, item.key);
		return (
			item.samples.length ||
			item.average !== undefined ||
			item.maximum !== undefined ||
			recorded.averageValue !== undefined ||
			recorded.maximumValue !== undefined
		);
	});
}
// Recorded statistics are displayed with their provenance, never relabeled as calculations.
export function recordedMetricSummary(
	workout: Workout,
	key: string
): { averageValue?: number; maximumValue?: number } {
	const summary = common(workout),
		sport = workout.workoutObservation.observationSport;
	switch (key) {
		case 'speed':
			return summary.summarySpeed;
		case 'power':
			return summary.summaryPower;
		case 'heart-rate':
			return summary.summaryHeartRate;
		case 'altitude':
			return summary.summaryAltitude;
		case 'grade':
			return summary.summaryGrade;
		case 'temperature':
			return summary.summaryTemperature;
		case 'step-length':
			return sport.type === 'running'
				? sport.data.runningSummary.recordedSummary.summaryStepLength
				: {};
		case 'vertical-oscillation':
			return sport.type === 'running'
				? sport.data.runningSummary.recordedSummary.summaryVerticalOscillation
				: {};
		case 'ground-contact-time':
			return sport.type === 'running'
				? sport.data.runningSummary.recordedSummary.summaryGroundContactTime
				: {};
		case 'cadence':
			return sport.type === 'cycling'
				? sport.data.cyclingSummary.recordedSummary.summaryCyclingCadence
				: sport.data.runningSummary.recordedSummary.summaryRunningCadence;
		default:
			return {};
	}
}
export const valueText = (value: number | undefined, factor = 1, digits = 0) =>
	value === undefined
		? L.value_not_recorded()
		: (value * factor).toLocaleString(formatLocale(), { maximumFractionDigits: digits });
export function duration(seconds: number | undefined) {
	if (seconds === undefined) return L.value_not_recorded();
	const total = Math.floor(seconds),
		h = Math.floor(total / 3600),
		m = Math.floor((total % 3600) / 60),
		s = total % 60;
	return [h, m, s].map((n) => String(n).padStart(2, '0')).join(':');
}
export function timeSummary(summary: CommonSummary) {
	if (summary.summaryMovingTime !== undefined)
		return { label: L.label_moving_time(), seconds: summary.summaryMovingTime };
	if (summary.summaryTimerTime !== undefined)
		return { label: L.label_timer_time(), seconds: summary.summaryTimerTime };
	return { label: L.label_elapsed_time(), seconds: summary.summaryElapsedTime };
}
export function dateText(value: string, zone = browserTimeZone(), locale = formatLocale()): string {
	if (!zone) return '—';
	return new Intl.DateTimeFormat(locale, {
		timeZone: zone,
		year: 'numeric',
		month: 'long',
		day: 'numeric',
		hour: '2-digit',
		minute: '2-digit',
		hour12: false
	}).format(new Date(value));
}
export function dayText(value: string, zone = browserTimeZone(), locale = formatLocale()): string {
	if (!zone) return '—';
	return new Intl.DateTimeFormat(locale, {
		timeZone: zone,
		year: 'numeric',
		month: 'long',
		day: 'numeric',
		weekday: 'long'
	}).format(new Date(value));
}

export function groupCards(
	items: readonly WorkoutCard[],
	zone = browserTimeZone()
): [string, WorkoutCard[]][] {
	const groups = new Map<string, WorkoutCard[]>();
	if (!zone) return [];
	for (const item of items) {
		const key = dayKey(item.range.rangeStart, zone);
		const group = groups.get(key);
		if (group) group.push(item);
		else groups.set(key, [item]);
	}
	return [...groups];
}
