import { randomUUID } from 'node:crypto';
import { expect, type Page } from '@playwright/test';
import { workouts } from '../../demo/fixtures';
export const password = 'Synthetic-test-password-2026';
export const newUsername = () => `web_${randomUUID().replaceAll('-', '')}`;
export async function register(page: Page, username = newUsername()) {
	await page.goto('/login');
	await page.getByRole('button', { name: '注册新账号' }).click();
	await page.getByLabel('用户名', { exact: true }).fill(username);
	await page.getByLabel('密码', { exact: true }).fill(password);
	await page.getByRole('button', { name: '创建账号', exact: true }).click();
	await expect(page.getByText('账号已创建，请登录。')).toBeVisible();
	return username;
}
export async function login(page: Page, username: string, secret = password) {
	await page.getByLabel('用户名', { exact: true }).fill(username);
	await page.getByLabel('密码', { exact: true }).fill(secret);
	await page.getByRole('button', { name: '登录', exact: true }).click();
	await expect(page.getByRole('button', { name: '退出登录', exact: true })).toBeVisible();
}
export async function seedWorkout(page: Page, title: string, index = 2) {
	const workout = workouts[index];
	return page.evaluate(
		async ({ observation, title, submissionId }) => {
			const csrfResponse = await fetch('/api/v1/auth/web/csrf');
			const csrf: { csrfToken: string } = await csrfResponse.json();
			const response = await fetch('/api/v1/workouts', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf.csrfToken },
				body: JSON.stringify({
					submissionId,
					observation,
					userData: {
						workoutTitle: title,
						workoutTags: ['synthetic'],
						statisticsInclusion: 'includeInStatistics'
					}
				})
			});
			if (response.status !== 200)
				throw new Error(`Synthetic fixture rejected: ${response.status}`);
			const saved: { workoutId: string } = await response.json();
			return saved.workoutId;
		},
		{ observation: workout.workoutObservation, title, submissionId: randomUUID() }
	);
}
