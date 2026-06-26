import { chromium } from 'playwright';
import { execSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL = 'pwtest+wb@example.com', PASS = 'TestPass123!';
const DB = process.env.SUPABASE_DB_URL;
mkdirSync('screenshots/avatar', { recursive: true });
const sql = (q) => execSync(`psql "${DB}" -tAc "${q.replace(/"/g, '\\"')}"`, { encoding: 'utf8' }).trim();
const sqlf = (q) => execSync(`psql "${DB}"`, { input: q, encoding: 'utf8' });
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 430, height: 932 }, deviceScaleFactor: 2 })).newPage();
p.setDefaultTimeout(8000);
const wait = (ms) => p.waitForTimeout(ms);
const kill = () => p.evaluate(() => { localStorage.setItem('wb_tutorial_v3','true'); localStorage.setItem('wb_launch_welcome_v1','1'); for (const m of ['daily','climb','freeplay','match','makeup']) localStorage.setItem('wb_obj_'+m,'1'); }).catch(()=>{});
const skipPin = async () => { await p.getByText(/skip for now/i).first().click({ timeout: 1200 }).catch(()=>{}); await wait(400); };
try {
  const uid = sql(`SELECT id FROM auth.users WHERE email='${EMAIL}'`);
  // grant the FX cosmetics + equip a decked-out look
  sqlf(`DELETE FROM user_cosmetics WHERE user_id='${uid}' AND cosmetic_id LIKE 'av\\_%';
    INSERT INTO user_cosmetics(user_id,cosmetic_id) VALUES ('${uid}','av_frame_neon'),('${uid}','av_overlay_crown'),('${uid}','av_fxshirt_holo'),('${uid}','av_aura_neon'),('${uid}','av_gfx_skull') ON CONFLICT DO NOTHING;
    UPDATE profiles SET username=COALESCE(username,'pwtest_wb'), bank=50000,
      avatar='{"skinColor":"edb98a","top":"shortFlat","hairColor":"4a312c","eyes":"happy","eyebrows":"raisedExcited","mouth":"smile","clothing":"graphicShirt","clothesColor":"ff488e","clothingGraphic":"skull","accessories":"sunglasses","accessoriesColor":"7cff6b","facialHair":"none","hatColor":"262e33","fxShirt":"holo","frame":"neon","overlay":"crown","aura":"neon"}'::jsonb WHERE id='${uid}'`);
  await p.goto(BASE, { waitUntil: 'domcontentloaded' }); await wait(500); await kill();
  if (await p.locator('input[type=password]').count()) {
    await p.getByPlaceholder(/email or username/i).first().fill(EMAIL);
    await p.locator('input[type=password]').first().fill(PASS);
    await p.getByRole('button', { name: /^log in$/i }).first().click().catch(()=>{}); await wait(2800);
  }
  await kill(); await skipPin(); await wait(800);
  await p.goto(BASE + '/avatar', { waitUntil: 'domcontentloaded' }); await wait(1500);
  console.log('categories:', await p.locator('.cat-chip').count());
  await p.screenshot({ path: 'screenshots/avatar/40-decked.png' });
  // scroll category bar to reveal FX categories
  await p.locator('.cat-chip', { hasText: 'Frame' }).click().catch(()=>{}); await wait(500);
  await p.screenshot({ path: 'screenshots/avatar/41-frame-cat.png' });
  console.log('done');
} catch (e) { console.log('FATAL', e.message); }
finally { await b.close(); }
