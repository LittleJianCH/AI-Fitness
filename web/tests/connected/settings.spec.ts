import { expect, type Browser, type BrowserContext, type Page } from '@playwright/test';
import { test } from './fixtures';
import { register, login, password } from './helpers';
async function anotherSession(browser: Browser, username: string, deviceName: string) {
	const context = await browser.newContext({
		baseURL: 'https://localhost:5181',
		ignoreHTTPSErrors: true
	});
	try {
		const bootstrap = await context.request.get('/api/v1/auth/web/csrf');
		const csrf = await bootstrap.json();
		const response = await context.request.post('/api/v1/auth/web/login', {
			headers: { Origin: 'https://localhost:5181', 'X-CSRF-Token': csrf.csrfToken },
			data: { username, password, deviceName }
		});
		expect(response.status()).toBe(200);
		return context;
	} catch (error) {
		await context.close();
		throw error;
	}
}
async function settings(page: Page) {
	await page
		.getByRole('navigation', { name: '主导航' })
		.getByRole('link', { name: '账号', exact: true })
		.click();
	await expect(page.getByRole('heading', { level: 1, name: '账号设置' })).toBeVisible();
}
async function confirm(page: Page, name: string) {
	const dialog = page.waitForEvent('dialog').then((dialog) => dialog.accept());
	await page.getByRole('button', { name, exact: true }).click();
	await dialog;
}

test('settings paginate sessions, recover stale cursors and revoke individual or current devices', async ({
	page,
	browser,
	restartBackend
}) => {
	const username = await register(page);
	await login(page, username);
	const others: BrowserContext[] = [];
	try {
		for (let index = 0; index < 5; index++)
			others.push(await anotherSession(browser, username, `Synthetic device ${index}`));
		await settings(page);
		await expect(
			page.getByRole('list', { name: '登录设备', exact: true }).getByRole('listitem')
		).toHaveCount(5);
		await restartBackend();
		await page.getByRole('button', { name: '加载更多设备', exact: true }).click();
		await expect(page.getByRole('alert')).toContainText('从第一页重新加载');
		await page.getByRole('button', { name: '重试', exact: true }).click();
		await expect(page.getByRole('alert')).toHaveCount(0);
		await page.getByRole('button', { name: '加载更多设备', exact: true }).click();
		await expect(
			page.getByRole('list', { name: '登录设备', exact: true }).getByRole('listitem')
		).toHaveCount(6);
		await expect(page.getByText('当前设备', { exact: true })).toBeVisible();
		const device = page
			.getByRole('listitem')
			.filter({ has: page.getByRole('heading', { name: 'Synthetic device 0', exact: true }) });
		const dialog = page.waitForEvent('dialog').then((dialog) => dialog.accept());
		await device.getByRole('button', { name: '退出这台设备', exact: true }).click();
		await dialog;
		await expect(page.getByText('已退出这台设备。', { exact: true })).toBeVisible();
		await expect(
			page.getByRole('heading', { name: 'Synthetic device 0', exact: true })
		).toHaveCount(0);
		expect((await others[0].request.get('/api/v1/me')).status()).toBe(401);
		expect((await others[1].request.get('/api/v1/me')).status()).toBe(200);
		await page.screenshot({ path: test.info().outputPath('account-settings.png'), fullPage: true });
		await page.setViewportSize({ width: 320, height: 852 });
		expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
			true
		);
		await confirm(page, '退出当前设备');
		await expect(page.getByRole('heading', { name: '欢迎回来', exact: true })).toBeVisible();
		expect((await others[1].request.get('/api/v1/me')).status()).toBe(200);
	} finally {
		await Promise.all(others.map((context) => context.close()));
	}
});

test('revoke all signs out current and other sessions', async ({ page, browser }) => {
	const username = await register(page);
	await login(page, username);
	const other = await anotherSession(browser, username, 'Synthetic other device');
	try {
		await settings(page);
		await confirm(page, '退出所有设备');
		await expect(page.getByRole('heading', { name: '欢迎回来', exact: true })).toBeVisible();
		expect((await other.request.get('/api/v1/me')).status()).toBe(401);
		await login(page, username);
		await expect(page.getByRole('button', { name: '退出登录', exact: true })).toBeVisible();
	} finally {
		await other.close();
	}
});

test('password change validates confirmation, keeps a valid session on wrong current password and revokes all on success', async ({
	page,
	browser
}) => {
	const username = await register(page);
	await login(page, username);
	const other = await anotherSession(browser, username, 'Synthetic password device');
	const replacement = 'Synthetic-replacement-password-2026';
	try {
		await settings(page);
		await page.getByLabel('当前密码', { exact: true }).fill('Synthetic-wrong-password');
		await page.getByLabel('新密码', { exact: true }).fill(replacement);
		await page.getByLabel('确认新密码', { exact: true }).fill('Synthetic-mismatched-password');
		await page.getByRole('button', { name: '修改密码并退出', exact: true }).click();
		await expect(page.getByRole('alert')).toContainText('两次输入的新密码不一致');
		await page.getByLabel('确认新密码', { exact: true }).fill(replacement);
		await page.getByRole('button', { name: '修改密码并退出', exact: true }).click();
		await expect(page.getByRole('alert')).toContainText('当前密码不正确');
		await expect(page.getByRole('button', { name: '退出登录', exact: true })).toBeVisible();
		await page.getByLabel('当前密码', { exact: true }).fill(password);
		await page.getByRole('button', { name: '修改密码并退出', exact: true }).click();
		await expect(page.getByRole('heading', { name: '欢迎回来', exact: true })).toBeVisible();
		expect((await other.request.get('/api/v1/me')).status()).toBe(401);
		await page.getByLabel('用户名', { exact: true }).fill(username);
		await page.getByLabel('密码', { exact: true }).fill(password);
		await page.getByRole('button', { name: '登录', exact: true }).click();
		await expect(page.getByRole('alert')).toContainText('用户名或密码不正确');
		await login(page, username, replacement);
		await expect(page.getByRole('heading', { level: 1, name: '账号设置' })).toBeVisible();
		await expect(page.getByLabel('当前密码', { exact: true })).toHaveValue('');
		await expect(page.getByLabel('新密码', { exact: true })).toHaveValue('');
	} finally {
		await other.close();
	}
});
