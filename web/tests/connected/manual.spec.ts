import { expect, type Page } from '@playwright/test';
import { test } from './fixtures';
import { register, login, newUsername, password } from './helpers';
async function fillWorkout(page: Page, title: string, sport = 'cycling') {
	await page.getByRole('link', { name: '手动录入', exact: true }).click();
	await expect(page.getByRole('heading', { name: '记录一次训练', exact: true })).toBeVisible();
	await page.getByRole('combobox', { name: '运动类型', exact: true }).selectOption(sport);
	await page.getByLabel('标题（可选）', { exact: true }).fill(title);
	await page.getByLabel('开始时间', { exact: true }).fill('2026-09-11T09:00');
	await page.getByLabel('经过时长（分钟）', { exact: true }).fill('30');
	await page.getByLabel('秒（可选）', { exact: true }).fill('15');
}
test('manual cycling and running records preserve summary-only and optional-distance semantics', async ({
	page
}) => {
	const username = await register(page);
	await login(page, username);
	await fillWorkout(page, 'Synthetic manual ride');
	await page.getByLabel('备注（可选）', { exact: true }).fill('Synthetic notes');
	await page.screenshot({ path: test.info().outputPath('manual-form.png'), fullPage: true });
	await page.getByLabel('添加标签', { exact: true }).fill('手动');
	await page
		.getByLabel('添加标签', { exact: true })
		.dispatchEvent('keydown', { key: 'Enter', isComposing: true });
	await expect(page.getByLabel('添加标签', { exact: true })).toHaveValue('手动');
	await expect(page.getByRole('list', { name: '已选标签' })).toHaveCount(0);
	await page.getByLabel('添加标签', { exact: true }).press('Enter');
	await expect(page.getByRole('list', { name: '已选标签' })).toContainText('手动');
	await page.getByLabel('添加标签', { exact: true }).fill('manual');
	await page.getByRole('button', { name: '保存训练', exact: true }).click();
	await expect(
		page.getByRole('heading', { level: 1, name: 'Synthetic manual ride' })
	).toBeVisible();
	await expect(
		page.getByText('这条训练缺少逐点采样，暂时无法计算指标平均值或最大值。')
	).toBeVisible();
	await expect(page.getByText('Synthetic notes', { exact: true })).toBeVisible();
	await expect(page.getByText('manual', { exact: true })).toBeVisible();
	await expect(page.locator('.summary-number').first()).toContainText('未记录');
	await expect(page.locator('.summary-number').nth(1)).toContainText('00:30:15');
	await page
		.getByRole('navigation', { name: '面包屑' })
		.getByRole('link', { name: '训练', exact: true })
		.click();
	await fillWorkout(page, 'Synthetic zero-distance run', 'running');
	await page.getByLabel('距离（km，可选）', { exact: true }).fill('0');
	await page.getByRole('button', { name: '保存训练', exact: true }).click();
	await expect(
		page.getByRole('heading', { level: 1, name: 'Synthetic zero-distance run' })
	).toBeVisible();
	await expect(page.locator('.summary-number').first()).toHaveText(/^0\s*km$/);
	await page.reload();
	await expect(
		page.getByRole('heading', { level: 1, name: 'Synthetic zero-distance run' })
	).toBeVisible();
});

test('retry after a lost success response reuses the same submission without duplicates', async ({
	page
}) => {
	const username = await register(page);
	await login(page, username);
	const bodies: string[] = [];
	await page.route('**/api/v1/workouts', async (route) => {
		if (route.request().method() !== 'POST') return route.continue();
		bodies.push(route.request().postData() ?? '');
		if (bodies.length === 1) {
			const response = await route.fetch();
			expect(response.status()).toBe(200);
			await route.abort('failed');
		} else await route.continue();
	});
	await fillWorkout(page, 'Synthetic retry once');
	await page.getByLabel('距离（km，可选）', { exact: true }).fill('12.345');
	await page.getByRole('button', { name: '保存训练', exact: true }).click();
	await expect(page.getByRole('button', { name: '重试保存', exact: true })).toBeVisible();
	await expect(page.getByLabel('标题（可选）', { exact: true })).toBeDisabled();
	await page.getByRole('button', { name: '重试保存', exact: true }).click();
	await expect(page.getByRole('heading', { level: 1, name: 'Synthetic retry once' })).toBeVisible();
	expect(bodies).toHaveLength(2);
	expect(bodies[0]).toBe(bodies[1]);
	await page
		.getByRole('navigation', { name: '面包屑' })
		.getByRole('link', { name: '训练', exact: true })
		.click();
	await expect(page.getByRole('heading', { name: 'Synthetic retry once' })).toHaveCount(1);
});

