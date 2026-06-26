// QA sweep for 1v1 + group challenges — screenshots every key screen/action.
//   BASE=http://localhost:5173 node scripts/check-challenges.mjs
import { chromium } from 'playwright';
import { execSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';

const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL = 'pwtest+wb@example.com', PASS = 'TestPass123!';
const DB = process.env.SUPABASE_DB_URL;
mkdirSync('screenshots/ch', { recursive: true });
const sql = (q) => execSync(`psql "${DB}" -tAc "${q.replace(/"/g, '\\"')}"`, { encoding: 'utf8' }).trim();
const sqlf = (q) => execSync(`psql "${DB}"`, { input: q, encoding: 'utf8' });

const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 430, height: 932 }, deviceScaleFactor: 2 })).newPage();
p.setDefaultTimeout(8000);
const wait = (ms) => p.waitForTimeout(ms);
const shot = (n) => p.screenshot({ path: `screenshots/ch/${n}.png` });
const skipPin = async () => { await p.getByText(/skip for now/i).first().click({ timeout: 1200 }).catch(()=>{}); await wait(400); };
const skipTut = async () => { for (let i=0;i<3;i++){ await p.getByText('Skip', { exact: true }).first().click({ timeout: 800 }).catch(()=>{}); await wait(300); } };
const toMenu = async () => {
  for (let i=0;i<3;i++) await p.keyboard.press('Escape').catch(()=>{});
  await p.locator('.menu-back-btn').first().click({ timeout: 3000 }).catch(()=>{}); await wait(1000);
  await p.locator('.sub-back').first().click({ timeout: 1000 }).catch(()=>{}); await wait(600);
};
const dismiss = async () => { for (const s of ['.close-btn','.wc-cta']) await p.locator(s).first().click({ timeout: 500 }).catch(()=>{}); await p.getByRole('button', { name: /got it|let.?s go/i }).first().click({ timeout: 500 }).catch(()=>{}); };

// ── identities ──
const me = sql(`SELECT id FROM auth.users WHERE email='${EMAIL}'`);
const others = sql(`SELECT string_agg(id::text, ',') FROM (SELECT id FROM auth.users WHERE id <> '${me}' LIMIT 2) q`).split(',');
const [opp1, opp2] = others;
const pid = sql(`SELECT id FROM daily_puzzles LIMIT 1`);
console.log('me', me, 'opps', opp1, opp2);

// helper: wipe my open matches + give me power-ups
function reset() {
  sqlf(`
    UPDATE profiles SET username=COALESCE(username,'pwtest_wb'), last_daily_play_date=NULL WHERE id='${me}';
    DELETE FROM challenge_participants WHERE match_id IN (SELECT id FROM challenge_matches WHERE host_id='${me}' AND status='open');
    DELETE FROM challenge_pack WHERE match_id IN (SELECT id FROM challenge_matches WHERE host_id='${me}' AND status='open');
    DELETE FROM challenge_matches WHERE host_id='${me}' AND status='open';
    INSERT INTO user_powerups_v2(user_id, powerup_id, pool, qty) VALUES
      ('${me}','free_reveal','cash',3), ('${me}','sabotage_tax','cash',3), ('${me}','sabotage_fog','cash',3)
      ON CONFLICT (user_id, powerup_id, pool) DO UPDATE SET qty=3;
  `);
}
// helper: create a match with given participants [{uid, pos, bankroll, state}]
function makeMatch(players, { wager = 500, pack = 1, group = null } = {}) {
  const mid = sql(`SELECT gen_random_uuid()`);
  sql(`INSERT INTO challenge_matches(id,host_id,group_id,mode,pack_size,wager,payout,status,items_allowed,settles_at)
    VALUES ('${mid}','${me}',${group?`'${group}'`:'NULL'},'standard',${pack},${wager},'winner','open',true,now()+interval '1 day')`);
  for (let i = 1; i <= pack; i++) sql(`INSERT INTO challenge_pack(match_id,position,puzzle_id) VALUES ('${mid}',${i},'${pid}')`);
  for (const pl of players) sql(`INSERT INTO challenge_participants(match_id,user_id,paid,position,bankroll,start_budget,state,solved,total_score)
    VALUES ('${mid}','${pl.uid}',true,${pl.pos},${pl.bankroll},500,'${pl.state}',${pl.pos-1},${pl.bankroll})`);
  return mid;
}
const openCommunityResume = async () => {
  await p.getByRole('button', { name: /community/i }).first().click().catch(()=>{}); await skipPin(); await skipTut(); await wait(1200);
  const items = await p.locator('.ch-item').count();
  const plays = await p.locator('.ch-play').count();
  console.log(`  community: ${items} matches, ${plays} play buttons`);
  for (let i = 0; i < 3; i++) {
    await p.locator('.ch-play').first().click({ timeout: 4000 }).catch(()=>{}); await wait(2600);
    await skipTut(); await dismiss(); await wait(500);
    if (await p.locator('.solve-vault, .bp-amount-btn').count()) break;
    await wait(1200);
  }
  const onPlay = await p.locator('.bp-amount-btn, .solve-vault, .match-pos').count();
  console.log(`  on play screen: ${onPlay} play-elements`);
};

