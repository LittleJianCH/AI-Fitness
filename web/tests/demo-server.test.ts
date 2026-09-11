import { beforeAll, afterAll, it, expect } from 'vitest';
import { createServer, type Server } from 'node:http';
import { demoMiddleware } from '../demo/server';
let server: Server;
let base: string;
beforeAll(async () => {
	server = createServer((req, res) =>
		demoMiddleware(req, res, () => {
			res.writeHead(404);
			res.end();
		})
	);
	await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
	const address = server.address();
	if (!address || typeof address === 'string') throw new Error('Expected port');
	base = `http://127.0.0.1:${address.port}`;
});
afterAll(
	() =>
		new Promise<void>((resolve, reject) =>
			server.close((error) => (error ? reject(error) : resolve()))
		)
);
it('serves paginated summaries without sample data and binds cursors to filters', async () => {
	const first = await (await fetch(`${base}/api/v1/workouts?limit=2`)).json();
	expect(first.items).toHaveLength(2);
	expect(first.items[0]).not.toHaveProperty('workoutObservation');
	const next = await (
		await fetch(`${base}/api/v1/workouts?limit=2&cursor=${first.nextCursor}`)
	).json();
	expect(next.items).toHaveLength(2);
	expect(next.nextCursor).toBeUndefined();
	expect(
		(await fetch(`${base}/api/v1/workouts?sport=cycling&cursor=${first.nextCursor}`)).status
	).toBe(400);
});
it('filters by sport and RFC3339 instants, including offsets', async () => {
	const result = await (await fetch(`${base}/api/v1/workouts?sport=running`)).json();
	expect(result.items).toHaveLength(2);
	const params = new URLSearchParams({ from: '2026-09-12T08:10:00+08:00' });
	const range = await (await fetch(`${base}/api/v1/workouts?${params}`)).json();
	expect(range.items).toHaveLength(1);
	const group = await (
		await fetch(`${base}/api/v1/workouts?groupId=00000000-0000-4000-8000-000000000001`)
	).json();
	expect(group.items).toEqual([]);
});
it('returns explicit invalid-query, missing-resource and read-only failures', async () => {
	expect((await fetch(`${base}/api/v1/workouts?limit=0`)).status).toBe(400);
	expect((await fetch(`${base}/api/v1/workouts/nope`)).status).toBe(404);
	expect((await fetch(`${base}/api/v1/workouts`, { method: 'POST', body: '{}' })).status).toBe(405);
});
