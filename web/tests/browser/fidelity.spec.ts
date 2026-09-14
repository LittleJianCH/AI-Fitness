import { test, expect } from '@playwright/test';
const ride = '00000000-0000-4000-8000-000000000001';
test('D fidelity: linked tooltip, zoom, themes and detail dialogs', async ({ page }, info) => {
	await page.goto(`/workouts/${ride}`);
	await expect(page.locator('.metric-open')).toHaveCount(5);
	await page.getByLabel('外观主题').selectOption('dark');
	const slider = page.getByRole('slider', { name: '选择时间点', exact: true });
	await slider.focus();
	await slider.press('End');
	await slider.press('ArrowLeft');
	const selectedIndex = await slider.inputValue();
	await expect(page.getByRole('button', { name: '解除固定', exact: true })).toBeVisible();

	const assertAlignment = async () => {
		await expect
			.poll(() =>
				page.evaluate(() => {
					const guide = document.querySelector('.linked-guide')?.getBoundingClientRect();
					const dots = [...document.querySelectorAll('.linked-plots .time-chart svg')].map((svg) =>
						svg.querySelector('path[transform^="matrix"]')
					);
					if (!guide || dots.length !== 5 || dots.some((dot) => !dot)) return Infinity;
					return Math.max(
						...dots.map((dot) => {
							if (!dot) return Infinity;
							const box = dot.getBoundingClientRect();
							return Math.abs(box.x + box.width / 2 - guide.x);
						})
					);
				})
			)
			.toBeLessThan(1);
	};
	await assertAlignment();
	await page.getByRole('button', { name: '放大时间范围' }).click();
	await assertAlignment();
	await page.getByRole('button', { name: '全程', exact: true }).click();
	await page.screenshot({
		path: `test-results/fidelity/${info.project.name}-dark.png`,
		fullPage: true
	});
	await page.getByRole('button', { name: '放大轨迹地图', exact: true }).click();
	await expect(page.getByRole('dialog', { name: '轨迹详情' })).toBeVisible();
	await page.screenshot({
		path: `test-results/fidelity/${info.project.name}-route.png`,
		fullPage: true
	});
	await page.getByRole('button', { name: '关闭详情', exact: true }).click();
	await page.getByRole('button', { name: '放大心率图表', exact: true }).click();
	await expect(page.getByRole('dialog', { name: '心率详情' })).toBeVisible();
	await page.screenshot({
		path: `test-results/fidelity/${info.project.name}-metric.png`,
		fullPage: true
	});
	await page.keyboard.press('Escape');
	await expect(slider).toHaveValue(selectedIndex);
	await page.getByLabel('外观主题').selectOption('light');
	await page.screenshot({
		path: `test-results/fidelity/${info.project.name}-light.png`,
		fullPage: true
	});
});
