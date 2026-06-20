// Phase 2 — verify the 3 earned power-ups render and their effects fire.
// Requires a seeded active arcade run with inventory {multiplier_boost, double_payout, extra_guess}.
import { chromium } from 'playwright';
const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL = 'pwtest+wb@example.com', PASS = 'TestPass123!';
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 430, height: 900 } })).newPage();
p.setDefaultTimeout(6000);
const wait = (ms) => p.waitForTimeout(ms);
const log = (...a) => console.log(...a);
const cell = async (label) => (await p.locator('.ah-cell', { hasText: label }).locator('.ah-val').innerText().catch(()=>'?')).replace(/\s+/g,' ').trim();
try {
  await p.goto(BASE, { waitUntil: 'networkidle' }); await wait(700);
  await p.evaluate(() => localStorage.setItem('wb_tutorial_seen', 'true'));
  if (await p.locator('input[type=password]').count()) {
    await p.fill('input[type=email]', EMAIL); await p.fill('input[type=password]', PASS);
    await p.getByRole('button', { name: /log in/i }).first().click().catch(()=>{}); await wait(2600);
  }
  await p.getByRole('button', { name: /arcade/i }).first().click().catch((e)=>log('arcade click', e.message));
  await wait(2600);
  log('chips:', await p.locator('.pu-chip').count(), '(expect 3)');
  const emojis = await p.locator('.pu-chip .pu-emoji').allInnerTexts();
  log('chip emojis:', JSON.stringify(emojis));
  log('Streak before:', await cell('Streak'), '· Solve before:', await cell('Solve'));
  // Spend ⚡ Multiplier Boost -> +0.5x streak, payout +$250
  await p.locator('.pu-chip', { hasText: '⚡' }).first().click().catch(()=>{}); await wait(1200);
  log('Streak after ⚡:', await cell('Streak'), '· Solve after ⚡:', await cell('Solve'), '(expect ×1.50 · +$750)');
  // Arm 💎 Double Payout -> ON
  await p.locator('.pu-chip', { hasText: '💎' }).first().click().catch(()=>{}); await wait(1200);
  log('💎 armed:', await p.locator('.pu-chip.armed', { hasText: '💎' }).count() > 0, '(expect true)');
  log('remaining chips:', await p.locator('.pu-chip').count());
  await p.screenshot({ path: 'screenshots/phase2.png' });
} catch (e) {
  log('FATAL', e.message);
} finally {
  await b.close();
  log('done');
}
