// Screenshot the login + menu with the new logo mark and wordmark.
import { chromium } from 'playwright';
const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL = 'pwtest+wb@example.com', PASS = 'TestPass123!';
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 430, height: 900 } })).newPage();
p.setDefaultTimeout(6000);
const wait = (ms) => p.waitForTimeout(ms);
const errs = []; p.on('pageerror', e => errs.push(String(e)));
try {
  await p.goto(BASE, { waitUntil: 'networkidle' }); await wait(900);
  // Login screen (if shown)
  if (await p.locator('input[type=password]').count()) {
    await p.screenshot({ path: 'screenshots/brand-login.png' });
    await p.fill('input[type=email]', EMAIL); await p.fill('input[type=password]', PASS);
    await p.getByRole('button', { name: /log in/i }).first().click().catch(()=>{}); await wait(2600);
  }
  await p.evaluate(() => localStorage.setItem('wb_tutorial_seen', 'true'));
  await p.reload({ waitUntil: 'networkidle' }); await wait(1800);
  console.log('menu mark img:', await p.locator('img.menu-mark').count(), ' wordmark img:', await p.locator('img.menu-wordmark').count());
  console.log('mark natural size:', await p.locator('img.menu-mark').evaluate(el => el.naturalWidth + 'x' + el.naturalHeight).catch(()=>'?'));
  await p.screenshot({ path: 'screenshots/brand-menu.png' });
  console.log('page errors:', errs.length, errs.slice(0,3));
} catch (e) { console.log('FATAL', e.message); } finally { await b.close(); console.log('done'); }
