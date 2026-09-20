import { isPartialSplit, metricValueText } from '../src/lib/analysis/presentation';
import { expect, it } from 'vitest';
import { workouts } from '../demo/fixtures';
import { buildManualWorkout } from '../src/lib/workouts/manual';
import { metrics, recordedMetricSummary } from '../src/lib/workouts/presentation';

it.each(['averageValue', 'maximumValue'] as const)(
	'keeps summary-only running dynamics with recorded %s provenance, including zero',
	(field) => {
		const input = buildManualWorkout(
			{
				sport: 'running',
				start: '2026-01-01T08:00',
				minutes: 20,
				seconds: 0,
				title: '',
				notes: '',
				tags: []
			},
			'00000000-0000-4000-8000-000000000001'
		);
		const workout = { ...workouts[1], workoutObservation: input.observation };
		const sport = workout.workoutObservation.observationSport;
		if (sport.type !== 'running') throw new Error('Expected running fixture');
		const summary = sport.data.runningSummary.recordedSummary;
		summary.summaryStepLength = { [field]: 0.45 };
		summary.summaryVerticalOscillation = { [field]: 0 };
		summary.summaryGroundContactTime = { [field]: 0.2 };
		expect(metrics(workout).map((metric) => metric.key)).toEqual([
			'step-length',
			'vertical-oscillation',
			'ground-contact-time'
		]);
		for (const metric of metrics(workout)) {
			expect(metric.samples).toEqual([]);
			expect(metric.average).toBeUndefined();
			expect(metric.maximum).toBeUndefined();
			expect(recordedMetricSummary(workout, metric.key)[field]).toBeDefined();
		}
		summary.summaryStepLength = {};
		summary.summaryVerticalOscillation = {};
		summary.summaryGroundContactTime = {};
		expect(metrics(workout)).toEqual([]);
	}
);

it.each([0, 1, 2])('preserves step-length precision with view default %s', (digits) => {
	expect(metricValueText(1.5, 'stepLengthMetric', digits)).toBe('1.50');
	expect(metricValueText(0.45, 'stepLengthMetric', digits)).toBe('0.45');
	expect(metricValueText(0, 'stepLengthMetric', digits)).toBe('0.00');
	expect(metricValueText(undefined, 'stepLengthMetric', digits)).toBe('Not recorded');
});
it('retains unit conversions and existing precision for other metrics', () => {
	expect(metricValueText(5, 'speedMetric', 1)).toBe('18');
	expect(metricValueText(0.095, 'verticalOscillationMetric', 1)).toBe('9.5');
	expect(metricValueText(0.2, 'groundContactTimeMetric')).toBe('200');
});

it('ignores floating point split-boundary noise but marks a real short final split', () => {
	expect(isPartialSplit(3.2 + 1000 * 3 - (3.2 + 1000 * 2), 1000)).toBe(false);
	expect(isPartialSplit(999.99999999999977, 1000)).toBe(false);
	expect(isPartialSplit(999.5, 1000)).toBe(true);
	expect(isPartialSplit(4999.999999999999, 5000)).toBe(false);
});
