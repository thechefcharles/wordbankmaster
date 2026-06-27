import { chromium } from 'playwright';
import { execSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
const BASE=process.env.BASE||'http://localhost:5173', EMAIL='pwtest+wb@example.com', PASS='TestPass123!', DB=process.env.SUPABASE_DB_URL;
mkdirSync('screenshots/lb',{recursive:true});
const sql=(q)=>execSync(`psql "${DB}" -tAc "${q.replace(/"/g,'\\"')}"`,{encoding:'utf8'}).trim();
const b=await chromium.launch(); const p=await(await b.newContext({viewport:{width:430,height:932},deviceScaleFactor:2})).newPage();
p.setDefaultTimeout(8000); const wait=(ms)=>p.waitForTimeout(ms);
const kill=()=>p.evaluate(()=>{localStorage.setItem('wb_tutorial_v3','true');localStorage.setItem('wb_launch_welcome_v1','1');for(const m of['daily','climb','freeplay','match','makeup'])localStorage.setItem('wb_obj_'+m,'1');}).catch(()=>{});
const skipPin=async()=>{await p.getByText(/skip for now/i).first().click({timeout:1200}).catch(()=>{});await wait(400);};
try{
  sql(`UPDATE profiles SET username=COALESCE(username,'pwtest_wb') WHERE id=(SELECT id FROM auth.users WHERE email='${EMAIL}')`);
  await p.goto(BASE,{waitUntil:'domcontentloaded'});await wait(500);await kill();
  if(await p.locator('input[type=password]').count()){await p.getByPlaceholder(/email or username/i).first().fill(EMAIL);await p.locator('input[type=password]').first().fill(PASS);await p.getByRole('button',{name:/^log in$/i}).first().click().catch(()=>{});await wait(2800);}
  await kill();await skipPin();await wait(800);
  await p.locator('.menu-card', { hasText: 'Leaderboard' }).click().catch(()=>{}); await wait(1400);
  console.log('sub-people on lb (should be 0):', await p.locator('.sub-people').count(), '| # header present:', await p.locator('th .sort').first().innerText().catch(()=>'?'));
  await p.screenshot({path:'screenshots/lb/20-centered.png'});
  // click # twice → reverse (last to top)
  await p.locator('th .sort', { hasText: '#' }).click().catch(()=>{}); await wait(300);
  await p.locator('th .sort', { hasText: '#' }).click().catch(()=>{}); await wait(400);
  const firstPlace = await p.locator('tbody tr td.rank').first().innerText().catch(()=>'?');
  console.log('after reversing #, top row rank:', firstPlace);
  await p.screenshot({path:'screenshots/lb/21-reversed.png'});
  console.log('done');
}catch(e){console.log('FATAL',e.message);} finally{await b.close();}
