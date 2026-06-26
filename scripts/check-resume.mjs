// Verify the multi-game Resume shortcut: with an active Daily AND active Cash Game,
// the home menu shows "▶ Resume <most-recent>" + "+1 more in progress", driven by
// server truth (get_open_games), independent of the localStorage save slot.
//   BASE=http://localhost:5173 node scripts/check-resume.mjs
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
  // Two live games: active Daily (most recent) + active Cash Game.
  sql(`UPDATE public.profiles SET username=COALESCE(username,'pwtest_wb'), last_daily_play_date=CURRENT_DATE WHERE id='${uid}'`);
  sql(`INSERT INTO public.climb_state(user_id, position, puzzle_id, state) SELECT '${uid}', 1, (SELECT id FROM public.daily_puzzles LIMIT 1), 'active' ON CONFLICT (user_id) DO UPDATE SET state='active', updated_at=now() - interval '5 min'`);
  sql(`INSERT INTO public.daily_sessions(user_id, puzzle_date, puzzle_id, state) SELECT '${uid}', CURRENT_DATE, (SELECT id FROM public.daily_puzzles LIMIT 1), 'active' ON CONFLICT (user_id, puzzle_date) DO UPDATE SET state='active', updated_at=now()`);
  console.log('open games (server):', sql(`SELECT string_agg(state,',') FROM (SELECT state FROM daily_sessions WHERE user_id='${uid}' AND puzzle_date=CURRENT_DATE UNION ALL SELECT state FROM climb_state WHERE user_id='${uid}') q`));

  await p.goto(BASE, { waitUntil: 'domcontentloaded' }); await wait(700);
  await p.evaluate(() => localStorage.setItem('wb_tutorial_seen', 'true'));
  if (await p.locator('input[type=password]').count()) {
    await p.getByPlaceholder(/email or username/i).first().fill(EMAIL);
    await p.locator('input[type=password]').first().fill(PASS);
    await p.getByRole('button', { name: /^log in$/i }).first().click().catch(()=>{}); await wait(2800);
  }
  await p.evaluate((u) => localStorage.removeItem('wordbank_game_state_' + u), uid); // clobbered slot
  await skipPin(); await skipTut(); await wait(800);

  // Home menu — the Resume card should be present without entering Play.
  const hasResume = await p.locator('.resume-card').count();
  const resumeText = await p.locator('.resume-card .mc-title').first().innerText().catch(()=>'?');
  const moreText = await p.locator('.resume-more').first().innerText().catch(()=>'');
  console.log(`RESULT → resume-card=${hasResume} | title="${resumeText}" | more="${moreText}"`);
  console.log(hasResume > 0 && /resume/i.test(resumeText) ? '✅ Resume shortcut shown' : '⚠️ Resume shortcut missing');
  await p.screenshot({ path: 'screenshots/resume-home.png' });

  // cleanup
  sql(`DELETE FROM public.daily_sessions WHERE user_id='${uid}' AND puzzle_date=CURRENT_DATE; UPDATE public.profiles SET last_daily_play_date=NULL WHERE id='${uid}'`);
} catch (e) { console.log('FATAL', e.message); await p.screenshot({ path: 'screenshots/resume-fatal.png' }).catch(()=>{}); }
finally { await b.close(); }
