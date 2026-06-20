// Verify the arcade power-up tray: chips render, spending extra_bank adds $250
// and decrements the chip, and arming double_payout shows the ON state.
// Requires a seeded active arcade run with inventory.
import { chromium } from 'playwright';
const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL = 'pwtest+wb@example.com', PASS = 'TestPass123!';
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 430, height: 900 } })).newPage();
p.setDefaultTimeout(6000);
const wait = (ms) => p.waitForTimeout(ms);
const log = (...a) => console.log(...a);
const bankroll = async () => (await p.locator('.bankroll-amount').innerText().catch(()=>'?')).replace(/\s/g, '');
try {
  await p.goto(BASE, { waitUntil: 'networkidle' }); await wait(700);
  await p.evaluate(() => localStorage.setItem('wb_tutorial_seen', 'true'));
  if (await p.locator('input[type=password]').count()) {
    await p.fill('input[type=email]', EMAIL); await p.fill('input[type=password]', PASS);
    await p.getByRole('button', { name: /log in/i }).first().click().catch(()=>{}); await wait(2600);
  }
  await p.getByRole('button', { name: /arcade/i }).first().click().catch((e)=>log('arcade click', e.message));
  await wait(2600);
  log('tray present:', await p.locator('.pu-tray').count() > 0);
  log('chips:', await p.locator('.pu-chip').count());
  log('bankroll before:', await bankroll());
  // Tap the extra_bank chip (💰) -> +$250
  const bankChip = p.locator('.pu-chip', { hasText: '💰' }).first();
  log('extra_bank count before:', await bankChip.locator('.pu-count').innerText().catch(()=>'?'));
  await bankChip.click().catch(()=>{}); await wait(1200);
  log('bankroll after extra_bank:', await bankroll());
  log('extra_bank count after:', await p.locator('.pu-chip', { hasText: '💰' }).first().locator('.pu-count').innerText().catch(()=>'(gone)'));
  // Arm double_payout (💎) -> ON
  await p.locator('.pu-chip', { hasText: '💎' }).first().click().catch(()=>{}); await wait(1200);
  log('double_payout armed:', await p.locator('.pu-chip.armed', { hasText: '💎' }).count() > 0);
  await p.screenshot({ path: 'screenshots/tray.png' });
} catch (e) {
  log('FATAL', e.message);
} finally {
  await b.close();
  log('done');
}
