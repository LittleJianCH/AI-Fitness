export type MessageLocale = 'en' | 'zh-Hans';
export type LanguagePreference = MessageLocale | 'system';
export const languageCookie = 'fitness-language';

export function supportedLocale(tag: string): MessageLocale | undefined {
	try {
		const locale = new Intl.Locale(tag);
		if (locale.language === 'en') return 'en';
		if (locale.language !== 'zh') return undefined;
		if (locale.script) return locale.script === 'Hans' ? 'zh-Hans' : undefined;
		return ['TW', 'HK', 'MO'].includes(locale.region ?? '') ? undefined : 'zh-Hans';
	} catch {
		return undefined;
	}
}

export function parseLanguagePreferences(header: string): string[] {
	return header
		.split(',')
		.map((entry, index) => {
			const [tag, ...parameters] = entry.trim().split(';');
			let quality = 1;
			if (parameters.length > 1) quality = 0;
			else if (parameters.length === 1) {
				const match = /^q=(0(?:\.\d{0,3})?|1(?:\.0{0,3})?)$/.exec(parameters[0].trim());
				quality = match ? Number(match[1]) : 0;
			}
			return { tag, quality, index };
		})
		.filter(({ tag, quality }) => quality > 0 && supportedLocale(tag))
		.sort((a, b) => b.quality - a.quality || a.index - b.index)
		.map(({ tag }) => tag);
}

export function languageOverride(cookies: string): MessageLocale | undefined {
	for (const entry of cookies.split(';')) {
		const [name, ...parts] = entry.trim().split('=');
		if (name !== languageCookie) continue;
		try {
			const value = decodeURIComponent(parts.join('='));
			return value === 'en' || value === 'zh-Hans' ? value : undefined;
		} catch {
			return undefined;
		}
	}
	return undefined;
}

export function resolveLanguage(override: unknown, preferences: readonly string[]) {
	const locale: MessageLocale =
		override === 'en' || override === 'zh-Hans'
			? override
			: (preferences.map(supportedLocale).find((item) => item !== undefined) ?? 'en');
	const regional = preferences.find((tag) => supportedLocale(tag) === locale);
	return { locale, formatLocale: regional ? new Intl.Locale(regional).toString() : locale };
}

export function requestLanguage(request: Request) {
	return resolveLanguage(
		languageOverride(request.headers.get('cookie') ?? ''),
		parseLanguagePreferences(request.headers.get('accept-language') ?? '')
	);
}
