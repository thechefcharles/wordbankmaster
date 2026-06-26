import { chromium } from 'playwright';
import { execSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL='pwtest+wb@example.com', PASS='TestPass123!', DB=process.env.SUPABASE_DB_URL;
mkdirSync('screenshots/profile',{recursive:true});
const sql=(q)=>execSync(`psql "${DB}" -tAc "${q.replace(/"/g,'\\"')}"`,{encoding:'utf8'}).trim();
const sqlf=(q)=>execSync(`psql "${DB}"`,{input:q,encoding:'utf8'});
const b=await chromium.launch(); const p=await(await b.newContext({viewport:{width:430,height:932},deviceScaleFactor:2})).newPage();
p.setDefaultTimeout(8000); const wait=(ms)=>p.waitForTimeout(ms);
const kill=()=>p.evaluate(()=>{localStorage.setItem('wb_tutorial_v3','true');localStorage.setItem('wb_launch_welcome_v1','1');for(const m of['daily','climb','freeplay','match','makeup'])localStorage.setItem('wb_obj_'+m,'1');}).catch(()=>{});
const skipPin=async()=>{await p.getByText(/skip for now/i).first().click({timeout:1200}).catch(()=>{});await wait(400);};
try{
  const uid=sql(`SELECT id FROM auth.users WHERE email='${EMAIL}'`);
  sqlf(`UPDATE profiles SET username=COALESCE(username,'pwtest_wb'), avatar='{"skinColor":"edb98a","top":"shortFlat","hairColor":"4a312c","eyes":"happy","mouth":"smile","clothing":"hoodie","clothesColor":"5199e4","frame":"neon","overlay":"crown"}'::jsonb WHERE id='${uid}';
    INSERT INTO user_cosmetics(user_id,cosmetic_id) VALUES ('${uid}','av_frame_neon'),('${uid}','av_overlay_crown') ON CONFLICT DO NOTHING;
    INSERT INTO user_badges(user_id,badge) VALUES ('${uid}','flawless'),('${uid}','gold_bank'),('${uid}','hustler') ON CONFLICT DO NOTHING;`);
  await p.goto(BASE,{waitUntil:'domcontentloaded'});await wait(500);await kill();
  if(await p.locator('input[type=password]').count()){await p.getByPlaceholder(/email or username/i).first().fill(EMAIL);await p.locator('input[type=password]').first().fill(PASS);await p.getByRole('button',{name:/^log in$/i}).first().click().catch(()=>{});await wait(2800);}
  await kill();await skipPin();await wait(600);
  await p.goto(BASE+'/profile',{waitUntil:'domcontentloaded'});await wait(1400);
  console.log('overview tab:', await p.locator('.tab',{hasText:'Overview'}).count(), '| people btn:', await p.locator('.ov-people').count(), '| badges:', await p.locator('.ov-badge').count(), '| nav links:', await p.locator('.ov-link').count());
  await p.screenshot({path:'screenshots/profile/01-overview.png'});
  console.log('done');
  // cleanup
  sqlf(`DELETE FROM user_cosmetics WHERE user_id='${uid}' AND cosmetic_id LIKE 'av\\_%'; DELETE FROM user_badges WHERE user_id='${uid}' AND badge IN ('flawless','gold_bank','hustler'); UPDATE profiles SET avatar=NULL WHERE id='${uid}';`);
}catch(e){console.log('FATAL',e.message);} finally{await b.close();}
