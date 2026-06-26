// Verify the new menu: ▶ Resume (multi → resume menu) + ⚔️ Challenges invite notification.
//   BASE=http://localhost:5173 node scripts/check-menu-resume.mjs
import { chromium } from 'playwright';
import { execSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';

const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL = 'pwtest+wb@example.com', PASS = 'TestPass123!';
const DB = process.env.SUPABASE_DB_URL;
mkdirSync('screenshots/menu', { recursive: true });
const sql = (q) => execSync(`psql "${DB}" -tAc "${q.replace(/"/g, '\\"')}"`, { encoding: 'utf8' }).trim();
const sqlf = (q) => execSync(`psql "${DB}"`, { input: q, encoding: 'utf8' });

const me = sql(`SELECT id FROM auth.users WHERE email='${EMAIL}'`);
const others = sql(`SELECT string_agg(id::text, ',') FROM (SELECT id FROM auth.users WHERE id <> '${me}' LIMIT 2) q`).split(',');
const [opp1, opp2] = others;
const pid = sql(`SELECT id FROM daily_puzzles LIMIT 1`);

function mkMatch(host, players) {
  const mid = sql(`SELECT gen_random_uuid()`);
  sql(`INSERT INTO challenge_matches(id,host_id,mode,pack_size,wager,payout,status,items_allowed,settles_at) VALUES ('${mid}','${host}','standard',1,500,'winner','open',true,now()+interval '1 day')`);
  sql(`INSERT INTO challenge_pack(match_id,position,puzzle_id) VALUES ('${mid}',1,'${pid}')`);
  for (const pl of players) sql(`INSERT INTO challenge_participants(match_id,user_id,paid,position,bankroll,start_budget,state,solved,total_score) VALUES ('${mid}','${pl.uid}',${pl.paid},1,500,500,'${pl.state}',0,500)`);
  return mid;
}
function setup() {
  sqlf(`DELETE FROM challenge_participants WHERE user_id='${me}'; DELETE FROM challenge_pack WHERE match_id IN (SELECT id FROM challenge_matches WHERE host_id IN ('${me}','${opp1}','${opp2}')); DELETE FROM challenge_matches WHERE host_id IN ('${me}','${opp1}','${opp2}');
    UPDATE profiles SET username=COALESCE(username,'pwtest_wb'), last_daily_play_date=CURRENT_DATE WHERE id='${me}';
    INSERT INTO daily_sessions(user_id,puzzle_date,puzzle_id,state) SELECT '${me}',CURRENT_DATE,'${pid}','active' ON CONFLICT (user_id,puzzle_date) DO UPDATE SET state='active';`);
  // a started challenge (I'm active) + two pending invites (I'm invited)
  mkMatch(opp1, [{ uid: opp1, paid: true, state: 'active' }, { uid: me, paid: true, state: 'active' }]);
  mkMatch(opp1, [{ uid: opp1, paid: true, state: 'active' }, { uid: me, paid: false, state: 'invited' }]);
  mkMatch(opp2, [{ uid: opp2, paid: true, state: 'active' }, { uid: me, paid: false, state: 'invited' }]);
}

const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 430, height: 932 }, deviceScaleFactor: 2 })).newPage();
p.setDefaultTimeout(8000);
const wait = (ms) => p.waitForTimeout(ms);
const killGates = () => p.evaluate(() => { localStorage.setItem('wb_tutorial_v3','true'); localStorage.setItem('wb_launch_welcome_v1','1'); for (const m of ['daily','climb','freeplay','match','makeup']) localStorage.setItem('wb_obj_'+m,'1'); }).catch(()=>{});
const skipPin = async () => { await p.getByText(/skip for now/i).first().click({ timeout: 1200 }).catch(()=>{}); await wait(400); };

try {
  setup();
  await p.goto(BASE, { waitUntil: 'domcontentloaded' }); await wait(500); await killGates();
  if (await p.locator('input[type=password]').count()) {
    await p.getByPlaceholder(/email or username/i).first().fill(EMAIL);
    await p.locator('input[type=password]').first().fill(PASS);
    await p.getByRole('button', { name: /^log in$/i }).first().click().catch(()=>{}); await wait(2800);
  }
  await killGates(); await skipPin(); await wait(1200);
  const resume = await p.locator('.resume-card').count();
  const invite = await p.locator('.invite-card').count();
  const resumeTitle = await p.locator('.resume-card .mc-title').first().innerText().catch(()=>'?');
  const inviteTitle = await p.locator('.invite-card .mc-title').first().innerText().catch(()=>'?');
  console.log(`menu: resume-card=${resume} ("${resumeTitle}") | invite-card=${invite} ("${inviteTitle}")`);
  await p.screenshot({ path: 'screenshots/menu/01-menu-top.png' });
  // open the resume menu (multiple resumables → menu)
  await p.locator('.resume-card').first().click().catch(()=>{}); await wait(800);
  const rows = await p.locator('.rm-row').count();
  console.log(`resume menu rows: ${rows}`);
  await p.screenshot({ path: 'screenshots/menu/02-resume-menu.png' });

  // cleanup
  sqlf(`DELETE FROM challenge_participants WHERE user_id='${me}'; DELETE FROM challenge_pack WHERE match_id IN (SELECT id FROM challenge_matches WHERE host_id IN ('${me}','${opp1}','${opp2}')); DELETE FROM challenge_matches WHERE host_id IN ('${me}','${opp1}','${opp2}'); DELETE FROM daily_sessions WHERE user_id='${me}' AND puzzle_date=CURRENT_DATE; UPDATE profiles SET last_daily_play_date=NULL WHERE id='${me}';`);
  console.log('done');
} catch (e) { console.log('FATAL', e.message); await p.screenshot({ path: 'screenshots/menu/fatal.png' }).catch(()=>{}); }
finally { await b.close(); }
