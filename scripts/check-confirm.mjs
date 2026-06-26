import { chromium } from 'playwright';
import { execSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
const BASE=process.env.BASE||'http://localhost:5173', EMAIL='pwtest+wb@example.com', PASS='TestPass123!', DB=process.env.SUPABASE_DB_URL;
mkdirSync('screenshots/confirm',{recursive:true});
const sql=(q)=>execSync(`psql "${DB}" -tAc "${q.replace(/"/g,'\\"')}"`,{encoding:'utf8'}).trim();
const sqlf=(q)=>execSync(`psql "${DB}"`,{input:q,encoding:'utf8'});
const b=await chromium.launch(); const p=await(await b.newContext({viewport:{width:430,height:932},deviceScaleFactor:2})).newPage();
p.setDefaultTimeout(8000); const wait=(ms)=>p.waitForTimeout(ms);
const kill=()=>p.evaluate(()=>{localStorage.setItem('wb_tutorial_v3','true');localStorage.setItem('wb_launch_welcome_v1','1');for(const m of['daily','climb','freeplay','match','makeup'])localStorage.setItem('wb_obj_'+m,'1');}).catch(()=>{});
const skipPin=async()=>{await p.getByText(/skip for now/i).first().click({timeout:1200}).catch(()=>{});await wait(400);};
try{
  const me=sql(`SELECT id FROM auth.users WHERE email='${EMAIL}'`); const other='3ccf702f-4788-4ce2-b84e-854cefed98e5';
  sqlf(`UPDATE profiles SET username=COALESCE(username,'pwtest_wb') WHERE id='${me}';
    INSERT INTO friendships(user_id,friend_id) VALUES ('${me}','${other}'),('${other}','${me}') ON CONFLICT DO NOTHING;`);
  await p.goto(BASE,{waitUntil:'domcontentloaded'});await wait(500);await kill();
  if(await p.locator('input[type=password]').count()){await p.getByPlaceholder(/email or username/i).first().fill(EMAIL);await p.locator('input[type=password]').first().fill(PASS);await p.getByRole('button',{name:/^log in$/i}).first().click().catch(()=>{});await wait(2800);}
  await kill();await skipPin();await wait(500);
  await p.goto(BASE+'/friends',{waitUntil:'domcontentloaded'});await wait(1200);
  await p.locator('.act.remove, [title="Remove friend"]').first().click().catch(()=>{}); await wait(500);
  console.log('confirm modal:', await p.locator('.cm-card').count(), '| title:', await p.locator('.cm-title').innerText().catch(()=>'?'));
  await p.screenshot({path:'screenshots/confirm/01-remove-friend.png'});
  console.log('done');
  sqlf(`DELETE FROM friendships WHERE (user_id='${me}' AND friend_id='${other}') OR (user_id='${other}' AND friend_id='${me}');`);
}catch(e){console.log('FATAL',e.message);} finally{await b.close();}
