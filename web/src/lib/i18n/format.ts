import { getLocale } from '$lib/paraglide/runtime.js';
export function formatLocale(): string {
	return typeof document === 'undefined'
		? getLocale()
		: (document.documentElement.dataset.formatLocale ?? getLocale());
}
export function dayKey(instant: string, timeZone: string): string {
	const parts = new Intl.DateTimeFormat('en-CA-u-ca-gregory-nu-latn', {
		timeZone,
		year: 'numeric',
		month: '2-digit',
		day: '2-digit'
	}).formatToParts(new Date(instant));
	const part = (type: Intl.DateTimeFormatPartTypes) =>
		parts.find((value) => value.type === type)?.value ?? '';
	return `${part('year')}-${part('month')}-${part('day')}`;
}
export function formatNumber(value: number, digits = 0, locale = formatLocale()): string {
	return new Intl.NumberFormat(locale, {
		minimumFractionDigits: digits,
		maximumFractionDigits: digits
	}).format(Number(value.toFixed(digits)));
}

export function browserTimeZone(): string | undefined {
	return typeof window === 'undefined'
		? undefined
		: Intl.DateTimeFormat().resolvedOptions().timeZone;
}
