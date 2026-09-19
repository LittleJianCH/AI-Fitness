import { expect } from '@playwright/test';
import { test } from './fixtures';
import { register, login } from './helpers';
import { getSettings200Response } from '../../src/lib/api/generated/schemas';

test('body history, appearance and equipment persist across restart with stale revision protection', async ({
	page,
	restartBackend
}) => {
	await login(page, await register(page));
	await page.goto('/settings');
	await page.getByRole('button', { name: '更新个人参数', exact: true }).click();
	await page.getByLabel('生效时间（本地）').fill('2026-01-01T00:00');
	await page.getByLabel('体重 (kg)', { exact: true }).fill('72');
	await page.getByLabel('骑行阈值功率 (W)').fill('250');
	await page.getByLabel('配置骑行心率参数').check();
	await page.getByLabel('骑行静息心率 (bpm)').fill('55');
	await page.getByLabel('骑行阈值心率 (bpm)').fill('165');
	await page.getByLabel('骑行最大心率 (bpm)').fill('190');
	await page.getByLabel('骑行TRIMP 指数').selectOption('exponent167');
	await page.getByLabel('账号外观').selectOption('darkAppearance');
	await page.getByRole('button', { name: '添加器材', exact: true }).click();
	await page.getByLabel('器材名称').fill('Synthetic bike');
	await page.getByRole('button', { name: '保存设置', exact: true }).click();
	await expect(page.getByText('设置已保存到当前账号。')).toBeVisible();
	const first = getSettings200Response.parse(
		await (await page.request.get('/api/v1/settings')).json()
	);
	expect(first.settingsBodyProfiles).toHaveLength(1);
	expect(first.settingsBodyProfiles[0].bodyMassKilograms).toBe(72);
	expect(first.settingsBodyProfiles[0].bodyCycling.sportHeartRate?.heartRateWeighting).toBe(
		'exponent167'
	);
	expect(first.settingsEquipment[0].equipmentName).toBe('Synthetic bike');
	await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
	await restartBackend();
	await page.reload();
	await expect(
		page.getByRole('button', { name: 'Synthetic bike · 自行车', exact: true })
	).toBeVisible();
	await page.getByRole('button', { name: 'Synthetic bike · 自行车', exact: true }).click();
	await page.getByLabel('器材名称').fill('Synthetic retired bike');
	await page.getByLabel('停用器材').check();
	await page.getByRole('button', { name: '保存设置', exact: true }).click();
	await expect(page.getByText('设置已保存到当前账号。')).toBeVisible();
	await page.getByRole('button', { name: '更新个人参数', exact: true }).click();
	await page.getByLabel('生效时间（本地）').fill('2026-02-01T00:00');
	await page.getByLabel('体重 (kg)', { exact: true }).fill('73');
	await page.getByRole('button', { name: '保存设置', exact: true }).click();
	await expect(page.getByText('设置已保存到当前账号。')).toBeVisible();
	const second = getSettings200Response.parse(
		await (await page.request.get('/api/v1/settings')).json()
	);
	expect(second.settingsBodyProfiles).toHaveLength(2);
	expect(second.settingsBodyProfiles[0]).toEqual(first.settingsBodyProfiles[0]);
	expect(second.settingsEquipment[0].equipmentRetired).toBe(true);
	// A second authenticated write advances the actual stored revision behind this editor.
	expect(
		await page.evaluate(async () => {
			const csrf = await (await fetch('/api/v1/auth/web/csrf')).json();
			const current = await (await fetch('/api/v1/settings')).json();
			return (
				await fetch('/api/v1/settings', {
					method: 'PUT',
					headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf.csrfToken },
					body: JSON.stringify(current)
				})
			).status;
		})
	).toBe(200);
	await page.getByLabel('账号外观').selectOption('lightAppearance');
	await page.getByRole('button', { name: '保存设置', exact: true }).click();
	await expect(page.getByRole('alert')).toContainText('设置已被其他会话更新');
	await expect(page.getByRole('button', { name: '保存设置', exact: true })).toBeDisabled();
	page.once('dialog', (dialog) => dialog.accept());
	await page.getByRole('button', { name: '重新加载设置', exact: true }).click();
	await expect(page.getByRole('alert')).toHaveCount(0);
	await page.getByRole('button', { name: '退出登录', exact: true }).click();
	await login(page, await register(page));
	await page.goto('/settings');
	await expect(page.getByText('尚未配置身体参数。')).toBeVisible();
	await expect(page.getByText('尚未添加器材。')).toBeVisible();
	await page.setViewportSize({ width: 320, height: 852 });
	expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});
