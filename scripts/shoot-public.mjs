// Screenshot public-ish routes (no auth needed) for the redesign loop.
import { chromium } from 'playwright';
import { qaBase } from './_qa-guard.mjs';
import { mkdirSync } from 'node:fs';
const BASE = qaBase('http://localhost:5174');
const TAG = process.env.TAG || 'pub';
mkdirSync('screenshots', { recursive: true });
const browser = await chromium.launch();
const ctx = await browser.newContext({
	viewport: { width: 430, height: 932 },
	deviceScaleFactor: 2
});
const page = await ctx.newPage();
const routes = [
	['reset', '/reset-password'],
	['leaderboard', '/leaderboard']
];
for (const [name, path] of routes) {
	await page.goto(`${BASE}${path}`, { waitUntil: 'networkidle' });
	await page.waitForTimeout(1500);
	await page.screenshot({ path: `screenshots/${TAG}-${name}.png` });
	console.log('shot', `${TAG}-${name}`);
}
await browser.close();
console.log('done');
