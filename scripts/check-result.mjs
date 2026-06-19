// Force a daily result modal by buying Reveals until win-by-reveal (or bust), then shoot it.
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

// Buy letters down the alphabet until the puzzle resolves (solved → win, or broke → loss)
const letters = 'EARSTONILCDUMPHGBYFVKWZXJQ'.split('');
for (const L of letters) {
  if (await p.locator('.result-modal').count()) break;
  const key = p.locator(`.key:has(.letter:text-is("${L}"))`).first();
  await key.click({ force: true }).catch(()=>{}); await wait(300);
  await p.getByRole('button', { name: /^confirm$/i }).click({ force: true }).catch(()=>{}); await wait(1300);
}
await wait(900);
await p.screenshot({ path: 'screenshots/result-modal.png' });
console.log('result-modal present:', await p.locator('.result-modal').count() > 0);
await b.close();
