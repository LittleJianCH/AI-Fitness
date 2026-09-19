import { randomUUID } from 'node:crypto';
import { expect, type Page } from '@playwright/test';
import { test } from './fixtures';
import { login, register } from './helpers';
import { buildManualWorkout } from '../../src/lib/workouts/manual';
import {
	getWorkoutsWorkoutIdAnalysis200Response,
	getSettings200Response
} from '../../src/lib/api/generated/schemas';

async function seed(
	page: Page,
	sport: 'cycling' | 'running',
	summaryOnly = false,
	withDistance = true
) {
	const input = buildManualWorkout(
		{
			sport,
			start: '2026-01-15T08:00:00',
			minutes: 20,
			seconds: 0,
			distanceKm: 6,
			title: 'Synthetic analysis',
			notes: 'Synthetic only',
			tags: []
		},
		randomUUID()
	);
	const activity = input.observation.observationSport;
	const motion =
		activity.type === 'cycling' ? activity.data.cyclingMotion : activity.data.runningMotion;
	const start = Date.parse(input.observation.observationRange.rangeStart);
	const samples = (value: (i: number) => number) =>
		Array.from({ length: 1201 }, (_, i) => ({
			timestamp: new Date(start + i * 1000).toISOString(),
			value: value(i)
		}));
	if (!summaryOnly) {
		motion.motionHeartRate = samples((i) => 140 + i / 120);
		motion.motionPower = samples((i) => 200 + i / 60);
		motion.motionSpeed = samples(() => 5);
		motion.motionDistance = withDistance ? samples((i) => i * 5) : [];
		motion.motionAltitude = samples((i) => 50 + i / 100);
		motion.motionGrade = samples(() => 1);
		motion.motionEnvironment.ambientTemperature = samples(() => 20);
		if (activity.type === 'running') {
			activity.data.runningCadence = samples(() => 180);
			activity.data.runningDynamics.stepLength = samples((i) => (i === 0 ? 0.45 : 1.5));
			activity.data.runningDynamics.verticalOscillation = samples(() => 0.09);
			activity.data.runningDynamics.groundContactTime = samples(() => 0.2);
		} else activity.data.cyclingCadence = samples(() => 90);
	} else if (activity.type === 'running') {
		const summary = activity.data.runningSummary.recordedSummary;
		summary.summaryStepLength = { averageValue: 0.45, maximumValue: 1.5 };
		summary.summaryVerticalOscillation = { averageValue: 0.09 };
		summary.summaryGroundContactTime = { maximumValue: 0.2 };
	}
	return page.evaluate(async (input) => {
		const csrf = await (await fetch('/api/v1/auth/web/csrf')).json();
		const response = await fetch('/api/v1/workouts', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf.csrfToken },
			body: JSON.stringify(input)
		});
		if (response.status !== 200) throw new Error(`Synthetic fixture rejected: ${response.status}`);
		return (await response.json()).workoutId as string;
	}, input);
}
async function profile(page: Page, effective: string, threshold: string, mass: string) {
	await page.goto('/settings');
	await page.getByRole('button', { name: '更新个人参数', exact: true }).click();
	await page.getByLabel('生效时间（本地）').fill(effective);
	await page.getByLabel('体重 (kg)', { exact: true }).fill(mass);
	for (const sport of ['骑行', '跑步']) {
		await page.getByLabel(`${sport}阈值功率 (W)`).fill('250');
		await page.getByLabel(`配置${sport}心率参数`).check();
		await page.getByLabel(`${sport}静息心率 (bpm)`).fill('60');
		await page.getByLabel(`${sport}阈值心率 (bpm)`).fill(threshold);
		await page.getByLabel(`${sport}最大心率 (bpm)`).fill('190');
	}
	await page.getByRole('button', { name: '保存设置', exact: true }).click();
	await expect(page.getByText('设置已保存到当前账号。')).toBeVisible();
	await page.reload();
	await expect(page.getByRole('button', { name: '更新个人参数', exact: true })).toBeVisible();
}
for (const sport of ['cycling', 'running'] as const) {
	test(`${sport} real analysis follows saved effective profiles, metric details and splits`, async ({
		page
	}) => {
		await login(page, await register(page));
		const id = await seed(page, sport);
		const read = async () =>
			getWorkoutsWorkoutIdAnalysis200Response.parse(
				await (await page.request.get(`/api/v1/workouts/${id}/analysis`)).json()
			);
		expect((await read()).analysisHeart.heartLoadStatus).toBe('heartProfileMissing');
		await profile(page, '2026-01-01T00:00', '165', '72');
		const first = await read();
		expect(first.analysisHeart.heartLoadStatus).toBe('heartLoadAvailable');
		expect(first.analysisHeart.heartHrss).toBeGreaterThan(0);
		expect(first.analysisPower.powerAthleteKilograms).toBe(72);
		expect(first.analysisBodyProfile?.bodyMassKilograms).toBe(72);
		await page.goto(`/workouts/${id}`);
		await expect(page.getByRole('region', { name: '心率与训练负荷' })).toContainText(
			'采样覆盖满足要求'
		);
		await expect(page.getByRole('region', { name: '距离分段表' }).locator('tbody tr')).toHaveCount(
			6
		);
		await page.getByLabel('分段长度').selectOption('5000');
		await expect(page.getByRole('region', { name: '距离分段表' }).locator('tbody tr')).toHaveCount(
			2
		);
		await expect(page.getByRole('button', { name: '放大坡度图表' })).toBeVisible();
		await expect(page.getByRole('button', { name: '放大温度图表' })).toBeVisible();
		if (sport === 'running')
			await expect(page.getByRole('region', { name: '跑姿' })).toContainText('3,600');
		await page.getByRole('button', { name: '放大功率图表' }).click();
		const dialog = page.getByRole('dialog');
		await expect(dialog.getByRole('heading', { name: '统计与分布', exact: true })).toBeVisible();
		await expect(dialog.getByRole('heading', { name: '相关分析', exact: true })).toBeVisible();
		await expect(dialog.getByRole('region', { name: '指标统计与分布' })).toContainText('210 W');
		await dialog.getByLabel('图表横轴').selectOption('distance');
		await expect(dialog.getByRole('heading', { name: '功率距离曲线' })).toBeVisible();
		await dialog.getByLabel('选择真实样本').fill('600');
		await expect(dialog.locator('.sample-value')).toContainText('3.00 km');
		await expect(dialog.locator('.sample-value')).toContainText('210 W');
		await dialog.getByRole('button', { name: '下一个样本' }).click();
		await expect(dialog.locator('.sample-value')).toContainText('3.00 km');
		await page.keyboard.press('Escape');
		await page.goto(`/workouts/${id}/metrics/temperature`);
		await expect(page.getByRole('heading', { level: 1, name: '温度分析' })).toBeVisible();
		await expect(page.getByRole('region', { name: '指标统计与分布' })).toContainText('20 °C');
		await page.getByLabel('图表横轴').selectOption('distance');
		await expect(page.getByRole('heading', { name: '温度距离曲线' })).toBeVisible();
		await page.getByLabel('选择真实样本').fill('1200');
		await expect(page.locator('.sample-value')).toContainText('6.00 km');
		await page.getByLabel('图表横轴').selectOption('time');
		await expect(page.getByRole('heading', { name: '温度时间曲线' })).toBeVisible();
		await profile(page, '2026-01-10T00:00', '150', '76');
		const settings = getSettings200Response.parse(
			await (await page.request.get('/api/v1/settings')).json()
		);
		const second = await read();
		expect(second.analysisSettingsRevision).toBe(settings.settingsRevision);
		expect(second.analysisBodyProfile?.bodyProfileId).toBe(
			settings.settingsBodyProfiles[1].bodyProfileId
		);
		expect(second.analysisHeart.heartHrss).toBeGreaterThan(
			first.analysisHeart.heartHrss ?? Infinity
		);
		expect(second.analysisPower.powerWattsPerKilogram).toBeLessThan(
			first.analysisPower.powerWattsPerKilogram ?? 0
		);
		await page.goto(`/workouts/${id}`);
		await expect(page.getByRole('region', { name: '功率分析' })).toContainText('76 kg');
		await page.setViewportSize({ width: 320, height: 852 });
		await expect
			.poll(() => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth))
			.toBe(true);
	});
}

