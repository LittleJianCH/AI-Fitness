import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

// Catalog validation complements the compiler's typed key/argument checks.
/**
 * @typedef {string | {declarations?: string[], match: Record<string, string>}[]} Message
 * @param {Record<string, Message>} source
 * @param {Record<string, Message>} translated
 */
export function validateCatalogs(source, translated) {
	/** @param {Record<string, Message>} catalog */
	const keys = (catalog) =>
		Object.keys(catalog)
			.filter((key) => key !== '$schema')
			.sort();
	if (JSON.stringify(keys(source)) !== JSON.stringify(keys(translated)))
		throw new Error('Translation keys must match the source catalog');
	/** @param {Message} message */
	const inputs = (message) =>
		[
			...new Set(
				(typeof message === 'string'
					? [message]
					: message.flatMap((variant) => Object.values(variant.match))
				).flatMap((text) => [...text.matchAll(/\{(\w+)\}/g)].map((match) => match[1]))
			)
		].sort();
	for (const key of keys(source)) {
		const original = source[key],
			translation = translated[key];
		for (const message of [original, translation]) {
			if (typeof message === 'string') {
				if (!message.trim()) throw new Error(`Empty translation: ${key}`);
			} else if (
				!Array.isArray(message) ||
				message.some(
					(variant) =>
						!Object.values(variant.match).every((text) => typeof text === 'string' && text.trim())
				)
			)
				throw new Error(`Invalid variants: ${key}`);
		}
		if (JSON.stringify(inputs(original)) !== JSON.stringify(inputs(translation)))
			throw new Error(`Placeholder mismatch: ${key}`);
		if (Array.isArray(original))
			for (const variant of original)
				for (const declaration of variant.declarations ?? []) {
					const selector = /^local (\w+) = \w+: plural$/.exec(declaration)?.[1];
					if (
						selector &&
						(!Object.hasOwn(variant.match, `${selector}=one`) ||
							!Object.hasOwn(variant.match, `${selector}=other`))
					)
						throw new Error(`Missing English plural branch: ${key}`);
				}
	}
}
export async function checkCatalogs() {
	const [source, translated] = await Promise.all(
		['en', 'zh-Hans'].map(async (locale) =>
			JSON.parse(await readFile(new URL(`../messages/${locale}.json`, import.meta.url), 'utf8'))
		)
	);
	validateCatalogs(source, translated);
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href)
	await checkCatalogs();
