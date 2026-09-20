import { expect, it } from 'vitest';
import { compile } from '@inlang/paraglide-js';
import { execFileSync } from 'node:child_process';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { paraglideOptions } from '../paraglide.config.js';
import settings from '../project.inlang/settings.json';

it('falls back to English at runtime if a translated message is missing', async () => {
	const root = await mkdtemp(join(tmpdir(), 'fitness-i18n-fallback-'));
	try {
		const project = join(root, 'project.inlang');
		await mkdir(project);
		await writeFile(
			join(project, 'settings.json'),
			JSON.stringify({
				...settings,
				modules: settings.modules.map((module) => resolve(module)),
				'plugin.inlang.messageFormat': { pathPattern: join(root, '{locale}.json') }
			})
		);
		await writeFile(join(root, 'en.json'), JSON.stringify({ fallback_probe: 'Hello {name}' }));
		await writeFile(join(root, 'zh-Hans.json'), '{}');
		const outdir = join(root, 'output');
		await compile({ ...paraglideOptions, project, outdir });
		const result = execFileSync(
			process.execPath,
			[
				'--input-type=module',
				'-e',
				'const {m} = await import(process.argv[1]); console.log(m.fallback_probe({name: "Synthetic"}, {locale: "zh-Hans"}));',
				pathToFileURL(join(outdir, 'messages.js')).href
			],
			{ encoding: 'utf8' }
		);
		expect(result.trim()).toBe('Hello Synthetic');
	} finally {
		await rm(root, { recursive: true, force: true });
	}
}, 15000);
