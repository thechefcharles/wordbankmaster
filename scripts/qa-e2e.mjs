// End-to-end QA sweep: signup → gates → page sweep (console-error/hang detection) →
// play a Daily to a real solve. Run: BASE=http://localhost:5174 node scripts/qa-e2e.mjs
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';

const BASE = process.env.BASE || 'http://localhost:5174';
const PASS = 'TestPass123!';
const EMAIL = process.env.QA_EMAIL || `qa${Date.now()}@example.com`;
const UNAME = 'qa' + String(Date.now()).slice(-7);
const DAILY = (process.env.DAILY_ANSWER || 'The Northern Lights').toUpperCase().replace(/[^A-Z]/g, '');
mkdirSync('screenshots', { recursive: true });

const results = [];
const ok = (n, m = '') => { results.push({ n, pass: true, m }); console.log(`  ✅ ${n}${m ? ' — ' + m : ''}`); };
const bad = (n, m = '') => { results.push({ n, pass: false, m }); console.log(`  ❌ ${n}${m ? ' — ' + m : ''}`); };

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 430, height: 932 }, deviceScaleFactor: 2 });
const page = await ctx.newPage();

// collect console errors + page errors per current label
let label = 'boot';
const errors = [];
page.on('console', (m) => { if (m.type() === 'error') errors.push({ where: label, text: m.text().slice(0, 200) }); });
page.on('pageerror', (e) => errors.push({ where: label, text: 'pageerror: ' + String(e).slice(0, 200) }));

const wait = (ms) => page.waitForTimeout(ms);
const shot = (n) => page.screenshot({ path: `screenshots/qa-${n}.png` }).catch(() => {});

try {
  // ---------- 1. Signup ----------
  label = 'signup';
  await page.goto(BASE, { waitUntil: 'networkidle' }); await wait(1200);
  if (!(await page.locator('input[type=password]').count())) { bad('signup', 'no auth form'); }
  else {
    // toggle to sign-up
    await page.getByRole('button', { name: /^sign up$/i }).first().click().catch(() => {});
    await wait(400);
    await page.fill('input[type=email]', EMAIL);
    await page.fill('input[type=password]', PASS);
    await page.getByRole('button', { name: /^sign up$/i }).first().click().catch(() => {});
    await wait(3500);
    (await page.locator('input[type=password]').count()) === 0 ? ok('signup', EMAIL) : bad('signup', 'still on auth form');
  }

  // ---------- 2. Username gate ----------
  label = 'username-gate';
  await wait(600);
  const claim = page.locator('input.claim-input');
  if (await claim.count()) {
    await claim.fill(UNAME);
    await page.locator('button.claim-btn').click().catch(() => {});
    await wait(1800);
    (await claim.count()) === 0 ? ok('username-gate', '@' + UNAME) : bad('username-gate', 'gate did not clear');
  } else bad('username-gate', 'no username prompt appeared');

  // ---------- 3. PIN gate (skip) ----------
  label = 'pin-gate';
  const skipPin = page.getByRole('button', { name: /skip for now/i });
  if (await skipPin.count()) { await skipPin.first().click().catch(() => {}); await wait(900); ok('pin-gate', 'skipped'); }
  else ok('pin-gate', 'no PIN prompt (ok)');

  // dismiss tutorial
  const skipTut = page.getByRole('button', { name: /^skip$/i });
  if (await skipTut.count()) { await skipTut.first().click().catch(() => {}); await wait(700); }
  await wait(600); await shot('01-menu');
  (await page.locator('.menu-card').count()) > 0 ? ok('reach-menu') : bad('reach-menu', 'no menu cards');

  // ---------- 4. Page sweep (console-error / hang detection) ----------
  const pages = ['/history', '/activity', '/leaderboard', '/groups', '/profile', '/badges', '/bank', '/streak', '/friends', '/shop'];
  for (const path of pages) {
    label = path;
    const before = errors.length;
    try {
      await page.goto(`${BASE}${path}`, { waitUntil: 'networkidle', timeout: 12000 });
      await wait(1200);
      const newErrs = errors.length - before;
      const bodyLen = (await page.locator('body').innerText().catch(() => '')).length;
      if (newErrs > 0) bad(`page ${path}`, `${newErrs} console error(s)`);
      else if (bodyLen < 5) bad(`page ${path}`, 'empty render');
      else ok(`page ${path}`);
    } catch (e) {
      bad(`page ${path}`, (e.message || '').includes('Timeout') ? 'HANG / networkidle timeout (possible loop)' : e.message.slice(0, 80));
    }
  }

  // ---------- 5. Play the Daily to a solve ----------
  label = 'daily';
  await page.goto(BASE, { waitUntil: 'networkidle' }); await wait(1500);
  // PIN should NOT reappear after skipping (regression guard for the persist-skip fix)
  if (await page.getByText(/create your pin/i).count()) bad('pin-skip-persists', 'PIN re-nagged after skip + reload');
  else ok('pin-skip-persists');
  const sk2 = page.getByRole('button', { name: /skip for now/i });
  if (await sk2.count()) { await sk2.first().click().catch(() => {}); await wait(700); }
  const st2 = page.getByRole('button', { name: /^skip$/i });
  if (await st2.count()) { await st2.first().click().catch(() => {}); await wait(600); }
  await page.getByRole('button', { name: /play now/i }).first().click().catch(() => {});
  await wait(700);
  await page.getByRole('button', { name: /daily/i }).first().click().catch(() => {});
  await wait(2800); await shot('02-daily-board');
  if (!(await page.getByRole('button', { name: /^solve$/i }).count())) { bad('daily-open', 'no Solve button — board did not load'); }
  else {
    ok('daily-open');
    await page.getByRole('button', { name: /^solve$/i }).first().click().catch(() => {}); // enter guess mode
    await wait(700);
    for (const ch of DAILY) { await page.keyboard.press(ch); await wait(70); }
    await wait(500); await shot('03-daily-filled');
    await page.getByRole('button', { name: /^submit$/i }).first().click().catch(() => {});
    await wait(2600); await shot('04-daily-result');
    const won = await page.getByText(/solved!/i).count();
    won > 0 ? ok('daily-solve', 'win modal shown') : bad('daily-solve', 'no win modal after submit');
  }

  // ---------- 6. Verify it landed in History ----------
  label = 'history-verify';
  // close result modal first
  await page.keyboard.press('Escape').catch(() => {});
  await page.goto(`${BASE}/history`, { waitUntil: 'networkidle' }); await wait(1600);
  const items = await page.locator('.item').count();
  items > 0 ? ok('history-verify', `${items} row(s)`) : bad('history-verify', 'history empty after a solve');
  await shot('05-history');

} catch (e) {
  bad('fatal', e.message);
} finally {
  await browser.close();
}

console.log('\n──────── QA SUMMARY ────────');
const fails = results.filter((r) => !r.pass);
for (const r of results) console.log(`${r.pass ? '✅' : '❌'} ${r.n}${r.m ? ' — ' + r.m : ''}`);
if (errors.length) { console.log('\nConsole errors:'); for (const e of errors.slice(0, 20)) console.log(`  [${e.where}] ${e.text}`); }
console.log(`\n${results.filter(r => r.pass).length}/${results.length} passed · ${fails.length} failed · ${errors.length} console errors`);
console.log('QA_EMAIL=' + EMAIL);
process.exit(fails.length ? 1 : 0);
