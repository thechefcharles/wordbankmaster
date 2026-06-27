import { chromium } from 'playwright';
import { execSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
const BASE=process.env.BASE||'http://localhost:5173', EMAIL='pwtest+wb@example.com', PASS='TestPass123!', DB=process.env.SUPABASE_DB_URL;
mkdirSync('screenshots/profile',{recursive:true});
const sql=(q)=>execSync(`psql "${DB}"`,{input:q,encoding:'utf8'});
const b=await chromium.launch(); const p=await(await b.newContext({viewport:{width:430,height:932},deviceScaleFactor:2})).newPage();
p.setDefaultTimeout(8000); const wait=(ms)=>p.waitForTimeout(ms);
const kill=()=>p.evaluate(()=>{localStorage.setItem('wb_tutorial_v3','true');localStorage.setItem('wb_launch_welcome_v1','1');for(const m of['daily','climb','freeplay','match','makeup'])localStorage.setItem('wb_obj_'+m,'1');}).catch(()=>{});
const skipPin=async()=>{await p.getByText(/skip for now/i).first().click({timeout:1200}).catch(()=>{});await wait(400);};
try{
  const uid='(SELECT id FROM auth.users WHERE email=\''+EMAIL+'\')';
  sql(`UPDATE profiles SET username=COALESCE(username,'pwtest_wb'), avatar='{"top":"shortFlat","clothing":"hoodie","clothesColor":"5199e4","frame":"neon"}'::jsonb WHERE id=${uid};
    INSERT INTO user_badges(user_id,badge) VALUES (${uid},'flawless'),(${uid},'gold_bank') ON CONFLICT DO NOTHING;`);
  await p.goto(BASE,{waitUntil:'domcontentloaded'});await wait(500);await kill();
  if(await p.locator('input[type=password]').count()){await p.getByPlaceholder(/email or username/i).first().fill(EMAIL);await p.locator('input[type=password]').first().fill(PASS);await p.getByRole('button',{name:/^log in$/i}).first().click().catch(()=>{});await wait(2800);}
  await kill();await skipPin();await wait(500);
  await p.goto(BASE+'/profile',{waitUntil:'domcontentloaded'});await wait(1200);
  console.log('tabs(should be 0):', await p.locator('.tabs .tab').count(), '| home btn(0):', await p.locator('[title="Main menu"]').count(), '| nav cards:', await p.locator('.ov-link').count(), '| clickable stats:', await p.locator('.ov-summary .stat-link').count());
  await p.screenshot({path:'screenshots/profile/10-clean.png'});
  sql(`DELETE FROM user_badges WHERE user_id=${uid} AND badge IN ('flawless','gold_bank'); UPDATE profiles SET avatar=NULL WHERE id=${uid};`);
  console.log('done');
}catch(e){console.log('FATAL',e.message);} finally{await b.close();}
