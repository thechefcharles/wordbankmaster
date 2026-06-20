// Screenshot the rewritten tutorial step 1 and the tidied My Account (no power-ups).
import { chromium } from 'playwright';
const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL = 'pwtest+wb@example.com', PASS = 'TestPass123!';
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 430, height: 900 } })).newPage();
p.setDefaultTimeout(6000);
const wait = (ms) => p.waitForTimeout(ms);
const log = (...a) => console.log(...a);
const errs = []; p.on('pageerror', e => errs.push(String(e)));
try {
  await p.goto(BASE, { waitUntil: 'networkidle' }); await wait(700);
  await p.evaluate(() => localStorage.removeItem('wb_tutorial_seen'));
  if (await p.locator('input[type=password]').count()) {
    await p.fill('input[type=email]', EMAIL); await p.fill('input[type=password]', PASS);
    await p.getByRole('button', { name: /log in/i }).first().click().catch(()=>{}); await wait(2600);
  }
  await p.evaluate(() => localStorage.removeItem('wb_tutorial_seen'));
  await p.reload({ waitUntil: 'networkidle' }); await wait(2200);
  log('tutorial title:', await p.locator('.tut-title').innerText().catch(()=>'—'));
  log('tutorial body:', await p.locator('.tut-body').innerText().catch(()=>'—'));
  await p.screenshot({ path: 'screenshots/tut-step1.png' });
  await p.locator('.tut-skip').click().catch(()=>{}); await wait(500);
  // Open My Account
  await p.getByRole('button', { name: /my account/i }).first().click().catch(()=>{}); await wait(1500);
  log('account has Power-ups section:', await p.getByText(/^Power-ups$/).count() > 0, '(want false)');
  log('account has Badges section:', await p.getByText(/Badges/).count() > 0);
  await p.screenshot({ path: 'screenshots/account.png' });
  log('page errors:', errs.length, errs.slice(0,3));
} catch (e) {
  log('FATAL', e.message);
} finally {
  await b.close();
  log('done');
}
