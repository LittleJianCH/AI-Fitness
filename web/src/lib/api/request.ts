import { z } from 'zod';
import { getWorkoutsDefaultResponse } from './generated/schemas';
import type { FieldError } from './generated/client';

export class ApiError extends Error {
	constructor(
		public code: string,
		public status = 0,
		public fields: FieldError[] = [],
		public retryAfter?: number
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
				seconds !== undefined && Number.isSafeInteger(seconds) ? seconds : undefined
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
	const code = error instanceof ApiError ? error.code : 'network_error';
	switch (code) {
		case 'not_found':
			return '没有找到这条记录，可能已被删除。';
		case 'unauthenticated':
			return import.meta.env.MODE === 'demo'
				? '当前会话不可用，请重新登录。演示模式可切回正常场景继续体验。'
				: '登录已失效，请重新登录。';
		case 'invalid_current_password':
			return '当前密码不正确，请重试。';
		case 'invalid_credentials':
			return '用户名或密码不正确，请重试。';
		case 'registration_closed':
			return '当前暂停注册，请使用已有账号登录。';
		case 'registration_conflict':
			return '这个用户名无法注册，请尝试其他用户名。';
		case 'session_conflict':
			return '会话状态已变化，请重试。';
		case 'csrf_failed':
			return '会话校验未通过，请重试；如果仍然失败，请重新登录。';
		case 'forbidden':
			return '当前账号无法执行这个操作。';
		case 'revision_conflict':
			return '这条训练已被更新，请重新加载最新版本后再修改。';
		case 'submission_conflict':
			return '本次提交的内容已发生变化，请确认已保存的记录。';
		case 'reconciliation_required':
			return '当前仅支持删除手动录入的训练，这条记录暂时无法删除。';
		case 'invalid_cursor':
			return '列表状态已变化，请从第一页重新加载。';
		case 'validation_failed':
			return '请检查填写内容，服务器未接受本次保存。';
		case 'invalid_query':
			return '请检查筛选条件和日期范围。';
		case 'rate_limited':
			return error instanceof ApiError && error.retryAfter
				? `操作过于频繁，请等待 ${error.retryAfter} 秒后重试。`
				: '操作过于频繁，请稍后重试。';
		case 'payload_too_large':
			return '文件超过服务器允许的大小，请选择较小的 FIT 文件。';
		case 'invalid_response':
			return '收到的数据不符合接口约定，暂时无法展示。';
		case 'internal_error':
			return '服务暂时无法完成请求，请稍后重试。';
		default:
			return '连接失败，请检查网络后重试。';
	}
}
