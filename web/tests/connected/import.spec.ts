import { readFile } from 'node:fs/promises';
import { expect } from '@playwright/test';
import { test } from './fixtures';
import { login, register } from './helpers';

const fixture = (sport: string) => `../backend/build/fit-fixtures-data/${sport}.fit`;

// The in-app WebKit on macOS 14.1 has AbortController but no AbortSignal.any.
// Exercise the real upload flow with that API absent in both viewport projects.
test.beforeEach(async ({ page }) => {
	await page.addInitScript(() => {
		Object.defineProperty(AbortSignal, 'any', { configurable: true, value: undefined });
	});
});

test('imports cycling and running, deduplicates renamed files, and survives restart', async ({
	page,
	restartBackend
}) => {
	await login(page, await register(page));
	await page.getByRole('link', { name: '上传 FIT', exact: true }).click();
	const input = page.getByLabel('FIT 文件', { exact: true });
	await input.setInputFiles(fixture('cycling'));
	await page.getByRole('button', { name: '开始导入', exact: true }).click();
	await expect(page.getByRole('heading', { name: '训练已导入' })).toBeVisible();
	const link = page.getByRole('link', { name: '查看训练', exact: true });
	const first = await link.getAttribute('href');
	await input.setInputFiles({
		name: 'renamed.FIT',
		mimeType: 'application/octet-stream',
		buffer: await readFile(fixture('cycling'))
	});
	await page.getByRole('button', { name: '开始导入', exact: true }).click();
	await expect(link).toHaveAttribute('href', first ?? 'missing-workout-link');
	await restartBackend();
	await page.reload();
	await input.setInputFiles(fixture('cycling'));
	await page.getByRole('button', { name: '开始导入', exact: true }).click();
	await expect(link).toHaveAttribute('href', first ?? 'missing-workout-link');
	await link.click();
	await expect(page.getByRole('heading', { name: '未命名训练' })).toBeVisible();
	const heartRate = page.getByRole('button', { name: '放大心率图表', exact: true });
	await expect(heartRate.locator('.metric-heading > .subtle')).toContainText('125');
	await expect(heartRate.locator('.metric-heading > .subtle')).toContainText('计算平均');
	await heartRate.click();
	await expect(page.locator('.summary-strip > div').filter({ hasText: '计算最大' })).toContainText(
		'130'
	);

	await page.goto('/workouts/import');
	await input.setInputFiles(fixture('running'));
	await page.getByRole('button', { name: '开始导入', exact: true }).click();
	await expect(link).toBeVisible();
	await expect(link).not.toHaveAttribute('href', first ?? 'missing-workout-link');
	await expect(page.locator('html')).toHaveJSProperty(
		'scrollWidth',
		await page.evaluate(() => innerWidth)
	);
});

test('reports parser failures and blocks empty or oversized files before sending', async ({
	page
}) => {
	await login(page, await register(page));
	await page.goto('/workouts/import');
	const input = page.getByLabel('FIT 文件', { exact: true });
	let uploads = 0;
	page.on('request', (request) => {
		if (request.url().endsWith('/api/v1/imports/fit')) uploads++;
	});
	await input.setInputFiles({
		name: 'empty.fit',
		mimeType: 'application/octet-stream',
		buffer: Buffer.alloc(0)
	});
	await page.getByRole('button', { name: '开始导入', exact: true }).click();
	await expect(page.getByRole('alert')).toContainText('空的');
	await input.setInputFiles({
		name: 'large.fit',
		mimeType: 'application/octet-stream',
		buffer: Buffer.alloc(16 * 1024 * 1024 + 1)
	});
	await page.getByRole('button', { name: '开始导入', exact: true }).click();
	await expect(page.getByRole('alert')).toContainText('大小限制');
	expect(uploads).toBe(0);
	await input.setInputFiles({
		name: 'broken.fit',
		mimeType: 'application/octet-stream',
		buffer: Buffer.from('synthetic invalid FIT')
	});
	await page.getByRole('button', { name: '开始导入', exact: true }).click();
	await expect(page.getByRole('heading', { name: '未能导入' })).toBeVisible();
	await expect(
		page.getByText('文件损坏或不是有效的 FIT 活动文件，请重新导出后再试。')
	).toBeVisible();
	await input.setInputFiles(fixture('swimming'));
	await page.getByRole('button', { name: '开始导入', exact: true }).click();
	await expect(page.getByText('暂时仅支持包含单次骑行或跑步的 FIT 活动文件。')).toBeVisible();
	await expect(page.getByRole('link', { name: '查看训练' })).toHaveCount(0);
});

test('a lost successful response can be retried without publishing a second workout', async ({
	page
}) => {
	await login(page, await register(page));
	await page.goto('/workouts/import');
	const input = page.getByLabel('FIT 文件', { exact: true });
	await input.setInputFiles(fixture('cycling'));
	let committedId: string | undefined;
	await page.route(
		'**/api/v1/imports/fit',
		async (route) => {
			const response = await route.fetch();
			const record: { lastSuccess: { parts: { workoutId: string }[] } } = await response.json();
			committedId = record.lastSuccess.parts[0]?.workoutId;
			await route.abort('failed');
		},
		{ times: 1 }
	);
	await page.getByRole('button', { name: '开始导入', exact: true }).click();
	await expect(
		page.getByText('结果尚未确认。请重试上传同一文件，服务器会核对已有记录。')
	).toBeVisible();
	await expect(input).toBeDisabled();
	await page.getByRole('button', { name: '重试上传', exact: true }).click();
	await expect(page.getByRole('link', { name: '查看训练', exact: true })).toHaveAttribute(
		'href',
		`/workouts/${committedId}`
	);
	const count = await page.evaluate(async () => {
		const response = await fetch('/api/v1/workouts');
		const result: { items: unknown[] } = await response.json();
		return result.items.length;
	});
	expect(count).toBe(1);
});
