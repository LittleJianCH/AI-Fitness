import { defineCustomServerStrategy } from '$lib/paraglide/runtime.js';
import { requestLanguage } from './locale';
defineCustomServerStrategy('custom-fitness', {
	getLocale: (request) => (request ? requestLanguage(request).locale : undefined)
});
