// Regression for "Daily shows complete+lost after playing another mode".
// Injects the exact bug state via psql: today's Daily session is ACTIVE (started,
// not won) while the local save slot does NOT point at the Daily (empty = the
// clobbered-by-Cash-Game case). Then loads the menu and checks the Daily card.
//   BUG:   ❌ lost chip (.daily-chip.lost) + title "Daily"
//   FIXED: ▶ Resume chip (.daily-chip.prog) + title "Resume Daily"
//   BASE=http://localhost:5173 node scripts/check-daily-resume.mjs
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
const skipPin = async () => { await p.getByText(/skip for now/i).first().click({ timeout: 1500 }).catch(()=>{}); await wait(600); };
const skipTut = async () => { for (let i=0;i<3;i++){ await p.getByText('Skip', { exact: true }).first().click({ timeout: 900 }).catch(()=>{}); await wait(400); } };

try {
  const uid = sql(`SELECT id FROM auth.users WHERE email='${EMAIL}'`);
  // Inject the bug state: started today's Daily, still ACTIVE, not won.
  sql(`UPDATE public.profiles SET username=COALESCE(username,'pwtest_wb'), last_daily_play_date=CURRENT_DATE WHERE id='${uid}'`);
  sql(`DELETE FROM public.game_results WHERE user_id='${uid}' AND game_mode='daily' AND played_at::date=CURRENT_DATE`);
  sql(`INSERT INTO public.daily_sessions(user_id, puzzle_date, puzzle_id, state) SELECT '${uid}', CURRENT_DATE, (SELECT id FROM public.daily_puzzles LIMIT 1), 'active' ON CONFLICT (user_id, puzzle_date) DO UPDATE SET state='active'`);
  console.log('server:', sql(`SELECT 'played='||(last_daily_play_date=CURRENT_DATE) FROM public.profiles WHERE id='${uid}'`), '|', sql(`SELECT 'session='||state FROM public.daily_sessions WHERE user_id='${uid}' AND puzzle_date=CURRENT_DATE`));

  await p.goto(BASE, { waitUntil: 'domcontentloaded' }); await wait(700);
  await p.evaluate(() => localStorage.setItem('wb_tutorial_seen', 'true'));
  if (await p.locator('input[type=password]').count()) {
    await p.getByPlaceholder(/email or username/i).first().fill(EMAIL);
    await p.locator('input[type=password]').first().fill(PASS);
    await p.getByRole('button', { name: /^log in$/i }).first().click().catch(()=>{}); await wait(2800);
  }
  // Ensure the local save slot is NOT a daily-in-progress (the clobbered case).
  await p.evaluate((u) => localStorage.removeItem('wordbank_game_state_' + u), uid);
  await skipPin();

  // Open Play Now → game-select submenu (clear PIN/tutorial gates if they appear).
  for (let i = 0; i < 4 && !(await p.locator('.menu-card', { hasText: 'Daily' }).count()); i++) {
    await p.getByRole('button', { name: /play now/i }).first().click().catch(()=>{});
    await skipPin(); await skipTut(); await wait(1000);
  }

  const lost = await p.locator('.daily-chip.lost').count();
  const resume = await p.locator('.daily-chip.prog').count();
  const title = await p.locator('.menu-card', { hasText: 'Daily' }).locator('.mc-title').first().innerText().catch(()=>'?');
  console.log(`RESULT → Daily card title="${title}" | ❌lost chip=${lost} | ▶resume chip=${resume}`);
  console.log(resume > 0 && lost === 0 ? '✅ FIXED: active Daily shown as resumable' : (lost > 0 ? '❌ BUG: active Daily shown as lost' : '⚠️ inconclusive (card not found)'));
  await p.screenshot({ path: 'screenshots/daily-resume-menu.png' });

  // cleanup: remove the injected session
  sql(`DELETE FROM public.daily_sessions WHERE user_id='${uid}' AND puzzle_date=CURRENT_DATE; UPDATE public.profiles SET last_daily_play_date=NULL WHERE id='${uid}'`);
} catch (e) { console.log('FATAL', e.message); await p.screenshot({ path: 'screenshots/daily-resume-fatal.png' }).catch(()=>{}); }
finally { await b.close(); }