test('distance axis explains missing samples and preserves the raw time chart when analysis fails', async ({
	page
}) => {
	await login(page, await register(page));
	const id = await seed(page, 'cycling', false, false);
	await page.route(`**/api/v1/workouts/${id}/analysis`, (route) => route.abort());
	await page.goto(`/workouts/${id}/metrics/power`);
	await page.getByLabel('图表横轴').selectOption('distance');
	await expect(page.getByText('没有可对齐的距离采样，请切换时间轴查看原始曲线。')).toBeVisible();
	await expect(page.locator('.sample-value')).toContainText('距离未记录');
	await page.getByLabel('图表横轴').selectOption('time');
	await expect(page.getByRole('heading', { name: '功率时间曲线' })).toBeVisible();
	await expect(page.locator('.time-chart svg')).toBeVisible();
	await page.getByRole('button', { name: '下一个样本' }).click();
	await expect(page.locator('.sample-value')).toContainText('00:00:01');
});

test('history distinguishes unknown from confirmed rest and explicit prior load', async ({
	page
}) => {
	await login(page, await register(page));
	await page.addInitScript(() => {
		Object.defineProperty(AbortSignal, 'any', { configurable: true, value: undefined });
	});
	await page.goto('/training-history');
	await page.getByLabel('开始日期', { exact: true }).fill('2026-01-01');
	await page.getByLabel('结束日期', { exact: true }).fill('2026-01-03');
	await page.getByLabel('开始前的训练负荷').selectOption('zero');
	await page.getByRole('button', { name: '计算训练历史', exact: true }).click();
	const table = page.getByRole('region', { name: '训练历史表' });
	await expect(table.locator('tbody tr')).toHaveCount(3);
	await expect(table.locator('tbody tr').first()).toContainText('未知');
	await page.getByLabel('确认所选日期全部记录完整').check();
	await page.getByRole('button', { name: '计算训练历史', exact: true }).click();
	await expect(table).not.toContainText('未知');
	await expect(table.locator('tbody tr').first().locator('td').nth(5)).toHaveText('0');
	await page.getByLabel('开始前的训练负荷').selectOption('known');
	await page.getByLabel('初始 CTL', { exact: true }).fill('42');
	await page.getByLabel('初始 ATL', { exact: true }).fill('7');
	await page.getByRole('button', { name: '计算训练历史', exact: true }).click();
	await expect(table.locator('tbody tr').first().locator('td').nth(5)).not.toHaveText('0');
	await page.setViewportSize({ width: 320, height: 852 });
	await expect
		.poll(() => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth))
		.toBe(true);
});

