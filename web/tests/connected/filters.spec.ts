import { expect } from '@playwright/test';
import { test } from './fixtures';
import { register, login, seedWorkout } from './helpers';

test('date and exact-tag filters apply to local workout start and survive back navigation', async ({
	page
}) => {
	const username = await register(page);
	await login(page, username);
	await seedWorkout(page, 'Synthetic before day', 2, {
		start: '2026-09-10T15:59:59Z',
		tags: ['match']
	});
	await seedWorkout(page, 'Synthetic day start', 2, {
		start: '2026-09-10T16:00:00Z',
		tags: ['match']
	});
	await seedWorkout(page, 'Synthetic day end', 2, {
		start: '2026-09-11T15:59:59Z',
		tags: ['match']
	});
	await seedWorkout(page, 'Synthetic next day', 2, {
		start: '2026-09-11T16:00:00Z',
		tags: ['match']
	});
	await seedWorkout(page, 'Synthetic partial tag', 2, {
		start: '2026-09-11T08:00:00Z',
		tags: ['match-other']
	});
	await page.reload();
	await page.getByLabel('开始日期', { exact: true }).fill('2026-09-01');
	await page.getByLabel('结束日期（含当天）', { exact: true }).fill('2026-09-02');
	await page.getByLabel('标签（精确匹配）', { exact: true }).fill('unapplied');
	await page.getByRole('button', { name: '清除筛选', exact: true }).click();
	await expect(page.getByLabel('开始日期', { exact: true })).toHaveValue('');
	await expect(page.getByLabel('结束日期（含当天）', { exact: true })).toHaveValue('');
	await expect(page.getByLabel('标签（精确匹配）', { exact: true })).toHaveValue('');
	await page.getByLabel('开始日期', { exact: true }).fill('2026-09-11');
	await page.getByLabel('结束日期（含当天）', { exact: true }).fill('2026-09-11');
	await page.getByLabel('标签（精确匹配）', { exact: true }).fill('match');
	await page.getByRole('button', { name: '应用筛选', exact: true }).click();
	await expect(page.getByText('已显示全部 2 条训练')).toBeVisible();
	await expect(page.getByRole('heading', { name: 'Synthetic day start' })).toBeVisible();
	await expect(page.getByRole('heading', { name: 'Synthetic day end' })).toBeVisible();
	await page.screenshot({ path: test.info().outputPath('filtered-list.png'), fullPage: true });
	const link = page.getByRole('link', { name: /Synthetic day start/ });
	await link.click();
	await expect(page.getByRole('heading', { level: 1, name: 'Synthetic day start' })).toBeVisible();
	await page.goBack();
	await expect(page.getByLabel('标签（精确匹配）', { exact: true })).toHaveValue('match');
	await expect(page.getByText('已显示全部 2 条训练')).toBeVisible();
	await page.setViewportSize({ width: 320, height: 852 });
	expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
	await page.getByRole('button', { name: '清除筛选', exact: true }).click();
	await expect(page.getByLabel('开始日期', { exact: true })).toHaveValue('');
	await expect(page.getByLabel('标签（精确匹配）', { exact: true })).toHaveValue('');
	await page.getByRole('button', { name: '加载更多训练', exact: true }).click();
	await expect(page.getByText('已显示全部 5 条训练')).toBeVisible();
});

test('invalid date URLs stay editable and stale workout cursors restart at the first page', async ({
	page,
	restartBackend
}) => {
	const username = await register(page);
	await login(page, username);
	for (let index = 0; index < 4; index++) await seedWorkout(page, `Synthetic pagination ${index}`);
	await page.goto('/workouts?from=2026-02-30');
	await expect(page.getByRole('alert')).toContainText('请使用有效的本地日期');
	await expect(page.getByRole('heading', { level: 3 })).toHaveCount(0);
	await page.getByRole('button', { name: '清除筛选', exact: true }).click();
	await expect(page.getByRole('heading', { level: 3 })).toHaveCount(3);
	await restartBackend();
	await page.getByRole('button', { name: '加载更多训练', exact: true }).click();
	await expect(page.getByRole('alert')).toContainText('从第一页重新加载');
	await page.getByRole('button', { name: '重试', exact: true }).click();
	await expect(page.getByRole('alert')).toHaveCount(0);
	await expect(page.getByRole('heading', { level: 3 })).toHaveCount(3);
	await page.getByRole('button', { name: '加载更多训练', exact: true }).click();
	await expect(page.getByText('已显示全部 4 条训练')).toBeVisible();
});

test.describe('midnight daylight-saving transition', () => {
	test.use({ timezoneId: 'America/Santiago' });
	test('a day starting at 01:00 excludes the first hour of the next day', async ({ page }) => {
		const username = await register(page);
		await login(page, username);
		await seedWorkout(page, 'Synthetic DST start', 2, { start: '2026-09-06T04:00:00Z', tags: [] });
		await seedWorkout(page, 'Synthetic DST end', 2, { start: '2026-09-07T02:59:59Z', tags: [] });
		await seedWorkout(page, 'Synthetic following day', 2, {
			start: '2026-09-07T03:30:00Z',
			tags: []
		});
		await page.reload();
		await page.getByLabel('开始日期', { exact: true }).fill('2026-09-06');
		await page.getByLabel('结束日期（含当天）', { exact: true }).fill('2026-09-06');
		await page.getByRole('button', { name: '应用筛选', exact: true }).click();
		await expect(page.getByText('已显示全部 2 条训练')).toBeVisible();
		await expect(page.getByRole('heading', { name: 'Synthetic DST start' })).toBeVisible();
		await expect(page.getByRole('heading', { name: 'Synthetic DST end' })).toBeVisible();
		await expect(page.getByRole('heading', { name: 'Synthetic following day' })).toHaveCount(0);
	});
});
