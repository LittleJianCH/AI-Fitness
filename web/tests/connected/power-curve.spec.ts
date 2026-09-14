import { randomUUID } from 'node:crypto';
import { expect } from '@playwright/test';
import { test } from './fixtures';
import { login, register } from './helpers';
import { workouts } from '../../demo/fixtures';
import { getWorkoutsWorkoutIdPowerCurve200Response } from '../../src/lib/api/generated/schemas';

for (const [index, sportName] of ['cycling', 'running'].entries()) {
	test(`${sportName} power analysis displays the real backend calculation`, async ({ page }) => {
		await login(page, await register(page));
		const observation = structuredClone(workouts[index].workoutObservation);
		const sport = observation.observationSport;
		const motion = sport.type === 'cycling' ? sport.data.cyclingMotion : sport.data.runningMotion;
		const start = Date.parse(observation.observationRange.rangeStart);
		// A linear decline from 400 W to 100 W has a 250 W full-minute mean.
		motion.motionPower = Array.from({ length: 61 }, (_, second) => ({
			timestamp: new Date(start + second * 1000).toISOString(),
			value: 400 - second * 5
		}));
		const id = await page.evaluate(
			async ({ observation, submissionId }) => {
				const csrf = await (await fetch('/api/v1/auth/web/csrf')).json();
				const response = await fetch('/api/v1/workouts', {
					method: 'POST',
					headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf.csrfToken },
					body: JSON.stringify({
						submissionId,
						observation,
						userData: {
							workoutTitle: 'Synthetic declining power',
							workoutTags: [],
							statisticsInclusion: 'includeInStatistics'
						}
					})
				});
				if (!response.ok) throw new Error(`Synthetic workout rejected: ${response.status}`);
				return (await response.json()).workoutId as string;
			},
			{ observation, submissionId: randomUUID() }
		);

		await page.goto(`/workouts/${id}`);
		const received = page.waitForResponse((response) =>
			response.url().endsWith(`/workouts/${id}/power-curve`)
		);
		await page.getByRole('button', { name: '放大功率图表' }).click();
		const response = await received;
		expect(response.status()).toBe(200);
		const curve = getWorkoutsWorkoutIdPowerCurve200Response.parse(await response.json());
		expect(curve.curveWorkoutId).toBe(id);
		expect(
			curve.points.find((point) => point.durationSeconds === 1)?.best?.averagePower
		).toBeCloseTo(397.5);
		expect(
			curve.points.find((point) => point.durationSeconds === 5)?.best?.averagePower
		).toBeCloseTo(387.5);
		expect(
			curve.points.find((point) => point.durationSeconds === 60)?.best?.averagePower
		).toBeCloseTo(250);
		expect(curve.points.find((point) => point.durationSeconds === 120)?.best).toBeUndefined();
		const section = page.getByRole('region', { name: '最佳持续功率', exact: true });
		await expect(section.getByText('00:01:00 · 250 W', { exact: true })).toBeVisible();
		await section.getByLabel('选择持续时长').selectOption('5');
		await expect(section.getByText('00:00:05 · 387.5 W', { exact: true })).toBeVisible();
		await page.getByRole('link', { name: '独立页面查看' }).click();
		await expect(section.getByRole('heading', { name: '最佳持续功率' })).toBeVisible();
	});
}
