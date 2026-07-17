// 1v1 challenge walkthrough. Phases via env PHASE: setup | create | play | results.
// Fixed creds so phases coordinate; clean up vsa@/vsb@ after.
import { chromium } from 'playwright';
import { qaBase } from './_qa-guard.mjs';
import { mkdirSync } from 'node:fs';
mkdirSync('screenshots', { recursive: true });

const BASE = qaBase('http://localhost:5173');
const PHASE = process.env.PHASE || 'setup';
const ANSWER = (process.env.ANSWER || '').toUpperCase().replace(/[^A-Z]/g, '');
const A = { email: 'vsa@example.com', pass: 'TestPass123!', user: 'vsalice' };
const B = { email: 'vsb@example.com', pass: 'TestPass123!', user: 'vsbob' };
const log = (...a) => console.log('  ', ...a);

const browser = await chromium.launch();
const ctx = () =>
	browser.newContext({ viewport: { width: 430, height: 932 }, deviceScaleFactor: 2 });
const wait = (p, ms) => p.waitForTimeout(ms);

async function dismissGates(p) {
	const sk = p.getByRole('button', { name: /skip for now/i });
	if (await sk.count()) {
		await sk
			.first()
			.click()
			.catch(() => {});
		await wait(p, 600);
	}
	const st = p.getByRole('button', { name: /^skip$/i });
	if (await st.count()) {
		await st
			.first()
			.click()
			.catch(() => {});
		await wait(p, 500);
	}
}
async function signup(p, acc) {
	await p.goto(BASE, { waitUntil: 'networkidle' });
	await wait(p, 1000);
	await p
		.getByRole('button', { name: /^sign up$/i })
		.first()
		.click()
		.catch(() => {});
	await wait(p, 300);
	await p.locator('input').first().fill(acc.email);
	await p.fill('input[type=password]', acc.pass);
	await p
		.getByRole('button', { name: /^sign up$/i })
		.first()
		.click()
		.catch(() => {});
	await wait(p, 3500);
	const claim = p.locator('input.claim-input');
	if (await claim.count()) {
		await claim.fill(acc.user);
		await p
			.locator('button.claim-btn')
			.click()
			.catch(() => {});
		await wait(p, 1800);
	}
	await dismissGates(p);
}
async function login(p, acc) {
	await p.goto(BASE, { waitUntil: 'networkidle' });
	await wait(p, 1000);
	if (await p.locator('input[type=password]').count()) {
		await p.locator('input').first().fill(acc.user);
		await p.fill('input[type=password]', acc.pass);
		await p
			.getByRole('button', { name: /log in/i })
			.first()
			.click();
		await wait(p, 3000);
	}
	await dismissGates(p);
}
// buy `wrong` letters (not in the answer → pure spend, keeps all tiles editable), then solve.
async function playSolve(p, answer, wrong) {
	// Dismiss the pre-game "How to win" objective card (shown on every match entry).
	const objGo = p.getByRole('button', { name: /let’s go|let's go/i });
	if (await objGo.count()) {
		await objGo
			.first()
			.click()
			.catch(() => {});
		await wait(p, 500);
	}
	for (const L of wrong) {
		await p.keyboard.press(L);
		await wait(p, 250);
		await p.keyboard.press('Enter');
		await wait(p, 900);
	}
	// enter guess mode
	await p
		.getByRole('button', { name: /^solve$/i })
		.first()
		.click()
		.catch(async () => {
			await p.keyboard.press(' ');
		});
	await wait(p, 700);
	for (const ch of answer) {
		await p.keyboard.press(ch);
		await wait(p, 60);
	}
	await wait(p, 400);
	await p
		.getByRole('button', { name: /^submit$/i })
		.first()
		.click()
		.catch(async () => {
			await p.keyboard.press('Enter');
		});
	await wait(p, 2500);
}
// Community hub → Challenges tab (the inbox of your matches).
async function openChallengeInbox(p) {
	await p
		.locator('.menu-card')
		.filter({ hasText: 'Community' })
		.first()
		.click()
		.catch(() => {});
	await wait(p, 1200);
}
// Community → Challenges → the New-Challenge builder modal.
async function openNewChallenge(p) {
	await openChallengeInbox(p);
	await p
		.getByRole('button', { name: /New Challenge/i })
		.first()
		.click()
		.catch(() => {});
	await wait(p, 1000);
}

// ──────────────────────────────────────────────────────────────
if (PHASE === 'setup') {
	const ca = await ctx();
	const pa = await ca.newPage();
	await signup(pa, A);
	log('A signed up', A.user);
	const cb = await ctx();
	const pb = await cb.newPage();
	await signup(pb, B);
	log('B signed up', B.user);
	console.log('SETUP_DONE');
}

if (PHASE === 'create') {
	const c = await ctx();
	const p = await c.newPage();
	await login(p, A);
	await openNewChallenge(p);
	await p.locator('input.ch-input').first().fill(B.user);
	await wait(p, 800);
	// pack size 1
	await p
		.locator('select.ch-input')
		.first()
		.selectOption('1')
		.catch(() => {});
	// wager 500
	await p
		.locator('input[type=number].ch-input')
		.first()
		.fill('500')
		.catch(() => {});
	await wait(p, 400);
	await p
		.getByRole('button', { name: /send challenge/i })
		.first()
		.click()
		.catch(() => {});
	await wait(p, 2500);
	await p.screenshot({ path: 'screenshots/vs-01-created.png' });
	console.log('CREATE_DONE');
}

if (PHASE === 'play') {
	// wrong letters not in the answer
	const pool = 'QZXJKVWBYG'.split('').filter((L) => !ANSWER.includes(L));
	// B accepts + plays (spends more → loses)
	const cb = await ctx();
	const pb = await cb.newPage();
	await login(pb, B);
	await openChallengeInbox(pb);
	await pb
		.getByRole('button', { name: /^play$/i })
		.first()
		.click()
		.catch(() => {});
	await wait(pb, 2600);
	await pb.screenshot({ path: 'screenshots/vs-02-B-board.png' });
	await playSolve(pb, ANSWER, pool.slice(0, 4)); // B buys 4 wrong letters
	await pb.screenshot({ path: 'screenshots/vs-03-B-after.png' });
	log('B played');
	// A plays (spends less → wins)
	const ca = await ctx();
	const pa = await ca.newPage();
	await login(pa, A);
	await openChallengeInbox(pa);
	await pa
		.getByRole('button', { name: /^(play|resume)$/i })
		.first()
		.click()
		.catch(() => {});
	await wait(pa, 2600);
	await playSolve(pa, ANSWER, pool.slice(0, 1)); // A buys 1 wrong letter
	await pa.screenshot({ path: 'screenshots/vs-04-A-result.png' });
	log('A played');
	console.log('PLAY_DONE');
}

if (PHASE === 'results') {
	const c = await ctx();
	const p = await c.newPage();
	await login(p, A);
	// 1) view results from the challenge inbox
	await openChallengeInbox(p);
	await p.screenshot({ path: 'screenshots/vs-05-inbox.png' });
	await p
		.getByRole('button', { name: /results/i })
		.first()
		.click()
		.catch(() => {});
	await wait(p, 1800);
	await p.screenshot({ path: 'screenshots/vs-06-results-modal.png' });
	// 2) History (Profile → History tab)
	await p.goto(`${BASE}/history`, { waitUntil: 'networkidle' });
	await wait(p, 1600);
	await p.screenshot({ path: 'screenshots/vs-07-history.png' });
	// 3) Profile stats
	await p.goto(`${BASE}/profile`, { waitUntil: 'networkidle' });
	await wait(p, 1500);
	await p.screenshot({ path: 'screenshots/vs-08-profile.png' });
	// 4) Leaderboard challenges
	await p.goto(`${BASE}/leaderboard?board=challenges`, { waitUntil: 'networkidle' });
	await wait(p, 1600);
	await p
		.getByRole('button', { name: /challenges/i })
		.first()
		.click()
		.catch(() => {});
	await wait(p, 1200);
	await p.screenshot({ path: 'screenshots/vs-09-leaderboard.png' });
	// 5) Activity
	await p.goto(`${BASE}/activity`, { waitUntil: 'networkidle' });
	await wait(p, 1600);
	await p.screenshot({ path: 'screenshots/vs-10-activity.png' });
	console.log('RESULTS_DONE');
}

await browser.close();