try {
  reset();
  const killGates = () => p.evaluate(() => {
    localStorage.setItem('wb_tutorial_v3', 'true');
    localStorage.setItem('wb_launch_welcome_v1', '1');
    for (const m of ['daily','climb','freeplay','match','makeup']) localStorage.setItem('wb_obj_' + m, '1');
  }).catch(()=>{});
  await p.goto(BASE, { waitUntil: 'domcontentloaded' }); await wait(500); await killGates();
  if (await p.locator('input[type=password]').count()) {
    await p.getByPlaceholder(/email or username/i).first().fill(EMAIL);
    await p.locator('input[type=password]').first().fill(PASS);
    await p.getByRole('button', { name: /^log in$/i }).first().click().catch(()=>{}); await wait(2800);
  }
  await killGates(); await dismiss(); await skipPin(); await skipTut(); await wait(500);
  await shot('00-menu');

  // ── 1) CREATE CHALLENGE FORM ──
  try {
    await p.getByRole('button', { name: /challenge friends/i }).first().click(); await skipPin(); await skipTut(); await wait(1200);
    await shot('01-create-form');
    await p.locator('.close-btn, .modal-backdrop').first().click({ timeout: 1500 }).catch(()=>{});
    await wait(600);
  } catch (e) { console.log('create-form FAIL', e.message); }

  // ── 2) 1v1 PLAY: ante hero, vault, ante explainer ──
  try {
    reset();
    makeMatch([{ uid: me, pos: 1, bankroll: 500, state: 'active' }, { uid: opp1, pos: 1, bankroll: 500, state: 'active' }]);
    await toMenu();
    await openCommunityResume();
    await shot('02-1v1-play');
    // open the vault/bag
    await p.locator('.solve-vault').first().click({ timeout: 3000 }).catch(()=>{}); await wait(900);
    await shot('03-1v1-bag');
    await p.locator('.close-btn').first().click({ timeout: 1500 }).catch(()=>{}); await wait(500);
    // tap the Left to Spend hero
    await p.locator('.bp-amount-btn').first().click({ timeout: 2000 }).catch(()=>{}); await wait(700);
    await shot('04-ante-explainer');
    await p.locator('.info-close').first().click({ timeout: 1500 }).catch(()=>{}); await wait(400);
  } catch (e) { console.log('1v1 FAIL', e.message); }

  // ── 3) DEBUFF banner + modal (someone hit me) ──
  try {
    await toMenu();
    sqlf(`UPDATE challenge_participants SET debuffs='{tax}', debuff_by=jsonb_build_object('tax','${opp1}')
          WHERE user_id='${me}' AND match_id IN (SELECT id FROM challenge_matches WHERE host_id='${me}' AND status='open');`);
    await openCommunityResume();
    await shot('05-debuff-banner');
    await p.locator('.debuff-banner').first().click({ timeout: 3000 }).catch(()=>{}); await wait(800);
    await shot('06-debuff-modal');
    await p.locator('.info-close').first().click({ timeout: 1500 }).catch(()=>{}); await wait(400);
  } catch (e) { console.log('debuff FAIL', e.message); }

  // ── 4) GROUP (3-player) sabotage target picker ──
  try {
    await toMenu();
    reset();
    makeMatch([
      { uid: me, pos: 1, bankroll: 500, state: 'active' },
      { uid: opp1, pos: 2, bankroll: 350, state: 'active' },
      { uid: opp2, pos: 1, bankroll: 480, state: 'active' },
    ]);
    await openCommunityResume();
    await shot('07-group-play');
    await p.locator('.solve-vault').first().click({ timeout: 3000 }).catch(()=>{}); await wait(900);
    await shot('08-group-bag');
    // tap a sabotage item (😈) → target picker
    await p.locator('.bag-use', { hasText: /Fog|Tax|Lock|Toll|Vowel/i }).first().click({ timeout: 3000 }).catch(()=>{}); await wait(1000);
    await shot('09-sabotage-picker');
  } catch (e) { console.log('group FAIL', e.message); }

  // cleanup
  reset();
  sqlf(`DELETE FROM challenge_participants WHERE match_id IN (SELECT id FROM challenge_matches WHERE host_id='${me}'); DELETE FROM challenge_pack WHERE match_id IN (SELECT id FROM challenge_matches WHERE host_id='${me}'); DELETE FROM challenge_matches WHERE host_id='${me}';`);
  console.log('done — see screenshots/ch/');
} catch (e) { console.log('FATAL', e.message); await shot('zz-fatal').catch(()=>{}); }
finally { await b.close(); }
