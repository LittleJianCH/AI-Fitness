import { m } from '$lib/paraglide/messages.js';
import { z } from 'zod';
import { getWorkoutsDefaultResponse } from './generated/schemas';
import type { FieldError } from './generated/client';

export class ApiError extends Error {
	constructor(
		public code: string,
		public status = 0,
		public fields: FieldError[] = [],
		public retryAfter?: number,
		public requestId?: string
	) {
		super(code);
		this.name = 'ApiError';
	}
}
export const requestOptions = (signal?: AbortSignal): RequestInit => ({
	signal,
	credentials: 'same-origin',
	cache: 'no-store'
});
type ResponseData = { status: number; data: unknown; headers?: Headers };
export async function request<T>(
	action: () => Promise<ResponseData>,
	schema: z.ZodType<T>,
	status = 200
): Promise<T> {
	try {
		const response = await action();
		if (response.status !== status) {
			const problem = getWorkoutsDefaultResponse.safeParse(response.data);
			const delay = response.headers?.get('Retry-After');
			const seconds = delay && /^\d+$/.test(delay) ? Number(delay) : undefined;
			throw new ApiError(
				problem.success ? problem.data.code : 'invalid_response',
				response.status,
				problem.success ? problem.data.fields : [],
				seconds !== undefined && Number.isSafeInteger(seconds) ? seconds : undefined,
				problem.success ? problem.data.requestId : undefined
			);
		}
		const result = schema.safeParse(status === 204 ? undefined : response.data);
		if (!result.success) throw new ApiError('invalid_response', response.status);
		return result.data;
	} catch (error) {
		if (error instanceof ApiError || (error instanceof Error && error.name === 'AbortError'))
			throw error;
		throw new ApiError(error instanceof SyntaxError ? 'invalid_response' : 'network_error');
	}
}
export function errorText(error: Error | null): string {
	if (error?.name === 'AbortError') return m.error_cancelled();
	const code = error instanceof ApiError ? error.code : 'unknown_error';
	switch (code) {
		case 'not_found':
			return m.error_not_found();
		case 'unauthenticated':
			return import.meta.env.MODE === 'demo' ? m.error_demo_session() : m.error_session();
		case 'invalid_current_password':
			return m.error_current_password();
		case 'invalid_credentials':
			return m.error_credentials();
		case 'registration_closed':
			return m.error_registration_closed();
		case 'registration_conflict':
			return m.error_registration_conflict();
		case 'session_conflict':
			return m.error_session_conflict();
		case 'csrf_failed':
			return m.error_csrf();
		case 'forbidden':
			return m.error_forbidden();
		case 'analysis_revision_conflict':
			return m.error_analysis_revision();
		case 'analysis_too_large':
			return m.error_analysis_large();
		case 'analysis_unavailable':
			return m.error_analysis_unavailable();
		case 'revision_conflict':
			return m.error_revision();
		case 'submission_conflict':
			return m.error_submission();
		case 'reconciliation_required':
			return m.error_delete_imported();
		case 'invalid_cursor':
			return m.error_cursor();
		case 'validation_failed':
			return m.error_validation();
		case 'invalid_query':
			return m.error_query();
		case 'rate_limited':
			return error instanceof ApiError && error.retryAfter
				? m.error_rate_wait({ seconds: error.retryAfter })
				: m.error_rate_limited();
		case 'payload_too_large':
			return m.error_upload_large();
		case 'invalid_response':
			return m.error_response();
		case 'internal_error':
			return m.error_server();
		case 'network_error':
			return m.error_network();
		default:
			return m.error_unknown();
	}
}
