// Verify the new daily Reveal: reveals a full letter and charges $150.
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

const revealed = async () => p.locator('.letter-box.locked').count();
const tries = async () => (await p.locator('.guesses-count').innerText().catch(()=>'?')).trim();

await p.screenshot({ path: 'screenshots/rev-1-fresh.png' });
console.log('fresh:   revealedTiles=', await revealed(), ' tries=', await tries());

await p.locator('.hint-button').click({ force: true }).catch(e=>console.log('reveal click', e.message)); await wait(500);
await p.screenshot({ path: 'screenshots/rev-2-pending.png' });

await p.getByRole('button', { name: /^confirm$/i }).click({ force: true }).catch(e=>console.log('confirm', e.message)); await wait(1800);
await p.screenshot({ path: 'screenshots/rev-3-after.png' });
console.log('after:   revealedTiles=', await revealed(), ' tries=', await tries());
await b.close();
