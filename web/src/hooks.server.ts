import type { Handle } from '@sveltejs/kit';
import '$lib/i18n/server';
import { paraglideMiddleware } from '$lib/paraglide/server.js';
import { requestLanguage } from '$lib/i18n/locale';

export const handle: Handle = ({ event, resolve }) =>
	paraglideMiddleware(event.request, async ({ locale }) => {
		const { formatLocale } = requestLanguage(event.request);
		const response = await resolve(event, {
			transformPageChunk: ({ html }) =>
				html
					.replace('%lang%', locale)
					.replace('%dir%', 'ltr')
					.replace('%format-locale%', formatLocale)
		});
		// The same URL has language-dependent HTML; never share personalized pages.
		response.headers.set('Cache-Control', 'private, no-store');
		return response;
	});
