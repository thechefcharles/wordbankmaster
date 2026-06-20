// Confirm the arcade HUD shows just the puzzle number (no "/29" cap).
import { chromium } from 'playwright';
const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL = 'pwtest+wb@example.com', PASS = 'TestPass123!';
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 430, height: 900 } })).newPage();
p.setDefaultTimeout(6000);
const wait = (ms) => p.waitForTimeout(ms);
try {
  await p.goto(BASE, { waitUntil: 'networkidle' }); await wait(700);
  await p.evaluate(() => localStorage.setItem('wb_tutorial_seen', 'true'));
  if (await p.locator('input[type=password]').count()) {
    await p.fill('input[type=email]', EMAIL); await p.fill('input[type=password]', PASS);
    await p.getByRole('button', { name: /log in/i }).first().click().catch(()=>{}); await wait(2600);
  }
  await p.getByRole('button', { name: /arcade/i }).first().click().catch(()=>{}); await wait(2600);
  const cells = await p.locator('.arcade-hud .ah-cell').allInnerTexts().catch(()=>[]);
  console.log('HUD cells:', JSON.stringify(cells));
  await p.screenshot({ path: 'screenshots/hud.png' });
} catch (e) { console.log('FATAL', e.message); } finally { await b.close(); console.log('done'); }
