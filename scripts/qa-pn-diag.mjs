import { chromium } from 'playwright';
import { execSync } from 'child_process';
const BASE='http://localhost:5173'; const SS='/private/tmp/claude-501/-Users-admin-wordbankmaster/89648cc7-8d73-41b0-94b4-5f4813950333/scratchpad';
const wait=(p,ms)=>p.waitForTimeout(ms);
const q=(sql)=>execSync(`psql "$SUPABASE_DB_URL" -tA -c "${sql}"`).toString().trim();
const EMAIL=`pnd_${Date.now()}@example.com`, UNAME=`pnd${Date.now()%100000}`;
const b=await chromium.launch();
const ctx=await b.newContext({viewport:{width:390,height:844}});
const page=await ctx.newPage();
const logs=[];
page.on('console',m=>{const t=m.text(); if(/daily|Daily|start|track|❌|⚠️/.test(t)) logs.push(m.type()[0]+':'+t.slice(0,80));});
page.on('request',r=>{ if(/daily_start/.test(r.url())) logs.push('REQ daily_start'); });
await page.goto(BASE,{waitUntil:'networkidle'}); await wait(page,1200);
await page.getByRole('button',{name:/^sign up$/i}).first().click().catch(()=>{}); await wait(page,400);
await page.fill('input[type=email]',EMAIL); await page.fill('input[type=password]','Testpass123!');
await page.getByRole('button',{name:/^sign up$/i}).first().click().catch(()=>{}); await wait(page,4000);
const cl=page.locator('input.claim-input'); if(await cl.count()){await cl.fill(UNAME);await page.locator('button.claim-btn').click().catch(()=>{});await wait(page,1800);}
for(const rx of [/skip for now/i,/^skip$/i]){const bt=page.getByRole('button',{name:rx});if(await bt.count()){await bt.first().click().catch(()=>{});await wait(page,700);}}
await wait(page,1800);
await page.screenshot({path:SS+'/pn-menu.png'});
// list menu-card buttons + any overlay
const info = await page.evaluate(()=>{
  const cards=[...document.querySelectorAll('button.menu-card')].map(c=>c.textContent.replace(/\s+/g,' ').trim().slice(0,40));
  const overlays=[...document.querySelectorAll('[class*=overlay],[class*=modal],[class*=objective],[class*=intro]')].filter(e=>e.offsetParent).map(e=>e.className);
  return { cards, overlays };
});
console.log('menu-cards:', JSON.stringify(info.cards));
console.log('visible overlays:', JSON.stringify(info.overlays));
logs.length=0;
await page.locator('button.menu-card').first().click().catch(e=>console.log('click err',e.message));
await wait(page,4000);
await page.screenshot({path:SS+'/pn-afterclick.png'});
const U=q(`SELECT id FROM auth.users WHERE email='${EMAIL}'`);
console.log('logs after click:', logs.slice(0,12));
console.log('sessions:', q(`SELECT count(*) FROM daily_sessions WHERE user_id='${U}'`));
const t=await page.evaluate(()=>document.body.innerText.slice(0,120).replace(/\n+/g,' | '));
console.log('page text:', t);
try{execSync(`psql "$SUPABASE_DB_URL" -c "DELETE FROM profiles WHERE id='${U}'"`,{stdio:'ignore'});}catch{}
await b.close();
