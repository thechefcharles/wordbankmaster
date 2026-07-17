// Two-player 1-on-1 (H2H) challenge E2E: two independent browser contexts play a
// real friendly match end-to-end. Reports console errors + UX observations.
// Run: set -a; . ./.env; set +a; BASE=http://localhost:5174 node scripts/qa-h2h.mjs
import { chromium } from 'playwright';
import { qaBase } from './_qa-guard.mjs';
import { execSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';

const BASE = qaBase('http://localhost:5174');
const DB = process.env.SUPABASE_DB_URL;
const PASS = 'TestPass123!';
const PACK = Number(process.env.PACK || 2);
const WAGER = Number(process.env.WAGER || 0); // 0=friendly, else 500/2000/10000
const WAGER_LABEL = { 500: '$500', 2000: '$2K', 10000: '$10K' }[WAGER] || null;
const stamp = String(Date.now());
const A = { email: `qaa${stamp}@example.com`, uname: 'qaa' + stamp.slice(-7) };
const B = { email: `qab${stamp}@example.com`, uname: 'qab' + stamp.slice(-7) };
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
async function makePlayer(tag) {
	const ctx = await browser.newContext({ viewport: { width: 430, height: 932 }, deviceScaleFactor: 2 });
	const page = await ctx.newPage();
	page.on('console', (m) => {
		if (m.type() === 'error') errors.push(`[${tag}] ${m.text().slice(0, 200)}`);
	});
	page.on('pageerror', (e) => errors.push(`[${tag}] pageerror: ${String(e).slice(0, 200)}`));
	return { ctx, page, tag };
}
const wait = (p, ms) => p.waitForTimeout(ms);
const shot = (p, n) => p.screenshot({ path: `screenshots/h2h-${n}.png` }).catch(() => {});

async function onboard(pl, who) {
	const { page } = pl;
	await page.goto(BASE, { waitUntil: 'networkidle' });
	await wait(page, 1200);
	// sign up
	await page.getByRole('button', { name: /^sign up$/i }).first().click().catch(() => {});
	await wait(page, 400);
	await page.fill('input[type=email]', who.email);
	await page.fill('input[type=password]', PASS);
	await page.getByRole('button', { name: /^sign up$/i }).first().click().catch(() => {});
	await wait(page, 3800);
	// username gate
	const claim = page.locator('input.claim-input');
	if (await claim.count()) {
		await claim.fill(who.uname);
		await page.locator('button.claim-btn').click().catch(() => {});
		await wait(page, 1800);
	}
	// PIN setup — skip (keeps requirePin a no-op)
	const skipPin = page.getByRole('button', { name: /skip for now/i });
	if (await skipPin.count()) {
		await skipPin.first().click().catch(() => {});
		await wait(page, 800);
	}
	// tutorial — skip
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

// Solve `packSize` puzzles in match mode; phrases keyed by 1-based position.
async function playMatch(pl, phrases, packSize) {
	const { page, tag } = pl;
	// dismiss objective card if present
	const objGo = page.getByRole('button', { name: /let’s go|let's go/i });
	if (await objGo.count()) {
		await objGo.first().click().catch(() => {});
		await wait(page, 700);
	}
	for (let pos = 1; pos <= packSize; pos++) {
		// wait for the Solve button (board ready for this puzzle)
		const solve = page.getByRole('button', { name: /^solve$/i });
		try {
			await solve.first().waitFor({ timeout: 14000 });
		} catch {
			// maybe a per-solve receipt is covering it — try to dismiss and retry
			await page.keyboard.press('Escape').catch(() => {});
			await page.getByRole('button', { name: /continue|next|keep going|play/i }).first().click().catch(() => {});
			await wait(page, 1200);
			try {
				await solve.first().waitFor({ timeout: 8000 });
			} catch {
				note(`[${tag}] puzzle ${pos}: Solve button never appeared`);
				await shot(page, `${tag}-stuck-p${pos}`);
				return false;
			}
		}
		const answer = (phrases[pos] || '').toUpperCase().replace(/[^A-Z]/g, '');
		await solve.first().click().catch(() => {}); // enter guess mode
		await wait(page, 600);
		const boxes = await page.locator('.letter-box').all();
		if (boxes.length !== answer.length) {
			note(`[${tag}] puzzle ${pos}: ${boxes.length} slots vs answer len ${answer.length} ("${phrases[pos]}") — punctuation/reveal mismatch`);
		}
		for (let k = 0; k < boxes.length && k < answer.length; k++) {
			const cls = (await boxes[k].getAttribute('class')) || '';
			if (cls.includes('locked')) continue;
			await page.keyboard.press(answer[k]);
			await wait(page, 45);
		}
		await wait(page, 400);
		await shot(page, `${tag}-p${pos}-filled`);
		await page.getByRole('button', { name: /^submit$/i }).first().click().catch(() => {});
		await wait(page, 3500); // reveal + advance
	}
	// finished the pack
	const winRe = /deposit|available balance|waiting|banking with wordbank|you (won|took)|standings|no luck|bust/i;
	await page.getByText(winRe).first().waitFor({ timeout: 9000 }).catch(() => {});
	await shot(page, `${tag}-done`);
	return true;
}

try {
	console.log('\n──────── H2H two-player match ────────');
	const pa = await makePlayer('A');
	const pb = await makePlayer('B');
	const okA = await onboard(pa, A);
	const okB = await onboard(pb, B);
	if (!okA || !okB) throw new Error('onboarding failed');

	// ---- A creates a friendly challenge vs B ----
	console.log('\n── A creates challenge ──');
	await pa.page.getByRole('button', { name: /challenge friends/i }).first().click().catch(() => {});
	await wait(pa.page, 1500);
	await pa.page.getByRole('button', { name: /new challenge/i }).first().click().catch(() => {});
	await wait(pa.page, 1000);
	await shot(pa.page, 'A-wizard-step1');
	// step 1: search B, pick from list
	const oppInput = pa.page.locator('input.ch-input').first();
	await oppInput.fill(B.uname);
	await wait(pa.page, 1400); // debounced search
	const pickrow = pa.page.locator('button.ch-pickrow');
	if (await pickrow.count()) {
		await pickrow.first().click().catch(() => {});
		note('A: opponent found via search + picked');
	} else {
		note('A: ❗ no search results for B username — cannot pick opponent');
		await shot(pa.page, 'A-nopick');
	}
	await wait(pa.page, 600);
	await pa.page.getByRole('button', { name: /continue/i }).first().click().catch(() => {});
	await wait(pa.page, 700);
	// step 2: pack size
	await pa.page.locator('button.ch-seg-btn', { hasText: new RegExp(`^${PACK}$`) }).first().click().catch(() => {});
	await wait(pa.page, 400);
	await pa.page.getByRole('button', { name: /continue/i }).first().click().catch(() => {});
	await wait(pa.page, 700);
	await shot(pa.page, 'A-wizard-step3');
	// step 3: ante (friendly or a wager), send
	if (WAGER_LABEL) {
		await pa.page
			.locator('button.ante-chip', { hasText: new RegExp('\\' + WAGER_LABEL.replace('$', '\\$')) })
			.first()
			.click()
			.catch(() => {});
		note(`A: wager ${WAGER_LABEL} selected`);
	} else {
		await pa.page.locator('button.ante-chip', { hasText: /friendly/i }).first().click().catch(() => {});
	}
	await wait(pa.page, 400);
	await pa.page.getByRole('button', { name: /send challenge/i }).first().click().catch(() => {});
	await wait(pa.page, 4000);
	await shot(pa.page, 'A-after-send');

	// ---- read match id + pack phrases from DB ----
	const mid = sql(`SELECT id FROM challenge_matches WHERE host_id=(SELECT id FROM profiles WHERE lower(username)=lower('${A.uname}')) ORDER BY created_at DESC LIMIT 1`);
	if (!mid) throw new Error('no match row found for A — create_match failed');
	note(`match id = ${mid}`);
	const packRows = sql(`SELECT cp.position || '|' || dp.phrase FROM challenge_pack cp JOIN daily_puzzles dp ON dp.id=cp.puzzle_id WHERE cp.match_id='${mid}' ORDER BY cp.position`);
	const phrases = {};
	for (const line of packRows.split('\n')) {
		const [pos, ...rest] = line.split('|');
		if (pos) phrases[Number(pos)] = rest.join('|');
	}
	note(`pack (${Object.keys(phrases).length}): ` + Object.entries(phrases).map(([k, v]) => `${k}:"${v}"`).join('  '));
	const packLen = Object.keys(phrases).length || PACK;

	// ---- B accepts via Community → Challenges ----
	console.log('\n── B accepts ──');
	await pb.page.getByRole('button', { name: /challenge friends/i }).first().click().catch(() => {});
	await wait(pb.page, 1800);
	await shot(pb.page, 'B-challenges-tab');
	const playBtn = pb.page.locator('button.ch-play', { hasText: /^play$/i });
	if (await playBtn.count()) {
		note('B: sees the invite with a Play button');
		await playBtn.first().click().catch(() => {});
		await wait(pb.page, 3500);
	} else {
		note('B: ❗ no "Play" invite row in Challenges tab');
		await shot(pb.page, 'B-noinvite');
	}

	// ---- both play their pack ----
	console.log('\n── A plays ──');
	const aPlayed = await playMatch(pa, phrases, packLen);
	console.log('\n── B plays ──');
	const bPlayed = await playMatch(pb, phrases, packLen);
	note(`A completed pack: ${aPlayed} · B completed pack: ${bPlayed}`);

	// ---- settlement ----
	console.log('\n── settlement ──');
	await wait(pa.page, 3000);
	let status = sql(`SELECT status FROM challenge_matches WHERE id='${mid}'`);
	note(`match status after both finish: ${status}`);
	if (status !== 'settled') {
		// nudge server settlement path
		sql(`SELECT settle_expired_matches()`);
		await wait(pa.page, 1500);
		status = sql(`SELECT status FROM challenge_matches WHERE id='${mid}'`);
		note(`match status after settle_expired_matches(): ${status}`);
	}
	const parts = sql(
		`SELECT p.username || ' | score=' || cp.total_score || ' solved=' || cp.solved || '/' || (SELECT pack_size FROM challenge_matches WHERE id='${mid}') || ' elapsed=' || round(public._match_elapsed(cp.started_at, cp.finished_at, cp.joined_at),1) || 's | outcome=' || coalesce(gr.outcome,'-') || ' rank=' || coalesce(gr.rank::text,'-') || ' earned=$' || coalesce(gr.earned,0) || ' net=$' || coalesce(gr.net,0) FROM challenge_participants cp JOIN profiles p ON p.id=cp.user_id LEFT JOIN game_results gr ON gr.match_id=cp.match_id AND gr.user_id=cp.user_id WHERE cp.match_id='${mid}' ORDER BY gr.rank NULLS LAST`
	);
	note(`final standings (DB) — wager=$${WAGER}:`);
	parts.split('\n').forEach((r) => console.log('       ' + r));
	if (WAGER > 0) {
		const bankDelta = sql(
			`SELECT p.username || ' bank=$' || pr.bank FROM challenge_participants cp JOIN profiles p ON p.id=cp.user_id JOIN profiles pr ON pr.id=cp.user_id WHERE cp.match_id='${mid}'`
		);
		note('post-settle bank:');
		bankDelta.split('\n').forEach((r) => console.log('       ' + r));
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
		const hasStandings = (await pa.page.locator('.md-standings .md-row').count()) > 0;
		note(`A results modal standings rows: ${await pa.page.locator('.md-standings .md-row').count()} (${hasStandings ? 'ok' : 'MISSING'})`);
	} else {
		note('A: ❗ no "Results" button on the settled match row');
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
	console.log(`\nA=${A.email} @${A.uname} · B=${B.email} @${B.uname}`);
}
