// Screenshot the full-body kit preview (no auth needed — it's a static preview).
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';
const BASE = process.env.BASE || 'http://localhost:5173';
mkdirSync('screenshots/avatar', { recursive: true });
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 430, height: 932 }, deviceScaleFactor: 2 })).newPage();
p.setDefaultTimeout(8000);
const wait = (ms) => p.waitForTimeout(ms);
try {
  await p.goto(BASE + '/avatar/kit', { waitUntil: 'networkidle' }); await wait(1200);
  console.log('layers rendered:', await p.locator('.kit-layer').count(), '| slots:', await p.locator('.kp-slot').count());
  await p.screenshot({ path: 'screenshots/avatar/20-kit-default.png' });
  // swap a few parts (hoodie, shorts, boots, long hair, glasses)
  await p.locator('.kp-opt', { hasText: 'Hoodie' }).click().catch(()=>{}); await wait(200);
  await p.locator('.kp-opt', { hasText: 'Shorts' }).click().catch(()=>{}); await wait(200);
  await p.locator('.kp-opt', { hasText: 'Boots' }).click().catch(()=>{}); await wait(200);
  await p.locator('.kp-opt', { hasText: 'Long' }).click().catch(()=>{}); await wait(200);
  await p.locator('.kp-opt', { hasText: 'Glasses' }).click().catch(()=>{}); await wait(300);
  await p.screenshot({ path: 'screenshots/avatar/21-kit-swapped.png' });
  console.log('done');
} catch (e) { console.log('FATAL', e.message); }
finally { await b.close(); }
