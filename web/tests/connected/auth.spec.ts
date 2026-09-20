import { expect } from '@playwright/test';
import { test } from './fixtures';
import { register, login, seedWorkout } from './helpers';

test('registration, safe return navigation, real reads, session restoration and logout', async ({
	page,
	context,
	restartBackend
}) => {
	const errors: string[] = [];
	page.on('pageerror', (error) => errors.push(error.message));
	await page.goto('/workouts');
	await expect(page).toHaveURL(/\/login\?next=/);
	const username = await register(page);
	await login(page, username);
	await expect(page.getByRole('heading', { name: '还没有训练记录' })).toBeVisible();
	const id = await seedWorkout(page, 'Synthetic saved workout');
	await page.reload();
	await page.getByRole('link', { name: /Synthetic saved workout/ }).click();
	await expect(page).toHaveURL(new RegExp(`/workouts/${id}$`));
	await expect(
		page.getByRole('heading', { level: 1, name: 'Synthetic saved workout' })
	).toBeVisible();
	await expect(page.getByText('合成训练', { exact: true })).toHaveCount(0);
	await restartBackend();
	await page.reload();
	await expect(
		page.getByRole('heading', { level: 1, name: 'Synthetic saved workout' })
	).toBeVisible();
	const cookie = (await context.cookies()).find(
		(item) => item.name === '__Host-ai-fitness-session'
	);
	expect(cookie).toMatchObject({ secure: true, httpOnly: true, sameSite: 'Lax', path: '/' });
	expect(await page.evaluate(() => document.cookie)).not.toContain('__Host-ai-fitness-session');
	// Only an explicit browser theme choice is stored locally.
	expect(await page.evaluate(() => Object.keys(localStorage))).toEqual([]);
	await page.getByRole('button', { name: '退出登录', exact: true }).click();
	await expect(page.getByRole('button', { name: '登录', exact: true })).toBeVisible();
	await page.goBack();
	await expect(page.getByRole('heading', { name: 'Synthetic saved workout' })).toHaveCount(0);
	expect(errors).toEqual([]);
});

test('invalid credentials, safe redirects and cross-tab logout', async ({ page, context }) => {
	const username = await register(page);
	await page.getByLabel('密码', { exact: true }).fill('incorrect-synthetic-password');
	await page.getByRole('button', { name: '登录', exact: true }).click();
	await expect(page.getByRole('alert')).toHaveText('用户名或密码不正确，请重试。');
	await page.goto('/login?next=https://example.invalid/steal');
	await login(page, username);
	await expect(page).toHaveURL(/\/workouts$/);
	const other = await context.newPage();
	await other.goto('/workouts');
	await expect(other.getByRole('button', { name: '退出登录', exact: true })).toBeVisible();
	await page.getByRole('button', { name: '退出登录', exact: true }).click();
	await expect(other.getByRole('button', { name: '登录', exact: true })).toBeVisible();
	await other.close();
});

test('a revoked session clears private data before another account signs in', async ({ page }) => {
	const first = await register(page);
	await login(page, first);
	await seedWorkout(page, 'Synthetic private first account');
	await page.reload();
	await expect(
		page.getByRole('heading', { name: 'Synthetic private first account' })
	).toBeVisible();
	await page.evaluate(async () => {
		const response = await fetch('/api/v1/auth/web/csrf');
		const { csrfToken }: { csrfToken: string } = await response.json();
		const logout = await fetch('/api/v1/auth/logout', {
			method: 'POST',
			headers: { 'X-CSRF-Token': csrfToken }
		});
		if (logout.status !== 204) throw new Error('Could not revoke synthetic session');
	});
	await page.getByRole('link', { name: /Synthetic private first account/ }).click();
	await expect(page.getByRole('button', { name: '登录', exact: true })).toBeVisible();
	await expect(page.getByRole('heading', { name: 'Synthetic private first account' })).toHaveCount(
		0
	);
	const second = await register(page);
	await login(page, second);
	await expect(page.getByRole('heading', { name: '还没有训练记录' })).toBeVisible();
	await expect(page.getByRole('heading', { name: 'Synthetic private first account' })).toHaveCount(
		0
	);
});

test('bootstrap network recovery and closed registration stay usable at narrow widths', async ({
	page,
	restartBackend
}) => {
	await restartBackend({ registrationOpen: false });
	await page.route('**/api/v1/me', (route) => route.abort('failed'), { times: 1 });
	await page.goto('/workouts');
	await expect(page.getByRole('heading', { name: '暂时无法加载' })).toBeVisible();
	await page.getByRole('button', { name: '重试', exact: true }).click();
	await expect(page.getByRole('button', { name: '登录', exact: true })).toBeVisible();
	await expect(page.getByText('当前仅开放已有账号登录。')).toBeVisible();
	await expect(page.getByRole('button', { name: '注册新账号' })).toHaveCount(0);
	await page.setViewportSize({ width: 320, height: 852 });
	expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});

test('failed login during initial restoration leaves a usable anonymous session', async ({
	page
}) => {
	let release: () => void = () => {};
	const held = new Promise<void>((resolve) => {
		release = resolve;
	});
	let restoring = false;
	await page.route(
		'**/api/v1/me',
		async (route) => {
			restoring = true;
			await held;
			await route.continue().catch(() => {});
		},
		{ times: 1 }
	);
	try {
		await page.goto('/login');
		await expect.poll(() => restoring).toBe(true);
		await page.getByLabel('用户名', { exact: true }).fill('missing_synthetic_user');
		await page.getByLabel('密码', { exact: true }).fill('incorrect-synthetic-password');
		await page.getByRole('button', { name: '登录', exact: true }).click();
		await expect(page.getByRole('alert')).toHaveText('用户名或密码不正确，请重试。');
		page.once('dialog', (dialog) => dialog.accept());
		await page.getByRole('link', { name: '训练', exact: true }).click();
		await expect(page).toHaveURL(/\/login\?next=/);
		await expect(page.getByRole('button', { name: '登录', exact: true })).toBeVisible();
	} finally {
		release();
	}
});
