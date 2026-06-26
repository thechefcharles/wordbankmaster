// Visual check: Double or Nothing CTA + armed state + run line + Cash Game leaderboard tab.
// Logs in as the shared pwtest account, opens Cash Game (creates climb_state), then the
// caller injects heat≥1.5 via psql and we reload to surface the DoN UI. Run:
//   BASE=http://localhost:5173 node scripts/check-don.mjs
import { chromium } from 'playwright';
import { execSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';

const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL = 'pwtest+wb@example.com', PASS = 'TestPass123!';
const DB = process.env.SUPABASE_DB_URL;
mkdirSync('screenshots', { recursive: true });
const sql = (q) => execSync(`psql "${DB}" -tAc "${q.replace(/"/g, '\\"')}"`, { encoding: 'utf8' }).trim();

const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 430, height: 900 }, deviceScaleFactor: 2 })).newPage();
p.setDefaultTimeout(8000);
const wait = (ms) => p.waitForTimeout(ms);
const dismiss = async () => { for (const s of ['.close-btn', '.wc-cta', 'button:has-text("Got it")', 'button:has-text("Skip")']) { await p.locator(s).first().click({ timeout: 800 }).catch(()=>{}); } };
const letsGo = async () => { await p.getByRole('button', { name: /let.?s go/i }).first().click({ timeout: 2000 }).catch(()=>{}); await wait(1500); };

try {
  // Make sure the shared test account has a username so it clears the gate → menu.
  const uid0 = sql(`SELECT id FROM auth.users WHERE email='${EMAIL}'`);
  sql(`UPDATE public.profiles SET username = COALESCE(username, 'pwtest_wb') WHERE id='${uid0}'`);

  await p.goto(BASE, { waitUntil: 'domcontentloaded' }); await wait(700);
  await p.evaluate(() => localStorage.setItem('wb_tutorial_seen', 'true'));
  if (await p.locator('input[type=password]').count()) {
    await p.getByPlaceholder(/email or username/i).first().fill(EMAIL);
    await p.locator('input[type=password]').first().fill(PASS);
    await p.getByRole('button', { name: /^log in$/i }).first().click().catch(()=>{}); await wait(2800);
  }
  await dismiss(); await wait(400);

  // Open Cash Game (ensures a climb_state row exists for the account).
  await p.getByRole('button', { name: /play now/i }).first().click().catch(()=>{}); await wait(900);
  await p.getByRole('button', { name: /cash game/i }).first().click().catch(()=>{}); await wait(2600);
  await dismiss(); await letsGo();

  const uid = sql(`SELECT id FROM auth.users WHERE email='${EMAIL}'`);
  console.log('uid:', uid);
  // Inject a hot run so DoN unlocks (heat ×1.6, 4-solve run, +$1,200).
  sql(`UPDATE public.climb_state SET heat_x100=160, run_solves=4, run_profit=1200, best_run_profit=1200, best_run_solves=4, don_armed=false, state='active' WHERE user_id='${uid}'`);

  // Reload Cash Game to pull the fresh board.
  await p.goto(BASE, { waitUntil: 'domcontentloaded' }); await wait(600); await dismiss();
  await p.getByRole('button', { name: /play now/i }).first().click().catch(()=>{}); await wait(900);
  await p.getByRole('button', { name: /cash game/i }).first().click().catch(()=>{}); await wait(2600); await dismiss(); await letsGo();

  const ctaSeen = await p.locator('.don-cta').count();
  const runSeen = await p.locator('.climb-run-line').count();
  console.log('DoN CTA visible:', ctaSeen, '| run line visible:', runSeen);
  await p.screenshot({ path: 'screenshots/don-cta.png' });

  // Arm Double or Nothing → modal → confirm → armed indicator.
  if (ctaSeen) {
    await p.locator('.don-cta').first().click(); await wait(500);
    await p.screenshot({ path: 'screenshots/don-modal.png' });
    await p.locator('.don-confirm').first().click().catch(()=>{}); await wait(1800);
    const armedSeen = await p.locator('.don-armed').count();
    console.log('Armed indicator visible:', armedSeen);
    await p.screenshot({ path: 'screenshots/don-armed.png' });
  }

  // Leaderboard → Cash Game tab.
  await p.goto(BASE + '/leaderboard', { waitUntil: 'domcontentloaded' }); await wait(1200);
  await p.getByRole('button', { name: /cash game/i }).first().click().catch(()=>{}); await wait(1400);
  await p.screenshot({ path: 'screenshots/leaderboard-cashgame.png' });

  // Reset the test account's heat so we don't leave it armed/hot.
  sql(`UPDATE public.climb_state SET heat_x100=100, run_solves=0, run_profit=0, don_armed=false WHERE user_id='${uid}'`);
  console.log('done');
} catch (e) { console.log('FATAL', e.message); await p.screenshot({ path: 'screenshots/don-fatal.png' }).catch(()=>{}); }
finally { await b.close(); }
