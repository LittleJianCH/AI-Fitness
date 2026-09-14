import { test, expect } from '@playwright/test';

const ride = '00000000-0000-4000-8000-000000000001';
const run = '00000000-0000-4000-8000-000000000002';
const indoor = '00000000-0000-4000-8000-000000000003';

test('power analysis in modal and page supports keyboard selection and unavailable durations', async ({
	page
}, testInfo) => {
	await page.goto(`/workouts/${ride}`);
	await page.getByRole('button', { name: '放大功率图表' }).click();
	const curve = page.getByRole('region', { name: '最佳持续功率', exact: true });
	await expect(curve.getByText('00:01:00 · 200 W', { exact: true })).toBeVisible();
	await curve.getByLabel('选择持续时长').selectOption('5');
	await expect(curve.getByText('00:00:05 · 200 W', { exact: true })).toBeVisible();
	await curve.getByText('查看最佳功率数据表', { exact: true }).click();
	await expect(curve.getByRole('row').filter({ hasText: '2:00' }).first()).toContainText(
		'连续采样不足'
	);
	await page.getByRole('link', { name: '独立页面查看' }).click();
	await expect(curve.getByRole('heading', { name: '最佳持续功率' })).toBeVisible();
	await page.goto(`/workouts/${run}/metrics/power`);
	await expect(curve.getByText('00:01:00 · 200 W', { exact: true })).toBeVisible();
	await curve.screenshot({ path: testInfo.outputPath('power-curve.png') });
	await page.setViewportSize({ width: 320, height: 852 });
	await expect(curve).toBeVisible();
	await expect
		.poll(() => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth))
		.toBe(true);
});

test('summary-only power has an explicit unavailable state', async ({ page }) => {
	const requests: string[] = [];
	page.on('request', (request) => {
		if (request.url().includes('/power-curve')) requests.push(request.url());
	});
	await page.goto(`/workouts/${indoor}/metrics/power`);
	await expect(page.getByText('没有足够的连续功率采样，无法计算最佳持续功率。')).toBeVisible();
	expect(requests).toEqual([]);
});

test('sampling explanation uses the backend gap threshold', async ({ page }) => {
	await page.route('**/power-curve', async (route) => {
		const response = await route.fetch();
		await route.fulfill({ response, json: { ...(await response.json()), maxGapSeconds: 3 } });
	});
	await page.goto(`/workouts/${ride}/metrics/power`);
	await expect(page.getByRole('region', { name: '最佳持续功率', exact: true })).toContainText(
		'相邻采样间隔最多 3'
	);
});

test('curve failure is local, retry works, and stale revisions are hidden', async ({ page }) => {
	let fail = true;
	await page.route('**/power-curve', async (route) => {
		if (fail)
			return route.fulfill({
				status: 500,
				json: { code: 'internal_error', message: 'synthetic', fields: [], requestId: 'synthetic' }
			});
		return route.continue();
	});
	await page.goto(`/workouts/${ride}/metrics/power`);
	const curve = page.getByRole('region', { name: '最佳持续功率', exact: true });
	await expect(curve.getByText('服务暂时无法完成请求，请稍后重试。')).toBeVisible();
	await expect(page.getByRole('heading', { name: '功率时间曲线' })).toBeVisible();
	fail = false;
	await curve.getByRole('button', { name: /重试/ }).click();
	await expect(curve.getByText('00:01:00 · 200 W', { exact: true })).toBeVisible();
	await page.unroute('**/power-curve');
	await page.route('**/power-curve', async (route) => {
		const response = await route.fetch();
		const data = await response.json();
		await route.fulfill({ response, json: { ...data, inputRevision: '2' } });
	});
	await page.reload();
	await expect(curve.getByText('训练已更新，请刷新后查看对应的功率曲线。')).toBeVisible();
	await expect(curve.getByLabel('选择持续时长')).toHaveCount(0);
});
