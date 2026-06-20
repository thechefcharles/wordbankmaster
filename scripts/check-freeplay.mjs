// Verify Free Play: menu card -> category grid -> pick category -> board + clue.
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
  await p.evaluate(() => localStorage.setItem('wb_tutorial_seen', 'true'));
  if (await p.locator('input[type=password]').count()) {
    await p.fill('input[type=email]', EMAIL); await p.fill('input[type=password]', PASS);
    await p.getByRole('button', { name: /log in/i }).first().click().catch(()=>{}); await wait(2600);
  }
  await p.getByRole('button', { name: /free play/i }).first().click().catch((e)=>log('freeplay click', e.message));
  await wait(800);
  log('category grid shown:', await p.locator('.cat-grid').count() > 0, ' tiles:', await p.locator('.cat-tile').count());
  await p.screenshot({ path: 'screenshots/freeplay-cats.png' });
  await p.locator('.cat-tile', { hasText: 'Movies & TV' }).first().click().catch(()=>{}); await wait(2600);
  log('board keys:', await p.locator('.key').count());
  log('clue:', await p.locator('.puzzle-clue').innerText().catch(()=>'—'));
  log('category chip:', await p.locator('.category-chip').innerText().catch(()=>'—'));
  await p.screenshot({ path: 'screenshots/freeplay-board.png' });
  // Buy a couple letters to confirm it plays
  for (const L of ['E','A']) {
    await p.locator(`.key:has(.letter:text-is("${L}"))`).first().click({ force: true }).catch(()=>{}); await wait(250);
    await p.getByRole('button', { name: /^confirm$/i }).click({ force: true }).catch(()=>{}); await wait(900);
  }
  log('played 2 letters ok, errors:', errs.length, errs.slice(0,3));
} catch (e) { log('FATAL', e.message); } finally { await b.close(); log('done'); }
