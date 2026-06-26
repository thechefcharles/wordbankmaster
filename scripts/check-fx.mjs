import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';
const BASE = process.env.BASE || 'http://localhost:5173';
mkdirSync('screenshots/avatar', { recursive: true });
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 430, height: 932 }, deviceScaleFactor: 2 })).newPage();
p.setDefaultTimeout(8000);
try {
  await p.goto(BASE + '/avatar/fx', { waitUntil: 'networkidle' }); await p.waitForTimeout(1500);
  console.log('holo svg:', await p.locator('.fx-inner svg').count(), '| ring:', await p.locator('.fx-ring').count(), '| crown:', await p.locator('.fx-crown').count(), '| holo gradient applied:', (await p.locator('.fx-inner').innerHTML()).includes('wbHolo'));
  await p.screenshot({ path: 'screenshots/avatar/30-fx.png' });
  console.log('done');
} catch (e) { console.log('FATAL', e.message); }
finally { await b.close(); }
