// Measure the fixed bottom UI (keyboard / action buttons / wager bar) and screenshot
// the game on mobile + desktop, in both daily and arcade(+wager) states.
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';

const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL = process.env.PW_EMAIL || 'pwtest+wb@example.com';
const PASS = process.env.PW_PASS || 'TestPass123!';
mkdirSync('screenshots', { recursive: true });

const viewports = [
  { tag: 'mobile', width: 390, height: 844 },
  { tag: 'desktop', width: 1440, height: 900 },
];

async function login(page) {
  await page.goto(BASE, { waitUntil: 'networkidle' });
  await page.waitForTimeout(900);
  if (await page.locator('input[type=password]').count()) {
    await page.fill('input[type=email]', EMAIL).catch(() => {});
    await page.fill('input[type=password]', PASS).catch(() => {});
    await page.getByRole('button', { name: /log in/i }).first().click().catch(() => {});
    await page.waitForTimeout(2600);
    if (await page.locator('input[type=password]').count()) {
      await page.getByRole('button', { name: /^sign up$/i }).first().click().catch(() => {});
      await page.waitForTimeout(300);
      await page.fill('input[type=email]', EMAIL).catch(() => {});
      await page.fill('input[type=password]', PASS).catch(() => {});
      await page.getByRole('button', { name: /^sign up$/i }).first().click().catch(() => {});
      await page.waitForTimeout(2600);
    }
  }
}

async function boxes(page, vh) {
  const sel = { keyboard: '.keyboard-container', buttons: '.main-button-wrapper', wager: '.wager-ui', solve: '.guess-phrase-button' };
  const out = {};
  for (const [k, s] of Object.entries(sel)) {
    const el = page.locator(s).first();
    if (await el.count()) {
      const b = await el.boundingBox();
      if (b) out[k] = { top: Math.round(b.y), bottom: Math.round(b.y + b.height), h: Math.round(b.height), gapBelow: Math.round(vh - (b.y + b.height)) };
    }
  }
  return out;
}

for (const vp of viewports) {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: vp.width, height: vp.height }, deviceScaleFactor: 1 });
  const page = await ctx.newPage();
  await login(page);

  // Daily
  await page.getByRole('button', { name: /daily/i }).first().click().catch(() => {});
  await page.waitForTimeout(2600);
  await page.screenshot({ path: `screenshots/fix-${vp.tag}-daily.png` });
  console.log(`\n[${vp.tag} ${vp.width}x${vp.height}] daily:`, JSON.stringify(await boxes(page, vp.height)));

  // Arcade gauntlet — start today's run from the menu (server-authoritative, no wager)
  await page.goto(BASE, { waitUntil: 'networkidle' });
  await page.waitForTimeout(1000);
  await page.getByRole('button', { name: /arcade/i }).first().click().catch(() => {});
  await page.waitForTimeout(3000);
  await page.screenshot({ path: `screenshots/fix-${vp.tag}-arcade.png` });
  console.log(`[${vp.tag}] arcade:`, JSON.stringify(await boxes(page, vp.height)));

  await browser.close();
}
console.log('\ndone');
