// Verify the guided tutorial: shows on first run, steps through, dismisses,
// stays dismissed, and replays from the ❓ button.
import { chromium } from 'playwright';
const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL = 'pwtest+wb@example.com', PASS = 'TestPass123!';
const b = await chromium.launch();
const ctx = await b.newContext({ viewport: { width: 430, height: 900 } });
const p = await ctx.newPage();
const wait = (ms) => p.waitForTimeout(ms);
await p.goto(BASE, { waitUntil: 'networkidle' }); await wait(700);
// Ensure a clean first-run state
await p.evaluate(() => localStorage.removeItem('wb_tutorial_seen'));
if (await p.locator('input[type=password]').count()) {
  await p.fill('input[type=email]', EMAIL); await p.fill('input[type=password]', PASS);
  await p.getByRole('button', { name: /log in/i }).first().click().catch(()=>{}); await wait(2600);
}
await p.evaluate(() => localStorage.removeItem('wb_tutorial_seen'));
await p.reload({ waitUntil: 'networkidle' });
await wait(2200);
console.log('tutorial on first run:', await p.locator('.tut-card').count() > 0);
console.log('step 1 title:', await p.locator('.tut-title').innerText().catch(()=>'—'));
// Step through to the end
for (let s = 0; s < 5; s++) {
  await p.locator('.tut-btn.primary').click().catch(()=>{}); await wait(350);
}
console.log('dismissed after Play:', await p.locator('.tut-card').count() === 0);
console.log('seen flag set:', await p.evaluate(() => localStorage.getItem('wb_tutorial_seen')));
// Replay from the ❓ button (accessible name is the emoji; select by title attr)
await p.locator('button[title="How to play"]').first().click().catch(()=>{}); await wait(500);
console.log('reopened from help:', await p.locator('.tut-card').count() > 0);
await p.screenshot({ path: 'screenshots/tutorial.png' });
await b.close();
