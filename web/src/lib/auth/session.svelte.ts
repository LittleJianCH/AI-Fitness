import { getContext, setContext } from 'svelte';
import { z } from 'zod';
import type { QueryClient } from '@tanstack/svelte-query';
import {
	getAuthWebCsrf,
	getMe,
	postAuthWebLogin,
	postAuthLogout,
	postAuthRegister,
	type Credentials,
	type Registration,
	type User
} from '$lib/api/generated/client';
import {
	getAuthWebCsrf200Response,
	getMe200Response,
	postAuthWebLogin200Response,
	postAuthRegister201Response
} from '$lib/api/generated/schemas';
import { ApiError, request, requestOptions } from '$lib/api/request';

type State =
	| { type: 'loading' }
	| { type: 'anonymous' }
	| { type: 'authenticated'; user: User }
	| { type: 'error'; error: Error };
const key = Symbol('browser-session');
export class BrowserSession {
	state = $state<State>({ type: 'loading' });
	private csrf = '';
	private lifetime = new AbortController();
	private channel?: BroadcastChannel;
	constructor(private client: QueryClient) {}
	get user() {
		return this.state.type === 'authenticated' ? this.state.user : undefined;
	}
	private clear() {
		this.lifetime.abort();
		this.lifetime = new AbortController();
		this.csrf = '';
		const privateQueries = {
			predicate: (query: { queryKey: readonly unknown[] }) => query.queryKey[0] !== 'auth-policy'
		};
		void this.client.cancelQueries(privateQueries);
		this.client.removeQueries(privateQueries);
	}
	expire() {
		this.clear();
		this.state = { type: 'anonymous' };
	}
	end() {
		this.expire();
		this.channel?.postMessage('changed');
	}
	async restore() {
		this.clear();
		this.state = { type: 'loading' };
		const signal = this.lifetime.signal;
		try {
			const csrf = await request(
				() => getAuthWebCsrf(requestOptions(signal)),
				getAuthWebCsrf200Response
			);
			const user = await request(() => getMe(undefined, requestOptions(signal)), getMe200Response);
			signal.throwIfAborted();
			this.csrf = csrf.csrfToken;
			this.state = { type: 'authenticated', user };
		} catch (error) {
			if (signal.aborted) return;
			this.state =
				error instanceof ApiError && error.code === 'unauthenticated'
					? { type: 'anonymous' }
					: {
							type: 'error',
							error: error instanceof Error ? error : new ApiError('network_error')
						};
		}
	}
	async login(input: Credentials) {
		this.clear();
		this.state = { type: 'anonymous' };
		const signal = this.lifetime.signal;
		const csrf = await request(
			() => getAuthWebCsrf(requestOptions(signal)),
			getAuthWebCsrf200Response
		);
		const result = await request(
			() => postAuthWebLogin(input, { 'X-CSRF-Token': csrf.csrfToken }, requestOptions(signal)),
			postAuthWebLogin200Response
		).catch((error: unknown) => {
			if (error instanceof ApiError && error.status === 401)
				throw new ApiError('invalid_credentials', 401);
			throw error;
		});
		signal.throwIfAborted();
		this.csrf = result.csrfToken;
		this.state = { type: 'authenticated', user: result.user };
		this.channel?.postMessage('changed');
	}
	async register(input: Registration) {
		const signal = this.lifetime.signal;
		const csrf = await request(
			() => getAuthWebCsrf(requestOptions(signal)),
			getAuthWebCsrf200Response
		);
		return request(
			() => postAuthRegister(input, { 'X-CSRF-Token': csrf.csrfToken }, requestOptions(signal)),
			postAuthRegister201Response,
			201
		);
	}
	async run<T>(action: (csrf: string, options: RequestInit) => Promise<T>): Promise<T> {
		const signal = this.lifetime.signal;
		try {
			if (!this.user) throw new ApiError('unauthenticated', 401);
			const result = await action(this.csrf, requestOptions(signal));
			signal.throwIfAborted();
			return result;
		} catch (error) {
			signal.throwIfAborted();
			if (error instanceof ApiError && error.code === 'unauthenticated') this.expire();
			if (error instanceof ApiError && error.code === 'csrf_failed' && !signal.aborted) {
				try {
					const token = await request(
						() => getAuthWebCsrf(requestOptions(signal)),
						getAuthWebCsrf200Response
					);
					this.csrf = token.csrfToken;
				} catch {
					/* The next explicit action can retry when the connection recovers. */
				}
			}
			throw error;
		}
	}
	async logout() {
		await this.run((csrf, options) =>
			request(() => postAuthLogout({ 'X-CSRF-Token': csrf }, options), z.void(), 204)
		);
		this.end();
	}
	mount() {
		if (typeof BroadcastChannel !== 'undefined') {
			this.channel = new BroadcastChannel('ai-fitness-browser-session');
			this.channel.onmessage = (event: MessageEvent<unknown>) => {
				if (event.data === 'changed') void this.restore();
			};
		}
		const verify = async () => {
			if (!this.user || document.visibilityState !== 'visible') return;
			const signal = this.lifetime.signal;
			try {
				const user = await request(
					() => getMe(undefined, requestOptions(signal)),
					getMe200Response
				);
				if (!signal.aborted && user.id !== this.user?.id) await this.restore();
			} catch (error) {
				if (!signal.aborted && error instanceof ApiError && error.code === 'unauthenticated')
					this.expire();
			}
		};
		window.addEventListener('focus', verify);
		document.addEventListener('visibilitychange', verify);
		void this.restore();
		return () => {
			this.lifetime.abort();
			this.channel?.close();
			window.removeEventListener('focus', verify);
			document.removeEventListener('visibilitychange', verify);
		};
	}
}
export function provideSession(client: QueryClient) {
	return setContext(key, new BrowserSession(client));
}
export function useSession() {
	return getContext<BrowserSession>(key);
}
