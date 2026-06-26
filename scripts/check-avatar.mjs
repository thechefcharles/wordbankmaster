// Verify the avatar builder: render, category switch, buy a locked item, save.
//   BASE=http://localhost:5173 node scripts/check-avatar.mjs
import { chromium } from 'playwright';
import { execSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL = 'pwtest+wb@example.com', PASS = 'TestPass123!';
const DB = process.env.SUPABASE_DB_URL;
mkdirSync('screenshots/avatar', { recursive: true });
const sql = (q) => execSync(`psql "${DB}" -tAc "${q.replace(/"/g, '\\"')}"`, { encoding: 'utf8' }).trim();
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 430, height: 932 }, deviceScaleFactor: 2 })).newPage();
p.setDefaultTimeout(8000);
const wait = (ms) => p.waitForTimeout(ms);
const kill = () => p.evaluate(() => { localStorage.setItem('wb_tutorial_v3','true'); localStorage.setItem('wb_launch_welcome_v1','1'); for (const m of ['daily','climb','freeplay','match','makeup']) localStorage.setItem('wb_obj_'+m,'1'); }).catch(()=>{});
const skipPin = async () => { await p.getByText(/skip for now/i).first().click({ timeout: 1200 }).catch(()=>{}); await wait(400); };
try {
  const uid = sql(`SELECT id FROM auth.users WHERE email='${EMAIL}'`);
  // clean slate + plenty of Cash
  sql(`DELETE FROM user_cosmetics WHERE user_id='${uid}' AND cosmetic_id LIKE 'av\\_%'`);
  sql(`UPDATE profiles SET username=COALESCE(username,'pwtest_wb'), bank=50000, avatar=NULL WHERE id='${uid}'`);
  await p.goto(BASE, { waitUntil: 'domcontentloaded' }); await wait(500); await kill();
  if (await p.locator('input[type=password]').count()) {
    await p.getByPlaceholder(/email or username/i).first().fill(EMAIL);
    await p.locator('input[type=password]').first().fill(PASS);
    await p.getByRole('button', { name: /^log in$/i }).first().click().catch(()=>{}); await wait(2800);
  }
  await kill(); await skipPin(); await wait(500);
  await p.goto(BASE + '/avatar', { waitUntil: 'domcontentloaded' }); await wait(1500);
  console.log('hero avatar:', await p.locator('.av-hero svg').count(), '| categories:', await p.locator('.cat-chip').count(), '| options:', await p.locator('.opt').count());
  await p.screenshot({ path: 'screenshots/avatar/01-builder.png' });
  // go to Glasses category, open a locked item
  await p.locator('.cat-chip', { hasText: 'Glasses' }).click().catch(()=>{}); await wait(500);
  await p.screenshot({ path: 'screenshots/avatar/02-glasses.png' });
  await p.locator('.opt.locked').first().click().catch(()=>{}); await wait(600);
  console.log('buy modal:', await p.locator('.buy-card').count());
  await p.screenshot({ path: 'screenshots/avatar/03-buy.png' });
  await p.locator('.buy-go').click().catch(()=>{}); await wait(1500); // unlock
  // pick a paid hairstyle category too, then save
  await p.locator('.cat-chip', { hasText: 'Clothes' }).click().catch(()=>{}); await wait(400);
  await p.locator('.opt').nth(3).click().catch(()=>{}); await wait(500); // may open buy or equip
  await p.locator('.buy-go').click({ timeout: 1500 }).catch(()=>{}); await wait(1200);
  await p.locator('.av-save').click().catch(()=>{}); await wait(1200);
  console.log('saved avatar in DB:', sql(`SELECT avatar IS NOT NULL FROM profiles WHERE id='${uid}'`), '| owned av items:', sql(`SELECT count(*) FROM user_cosmetics WHERE user_id='${uid}' AND cosmetic_id LIKE 'av\\_%'`));
  await p.screenshot({ path: 'screenshots/avatar/04-saved.png' });
  // cleanup
  sql(`DELETE FROM user_cosmetics WHERE user_id='${uid}' AND cosmetic_id LIKE 'av\\_%'`);
  sql(`UPDATE profiles SET avatar=NULL WHERE id='${uid}'`);
  console.log('done');
} catch (e) { console.log('FATAL', e.message); await p.screenshot({ path: 'screenshots/avatar/fatal.png' }).catch(()=>{}); }
finally { await b.close(); }
