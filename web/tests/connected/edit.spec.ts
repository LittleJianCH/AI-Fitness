import { expect, type Page } from '@playwright/test';
import { test } from './fixtures';
import { register, login, seedWorkout } from './helpers';
import { getWorkoutsWorkoutId200Response } from '../../src/lib/api/generated/schemas';
import type { Workout, WorkoutUserData } from '../../src/lib/api/generated/client';
async function saved(page: Page, id: string): Promise<Workout> {
	return getWorkoutsWorkoutId200Response.parse(
		await page.evaluate(async (id) => {
			const response = await fetch(`/api/v1/workouts/${id}`);
			if (response.status !== 200) throw new Error('Synthetic workout read failed');
			return response.json();
		}, id)
	);
}
async function update(page: Page, workout: Workout, userData: WorkoutUserData) {
	return page.evaluate(
		async ({ id, revision, userData }) => {
			const csrf = await (await fetch('/api/v1/auth/web/csrf')).json();
			const response = await fetch(`/api/v1/workouts/${id}/user-data`, {
				method: 'PUT',
				headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf.csrfToken },
				body: JSON.stringify({ expectedRevision: revision, userData })
			});
			return response.status;
		},
		{ id: workout.workoutId, revision: workout.workoutRevision, userData }
	);
}
async function openEditor(page: Page, id: string) {
	await page.goto(`/workouts/${id}`);
	await page.getByRole('link', { name: '编辑训练', exact: true }).click();
	await expect(page.getByRole('heading', { name: '编辑训练', exact: true })).toBeVisible();
}
async function confirmClick(page: Page, button: string, accept = true) {
	const dialog = page
		.waitForEvent('dialog')
		.then((dialog) => (accept ? dialog.accept() : dialog.dismiss()));
	await page.getByRole('button', { name: button, exact: true }).click();
	await dialog;
}

test('metadata editing preserves observations and statistics policy with an unsaved tag removal', async ({
	page
}) => {
	const username = await register(page);
	await login(page, username);
	const id = await seedWorkout(page, 'Synthetic editable ride');
	const initial = await saved(page, id);
	expect(
		await update(page, initial, {
			...initial.workoutUserData,
			statisticsInclusion: 'excludeFromStatistics',
			workoutTags: ['keep me', 'remove me']
		})
	).toBe(200);
	const before = await saved(page, id);
	await openEditor(page, id);
	await page.getByRole('button', { name: '移除标签 remove me', exact: true }).click();
	const cancelled = page.waitForEvent('dialog').then((dialog) => dialog.dismiss());
	await page.getByRole('link', { name: '返回详情', exact: true }).click();
	await cancelled;
	await expect(page.getByRole('list', { name: '已选标签' })).toContainText('keep me');
	await page.getByLabel('标题（可选）', { exact: true }).fill('Synthetic edited title');
	await page.getByLabel('备注（可选）', { exact: true }).fill('Two lines\nSynthetic notes');
	await page.getByLabel('添加标签', { exact: true }).fill('new tag');
	await page.screenshot({ path: test.info().outputPath('edit-form.png'), fullPage: true });
	await page.getByRole('button', { name: '保存修改', exact: true }).click();
	await expect(
		page.getByRole('heading', { level: 1, name: 'Synthetic edited title' })
	).toBeVisible();
	const after = await saved(page, id);
	const beforeSport = before.workoutObservation.observationSport;
	const afterSport = after.workoutObservation.observationSport;
	if (beforeSport.type !== 'cycling' || afterSport.type !== 'cycling')
		throw new Error('Expected cycling fixture');
	expect(afterSport.data.cyclingSummary.calculatedSummary?.calculationInputRevision).toBe(
		after.workoutRevision
	);
	expect(afterSport.data.cyclingSummary.calculatedSummary?.calculationValue).toEqual(
		beforeSport.data.cyclingSummary.calculatedSummary?.calculationValue
	);
	const beforeSource = structuredClone(before.workoutObservation);
	const afterSource = structuredClone(after.workoutObservation);
	if (beforeSource.observationSport.type === 'cycling')
		delete beforeSource.observationSport.data.cyclingSummary.calculatedSummary;
	if (afterSource.observationSport.type === 'cycling')
		delete afterSource.observationSport.data.cyclingSummary.calculatedSummary;
	expect(afterSource).toEqual(beforeSource);
	expect(after.workoutUserData).toEqual({
		statisticsInclusion: 'excludeFromStatistics',
		workoutTitle: 'Synthetic edited title',
		workoutNotes: 'Two lines\nSynthetic notes',
		workoutTags: ['keep me', 'new tag']
	});
	expect(BigInt(after.workoutRevision)).toBe(BigInt(before.workoutRevision) + 1n);
	await page.reload();
	await expect(
		page.getByRole('heading', { level: 1, name: 'Synthetic edited title' })
	).toBeVisible();
});

