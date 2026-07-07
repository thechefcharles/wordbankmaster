import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';
mkdirSync('screenshots', { recursive: true });
const BASE = process.env.BASE || 'http://localhost:5173';
const PHASE = process.env.PHASE || 'setup';
const ACC = { email: 'mka@example.com', pass: 'TestPass123!', user: 'mkalice' };
const ANSWER = 'THEICEAGE';
const b = await chromium.launch();
const c = await b.newContext({ viewport: { width: 430, height: 932 }, deviceScaleFactor: 2 });
const p = await c.newPage();
const w = (ms) => p.waitForTimeout(ms);
async function gates() {
	const sk = p.getByRole('button', { name: /skip for now/i });
	if (await sk.count()) {
		await sk
			.first()
			.click()
			.catch(() => {});
		await w(500);
	}
	const st = p.getByRole('button', { name: /^skip$/i });
	if (await st.count()) {
		await st
			.first()
			.click()
			.catch(() => {});
		await w(400);
	}
}
await p.goto(BASE, { waitUntil: 'networkidle' });
await w(1000);
if (PHASE === 'setup') {
	await p
		.getByRole('button', { name: /^sign up$/i })
		.first()
		.click()
		.catch(() => {});
	await w(300);
	await p.locator('input').first().fill(ACC.email);
	await p.fill('input[type=password]', ACC.pass);
	await p
		.getByRole('button', { name: /^sign up$/i })
		.first()
		.click()
		.catch(() => {});
	await w(3500);
	const claim = p.locator('input.claim-input');
	if (await claim.count()) {
		await claim.fill(ACC.user);
		await p
			.locator('button.claim-btn')
			.click()
			.catch(() => {});
		await w(1800);
	}
	await gates();
	console.log('SETUP_DONE');
}
if (PHASE === 'play') {
	if (await p.locator('input[type=password]').count()) {
		await p.locator('input').first().fill(ACC.user);
		await p.fill('input[type=password]', ACC.pass);
		await p
			.getByRole('button', { name: /log in/i })
			.first()
			.click();
		await w(3000);
	}
	await gates();
	// bankroll shown on the menu top chip
	const menuBank = await p
		.locator('text=/\\$[0-9,]+/')
		.first()
		.innerText()
		.catch(() => '?');
	console.log('menu bankroll:', menuBank);
	await p.goto(`${BASE}/streak`, { waitUntil: 'networkidle' });
	await w(1500);
	await p.screenshot({ path: 'screenshots/mk-01-calendar.png' });
	// tap day 22 (a makeable past day → "The Ice Age")
	await p
		.locator('.cell.playable', { has: p.locator('.cell-day', { hasText: /^22$/ }) })
		.first()
		.click()
		.catch(async () => {
			await p
				.locator('.cell.playable')
				.first()
				.click()
				.catch(() => {});
		});
	await w(2800);
	await p.screenshot({ path: 'screenshots/mk-02-board.png' });
	const clue = await p
		.locator('.puzzle-clue')
		.innerText()
		.catch(() => '(no clue)');
	const boardBank = await p
		.locator('text=/\\$[0-9,]+/')
		.first()
		.innerText()
		.catch(() => '?');
	console.log('makeup clue:', clue);
	console.log('makeup board bankroll:', boardBank);
	// solve
	await p
		.getByRole('button', { name: /^solve$/i })
		.first()
		.click()
		.catch(async () => {
			await p.keyboard.press(' ');
		});
	await w(700);
	for (const ch of ANSWER) {
		await p.keyboard.press(ch);
		await w(70);
	}
	await w(400);
	await p
		.getByRole('button', { name: /^submit$/i })
		.first()
		.click()
		.catch(async () => {
			await p.keyboard.press('Enter');
		});
	await w(2600);
	await p.screenshot({ path: 'screenshots/mk-03-result.png' });
	console.log('PLAY_DONE');
}
await b.close();