test('unsaved manual drafts can cancel navigation and remain usable on a narrow viewport', async ({
	page
}) => {
	const username = await register(page);
	await login(page, username);
	await fillWorkout(page, 'Synthetic unsaved draft');
	await page.setViewportSize({ width: 320, height: 852 });
	expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
	const dismissed = page.waitForEvent('dialog').then((dialog) => dialog.dismiss());
	await page.getByRole('link', { name: '返回训练', exact: true }).click();
	await dismissed;
	await expect(page.getByLabel('标题（可选）', { exact: true })).toHaveValue(
		'Synthetic unsaved draft'
	);
	const accepted = page.waitForEvent('dialog').then((dialog) => dialog.accept());
	await page.getByRole('link', { name: '返回训练', exact: true }).click();
	await accepted;
	await expect(page.getByRole('heading', { name: '还没有训练记录' })).toBeVisible();
});

test('a late successful save refreshes the list without taking over navigation', async ({
	page
}) => {
	const username = await register(page);
	await login(page, username);
	let published = false;
	let release: () => void = () => {};
	const held = new Promise<void>((resolve) => {
		release = resolve;
	});
	await page.route('**/api/v1/workouts', async (route) => {
		if (route.request().method() !== 'POST') return route.continue();
		const response = await route.fetch();
		expect(response.status()).toBe(200);
		published = true;
		await held;
		await route.fulfill({ response }).catch(() => {});
	});
	try {
		await fillWorkout(page, 'Synthetic delayed save');
		await page.getByRole('button', { name: '保存训练', exact: true }).click();
		await expect.poll(() => published).toBe(true);
		const accepted = page.waitForEvent('dialog').then((dialog) => dialog.accept());
		await page.getByRole('link', { name: '返回训练', exact: true }).click();
		await accepted;
		await expect(page).toHaveURL(/\/workouts$/);
		release();
		await expect(
			page.getByRole('heading', { level: 3, name: 'Synthetic delayed save' })
		).toBeVisible();
		await expect(page).toHaveURL(/\/workouts$/);
	} finally {
		release();
	}
});

test('a changed account cookie cannot publish the previous account draft', async ({ page }) => {
	const first = await register(page);
	await login(page, first);
	await fillWorkout(page, 'Synthetic previous account draft');
	const second = newUsername();
	await page.evaluate(
		async ({ username, password }) => {
			const csrf = await (await fetch('/api/v1/auth/web/csrf')).json();
			const headers = { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf.csrfToken };
			const registration = await fetch('/api/v1/auth/register', {
				method: 'POST',
				headers,
				body: JSON.stringify({ username, password })
			});
			if (registration.status !== 201) throw new Error('Synthetic registration failed');
			const login = await fetch('/api/v1/auth/web/login', {
				method: 'POST',
				headers,
				body: JSON.stringify({ username, password })
			});
			if (login.status !== 200) throw new Error('Synthetic account switch failed');
		},
		{ username: second, password }
	);
	await page.getByRole('button', { name: '保存训练', exact: true }).click();
	await expect(page.getByText(second, { exact: true })).toBeVisible();
	await expect(page.getByLabel('标题（可选）', { exact: true })).toHaveValue('');
	await page.getByRole('link', { name: '返回训练', exact: true }).click();
	await expect(page.getByRole('heading', { name: '还没有训练记录' })).toBeVisible();
});

test('an uncertain submission keeps its identity through same-account CSRF recovery', async ({
	page
}) => {
	const username = await register(page);
	await login(page, username);
	const bodies: string[] = [];
	await page.route('**/api/v1/workouts', async (route) => {
		if (route.request().method() !== 'POST') return route.continue();
		bodies.push(route.request().postData() ?? '');
		if (bodies.length === 1) {
			const response = await route.fetch();
			expect(response.status()).toBe(200);
			await route.abort('failed');
		} else await route.continue();
	});
	await fillWorkout(page, 'Synthetic recovered retry');
	await page.getByRole('button', { name: '保存训练', exact: true }).click();
	await expect(page.getByRole('button', { name: '重试保存', exact: true })).toBeVisible();
	await page.evaluate(
		async ({ username, password }) => {
			const csrf = await (await fetch('/api/v1/auth/web/csrf')).json();
			const result = await fetch('/api/v1/auth/web/login', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf.csrfToken },
				body: JSON.stringify({ username, password })
			});
			if (result.status !== 200) throw new Error('Synthetic session rotation failed');
		},
		{ username, password }
	);
	await page.getByRole('button', { name: '重试保存', exact: true }).click();
	await expect(page.getByRole('alert')).toContainText('会话校验未通过');
	await expect(page.getByLabel('标题（可选）', { exact: true })).toBeDisabled();
	await page.getByRole('button', { name: '重试保存', exact: true }).click();
	await expect(
		page.getByRole('heading', { level: 1, name: 'Synthetic recovered retry' })
	).toBeVisible();
	expect(bodies).toHaveLength(3);
	expect(new Set(bodies).size).toBe(1);
	await page
		.getByRole('navigation', { name: '面包屑' })
		.getByRole('link', { name: '训练', exact: true })
		.click();
	await expect(page.getByRole('heading', { name: 'Synthetic recovered retry' })).toHaveCount(1);
});
