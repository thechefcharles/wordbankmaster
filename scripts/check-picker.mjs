// Verify the pre-game power-up picker + extra_bank ($250 start).
import { chromium } from 'playwright';
const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL = 'pwtest+wb@example.com', PASS = 'TestPass123!';
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 430, height: 900 } })).newPage();
const wait = (ms) => p.waitForTimeout(ms);
await p.goto(BASE, { waitUntil: 'networkidle' }); await wait(900);
if (await p.locator('input[type=password]').count()) {
  await p.fill('input[type=email]', EMAIL); await p.fill('input[type=password]', PASS);
  await p.getByRole('button', { name: /log in/i }).first().click().catch(()=>{}); await wait(2600);
  if (await p.locator('input[type=password]').count()) {
    await p.getByRole('button', { name: /^sign up$/i }).first().click().catch(()=>{}); await wait(300);
    await p.fill('input[type=email]', EMAIL); await p.fill('input[type=password]', PASS);
    await p.getByRole('button', { name: /^sign up$/i }).first().click().catch(()=>{}); await wait(2600);
  }
}
// Tap Daily Puzzle -> picker
await p.getByRole('button', { name: /daily/i }).first().click().catch(()=>{}); await wait(1800);
const pickerShown = await p.locator('.picker-list').count() > 0;
console.log('picker shown:', pickerShown, ' items:', await p.locator('.picker-item').count());
await p.screenshot({ path: 'screenshots/picker-1.png' });
// Select +$250 Start then Start
await p.locator('.picker-item', { hasText: '250' }).first().click({ force: true }).catch(e=>console.log('select', e.message)); await wait(400);
await p.getByRole('button', { name: /^start/i }).first().click({ force: true }).catch(e=>console.log('start', e.message)); await wait(2600);
await p.screenshot({ path: 'screenshots/picker-2-board.png' });
await b.close();
