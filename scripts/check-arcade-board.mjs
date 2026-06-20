// Verify the arcade leaderboard tab renders banked/furthest columns.
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
await p.goto(BASE + '/leaderboard?mode=arcade', { waitUntil: 'networkidle' }); await wait(1500);
await p.getByRole('button', { name: /^arcade$/i }).first().click().catch(()=>{}); await wait(1500);
console.log('headers:', await p.locator('table thead th').allInnerTexts().catch(()=>[]));
console.log('period btns:', await p.locator('.period-filters .period-btn').allInnerTexts().catch(()=>[]));
console.log('sort filters present:', await p.locator('.sort-filters').count());
console.log('first row:', await p.locator('table tbody tr').first().allInnerTexts().catch(()=>['—']));
await p.screenshot({ path: 'screenshots/arcade-board.png', fullPage: true });
await b.close();
