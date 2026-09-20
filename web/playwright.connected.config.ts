import { defineConfig } from '@playwright/test';
export default defineConfig({
	testDir: './tests/connected',
	fullyParallel: false,
	workers: 1,
	reporter: [['list']],
	timeout: 30_000,
	use: {
		locale: 'zh-CN',
		baseURL: 'https://localhost:5181',
		timezoneId: 'Asia/Shanghai',
		ignoreHTTPSErrors: true,
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
				hasTouch: true
			}
		}
	],
	webServer: {
		command: 'pnpm dev --port 5181 --strictPort',
		url: 'https://localhost:5181',
		ignoreHTTPSErrors: true,
		reuseExistingServer: false,
		timeout: 60_000
	}
});
