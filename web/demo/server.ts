import type { Plugin, Connect } from 'vite';
import { card, workouts } from './fixtures.ts';
import { getWorkoutsQueryParams } from '../src/lib/api/generated/schemas.ts';

// Explicit demo mode only: a stateless, read-only fixture transport. No real
// records, credentials, uploads, persistence or production handlers live here.
export const demoMiddleware: Connect.NextHandleFunction = (request, response, next) => {
	const url = new URL(request.url ?? '/', 'http://demo.local');
	if (!url.pathname.startsWith('/api/v1/')) return next();
	const send = (status: number, data: unknown) => {
		if (response.destroyed) return;
		response.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
		response.end(JSON.stringify(data));
	};
	const problem = (status: number, code: string) =>
		send(status, { code, message: 'Demo response', fields: [], requestId: 'synthetic-demo' });
	if (request.method !== 'GET') return problem(405, 'demo_read_only');
	const scenario = request.headers['x-demo-scenario'];
	const delay = scenario === 'slow' ? 1800 : 120;
	const timer = setTimeout(() => {
		if (scenario === 'error') return problem(500, 'internal_error');
		if (scenario === 'unauthenticated') return problem(401, 'unauthenticated');
		if (url.pathname === '/api/v1/workouts') {
			const parsed = getWorkoutsQueryParams.safeParse(
				Object.fromEntries(
					[...url.searchParams].map(([key, value]) => [
						key,
						key === 'limit' ? Number(value) : value
					])
				)
			);
			if (!parsed.success) return problem(400, 'invalid_query');
			const q = parsed.data;
			const limit = q.limit ?? 3;
			if (!Number.isInteger(limit) || limit < 1 || limit > 100)
				return problem(400, 'invalid_query');
			// Synthetic fixtures have no group memberships.
			const filtered = workouts.filter(
				(w) =>
					!q.groupId &&
					(!q.sport || w.workoutObservation.observationSport.type === q.sport) &&
					(!q.from ||
						Date.parse(w.workoutObservation.observationRange.rangeStart) >= Date.parse(q.from)) &&
					(!q.before ||
						Date.parse(w.workoutObservation.observationRange.rangeStart) < Date.parse(q.before)) &&
					(!q.tag || w.workoutUserData.workoutTags.includes(q.tag))
			);
			const scope = JSON.stringify([q.sport, q.from, q.before, q.tag, q.groupId]);
			let offset = 0;
			if (q.cursor) {
				try {
					const cursor: unknown = JSON.parse(Buffer.from(q.cursor, 'base64url').toString());
					if (
						!Array.isArray(cursor) ||
						cursor.length !== 2 ||
						cursor[0] !== scope ||
						!Number.isInteger(cursor[1]) ||
						cursor[1] < 0
					)
						return problem(400, 'invalid_cursor');
					offset = cursor[1];
				} catch {
					return problem(400, 'invalid_cursor');
				}
			}
			if (scenario === 'empty') return send(200, { items: [] });
			if (scenario === 'invalid') return send(200, { items: [{ id: 123 }] });
			return send(200, {
				items: filtered.slice(offset, offset + limit).map(card),
				...(offset + limit < filtered.length
					? {
							nextCursor: Buffer.from(JSON.stringify([scope, offset + limit])).toString('base64url')
						}
					: {})
			});
		}
		const id = url.pathname.match(/^\/api\/v1\/workouts\/([^/]+)$/)?.[1];
		const workout = workouts.find((w) => w.workoutId === id);
		if (!workout) return problem(404, 'not_found');
		if (scenario === 'invalid') return send(200, { ...workout, workoutRevision: 123 });
		return send(200, workout);
	}, delay);
	response.once('close', () => clearTimeout(timer));
};
export const demoPlugin = (): Plugin => ({
	name: 'fitness-read-only-demo',
	configureServer(server) {
		server.middlewares.use(demoMiddleware);
	},
	configurePreviewServer(server) {
		server.middlewares.use(demoMiddleware);
	}
});
