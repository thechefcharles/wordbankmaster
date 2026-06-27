import { chromium } from 'playwright';
import { execSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
const BASE=process.env.BASE||'http://localhost:5173', EMAIL='pwtest+wb@example.com', PASS='TestPass123!', DB=process.env.SUPABASE_DB_URL;
mkdirSync('screenshots/menu',{recursive:true});
const sql=(q)=>execSync(`psql "${DB}"`,{input:q,encoding:'utf8'});
const b=await chromium.launch(); const p=await(await b.newContext({viewport:{width:430,height:932},deviceScaleFactor:2})).newPage();
p.setDefaultTimeout(8000); const wait=(ms)=>p.waitForTimeout(ms);
const kill=()=>p.evaluate(()=>{localStorage.setItem('wb_tutorial_v3','true');localStorage.setItem('wb_launch_welcome_v1','1');for(const m of['daily','climb','freeplay','match','makeup'])localStorage.setItem('wb_obj_'+m,'1');}).catch(()=>{});
const skipPin=async()=>{await p.getByText(/skip for now/i).first().click({timeout:1200}).catch(()=>{});await wait(400);};
try{
  // reset pwtest's daily so it shows NOT started
  sql(`UPDATE profiles SET username=COALESCE(username,'pwtest_wb'), last_daily_play_date=NULL WHERE id=(SELECT id FROM auth.users WHERE email='${EMAIL}');
    DELETE FROM daily_sessions WHERE user_id=(SELECT id FROM auth.users WHERE email='${EMAIL}') AND puzzle_date=CURRENT_DATE;
    DELETE FROM game_results WHERE user_id=(SELECT id FROM auth.users WHERE email='${EMAIL}') AND game_mode='daily' AND created_at::date=CURRENT_DATE;`);
  await p.goto(BASE,{waitUntil:'domcontentloaded'});await wait(500);await kill();
  if(await p.locator('input[type=password]').count()){await p.getByPlaceholder(/email or username/i).first().fill(EMAIL);await p.locator('input[type=password]').first().fill(PASS);await p.getByRole('button',{name:/^log in$/i}).first().click().catch(()=>{});await wait(2800);}
  await kill();await skipPin();await wait(700);
  await p.getByRole('button',{name:/play now/i}).first().click().catch(()=>{}); await skipPin(); await wait(900);
  const dailyCard = p.locator('.menu-card', { hasText: 'Daily' }).first();
  console.log('daily card classes:', await dailyCard.getAttribute('class'));
  await p.screenshot({path:'screenshots/menu/30-daily-gold.png'});
  console.log('done');
}catch(e){console.log('FATAL',e.message);} finally{await b.close();}
