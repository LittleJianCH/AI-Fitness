import { defineCustomClientStrategy } from '$lib/paraglide/runtime.js';
const documentLocale = () => (document.documentElement.lang === 'zh-Hans' ? 'zh-Hans' : 'en');
defineCustomClientStrategy('custom-fitness', {
	getLocale: documentLocale,
	// Paraglide synchronizes the initial locale via this callback. Persisting a
	// different language remains the guarded picker's responsibility.
	setLocale: (locale) => {
		if (locale !== documentLocale()) throw new Error('Use the guarded language picker');
	}
});
