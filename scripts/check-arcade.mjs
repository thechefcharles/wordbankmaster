// Verify the arcade gauntlet: HUD + play to a solve/bust transition + continue.
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
await p.getByRole('button', { name: /arcade/i }).first().click().catch(e=>console.log('arcade', e.message));
await wait(2600);
console.log('arcade HUD present:', await p.locator('.arcade-hud').count() > 0,
            ' cells:', await p.locator('.ah-cell .ah-val').allInnerTexts().catch(()=>[]));
await p.screenshot({ path: 'screenshots/arcade-1-board.png' });
// Buy letters down the alphabet until the puzzle resolves
const letters = 'EARSTONILCDUMPHGBYFVKWZXJQ'.split('');
for (const L of letters) {
  if (await p.locator('.result-modal').count()) break;
  await p.locator(`.key:has(.letter:text-is("${L}"))`).first().click({ force: true }).catch(()=>{}); await wait(300);
  await p.getByRole('button', { name: /^confirm$/i }).click({ force: true }).catch(()=>{}); await wait(1200);
}
await wait(700);
await p.screenshot({ path: 'screenshots/arcade-2-transition.png' });
console.log('transition modal:', await p.locator('.result-modal h2').innerText().catch(()=>'—'));
await b.close();
