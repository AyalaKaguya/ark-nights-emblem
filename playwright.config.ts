import { defineConfig, devices } from '@playwright/test';
import { existsSync } from 'node:fs';

const installed = (locations: string[]) => locations.some(path => existsSync(path));
const chromeInstalled = installed([
	'C:/Program Files/Google/Chrome/Application/chrome.exe',
	'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
	`${process.env.LOCALAPPDATA ?? ''}/Google/Chrome/Application/chrome.exe`,
]);

export default defineConfig({
	testDir: './tests/e2e',
	outputDir: './.qa/playwright/results',
	fullyParallel: false,
	workers: 1,
	timeout: 180_000,
	expect: { timeout: 15_000 },
	forbidOnly: !!process.env.CI,
	retries: 0,
	reporter: [['list'], ['html', { open: 'never', outputFolder: '.qa/playwright/report' }]],
	use: {
		baseURL: process.env.HOTEL_BASE_URL ?? 'http://127.0.0.1:4173',
		viewport: { width: 1600, height: 1000 },
		trace: 'retain-on-failure',
		screenshot: 'only-on-failure',
		actionTimeout: 15_000,
		launchOptions: { args: ['--enable-webgl', '--ignore-gpu-blocklist'] },
	},
	projects: [
		{ name: 'edge', use: { ...devices['Desktop Edge'], channel: 'msedge' } },
		...(chromeInstalled ? [{ name: 'chrome', use: { ...devices['Desktop Chrome'], channel: 'chrome' as const } }] : []),
	],
	webServer: {
		command: 'npm run dev -- --port 4173 --strictPort',
		url: 'http://127.0.0.1:4173',
		reuseExistingServer: !process.env.CI,
		timeout: 60_000,
	},
});
