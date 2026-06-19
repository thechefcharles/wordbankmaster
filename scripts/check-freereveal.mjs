// Verify the Free Reveal power-up: FREE badge on Reveal, and using it reveals a
// letter without charging bankroll.
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
await p.getByRole('button', { name: /daily/i }).first().click().catch(()=>{}); await wait(2600);
const freeBadge = await p.locator('.free-badge').count();
const revealedBefore = await p.locator('.letter-box.locked').count();
console.log('free-badge shown:', freeBadge > 0, ' badge text:', await p.locator('.free-badge').innerText().catch(()=>'—'));
await p.screenshot({ path: 'screenshots/freereveal-1.png' });
// Use Reveal (will be free if a power-up is owned)
await p.locator('.hint-button').click({ force: true }).catch(()=>{}); await wait(400);
await p.getByRole('button', { name: /^confirm$/i }).click({ force: true }).catch(()=>{}); await wait(1600);
await p.screenshot({ path: 'screenshots/freereveal-2.png' });
console.log('free-badge after:', await p.locator('.free-badge').innerText().catch(()=>'—'));
await b.close();
