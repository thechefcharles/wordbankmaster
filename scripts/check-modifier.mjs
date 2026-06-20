// Verify the Daily Modifier banner shows on a fresh daily (no picker), and that
// a vowel is half-price when today's modifier is Vowel Vision.
import { chromium } from 'playwright';
const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL = 'pwtest+wb@example.com', PASS = 'TestPass123!';
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 430, height: 900 } })).newPage();
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
  await p.getByRole('button', { name: /daily/i }).first().click().catch((e)=>log('daily click', e.message));
  await wait(2600);
  log('no picker shown (good):', await p.getByText(/use a power-up/i).count() === 0);
  log('modifier banner present:', await p.locator('.daily-modifier').count() > 0);
  log('modifier name:', await p.locator('.dm-name').innerText().catch(()=>'—'));
  log('modifier blurb:', await p.locator('.dm-blurb').innerText().catch(()=>'—'));
  log('board keys:', await p.locator('.key').count());
  // Vowel Vision: vowels half price (E 140 -> 70), consonants unchanged (Q 30).
  const priceOf = async (L) => (await p.locator(`.key:has(.letter:text-is("${L}")) .price`).first().innerText().catch(()=>'?'));
  log('E (vowel) price:', await priceOf('E'), ' expected $70');
  log('Q (consonant) price:', await priceOf('Q'), ' expected $30');
  await p.screenshot({ path: 'screenshots/modifier.png' });
} catch (e) {
  log('FATAL', e.message);
} finally {
  await b.close();
  log('done');
}
