// Verify My Account additions: legal links, version, Delete Account → confirm gate.
// Does NOT actually delete (stops before confirming).  node scripts/check-account.mjs
import { chromium } from 'playwright';
import { execSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL = 'pwtest+wb@example.com', PASS = 'TestPass123!';
const DB = process.env.SUPABASE_DB_URL;
mkdirSync('screenshots/account', { recursive: true });
const sql = (q) => execSync(`psql "${DB}" -tAc "${q.replace(/"/g, '\\"')}"`, { encoding: 'utf8' }).trim();
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 430, height: 932 }, deviceScaleFactor: 2 })).newPage();
p.setDefaultTimeout(8000);
const wait = (ms) => p.waitForTimeout(ms);
const kill = () => p.evaluate(() => { localStorage.setItem('wb_tutorial_v3','true'); localStorage.setItem('wb_launch_welcome_v1','1'); for (const m of ['daily','climb','freeplay','match','makeup']) localStorage.setItem('wb_obj_'+m,'1'); }).catch(()=>{});
const skipPin = async () => { await p.getByText(/skip for now/i).first().click({ timeout: 1200 }).catch(()=>{}); await wait(400); };
try {
  sql(`UPDATE profiles SET username=COALESCE(username,'pwtest_wb') WHERE id=(SELECT id FROM auth.users WHERE email='${EMAIL}')`);
  await p.goto(BASE, { waitUntil: 'domcontentloaded' }); await wait(500); await kill();
  if (await p.locator('input[type=password]').count()) {
    await p.getByPlaceholder(/email or username/i).first().fill(EMAIL);
    await p.locator('input[type=password]').first().fill(PASS);
    await p.getByRole('button', { name: /^log in$/i }).first().click().catch(()=>{}); await wait(2800);
  }
  await kill(); await skipPin(); await wait(500);
  await p.goto(BASE + '/?account=1', { waitUntil: 'domcontentloaded' }); await wait(1200);
  console.log('delete btn:', await p.locator('.ma-danger').count(), '| privacy link:', await p.getByRole('link', { name: 'Privacy' }).count(), '| terms link:', await p.getByRole('link', { name: 'Terms' }).count(), '| version:', await p.locator('.ma-version').innerText().catch(()=>'?'));
  await p.locator('.ma-content, .modal-card, [class*="modal"]').first().scrollIntoViewIfNeeded().catch(()=>{});
  await p.screenshot({ path: 'screenshots/account/01-my-account.png' });
  // open delete confirm
  await p.locator('.ma-danger').first().click().catch(()=>{}); await wait(700);
  const armedBefore = await p.locator('.del-card .ma-danger').isDisabled().catch(()=>null);
  await p.screenshot({ path: 'screenshots/account/02-delete-confirm.png' });
  // type DELETE → button should enable (do NOT click)
  await p.locator('.del-input').fill('DELETE'); await wait(400);
  const armedAfter = await p.locator('.del-card .ma-danger').isDisabled().catch(()=>null);
  console.log(`delete button disabled — before typing: ${armedBefore}, after typing DELETE: ${armedAfter}`);
  await p.screenshot({ path: 'screenshots/account/03-delete-armed.png' });
  console.log('done (did NOT delete)');
} catch (e) { console.log('FATAL', e.message); await p.screenshot({ path: 'screenshots/account/fatal.png' }).catch(()=>{}); }
finally { await b.close(); }
