// Render the menu hero against several background options for picking.
import { chromium } from 'playwright';

const COIN = 'file:///Users/admin/wordbankmaster/static/logo-coin.png';
const WM = 'file:///Users/admin/wordbankmaster/static/wordmark-slogan.png';

// Subtle SVG noise texture (data URI) for "textured" options
const noise = (op) =>
	`url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='2'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)' opacity='${op}'/%3E%3C/svg%3E")`;

const variants = [
	{ name: '1 · Current Navy', bg: `#0a0e14` },
	{
		name: '2 · Onyx + Gold Glow',
		bg: `radial-gradient(120% 80% at 50% 0%, rgba(251,191,36,0.12), rgba(0,0,0,0) 55%), #0b0b0d`
	},
	{ name: '3 · Charcoal Gold', bg: `radial-gradient(130% 90% at 50% 18%, #211a10, #0d0b08 70%)` },
	{ name: '4 · Espresso', bg: `linear-gradient(180deg, #241a10, #100a06)` },
	{ name: '5 · Casino Felt', bg: `radial-gradient(130% 90% at 50% 20%, #11402b, #06170f 72%)` },
	{ name: '6 · Burgundy Luxe', bg: `radial-gradient(130% 90% at 50% 18%, #2a0f17, #0c0609 72%)` },
	{
		name: '7 · Carbon Texture',
		bg: `${noise(0.5)}, radial-gradient(130% 90% at 50% 12%, #181818, #090909 75%)`
	},
	{
		name: '8 · Gold Spotlight',
		bg: `radial-gradient(60% 38% at 50% 30%, rgba(251,191,36,0.22), rgba(0,0,0,0) 60%), #070707`
	}
];

const page = (bg) => `<!doctype html><html><head><meta charset=utf8><style>
  * { margin:0; box-sizing:border-box; font-family: -apple-system, system-ui, sans-serif; }
  body { width:390px; height:844px; background:${bg}; background-size:cover; color:#fff;
         display:flex; flex-direction:column; align-items:center; padding:18px 16px; }
  .top { width:100%; display:flex; justify-content:space-between; align-items:center; margin-bottom:6px; }
  .cash { background:rgba(255,255,255,0.06); border:1px solid rgba(255,255,255,0.1); border-radius:999px;
          padding:5px 12px; font-weight:800; color:#fbbf24; font-size:13px; }
  .ic { width:30px; height:30px; border-radius:9px; background:rgba(255,255,255,0.06);
        border:1px solid rgba(255,255,255,0.1); display:inline-block; margin-left:6px; }
  .coin { width:200px; height:auto; margin-top:8px;
          filter: drop-shadow(0 0 26px rgba(251,191,36,0.55)) drop-shadow(0 10px 40px rgba(251,191,36,0.4)); }
  .wm { width:260px; height:auto; margin:2px 0 22px; }
  .btn { width:100%; padding:16px; border-radius:16px; margin-bottom:11px; font-weight:800; font-size:15px;
         display:flex; align-items:center; gap:10px; border:1px solid rgba(255,255,255,0.08);
         background:rgba(255,255,255,0.04); color:#e8e8ea; }
  .play { background:linear-gradient(135deg,#34d399,#a3e635); color:#06210f; border:none; }
  .lbl { position:fixed; top:8px; left:50%; transform:translateX(-50%); background:rgba(0,0,0,0.6);
         padding:3px 10px; border-radius:8px; font-size:12px; font-weight:700; }
</style></head><body>
  <div class=top><span class=cash>💰 $1,339</span><span><i class=ic></i><i class=ic></i></span></div>
  <img class=coin src="${COIN}">
  <img class=wm src="${WM}">
  <div class="btn play">▶ Play Now</div>
  <div class=btn>⚔ Challenge Friends</div>
  <div class=btn>📅 Daily Quests</div>
  <div class=btn>🏆 Leaderboard</div>
</body></html>`;

const b = await chromium.launch();
const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
const p = await ctx.newPage();
for (let i = 0; i < variants.length; i++) {
	await p.setContent(page(variants[i].bg), { waitUntil: 'networkidle' });
	await p.waitForTimeout(250);
	await p.screenshot({ path: `/tmp/bg-${i}.png` });
}
await b.close();
console.log('done', variants.map((v) => v.name).join(' | '));
