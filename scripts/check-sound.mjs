// Verify the sound/haptics toggle renders + toggles, and that the game still
// plays without throwing (WebAudio is best-effort under headless chromium).
import { chromium } from 'playwright';
const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL = 'pwtest+wb@example.com', PASS = 'TestPass123!';
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 430, height: 900 } })).newPage();
const errors = [];
p.on('pageerror', (e) => errors.push(String(e)));
p.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
const wait = (ms) => p.waitForTimeout(ms);
await p.goto(BASE, { waitUntil: 'networkidle' }); await wait(900);
if (await p.locator('input[type=password]').count()) {
  await p.fill('input[type=email]', EMAIL); await p.fill('input[type=password]', PASS);
  await p.getByRole('button', { name: /log in/i }).first().click().catch(()=>{}); await wait(2600);
}
const toggle = p.getByRole('button', { name: /toggle sound and haptics/i }).first();
console.log('toggle present:', await toggle.count() > 0, ' label before:', await toggle.innerText().catch(()=>'—'));
await toggle.click().catch(()=>{}); await wait(300);
console.log('label after toggle:', await toggle.innerText().catch(()=>'—'));
await toggle.click().catch(()=>{}); await wait(300); // back to on
console.log('label restored:', await toggle.innerText().catch(()=>'—'));
// Play a couple arcade letters to exercise fx() paths
await p.getByRole('button', { name: /arcade/i }).first().click().catch(()=>{}); await wait(2600);
for (const L of ['E','A','R']) {
  if (await p.locator('.result-modal').count()) break;
  await p.locator(`.key:has(.letter:text-is("${L}"))`).first().click({ force: true }).catch(()=>{}); await wait(250);
  await p.getByRole('button', { name: /^confirm$/i }).click({ force: true }).catch(()=>{}); await wait(900);
}
console.log('arcade HUD present:', await p.locator('.arcade-hud').count() > 0);
console.log('page/console errors:', errors.length, errors.slice(0, 4));
await b.close();