test('analysis failures and revision mismatch preserve the original workout controls', async ({
	page
}) => {
	await login(page, await register(page));
	const id = await seed(page, 'cycling');
	await page.route(`**/api/v1/workouts/${id}/analysis`, (route) => route.abort());
	await page.goto(`/workouts/${id}`);
	await expect(page.getByRole('alert')).toContainText('连接失败');
	await expect(page.getByLabel('选择时间点')).toBeVisible();
	await page.unroute(`**/api/v1/workouts/${id}/analysis`);
	await page.route(`**/api/v1/workouts/${id}/analysis`, async (route) => {
		const response = await route.fetch();
		const actual = getWorkoutsWorkoutIdAnalysis200Response.parse(await response.json());
		await route.fulfill({ response, json: { ...actual, analysisRevision: '999999' } });
	});
	await page.getByRole('button', { name: '重试', exact: true }).click();
	await expect(page.getByRole('alert')).toContainText('训练已更新');
	await expect(page.getByRole('region', { name: '功率分析' })).toHaveCount(0);
	await page.unroute(`**/api/v1/workouts/${id}/analysis`);
	await page.getByRole('button', { name: '重试', exact: true }).click();
	await expect(page.getByRole('region', { name: '功率分析' })).toBeVisible();
	await expect(page.getByRole('alert')).toHaveCount(0);
});

