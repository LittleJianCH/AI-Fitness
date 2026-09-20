import { expect } from '@playwright/test';
import { test } from './fixtures';
import { login, register, seedWorkout } from './helpers';

test('SSR negotiates each request without leaking languages and hydrates the resolved locale', async ({
	browser,
	request
}) => {
	const results = await Promise.all(
		Array.from({ length: 12 }, (_, index) =>
			request.get('/login', { headers: { 'Accept-Language': index % 2 ? 'zh-Hans' : 'en-GB' } })
		)
	);
	for (let index = 0; index < results.length; index++) {
		expect(results[index].headers()['cache-control']).toContain('no-store');
		expect(await results[index].text()).toContain(`lang="${index % 2 ? 'zh-Hans' : 'en'}"`);
	}
	const context = await browser.newContext({
		locale: 'en-GB',
		ignoreHTTPSErrors: true,
		baseURL: 'https://localhost:5181'
	});
	try {
		const page = await context.newPage();
		const errors: string[] = [];
		page.on('console', (message) => {
			if (message.type() === 'error' || message.type() === 'warning') errors.push(message.text());
		});
		await page.goto('/login');
		await expect(page.getByRole('heading', { name: 'Welcome back', exact: true })).toBeVisible();
		await expect(page.locator('html')).toHaveAttribute('lang', 'en');
		await page.getByTestId('language-picker').selectOption('zh-Hans');
		await expect(page.getByRole('heading', { name: '欢迎回来', exact: true })).toBeVisible();
		await page.getByTestId('language-picker').selectOption('system');
		await expect(page.getByRole('heading', { name: 'Welcome back', exact: true })).toBeVisible();
		expect(
			(await context.cookies()).find((cookie) => cookie.name === 'fitness-language')
		).toBeUndefined();
		expect(errors.filter((error) => /hydration/i.test(error))).toEqual([]);
	} finally {
		await context.close();
	}
});
test('language switching protects drafts and leaves user content, measurements and revisions unchanged', async ({
	page
}) => {
	const username = await register(page);
	await login(page, username);
	const id = await seedWorkout(page, 'metric_power');
	const before = await (await page.request.get(`/api/v1/workouts/${id}`)).json();
	await page.goto(`/workouts/${id}/edit`);
	await page.getByLabel('标题（可选）', { exact: true }).fill('Synthetic <b>title</b> 中文');
	const cancelled = page.waitForEvent('dialog').then((dialog) => dialog.dismiss());
	await page.getByTestId('language-picker').selectOption('en');
	await cancelled;
	await expect(page.getByLabel('标题（可选）', { exact: true })).toHaveValue(
		'Synthetic <b>title</b> 中文'
	);
	expect(
		(await page.context().cookies()).find((cookie) => cookie.name === 'fitness-language')
	).toBeUndefined();
	const accepted = page.waitForEvent('dialog').then((dialog) => dialog.accept());
	await page.getByTestId('language-picker').selectOption('en');
	await accepted;
	await expect(page.getByLabel('Title (optional)', { exact: true })).toHaveValue('metric_power');
	await page.getByRole('link', { name: 'Back to details', exact: true }).click();
	await expect(page.getByRole('heading', { name: 'metric_power', exact: true })).toBeVisible();
	expect(await (await page.request.get(`/api/v1/workouts/${id}`)).json()).toEqual(before);
	await page.setViewportSize({ width: 320, height: 852 });
	expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
	await page.screenshot({ path: test.info().outputPath('workout-en.png'), fullPage: true });
});

test('cleared optional profile fields save and the local theme survives account saves', async ({
	page
}) => {
	await login(page, await register(page));
	await page.getByRole('combobox', { name: '外观主题', exact: true }).selectOption('dark');
	await page.goto('/settings');
	await page.getByRole('button', { name: '更新个人参数', exact: true }).click();
	await page.getByLabel('生效时间（本地）').fill('2026-01-01T08:00');
	for (const name of ['体重 (kg)', '身高 (m)', '骑行阈值功率 (W)', '跑步阈值功率 (W)']) {
		const field = page.getByLabel(name, { exact: true });
		await field.fill('10');
		await field.fill('');
	}
	await page
		.getByRole('combobox', { name: '账号外观', exact: true })
		.selectOption('lightAppearance');
	await page.getByRole('button', { name: '保存设置', exact: true }).click();
	await expect(page.getByText('设置已保存到当前账号。', { exact: true })).toBeVisible();
	await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
	const saved = await (await page.request.get('/api/v1/settings')).json();
	const body = saved.settingsBodyProfiles.at(-1);
	expect(body.bodyMassKilograms).toBeUndefined();
	expect(body.bodyHeightMetres).toBeUndefined();
	expect(body.bodyCycling.sportThresholdWatts).toBeUndefined();
	expect(body.bodyRunning.sportThresholdWatts).toBeUndefined();
	await page.reload();
	await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
	await page.getByRole('button', { name: '更新个人参数', exact: true }).click();
	await page.getByLabel('体重 (kg)', { exact: true }).fill('11');
	const dialogs: string[] = [];
	page.on('dialog', async (dialog) => {
		dialogs.push(dialog.type());
		await dialog.accept();
	});
	await page.getByTestId('language-picker').selectOption('en');
	await expect(page.getByRole('heading', { name: 'Settings', exact: true })).toBeVisible();
	expect(dialogs).toEqual(['confirm']);
});
