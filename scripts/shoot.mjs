// Screenshot harness for the WordBank UI baseline/redesign loop.
import { chromium } from 'playwright';
import { qaBase } from './_qa-guard.mjs';
import { mkdirSync } from 'node:fs';

const BASE = qaBase('http://localhost:5174');
const EMAIL = process.env.PW_EMAIL || 'pwtest+wb@example.com';
const PASS = process.env.PW_PASS || 'TestPass123!';
const TAG = process.env.TAG || 'base';
mkdirSync('screenshots', { recursive: true });

const browser = await chromium.launch();
const ctx = await browser.newContext({
	viewport: { width: 430, height: 932 },
	deviceScaleFactor: 2
});
const page = await ctx.newPage();
page.on('console', (m) => {
	if (m.type() === 'error') console.log('  [console.error]', m.text().slice(0, 160));
});
const shot = async (name) => {
	await page.screenshot({ path: `screenshots/${TAG}-${name}.png` });
	console.log('shot', `${TAG}-${name}`);
};
const wait = (ms) => page.waitForTimeout(ms);

await page.goto(BASE, { waitUntil: 'networkidle' });
await wait(1000);
if (await page.locator('input[type=password]').count()) {
	await shot('01-login');
	await page
		.locator('input')
		.first()
		.fill(EMAIL)
		.catch(() => {});
	await page.fill('input[type=password]', PASS).catch(() => {});
	await page
		.getByRole('button', { name: /log in/i })
		.first()
		.click()
		.catch(() => {});
	await wait(2800);
	// If login failed (e.g. fresh DB / deleted test user), sign up instead.
	if (await page.locator('input[type=password]').count()) {
		await page
			.getByRole('button', { name: /^sign up$/i })
			.first()
			.click()
			.catch(() => {}); // toggle link
		await wait(300);
		await page
			.locator('input')
			.first()
			.fill(EMAIL)
			.catch(() => {});
		await page.fill('input[type=password]', PASS).catch(() => {});
		await page
			.getByRole('button', { name: /^sign up$/i })
			.first()
			.click()
			.catch(() => {}); // submit
		await wait(2800);
	}
}
await wait(800);
await shot('02-menu');

// Daily board
await page
	.getByRole('button', { name: /daily puzzle/i })
	.click()
	.catch((e) => console.log('daily click', e.message));
await wait(2500);
await shot('03-daily-board');

// Buy a letter: tap E, then confirm
await page
	.locator('.key:has(.letter:text-is("E"))')
	.first()
	.click({ force: true })
	.catch((e) => console.log('key E', e.message));
await wait(600);
await shot('04-letter-pending');
await page
	.getByRole('button', { name: /^confirm$/i })
	.click({ force: true })
	.catch((e) => console.log('confirm', e.message));
await wait(1800);
await shot('05-after-letter');

// Enter guess mode (Solve), screenshot
await page
	.getByRole('button', { name: /^solve$/i })
	.click({ force: true })
	.catch(() => {});
await wait(800);
await shot('06-guess-mode');

// Leaderboard
await page.goto(`${BASE}/leaderboard`, { waitUntil: 'networkidle' });
await wait(2000);
await shot('07-leaderboard');

await browser.close();
console.log('done');