test('step length keeps decimals in overview, timepoint, metric summary and analysis statistics', async ({
	page
}) => {
	await login(page, await register(page));
	const id = await seed(page, 'running');
	await page.goto(`/workouts/${id}`);
	await page.getByRole('button', { name: '固定时间点', exact: true }).click();
	const preview = page.getByRole('button', { name: '放大步长图表' });
	await expect(preview).toContainText('1.50 m ·计算平均');
	await expect(preview).toContainText('此刻 0.45 m');
	const timepoint = page
		.locator('.accessible-details')
		.locator('dl > div')
		.filter({ has: page.locator('dt', { hasText: '步长' }) });
	await expect(timepoint.locator('dd')).toHaveText('0.45m');
	await preview.click();
	const dialog = page.getByRole('dialog');
	await expect(dialog.locator('.summary-strip')).toContainText('1.50m');
	await expect(dialog.locator('.sample-value')).toContainText('0.45 m');
	await expect(dialog.getByLabel('选择真实样本')).toHaveAttribute('aria-valuetext', /0.45 m/);
	const statistics = dialog.getByRole('region', { name: '指标统计与分布' });
	await expect(statistics.locator('dl > div').filter({ hasText: '最大' })).toContainText('1.50 m');
	await expect(statistics.locator('dl > div').filter({ hasText: '最小' })).toContainText('0.45 m');
	await dialog.getByRole('button', { name: '下一个样本' }).click();
	await expect(dialog.locator('.sample-value')).toContainText('1.50 m');
	await dialog.getByText('查看样本数据表', { exact: true }).click();
	await expect(
		dialog.getByRole('region', { name: '指标样本表' }).locator('tbody tr').first()
	).toContainText('0.45');
	await page.keyboard.press('Escape');
	await page.goto(`/workouts/${id}/metrics/step-length`);
	await expect(page.getByRole('heading', { level: 1, name: '步长分析' })).toBeVisible();
	await expect(page.locator('.summary-strip')).toContainText('1.50m');
	await expect(page.locator('.sample-value')).toContainText('0.45 m');
});

test('summary-only running dynamics retain overview, modal and direct routes with recorded provenance', async ({
	page
}) => {
	await login(page, await register(page));
	const id = await seed(page, 'running', true);
	await page.goto(`/workouts/${id}`);
	for (const [key, title, summary] of [
		['step-length', '步长', '0.45 m ·记录平均'],
		['vertical-oscillation', '垂直振幅', '9 cm ·记录平均'],
		['ground-contact-time', '触地时间', '200 ms ·记录最大']
	]) {
		const preview = page.getByRole('button', { name: `放大${title}图表` });
		await expect(preview).toContainText(summary);
		await expect(preview).toContainText('仅记录汇总 · 无逐点曲线');
		await preview.click();
		const dialog = page.getByRole('dialog');
		await expect(dialog.getByRole('heading', { name: '这次训练仅包含汇总数据' })).toBeVisible();
		await expect(dialog.locator('.summary-strip')).not.toContainText('计算');
		await dialog.getByRole('link', { name: '独立页面查看' }).click();
		await expect(page).toHaveURL(new RegExp(`/metrics/${key}$`));
		await expect(page.getByRole('heading', { level: 1, name: `${title}分析` })).toBeVisible();
		await expect(page.getByRole('heading', { name: '这次训练仅包含汇总数据' })).toBeVisible();
		await expect(page.locator('.summary-strip')).not.toContainText('计算');
		if (key === 'step-length') {
			await expect(page.locator('.summary-strip')).toContainText('0.45m');
			await expect(page.locator('.summary-strip')).toContainText('1.50m');
		}
		await page.goto(`/workouts/${id}`);
	}
});
