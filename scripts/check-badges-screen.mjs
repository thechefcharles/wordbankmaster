// Screenshot the Badges screen (category levels + achievements).
import { chromium } from 'playwright';
const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL = 'pwtest+wb@example.com', PASS = 'TestPass123!';
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 430, height: 1100 } })).newPage();
p.setDefaultTimeout(6000);
const wait = (ms) => p.waitForTimeout(ms);
const log = (...a) => console.log(...a);
try {
  await p.goto(BASE, { waitUntil: 'networkidle' }); await wait(700);
  await p.evaluate(() => localStorage.setItem('wb_tutorial_seen', 'true'));
  if (await p.locator('input[type=password]').count()) {
    await p.fill('input[type=email]', EMAIL); await p.fill('input[type=password]', PASS);
    await p.getByRole('button', { name: /log in/i }).first().click().catch(()=>{}); await wait(2600);
  }
  await p.locator('.menu-card:has(.mc-title:text-is("Badges"))').first().click().catch((e)=>log('badges click', e.message));
  await wait(1500);
  log('badges modal:', await p.locator('.badges-page').count() > 0);
  log('total line:', await p.locator('.badges-total').innerText().catch(()=>'—'));
  log('category rows:', await p.locator('.bm-cat').count());
  log('Movies tier:', await p.locator('.bm-cat', { hasText: 'Movies & TV' }).locator('.bm-cat-tier').innerText().catch(()=>'—'));
  log('Tech tier:', await p.locator('.bm-cat', { hasText: 'Tech & Internet' }).locator('.bm-cat-tier').innerText().catch(()=>'—'));
  log('achievements:', await p.locator('.bm-ach').count(), ' earned:', await p.locator('.bm-ach.earned').count());
  await p.screenshot({ path: 'screenshots/badges.png', fullPage: true });
} catch (e) { log('FATAL', e.message); } finally { await b.close(); log('done'); }
