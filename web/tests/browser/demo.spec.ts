import { test as base, expect } from '@playwright/test';
const test = base.extend<{ consoleErrors: string[] }>({
	consoleErrors: [
		async ({ page }, use) => {
			const errors: string[] = [];
			page.on('pageerror', (error) => errors.push(error.message));
			await page.exposeFunction('recordWindowError', (message: string) => errors.push(message));
			await page.addInitScript(() => {
				window.addEventListener('error', (event) => {
					(
						window as unknown as Window & { recordWindowError: (message: string) => void }
					).recordWindowError(event.message);
				});
			});
			await use(errors);
			expect(errors).toEqual([]);
		},
		{ auto: true }
	]
});
const ride = '00000000-0000-4000-8000-000000000001';
const indoor = '00000000-0000-4000-8000-000000000003';
const noHr = '00000000-0000-4000-8000-000000000004';

test('list, sport filters, cursor pagination and browser back', async ({ page }) => {
	await page.goto('/workouts');
	await expect(page.getByRole('heading', { name: '周末环湖 · 耐力骑行' })).toBeVisible();
	await page.getByRole('button', { name: '加载更多训练' }).click();
	await expect(page.getByRole('heading', { name: '午后慢跑 · 无心率' })).toBeVisible();
	await page.getByRole('button', { name: '跑步', exact: true }).click();
	await expect(page.getByRole('heading', { name: '周末环湖 · 耐力骑行' })).toHaveCount(0);
	await page.getByRole('link', { name: /清晨轻松跑/ }).focus();
	await page.getByRole('link', { name: /清晨轻松跑/ }).press('Enter');
	await expect(
		page.getByRole('heading', { name: '清晨轻松跑', exact: true, level: 1 })
	).toBeVisible();
	await page.goBack();
	await expect(page.getByRole('button', { name: '跑步', exact: true })).toHaveAttribute(
		'aria-pressed',
		'true'
	);
	await expect(page.getByRole('heading', { name: '清晨轻松跑' })).toBeVisible();
	await expect(page.getByRole('link', { name: /清晨轻松跑/ })).toBeFocused();
});

test('metric navigation, keyboard samples, table and route selection', async ({ page }) => {
	const errors: string[] = [];
	page.on('pageerror', (e) => errors.push(e.message));
	await page.goto(`/workouts/${ride}`);
	await page.getByRole('link', { name: /心率.*记录平均/ }).click();
	await expect(page.getByRole('heading', { name: '心率分析', exact: true })).toBeVisible();
	const slider = page.getByRole('slider', { name: /选择真实样本/ });
	await slider.focus();
	await slider.press('ArrowRight');
	await expect(slider).toHaveValue('1');
	await expect(slider).toHaveAttribute('aria-valuetext', /00:00:30/);
	await page.getByRole('button', { name: '下一个样本' }).click();
	await expect(slider).toHaveValue('2');
	await page.getByText('查看样本数据表').click();
	await expect(page.getByRole('table')).toBeVisible();
	await page.reload();
	await expect(page.getByRole('heading', { name: '心率分析', exact: true })).toBeVisible();
	await page.getByRole('link', { name: '训练详情', exact: true }).click();
	await page.getByRole('link', { name: '查看完整轨迹' }).click();
	const route = page.getByRole('slider', { name: '选择轨迹样本' });
	await route.focus();
	await route.press('End');
	await expect(route).toHaveValue('180');
	await expect(page.getByText('经过时间：01:30:00')).toBeVisible();
	expect(errors).toEqual([]);
});