test('stale edits and deletions require explicit reload before replacing or removing data', async ({
	page
}) => {
	const username = await register(page);
	await login(page, username);
	const id = await seedWorkout(page, 'Synthetic revision one');
	await openEditor(page, id);
	await page.getByLabel('标题（可选）', { exact: true }).fill('Synthetic local draft');
	const first = await saved(page, id);
	expect(
		await update(page, first, {
			...first.workoutUserData,
			workoutTitle: 'Synthetic remote revision'
		})
	).toBe(200);
	await page.getByRole('button', { name: '保存修改', exact: true }).click();
	await expect(page.getByRole('alert')).toContainText('这条训练已被更新');
	await expect(page.getByLabel('标题（可选）', { exact: true })).toHaveValue(
		'Synthetic local draft'
	);
	await expect(page.getByRole('button', { name: '保存修改', exact: true })).toBeDisabled();
	await confirmClick(page, '重新加载最新版本', false);
	await expect(page.getByLabel('标题（可选）', { exact: true })).toHaveValue(
		'Synthetic local draft'
	);
	await confirmClick(page, '重新加载最新版本');
	await expect(page.getByLabel('标题（可选）', { exact: true })).toHaveValue(
		'Synthetic remote revision'
	);
	await page.getByLabel('标题（可选）', { exact: true }).fill('Synthetic resolved title');
	await page.getByRole('button', { name: '保存修改', exact: true }).click();
	await expect(
		page.getByRole('heading', { level: 1, name: 'Synthetic resolved title' })
	).toBeVisible();
	await page.getByRole('link', { name: '编辑训练', exact: true }).click();
	const current = await saved(page, id);
	expect(
		await update(page, current, {
			...current.workoutUserData,
			workoutNotes: 'Synthetic newer notes'
		})
	).toBe(200);
	await confirmClick(page, '删除这条训练');
	await expect(page.getByRole('alert')).toContainText('这条训练已被更新');
	expect((await saved(page, id)).workoutUserData.workoutNotes).toBe('Synthetic newer notes');
	await page.getByRole('button', { name: '重新加载最新版本', exact: true }).click();
	await expect(page.getByLabel('备注（可选）', { exact: true })).toHaveValue(
		'Synthetic newer notes'
	);
	await confirmClick(page, '删除这条训练', false);
	await expect(page.getByRole('heading', { name: '编辑训练', exact: true })).toBeVisible();
	await page.setViewportSize({ width: 320, height: 852 });
	expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
	await confirmClick(page, '删除这条训练');
	await expect(page).toHaveURL(/\/workouts$/);
	await expect(page.getByRole('heading', { name: '还没有训练记录' })).toBeVisible();
	await page.goto(`/workouts/${id}`);
	await expect(page.getByText('没有找到这条记录，可能已被删除。')).toBeVisible();
});

test('a late metadata save refreshes data without taking over accepted navigation', async ({
	page
}) => {
	const username = await register(page);
	await login(page, username);
	const id = await seedWorkout(page, 'Synthetic delayed edit');
	await openEditor(page, id);
	let published = false;
	let release: () => void = () => {};
	const held = new Promise<void>((resolve) => {
		release = resolve;
	});
	await page.route(`**/api/v1/workouts/${id}/user-data`, async (route) => {
		const response = await route.fetch();
		expect(response.status()).toBe(200);
		published = true;
		await held;
		await route.fulfill({ response }).catch(() => {});
	});
	try {
		await page.getByLabel('标题（可选）', { exact: true }).fill('Synthetic delayed edited title');
		await page.getByRole('button', { name: '保存修改', exact: true }).click();
		await expect.poll(() => published).toBe(true);
		const accepted = page.waitForEvent('dialog').then((dialog) => dialog.accept());
		await page
			.getByRole('navigation', { name: '面包屑' })
			.getByRole('link', { name: '训练', exact: true })
			.click();
		await accepted;
		await expect(page).toHaveURL(/\/workouts$/);
		release();
		await expect(
			page.getByRole('heading', { name: 'Synthetic delayed edited title', level: 3 })
		).toBeVisible();
		await expect(page).toHaveURL(/\/workouts$/);
	} finally {
		release();
	}
});

test('an account cannot open or mutate another account workout', async ({ page }) => {
	const first = await register(page);
	await login(page, first);
	const id = await seedWorkout(page, 'Synthetic owner only');
	const original = await saved(page, id);
	await page.getByRole('button', { name: '退出登录', exact: true }).click();
	const second = await register(page);
	await login(page, second);
	await page.goto(`/workouts/${id}/edit`);
	await expect(page.getByText('没有找到这条记录，可能已被删除。')).toBeVisible();
	await expect(page.getByLabel('标题（可选）', { exact: true })).toHaveCount(0);
	expect(
		await update(page, original, {
			...original.workoutUserData,
			workoutTitle: 'Unauthorized synthetic edit'
		})
	).toBe(404);
	const deletion = await page.evaluate(
		async ({ id, revision }) => {
			const csrf = await (await fetch('/api/v1/auth/web/csrf')).json();
			return (
				await fetch(`/api/v1/workouts/${id}?expectedRevision=${revision}&deleteEmptyGroups=false`, {
					method: 'DELETE',
					headers: { 'X-CSRF-Token': csrf.csrfToken }
				})
			).status;
		},
		{ id, revision: original.workoutRevision }
	);
	expect(deletion).toBe(404);
});

