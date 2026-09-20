import { defineConfig } from '@playwright/test';
export default defineConfig({
	testDir: './tests/browser',
	fullyParallel: false,
	workers: 1,
	reporter: [['list']],
	use: {
		locale: 'zh-CN',
		baseURL: 'http://127.0.0.1:5180',
		trace: 'retain-on-failure',
		screenshot: 'only-on-failure'
	},
	projects: [
		{ name: 'desktop', use: { browserName: 'chromium', viewport: { width: 1440, height: 900 } } },
		{
			name: 'mobile',
			use: {
				browserName: 'chromium',
				viewport: { width: 393, height: 852 },
				isMobile: true,
				hasTouch: true,
				deviceScaleFactor: 1
			}
		}
	],
	webServer: {
		command: 'pnpm demo --port 5180 --strictPort',
		url: 'http://127.0.0.1:5180',
		reuseExistingServer: false,
		timeout: 60_000
	}
});