test('summary-only and unavailable metrics keep their meaning', async ({ page }) => {
	await page.goto(`/workouts/${indoor}`);
	await expect(page.getByRole('heading', { name: '室内骑行 · 仅汇总' })).toBeVisible();
	await expect(page.getByRole('link', { name: '查看完整轨迹' })).toHaveCount(0);
	await page.getByRole('link', { name: /功率.*记录平均/ }).click();
	await expect(page.getByRole('heading', { name: '这次训练仅包含汇总数据' })).toBeVisible();
	await expect(page.getByRole('slider')).toHaveCount(0);
	await page.goto(`/workouts/${noHr}`);
	await expect(page.getByRole('heading', { name: '午后慢跑 · 无心率' })).toBeVisible();
	await expect(page.getByRole('link', { name: /心率.*记录平均/ })).toHaveCount(0);
	await page.getByRole('link', { name: /步频.*记录平均/ }).click();
	await expect(page.getByText('跑步步频使用双脚总步数（步/分钟）。')).toBeVisible();
	await page.goto(`/workouts/${noHr}/metrics/heart-rate`);
	await expect(page.getByRole('heading', { name: '这项指标没有可用数据' })).toBeVisible();
});

test('loading, empty, invalid response, missing and session errors', async ({ page }) => {
	await page.goto('/workouts?scenario=slow');
	await expect(page.getByRole('status')).toContainText('正在读取');
	await expect(page.getByRole('heading', { name: '周末环湖 · 耐力骑行' })).toBeVisible();
	await page.getByLabel('演示场景').selectOption('empty');
	await expect(page.getByRole('heading', { name: '还没有训练记录' })).toBeVisible();
	await page.getByLabel('演示场景').selectOption('invalid');
	await expect(page.getByRole('alert')).toContainText('收到的数据不符合接口约定');
	await page.getByLabel('演示场景').selectOption('unauthenticated');
	await expect(page.getByRole('alert')).toContainText('当前会话不可用');
	await page.getByLabel('演示场景').selectOption('normal');
	await expect(page.getByRole('heading', { name: '周末环湖 · 耐力骑行' })).toBeVisible();
	await page.goto('/workouts/not-an-id');
	await expect(page.getByRole('alert')).toContainText('没有找到');
});

test('retry recovers from one HTTP failure', async ({ page }) => {
	let attempts = 0;
	await page.route('**/api/v1/workouts?*', async (route) => {
		if (attempts++ === 0)
			await route.fulfill({
				status: 500,
				json: {
					code: 'internal_error',
					message: 'Synthetic failure',
					fields: [],
					requestId: 'test'
				}
			});
		else await route.continue();
	});
	await page.goto('/workouts');
	await expect(page.getByRole('alert')).toContainText('服务暂时无法完成请求');
	await page.getByRole('button', { name: '重试', exact: true }).click();
	await expect(page.getByRole('heading', { name: '周末环湖 · 耐力骑行' })).toBeVisible();
});

test('responsive grid and review screenshots', async ({ page }, info) => {
	await page.goto('/workouts');
	await expect(page.getByRole('heading', { name: '周末环湖 · 耐力骑行' })).toBeVisible();
	await page.screenshot({ path: `test-results/screenshots/${info.project.name}-list.png` });
	await page.goto(`/workouts/${ride}`);
	await expect(
		page.getByRole('heading', { name: '周末环湖 · 耐力骑行', exact: true })
	).toBeVisible();
	await expect(page.locator('.time-chart svg').first()).toBeVisible();
	const sizes =
		info.project.name === 'desktop' ? [1280, 1440, 1920] : [320, 375, 393, 430, 768, 1024];
	for (const width of sizes) {
		await page.setViewportSize({ width, height: info.project.name === 'desktop' ? 900 : 852 });
		await page.reload();
		await expect(page.locator('.time-chart svg').first()).toBeVisible();
		await expect
			.poll(async () =>
				page.evaluate((width) => document.documentElement.scrollWidth <= width, width)
			)
			.toBe(true);
		if (width === 1440) {
			await expect(page.locator('.overview-grid')).toHaveClass(/two-columns/);
			const chart = await page.locator('.metric-card').first().boundingBox();
			const map = await page.locator('.route-card').boundingBox();
			expect(chart && map && Math.abs(chart.y - map.y) < 2).toBeTruthy();
		}
		if (width <= 430) await expect(page.locator('.overview-grid')).not.toHaveClass(/two-columns/);
	}
	await page.setViewportSize({
		width: info.project.name === 'desktop' ? 1440 : 393,
		height: info.project.name === 'desktop' ? 900 : 852
	});
	await page.reload();
	await expect(page.locator('.time-chart svg').first()).toBeVisible();
	await expect.poll(() => page.evaluate(() => window.visualViewport?.scale)).toBe(1);
	await page.screenshot({ path: `test-results/screenshots/${info.project.name}-overview.png` });
	await page.getByRole('link', { name: /心率.*记录平均/ }).click();
	await expect(page.getByRole('heading', { name: '心率分析', exact: true })).toBeVisible();
	await expect(page.locator('.time-chart svg')).toBeVisible();
	await page.screenshot({ path: `test-results/screenshots/${info.project.name}-heart-rate.png` });
});

