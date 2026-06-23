// Screenshots for the stats/history/profile/group/activity UI (seeded pwtest account).
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';

const BASE = process.env.BASE || 'http://localhost:5174';
const EMAIL = process.env.PW_EMAIL || 'pwtest+wb@example.com';
const PASS = process.env.PW_PASS || 'TestPass123!';
mkdirSync('screenshots', { recursive: true });

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 430, height: 932 }, deviceScaleFactor: 2 });
const page = await ctx.newPage();
page.on('console', (m) => { if (m.type() === 'error') console.log('  [err]', m.text().slice(0, 140)); });
const shot = async (n) => { await page.screenshot({ path: `screenshots/stats-${n}.png` }); console.log('shot', n); };
const wait = (ms) => page.waitForTimeout(ms);

await page.goto(BASE, { waitUntil: 'networkidle' });
await wait(1200);

// login
if (await page.locator('input[type=password]').count()) {
  await page.fill('input[type=email]', EMAIL).catch(() => {});
  await page.fill('input[type=password]', PASS).catch(() => {});
  await page.getByRole('button', { name: /log in/i }).first().click().catch(() => {});
  await wait(3000);
}
// skip PIN set if shown
const skip = page.getByRole('button', { name: /skip for now/i });
if (await skip.count()) { await skip.first().click().catch(() => {}); await wait(800); }
await wait(1000);
await shot('00-menu');

// Progress submenu (to show new cards)
const prog = page.getByRole('button', { name: /progress/i });
if (await prog.count()) { await prog.first().click().catch(() => {}); await wait(600); await shot('01-progress-menu'); }

// History
await page.goto(`${BASE}/history`, { waitUntil: 'networkidle' }); await wait(1800); await shot('02-history');
// expand a solo (daily) row
await page.locator('.item-main').first().click().catch(() => {}); await wait(700); await shot('03-history-expanded');
// filter to Versus
const versus = page.getByRole('button', { name: /versus/i });
if (await versus.count()) { await versus.first().click().catch(() => {}); await wait(1200); await shot('04-history-versus'); }

// Activity
await page.goto(`${BASE}/activity`, { waitUntil: 'networkidle' }); await wait(1800); await shot('05-activity');

// Public profile + head-to-head
await page.goto(`${BASE}/u/edithpink`, { waitUntil: 'networkidle' }); await wait(1800); await shot('06-profile-h2h');

// Groups → open group → Compete tab
await page.goto(`${BASE}/groups`, { waitUntil: 'networkidle' }); await wait(1600); await shot('07-groups-list');
await page.locator('.g-card, .group-card, [class*=card]').first().click().catch(() => {});
await wait(1400); await shot('08-group-wealth');
const compete = page.getByRole('button', { name: /compete/i });
if (await compete.count()) { await compete.first().click().catch(() => {}); await wait(1400); await shot('09-group-compete'); }

// Leaderboard (clickable names)
await page.goto(`${BASE}/leaderboard`, { waitUntil: 'networkidle' }); await wait(1800); await shot('10-leaderboard');

await browser.close();
console.log('done');
