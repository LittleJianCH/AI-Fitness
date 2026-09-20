/** Shared by CLI generation and Vite; no URL localization or remote plugins. */
/** @type {import('@inlang/paraglide-js').CompilerOptions} */
export const paraglideOptions = {
	project: './project.inlang',
	outdir: './src/lib/paraglide',
	emitTsDeclarations: true,
	strategy: ['custom-fitness', 'baseLocale'],
	cookieName: 'fitness-language'
};
