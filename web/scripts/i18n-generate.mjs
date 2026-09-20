import { checkCatalogs } from './i18n-catalogs.mjs';
import { compile } from '@inlang/paraglide-js';
import { paraglideOptions } from '../paraglide.config.js';
await checkCatalogs();
await compile(paraglideOptions);
