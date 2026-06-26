import { chromium } from 'playwright';
import { execSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
const BASE = process.env.BASE || 'http://localhost:5173';
const EMAIL='pwtest+wb@example.com', PASS='TestPass123!', DB=process.env.SUPABASE_DB_URL;
mkdirSync('screenshots/avatar',{recursive:true});
const sql=(q)=>execSync(`psql "${DB}" -tAc "${q.replace(/"/g,'\\"')}"`,{encoding:'utf8'}).trim();
const b=await chromium.launch(); const p=await(await b.newContext({viewport:{width:430,height:932},deviceScaleFactor:2})).newPage();
p.setDefaultTimeout(8000); const wait=(ms)=>p.waitForTimeout(ms);
const kill=()=>p.evaluate(()=>{localStorage.setItem('wb_tutorial_v3','true');localStorage.setItem('wb_launch_welcome_v1','1');for(const m of['daily','climb','freeplay','match','makeup'])localStorage.setItem('wb_obj_'+m,'1');}).catch(()=>{});
const skipPin=async()=>{await p.getByText(/skip for now/i).first().click({timeout:1200}).catch(()=>{});await wait(400);};
try{
  const uid=sql(`SELECT id FROM auth.users WHERE email='${EMAIL}'`);
  sql(`UPDATE profiles SET username=COALESCE(username,'pwtest_wb'), bank=50000, avatar='{"clothing":"hoodie","clothesColor":"5199e4"}'::jsonb WHERE id='${uid}'`);
  await p.goto(BASE,{waitUntil:'domcontentloaded'});await wait(500);await kill();
  if(await p.locator('input[type=password]').count()){await p.getByPlaceholder(/email or username/i).first().fill(EMAIL);await p.locator('input[type=password]').first().fill(PASS);await p.getByRole('button',{name:/^log in$/i}).first().click().catch(()=>{});await wait(2800);}
  await kill();await skipPin();await wait(600);
  await p.goto(BASE+'/avatar',{waitUntil:'domcontentloaded'});await wait(1400);
  await p.locator('.cat-chip',{hasText:'Shirt Design'}).click().catch(()=>{});await wait(500);
  await p.locator('.opt',{hasText:'Skull'}).first().click().catch(()=>{});await wait(700); // pick skull → should auto-wear graphic tee
  const cfg = await p.evaluate(()=>document.querySelector('.av-hero svg')?'has-svg':'no');
  console.log('hero after picking design:', cfg);
  await p.screenshot({path:'screenshots/avatar/50-gfx-applied.png'});
  // randomize
  await p.locator('.av-rand').click().catch(()=>{});await wait(600);
  await p.screenshot({path:'screenshots/avatar/51-random.png'});
  console.log('done');
}catch(e){console.log('FATAL',e.message);} finally{await b.close();}
