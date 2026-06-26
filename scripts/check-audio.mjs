// Screenshot the in-game audio button + the Sound & Music panel.
//   BASE=http://localhost:5173 node scripts/check-audio.mjs
import { chromium } from 'playwright';
import { execSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL = 'pwtest+wb@example.com', PASS = 'TestPass123!';
const DB = process.env.SUPABASE_DB_URL;
mkdirSync('screenshots/audio', { recursive: true });
const sql = (q) => execSync(`psql "${DB}" -tAc "${q.replace(/"/g, '\\"')}"`, { encoding: 'utf8' }).trim();
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 430, height: 932 }, deviceScaleFactor: 2 })).newPage();
p.setDefaultTimeout(8000);
const wait = (ms) => p.waitForTimeout(ms);
const kill = () => p.evaluate(() => { localStorage.setItem('wb_tutorial_v3','true'); localStorage.setItem('wb_launch_welcome_v1','1'); for (const m of ['daily','climb','freeplay','match','makeup']) localStorage.setItem('wb_obj_'+m,'1'); }).catch(()=>{});
const skipPin = async () => { await p.getByText(/skip for now/i).first().click({ timeout: 1200 }).catch(()=>{}); await wait(400); };
const letsGo = async () => { await p.getByRole('button', { name: /let.?s go/i }).first().click({ timeout: 2000 }).catch(()=>{}); await wait(1200); };
try {
  const uid = sql(`SELECT id FROM auth.users WHERE email='${EMAIL}'`);
  sql(`UPDATE profiles SET username=COALESCE(username,'pwtest_wb') WHERE id='${uid}'`);
  await p.goto(BASE, { waitUntil: 'domcontentloaded' }); await wait(500); await kill();
  if (await p.locator('input[type=password]').count()) {
    await p.getByPlaceholder(/email or username/i).first().fill(EMAIL);
    await p.locator('input[type=password]').first().fill(PASS);
    await p.getByRole('button', { name: /^log in$/i }).first().click().catch(()=>{}); await wait(2800);
  }
  await kill(); await skipPin(); await wait(500);
  await p.getByRole('button', { name: /play now/i }).first().click().catch(()=>{}); await skipPin(); await wait(900);
  await p.locator('.menu-card', { hasText: 'Cash Game' }).first().click().catch(()=>{}); await wait(2600); await letsGo();
  console.log('audio button present:', await p.locator('.audio-btn').count());
  await p.screenshot({ path: 'screenshots/audio/01-ingame-button.png' });
  await p.locator('.audio-btn').first().click().catch(()=>{}); await wait(700);
  console.log('panel toggles:', await p.locator('.ap-toggle').count(), '| tracks:', await p.locator('.ma-track').count());
  await p.screenshot({ path: 'screenshots/audio/02-audio-panel.png' });
  console.log('done');
} catch (e) { console.log('FATAL', e.message); await p.screenshot({ path: 'screenshots/audio/fatal.png' }).catch(()=>{}); }
finally { await b.close(); }