// Hold route modules to cover accepted navigation before component destruction.
for (const operation of ['save', 'delete'] as const) {
	test(`a completed ${operation} respects an accepted route that is still loading`, async ({
		page
	}) => {
		const username = await register(page);
		await login(page, username);
		const id = await seedWorkout(page, 'Synthetic loading navigation');
		await page.goto(`/workouts/${id}/edit`);
		await expect(page.getByLabel('标题（可选）', { exact: true })).toBeVisible();
		let releaseModule: () => void = () => {};
		let releaseWrite: () => void = () => {};
		const moduleHeld = new Promise<void>((resolve) => {
			releaseModule = resolve;
		});
		const writeHeld = new Promise<void>((resolve) => {
			releaseWrite = resolve;
		});
		let moduleRequested = false;
		let published = false;
		const destinationModule =
			operation === 'save'
				? '/src/routes/workouts/+page.svelte'
				: '/src/routes/workouts/[id]/+page.svelte';
		await page.route('**/*', async (route) => {
			const path = decodeURIComponent(new URL(route.request().url()).pathname);
			if (path.endsWith(destinationModule)) {
				moduleRequested = true;
				await moduleHeld;
			}
			await route.continue().catch(() => {});
		});
		await page.route(
			`**/api/v1/workouts/${id}${operation === 'save' ? '/user-data' : '?*'}`,
			async (route) => {
				const response = await route.fetch();
				expect(response.status()).toBe(operation === 'save' ? 200 : 204);
				published = true;
				await writeHeld;
				await route.fulfill({ response }).catch(() => {});
			}
		);
		try {
			if (operation === 'save') {
				await page
					.getByLabel('标题（可选）', { exact: true })
					.fill('Synthetic accepted navigation save');
				await page.getByRole('button', { name: '保存修改', exact: true }).click();
			} else await confirmClick(page, '删除这条训练');
			await expect.poll(() => published).toBe(true);
			page.on('dialog', (dialog) => dialog.accept());
			const destination =
				operation === 'save'
					? page
							.getByRole('navigation', { name: '面包屑' })
							.getByRole('link', { name: '训练', exact: true })
					: page
							.getByRole('navigation', { name: '面包屑' })
							.getByRole('link', { name: '训练详情', exact: true });
			await destination.click({ noWaitAfter: true });
			await expect.poll(() => moduleRequested).toBe(true);
			releaseWrite();
			// Wait for the write handler to settle while the destination remains held.
			await expect(page.getByRole('button', { name: '保存修改', exact: true })).toBeEnabled();
			releaseModule();
			await expect(page).toHaveURL(
				operation === 'save' ? /\/workouts$/ : new RegExp(`/workouts/${id}$`)
			);
		} finally {
			releaseWrite();
			releaseModule();
		}
	});
}

test('an older in-flight detail read cannot replace a completed metadata save', async ({
	page
}) => {
	const username = await register(page);
	await login(page, username);
	const id = await seedWorkout(page, 'Synthetic old cached title');
	await page.goto(`/workouts/${id}/edit`);
	await expect(page.getByLabel('标题（可选）', { exact: true })).toBeVisible();
	await page.clock.install();
	let releaseRead: () => void = () => {};
	let releaseModule: () => void = () => {};
	const heldRead = new Promise<void>((resolve) => {
		releaseRead = resolve;
	});
	const heldModule = new Promise<void>((resolve) => {
		releaseModule = resolve;
	});
	let readRequested = false;
	let moduleRequested = false;
	await page.route('**/*', async (route) => {
		if (
			decodeURIComponent(new URL(route.request().url()).pathname).endsWith(
				'/src/routes/workouts/[id]/+page.svelte'
			)
		) {
			moduleRequested = true;
			await heldModule;
		}
		await route.continue().catch(() => {});
	});
	await page.route(`**/api/v1/workouts/${id}`, async (route) => {
		const response = await route.fetch();
		readRequested = true;
		await heldRead;
		await route.fulfill({ response }).catch(() => {});
	});
	try {
		await page.clock.fastForward(31_000);
		await page.evaluate(() => {
			window.dispatchEvent(new Event('offline'));
			window.dispatchEvent(new Event('online'));
		});
		await expect.poll(() => readRequested).toBe(true);
		await page.getByLabel('标题（可选）', { exact: true }).fill('Synthetic fresh saved title');
		await page.getByRole('button', { name: '保存修改', exact: true }).click();
		await expect.poll(() => moduleRequested).toBe(true);
		releaseRead();
		releaseModule();
		await expect(
			page.getByRole('heading', { level: 1, name: 'Synthetic fresh saved title' })
		).toBeVisible();
		expect((await saved(page, id)).workoutUserData.workoutTitle).toBe(
			'Synthetic fresh saved title'
		);
	} finally {
		releaseRead();
		releaseModule();
	}
});