test('browser back restores metric and route focus without changing scroll', async ({ page }) => {
	await page.goto(`/workouts/${ride}`);
	const metric = page.getByRole('link', { name: /海拔.*记录/ });
	await metric.focus();
	const scroll = await page.evaluate(() => window.scrollY);
	await metric.press('Enter');
	await expect(page.getByRole('heading', { name: '海拔分析', exact: true })).toBeVisible();
	await page.goBack();
	await expect(metric).toBeFocused();
	await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(scroll);
	const route = page.getByRole('link', { name: '查看完整轨迹' });
	await route.focus();
	await route.press('Enter');
	await expect(
		page.getByRole('heading', { name: '沿着轨迹，再看一次', exact: true })
	).toBeVisible();
	await page.goBack();
	await expect(route).toBeFocused();
});

test('simulated 200 percent text keeps content within the viewport', async ({ page }) => {
	for (const path of ['/workouts', `/workouts/${ride}`, `/workouts/${ride}/metrics/heart-rate`]) {
		await page.goto(path);
		await expect(
			page.getByRole('heading', {
				name: path.endsWith('heart-rate') ? '心率分析' : '周末环湖 · 耐力骑行',
				exact: true
			})
		).toBeVisible();
		await page.evaluate(() => {
			const sizes = [...document.querySelectorAll('body, body *')]
				.filter((element): element is HTMLElement => element instanceof HTMLElement)
				.map((element) => ({
					element,
					font: parseFloat(getComputedStyle(element).fontSize),
					line: parseFloat(getComputedStyle(element).lineHeight)
				}));
			for (const { element, font, line } of sizes) {
				element.style.fontSize = `${font * 2}px`;
				if (Number.isFinite(line)) element.style.lineHeight = `${line * 2}px`;
			}
		});
		await expect
			.poll(() =>
				page.evaluate(
					(width) => document.documentElement.scrollWidth <= width,
					page.viewportSize()!.width
				)
			)
			.toBe(true);
	}
});

test('detail refresh then back reloads the visible list pages before restoring focus and scroll', async ({
	page
}) => {
	for (const name of ['室内骑行 · 仅汇总', '午后慢跑 · 无心率']) {
		await page.goto('/workouts');
		if (name === '午后慢跑 · 无心率')
			await page.getByRole('button', { name: '加载更多训练' }).click();
		const origin = page.getByRole('link', { name: new RegExp(name) });
		await origin.focus();
		const scroll = await page.evaluate(() => window.scrollY);
		await origin.press('Enter');
		await expect(page.getByRole('heading', { name, exact: true, level: 1 })).toBeVisible();
		await page.reload();
		await expect(page.getByRole('heading', { name, exact: true, level: 1 })).toBeVisible();
		await page.goBack();
		await expect(origin).toBeFocused();
		await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(scroll);
		if (name === '午后慢跑 · 无心率')
			await expect(page.getByText('已显示全部 4 条训练')).toBeVisible();
	}
});
