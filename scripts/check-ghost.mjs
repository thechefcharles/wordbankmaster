// Verify the "ghost of yesterday" block in the daily result modal.
// Requires DB prep: test user's today daily cleared + a seeded yesterday result.
import { chromium } from 'playwright';
const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL = 'pwtest+wb@example.com', PASS = 'TestPass123!';
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 430, height: 900 } })).newPage();
p.setDefaultTimeout(5000); // fail fast instead of the 30s default
const wait = (ms) => p.waitForTimeout(ms);
const log = (...a) => console.log(...a);
try {
  await p.goto(BASE, { waitUntil: 'networkidle' }); await wait(700);
  await p.evaluate(() => localStorage.setItem('wb_tutorial_seen', 'true'));
  if (await p.locator('input[type=password]').count()) {
    await p.fill('input[type=email]', EMAIL); await p.fill('input[type=password]', PASS);
    await p.getByRole('button', { name: /log in/i }).first().click().catch(()=>{}); await wait(2600);
  }
  log('logged in:', !(await p.locator('input[type=password]').count()));
  await p.getByRole('button', { name: /daily/i }).first().click().catch((e)=>log('daily click err', e.message));
  await wait(1200);
  // A fresh daily with owned pre-game power-ups shows a picker — skip it.
  const skip = p.getByRole('button', { name: /^skip$/i });
  if (await skip.count()) { log('powerup picker shown — skipping'); await skip.click().catch(()=>{}); }
  await wait(2200);
  const keyCount = await p.locator('.key').count();
  log('daily board keys:', keyCount, ' bankroll text:', await p.locator('.bankroll-amount').innerText().catch(()=>'—'));
  const letters = 'EARSTONILCDUMPHGBYFVKWZXJQ'.split('');
  for (let i = 0; i < letters.length; i++) {
    if (await p.locator('.result-modal').count()) { log(`resolved after ${i} buys`); break; }
    const L = letters[i];
    await p.locator(`.key:has(.letter:text-is("${L}"))`).first().click({ force: true }).catch(()=>{}); await wait(200);
    const confirm = p.getByRole('button', { name: /^confirm$/i });
    if (await confirm.count()) { await confirm.click({ force: true }).catch(()=>{}); await wait(900); }
  }
  await wait(1400);
  log('result modal:', await p.locator('.result-modal h2').innerText().catch(()=>'—'));
  log('ghost block present:', await p.locator('.ghost-compare').count() > 0);
  log('ghost line:', await p.locator('.ghost-line').innerText().catch(()=>'—'));
  log('ghost delta:', await p.locator('.ghost-delta').innerText().catch(()=>'(none)'));
  await p.screenshot({ path: 'screenshots/ghost.png' });
} catch (e) {
  log('FATAL', e.message);
} finally {
  await b.close();
  log('done');
}
