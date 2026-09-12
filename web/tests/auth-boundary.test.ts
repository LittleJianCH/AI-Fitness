import { afterEach, expect, it, vi } from 'vitest';
import { z } from 'zod';
import { loginDestination } from '../src/lib/auth/navigation';
import { ApiError, request } from '../src/lib/api/request';
import { postAuthRegister, postAuthLogout } from '../src/lib/api/generated/client';
import { postAuthRegister201Response } from '../src/lib/api/generated/schemas';
afterEach(() => vi.unstubAllGlobals());
it('accepts generated 201 and bodyless 204 responses and sends the CSRF header', async () => {
	const fetch = vi
		.fn()
		.mockResolvedValueOnce(
			Response.json(
				{
					id: '00000000-0000-0000-0000-000000000001',
					username: 'synthetic',
					createdAt: '2026-09-12T00:00:00Z'
				},
				{ status: 201 }
			)
		)
		.mockResolvedValueOnce(new Response(null, { status: 204 }));
	vi.stubGlobal('fetch', fetch);
	const user = await request(
		() =>
			postAuthRegister(
				{ username: 'synthetic', password: 'synthetic-password' },
				{ 'X-CSRF-Token': 'synthetic-csrf' }
			),
		postAuthRegister201Response,
		201
	);
	expect(user.username).toBe('synthetic');
	expect(new Headers(fetch.mock.calls[0][1].headers).get('X-CSRF-Token')).toBe('synthetic-csrf');
	await expect(request(() => postAuthLogout(), z.void(), 204)).resolves.toBeUndefined();
});
it('preserves status, field errors and retry delay without trusting an error response as success', async () => {
	await expect(
		request(
			async () => ({
				status: 429,
				data: {
					code: 'rate_limited',
					message: 'not displayed',
					fields: [],
					requestId: 'synthetic'
				},
				headers: new Headers({ 'Retry-After': '60' })
			}),
			z.object({})
		)
	).rejects.toMatchObject({ code: 'rate_limited', status: 429, retryAfter: 60 });
	await expect(
		request(async () => ({ status: 201, data: {} }), z.void(), 204)
	).rejects.toBeInstanceOf(ApiError);
});
it('keeps login returns inside implemented application destinations', () => {
	expect(loginDestination('/workouts/00000000-0000-4000-8000-000000000001?x=1')).toBe(
		'/workouts/00000000-0000-4000-8000-000000000001?x=1'
	);
	for (const value of [
		null,
		'https://evil.invalid',
		'/workouts/..//evil.invalid',
		'/workouts/../login',
		'//evil.invalid',
		'/workouts\\evil.invalid',
		'javascript:alert(1)',
		'/login?next=/login',
		'/workouts\n'
	])
		expect(loginDestination(value)).toBe('/workouts');
});
