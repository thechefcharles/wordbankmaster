// Screenshot every tutorial step + log title/body so the full arc can be reviewed.
import { chromium } from 'playwright';
const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL = 'pwtest+wb@example.com', PASS = 'TestPass123!';
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 430, height: 900 } })).newPage();
p.setDefaultTimeout(6000);
const wait = (ms) => p.waitForTimeout(ms);
try {
  await p.goto(BASE, { waitUntil: 'networkidle' }); await wait(700);
  await p.evaluate(() => localStorage.removeItem('wb_tutorial_seen'));
  if (await p.locator('input[type=password]').count()) {
    await p.fill('input[type=email]', EMAIL); await p.fill('input[type=password]', PASS);
    await p.getByRole('button', { name: /log in/i }).first().click().catch(()=>{}); await wait(2600);
  }
  await p.evaluate(() => localStorage.removeItem('wb_tutorial_seen'));
  await p.reload({ waitUntil: 'networkidle' }); await wait(2200);
  for (let s = 1; s <= 5; s++) {
    const t = await p.locator('.tut-title').innerText().catch(()=>'—');
    const body = await p.locator('.tut-body').innerText().catch(()=>'—');
    console.log(`STEP ${s}: ${t} :: ${body}`);
    await p.screenshot({ path: `screenshots/tut-${s}.png` });
    await p.locator('.tut-btn.primary').click().catch(()=>{}); await wait(450);
  }
  // After finishing, the menu shows — capture the tagline.
  await wait(600);
  console.log('menu tagline:', await p.locator('.menu-tagline').innerText().catch(()=>'—'));
  await p.screenshot({ path: 'screenshots/menu-tagline.png' });
} catch (e) {
  console.log('FATAL', e.message);
} finally {
  await b.close();
  console.log('done');
}
