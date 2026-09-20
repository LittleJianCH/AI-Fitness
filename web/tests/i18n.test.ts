import { expect, it } from 'vitest';
import { validateCatalogs } from '../scripts/i18n-catalogs.mjs';
import en from '../messages/en.json';
import zh from '../messages/zh-Hans.json';
import {
	languageOverride,
	parseLanguagePreferences,
	resolveLanguage,
	supportedLocale
} from '../src/lib/i18n/locale';
import { dayKey, formatNumber } from '../src/lib/i18n/format';
import { dayText, duration } from '../src/lib/workouts/presentation';
import { metricInfo } from '../src/lib/analysis/presentation';
import { ApiError, errorText } from '../src/lib/api/request';
import { m } from '../src/lib/paraglide/messages.js';
import '../src/lib/i18n/server';
import { paraglideMiddleware } from '../src/lib/paraglide/server.js';

it('honors supported scripts, overrides, regional formats, order and quality', () => {
	expect(resolveLanguage('en', ['zh-CN', 'en-GB'])).toEqual({
		locale: 'en',
		formatLocale: 'en-GB'
	});
	expect(resolveLanguage('invalid', ['zh-Hant', 'en-GB']).locale).toBe('en');
	expect(resolveLanguage(undefined, ['zh-Hant', 'zh-SG']).locale).toBe('zh-Hans');
	for (const tag of ['zh-Hant', 'zh-TW', 'zh-HK', 'zh-MO', 'bad_tag'])
		expect(supportedLocale(tag)).toBeUndefined();
	expect(supportedLocale('zh-Hans-TW')).toBe('zh-Hans');
	expect(supportedLocale('zh-Hant-CN')).toBeUndefined();
	expect(
		parseLanguagePreferences('zh-CN;q=0, en-GB;q=.8, zh-SG;q=0.7,en-US;q=0.9,en;q=1.1')
	).toEqual(['en-US', 'zh-SG']);
	expect(parseLanguagePreferences('zh-Hant,zh-CN;q=0.8,en-GB;q=0.8')).toEqual(['zh-CN', 'en-GB']);
	expect(resolveLanguage(undefined, [])).toEqual({ locale: 'en', formatLocale: 'en' });
	expect(languageOverride('fitness-language=%ZZ')).toBeUndefined();
	expect(languageOverride('fitness-language=system')).toBeUndefined();
	expect(languageOverride('fitness-language=zh-Hans')).toBe('zh-Hans');
});
it('detects missing translations, placeholders and plural branches', () => {
	expect(() => validateCatalogs(en, zh)).not.toThrow();
	const missing = { ...zh };
	delete (missing as Record<string, unknown>).auth_login;
	expect(() => validateCatalogs(en, missing)).toThrow(/keys/);
	expect(() => validateCatalogs({ greeting: 'Hello {name}' }, { greeting: '你好' })).toThrow(
		/Placeholder/
	);
	expect(() =>
		validateCatalogs(
			{ x: [{ declarations: ['local count = n: plural'], match: { 'count=other': '{n}' } }] },
			{ x: '{n}' }
		)
	).toThrow(/plural/);
	expect(m.workouts_all_shown({ count: 1 }, { locale: 'en' })).toBe('All 1 workout shown');
	expect(m.workouts_all_shown({ count: 2 }, { locale: 'en' })).toBe('All 2 workouts shown');
	expect(m.workouts_all_shown({ count: 2 }, { locale: 'zh-Hans' })).toBe('已显示全部 2 条训练');
});
it('keeps calendar identities stable across languages, midnight and DST', () => {
	for (const instant of [
		'2026-03-08T07:59:59Z',
		'2026-03-08T08:00:00Z',
		'2026-11-01T08:30:00Z',
		'2026-11-01T09:30:00Z'
	]) {
		const key = dayKey(instant, 'America/Los_Angeles');
		expect(key).toMatch(/^2026-\d{2}-\d{2}$/);
		expect(dayText(instant, 'America/Los_Angeles', 'en-GB')).not.toBe(
			dayText(instant, 'America/Los_Angeles', 'zh-CN')
		);
	}
	expect(dayKey('2026-01-01T00:30:00Z', 'America/Los_Angeles')).toBe('2025-12-31');
	expect(dayKey('2026-01-01T00:30:00Z', 'Asia/Shanghai')).toBe('2026-01-01');
	expect(formatNumber(1234.5, 1, 'en-GB')).toBe('1,234.5');
	expect(formatNumber(3, 2, 'en-GB')).toBe('3.00');
	expect(formatNumber(3, 2, 'zh-CN')).toBe('3.00');
	expect(formatNumber(3.005, 2, 'en-GB')).toBe('3.00');
	expect(dayText('2026-01-01T00:30:00Z')).toBe('—');
});
it('isolates interleaved request locales including lazy metric labels and errors', async () => {
	const results = await Promise.all(
		Array.from({ length: 30 }, async (_, index) => {
			const locale = index % 2 ? 'zh-Hans' : 'en';
			return paraglideMiddleware(
				new Request('https://fitness.invalid/login', { headers: { 'accept-language': locale } }),
				async () => {
					await new Promise((resolve) => setTimeout(resolve, index % 3));
					const unknown = errorText(new ApiError('future_server_code', 500));
					expect(unknown).not.toBe(errorText(new ApiError('network_error')));
					expect(unknown).not.toContain('future_server_code');
					expect(duration(0)).toBe('00:00:00');
					return new Response(
						[metricInfo.powerMetric.title, duration(undefined), unknown].join('|')
					);
				}
			);
		})
	);
	const bodies = await Promise.all(results.map((result) => result.text()));
	bodies.forEach((body, index) =>
		expect(body.startsWith(index % 2 ? '功率|未记录|' : 'Power|Not recorded|')).toBe(true)
	);
});
