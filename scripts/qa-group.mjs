// Group challenge E2E: THREE independent browser contexts play a real group match
// (host + 2 members) end-to-end, then verify the podium settlement + tiebreaker.
// Group membership is seeded in the DB (that flow is covered elsewhere); the
// challenge → accept → play → settle path is driven fully through the UI.
// Run: set -a; . ./.env; set +a; BASE=http://localhost:5174 WAGER=500 node scripts/qa-group.mjs
import { chromium } from 'playwright';
import { qaBase } from './_qa-guard.mjs';
import { execSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';

const BASE = qaBase('http://localhost:5174');
const DB = process.env.SUPABASE_DB_URL;
const PASS = 'TestPass123!';
const PACK = Number(process.env.PACK || 1);
const WAGER = Number(process.env.WAGER || 0);
const WAGER_LABEL = { 500: '$500', 2000: '$2K', 10000: '$10K' }[WAGER] || null;
const stamp = String(Date.now());
const GNAME = 'QA Group ' + stamp.slice(-5);
const NP = Math.min(Math.max(Number(process.env.PLAYERS || 3), 2), 8);
const PLAYERS = 'abcdefgh'
	.slice(0, NP)
	.split('')
	.map((x) => ({
		email: `qg${x}${stamp}@example.com`,
		uname: `qg${x}${stamp.slice(-6)}`,
		tag: x.toUpperCase()
	}));
mkdirSync('screenshots', { recursive: true });

const sql = (q) =>
	execSync(`psql "${DB}" -tA -c ${JSON.stringify(q)}`, { encoding: 'utf8' }).trim();
const notes = [];
const note = (t) => {
	notes.push(t);
	console.log('  • ' + t);
};

const browser = await chromium.launch();
const errors = [];
async function makePlayer(who) {
	const ctx = await browser.newContext({ viewport: { width: 430, height: 932 }, deviceScaleFactor: 2 });
	const page = await ctx.newPage();
	page.on('console', (m) => {
		if (m.type() === 'error') errors.push(`[${who.tag}] ${m.text().slice(0, 200)}`);
	});
	page.on('pageerror', (e) => errors.push(`[${who.tag}] pageerror: ${String(e).slice(0, 200)}`));
	return { ctx, page, tag: who.tag, who };
}
const wait = (p, ms) => p.waitForTimeout(ms);
const shot = (p, n) => p.screenshot({ path: `screenshots/group-${n}.png` }).catch(() => {});

async function onboard(pl) {
	const { page, who } = pl;
	await page.goto(BASE, { waitUntil: 'networkidle' });
	await wait(page, 1200);
	await page.getByRole('button', { name: /^sign up$/i }).first().click().catch(() => {});
	await wait(page, 400);
	await page.fill('input[type=email]', who.email);
	await page.fill('input[type=password]', PASS);
	await page.getByRole('button', { name: /^sign up$/i }).first().click().catch(() => {});
	await wait(page, 3800);
	const claim = page.locator('input.claim-input');
	if (await claim.count()) {
		await claim.fill(who.uname);
		await page.locator('button.claim-btn').click().catch(() => {});
		await wait(page, 1800);
	}
	const skipPin = page.getByRole('button', { name: /skip for now/i });
	if (await skipPin.count()) {
		await skipPin.first().click().catch(() => {});
		await wait(page, 800);
	}
	const skipTut = page.getByRole('button', { name: /^skip$/i });
	if (await skipTut.count()) {
		await skipTut.first().click().catch(() => {});
		await wait(page, 700);
	}
	await wait(page, 500);
	const reached = (await page.getByText(/play now/i).count()) > 0;
	console.log(`  ${reached ? '✅' : '❌'} onboard ${pl.tag} (@${who.uname})`);
	return reached;
}

// Solve `packSize` puzzles in match mode (same engine as H2H).
async function playMatch(pl, phrases, packSize) {
	const { page, tag } = pl;
	const objGo = page.getByRole('button', { name: /let’s go|let's go/i });
	if (await objGo.count()) {
		await objGo.first().click().catch(() => {});
		await wait(page, 700);
	}
	for (let pos = 1; pos <= packSize; pos++) {
		const solve = page.getByRole('button', { name: /^solve$/i });
		try {
			await solve.first().waitFor({ timeout: 14000 });
		} catch {
			await page.keyboard.press('Escape').catch(() => {});
			await page.getByRole('button', { name: /continue|next|keep going/i }).first().click().catch(() => {});
			await wait(page, 1200);
			try {
				await solve.first().waitFor({ timeout: 8000 });
			} catch {
				note(`[${tag}] puzzle ${pos}: Solve never appeared`);
				await shot(page, `${tag}-stuck-p${pos}`);
				return false;
			}
		}
		const answer = (phrases[pos] || '').toUpperCase().replace(/[^A-Z]/g, '');
		await solve.first().click().catch(() => {});
		await wait(page, 600);
		const boxes = await page.locator('.letter-box').all();
		for (let k = 0; k < boxes.length && k < answer.length; k++) {
			const cls = (await boxes[k].getAttribute('class')) || '';
			if (cls.includes('locked')) continue;
			await page.keyboard.press(answer[k]);
			await wait(page, 45);
		}
		await wait(page, 400);
		await page.getByRole('button', { name: /^submit$/i }).first().click().catch(() => {});
		await wait(page, 3500);
	}
	await shot(page, `${tag}-done`);
	return true;
}

async function acceptAndPlay(pl, phrases, packLen) {
	const { page, tag } = pl;
	await page.goto(BASE, { waitUntil: 'networkidle' });
	await wait(page, 1000);
	await page.getByRole('button', { name: /challenge friends/i }).first().click().catch(() => {});
	await wait(page, 1800);
	const playBtn = page.locator('button.ch-play', { hasText: /^play$/i });
	if (await playBtn.count()) {
		note(`${tag}: sees the group invite`);
		await playBtn.first().click().catch(() => {});
		await wait(page, 3500);
	} else {
		note(`${tag}: ❗ no group invite Play button`);
		await shot(page, `${tag}-noinvite`);
		return false;
	}
	return playMatch(pl, phrases, packLen);
}

try {
	console.log('\n──────── Group challenge (3 players) ────────');
	const P = [];
	for (const who of PLAYERS) P.push(await makePlayer(who));
	for (const pl of P) if (!(await onboard(pl))) throw new Error(`onboard ${pl.tag} failed`);

	// ---- seed the group (owner = A, members A/B/C) + bank ----
	const ids = PLAYERS.map(
		(w) => sql(`SELECT id FROM profiles WHERE lower(username)=lower('${w.uname}')`)
	);
	sql(`UPDATE profiles SET bank = GREATEST(bank, 5000) WHERE id IN ('${ids.join("','")}')`);
	const gid = sql(
		`WITH ins AS (INSERT INTO groups(name, owner_id, join_code) VALUES ('${GNAME}', '${ids[0]}', 'QG${stamp.slice(-4)}') RETURNING id) SELECT id FROM ins`
	);
	for (const id of ids) sql(`INSERT INTO group_members(group_id, user_id) VALUES ('${gid}','${id}') ON CONFLICT DO NOTHING`);
	// mutual friendships (belt-and-suspenders for any UI path)
	for (let i = 0; i < ids.length; i++)
		for (let j = 0; j < ids.length; j++)
			if (i !== j) sql(`INSERT INTO friendships(user_id, friend_id) VALUES ('${ids[i]}','${ids[j]}') ON CONFLICT DO NOTHING`);
	note(`seeded group "${GNAME}" (${gid}) with ${ids.length} members`);

	// ---- A creates a GROUP challenge ----
	console.log('\n── A creates group challenge ──');
	const pa = P[0];
	await pa.page.getByRole('button', { name: /challenge friends/i }).first().click().catch(() => {});
	await wait(pa.page, 1500);
	await pa.page.getByRole('button', { name: /new challenge/i }).first().click().catch(() => {});
	await wait(pa.page, 1000);
	// step 1: switch to "A group" mode, pick the group
	await pa.page.locator('button.ch-mode', { hasText: /group/i }).first().click().catch(() => {});
	await wait(pa.page, 600);
	await shot(pa.page, 'A-wizard-group');
	const groupSelect = pa.page.locator('select.ch-input').first();
	if (await groupSelect.count()) {
		await groupSelect.selectOption({ label: GNAME }).catch(async () => {
			// fallback: select by index (last option = newest group)
			await groupSelect.selectOption({ index: 1 }).catch(() => {});
		});
		note('A: group selected in wizard');
	} else {
		note('A: ❗ no group dropdown');
	}
	await wait(pa.page, 500);
	await pa.page.getByRole('button', { name: /continue/i }).first().click().catch(() => {});
	await wait(pa.page, 700);
	await pa.page.locator('button.ch-seg-btn', { hasText: new RegExp(`^${PACK}$`) }).first().click().catch(() => {});
	await wait(pa.page, 400);
	await pa.page.getByRole('button', { name: /continue/i }).first().click().catch(() => {});
	await wait(pa.page, 700);
	if (WAGER_LABEL) {
		await pa.page
			.locator('button.ante-chip', { hasText: new RegExp('\\' + WAGER_LABEL.replace('$', '\\$')) })
			.first()
			.click()
			.catch(() => {});
		note(`A: wager ${WAGER_LABEL}`);
	} else {
		await pa.page.locator('button.ante-chip', { hasText: /friendly/i }).first().click().catch(() => {});
	}
	await wait(pa.page, 400);
	await pa.page.getByRole('button', { name: /send challenge/i }).first().click().catch(() => {});
	await wait(pa.page, 4000);
	await shot(pa.page, 'A-after-send');

	// ---- read match id + pack ----
	const mid = sql(`SELECT id FROM challenge_matches WHERE group_id='${gid}' ORDER BY created_at DESC LIMIT 1`);
	if (!mid) throw new Error('no group match created');
	note(`match id = ${mid}`);
	const packRows = sql(`SELECT cp.position || '|' || dp.phrase FROM challenge_pack cp JOIN daily_puzzles dp ON dp.id=cp.puzzle_id WHERE cp.match_id='${mid}' ORDER BY cp.position`);
	const phrases = {};
	for (const line of packRows.split('\n')) {
		const [pos, ...rest] = line.split('|');
		if (pos) phrases[Number(pos)] = rest.join('|');
	}
	const packLen = Object.keys(phrases).length || PACK;
	note(`pack (${packLen}): ` + Object.entries(phrases).map(([k, v]) => `${k}:"${v}"`).join('  '));
	note(`participants enrolled: ${sql(`SELECT count(*) FROM challenge_participants WHERE match_id='${mid}'`)}`);

	// ---- A (host) plays; everyone else accepts + plays ----
	console.log('\n── A (host) plays ──');
	const played = { A: await playMatch(pa, phrases, packLen) };
	for (let i = 1; i < P.length; i++) {
		console.log(`\n── ${P[i].tag} accepts + plays ──`);
		played[P[i].tag] = await acceptAndPlay(P[i], phrases, packLen);
	}
	note('played — ' + Object.entries(played).map(([k, v]) => `${k}:${v}`).join(' '));

	// ---- settlement ----
	console.log('\n── settlement ──');
	await wait(pa.page, 3000);
	let status = sql(`SELECT status FROM challenge_matches WHERE id='${mid}'`);
	if (status !== 'settled') {
		sql(`SELECT settle_expired_matches()`);
		await wait(pa.page, 1500);
		status = sql(`SELECT status FROM challenge_matches WHERE id='${mid}'`);
	}
	note(`match status: ${status} · payout=${sql(`SELECT payout FROM challenge_matches WHERE id='${mid}'`)} · wager=$${WAGER}`);
	const parts = sql(
		`SELECT p.username || ' | score=' || cp.total_score || ' solved=' || cp.solved || ' elapsed=' || round(public._match_elapsed(cp.started_at,cp.finished_at,cp.joined_at),1) || 's | ' || cp.state || ' | outcome=' || coalesce(gr.outcome,'-') || ' rank=' || coalesce(gr.rank::text,'-') || ' earned=$' || coalesce(gr.earned,0) || ' net=$' || coalesce(gr.net,0) FROM challenge_participants cp JOIN profiles p ON p.id=cp.user_id LEFT JOIN game_results gr ON gr.match_id=cp.match_id AND gr.user_id=cp.user_id WHERE cp.match_id='${mid}' ORDER BY gr.rank NULLS LAST`
	);
	note('podium standings (DB):');
	parts.split('\n').forEach((r) => console.log('       ' + r));
	if (WAGER > 0) {
		const pot = sql(`SELECT coalesce(sum(stake),0) FROM challenge_participants WHERE match_id='${mid}' AND paid`);
		const split = NP >= 4 ? '60/30/10 across top 3' : '70/30 across top 2';
		note(`pot=$${pot} of ${NP} players (should split ${split})`);
	}

	// ---- A opens Results ----
	console.log('\n── A views results ──');
	await pa.page.goto(BASE, { waitUntil: 'networkidle' });
	await wait(pa.page, 1200);
	await pa.page.getByRole('button', { name: /challenge friends/i }).first().click().catch(() => {});
	await wait(pa.page, 2000);
	const resultsBtn = pa.page.getByRole('button', { name: /results/i });
	if (await resultsBtn.count()) {
		await resultsBtn.first().click().catch(() => {});
		await wait(pa.page, 1500);
		await shot(pa.page, 'A-results-modal');
		note(`A results modal standings rows: ${await pa.page.locator('.md-standings .md-row').count()}`);
	} else {
		note('A: ❗ no Results button');
		await shot(pa.page, 'A-noresults');
	}
} catch (e) {
	console.log('\n❌ FATAL: ' + (e?.message || e));
} finally {
	console.log('\n──────── console/page errors ────────');
	if (!errors.length) console.log('  ✅ none');
	else errors.forEach((e) => console.log('  ⚠️  ' + e));
	console.log('\n──────── observations ────────');
	notes.forEach((n) => console.log('  • ' + n));
	await browser.close();
	console.log(`\ngroup=${GNAME} · players: ${PLAYERS.map((p) => '@' + p.uname).join(' ')}`);
}
