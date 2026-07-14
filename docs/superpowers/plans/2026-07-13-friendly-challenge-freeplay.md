# Friendly Challenges as Free Play — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make friendly challenge matches (wager = $0) present as ★ points like Free Play, bank their earned ★ into the device Free Play total, and stop them from feeding any global stats, leaderboards, or badges.

**Architecture:** Friendly matches already play under `gameMode:'match'` on a self-contained per-puzzle bounty budget (no real money). This change is (1) a client display swap `$`→`★` gated on a new `isFriendlyMatch`/`matchInfo.friendly` flag, (2) a client points-bank hook on match completion with per-match dedup, and (3) server-side gating so friendly settles write no `game_results` row and award no badges/category credit, plus read-side `wager > 0` backstops.

**Tech Stack:** SvelteKit 2.16 (mixed Svelte 4/5), Supabase Postgres SECURITY DEFINER RPCs, `node:test` for pure-unit tests, prod migrations applied directly via `psql "$SUPABASE_DB_URL"`.

## Global Constraints

- **Friendly ≡ `challenge_matches.wager = 0`.** There is no separate flag column; derive everything from wager.
- **Money matches (`wager > 0`) must be completely unaffected** — same `$` HUD, same stats, same payout.
- **The ★ points unit** is the existing Free Play mark; reuse the `.bp-fp-mark` / `.brc-star` styling, do not invent new glyphs.
- **Free Play points are device-local** localStorage under the `freeplay:` namespace; banking must dedup per match id so re-observing a completed board never double-counts.
- Test files use RELATIVE imports (`../freeplay/points.js`), never `$lib` aliases, so `node --test` runs outside Vite.
- SQL migrations are built from the **live** function bodies (files carry `Full body applied via MCP` notes and may lag the DB); dump live → transform → assert anchor counts → rollback-test → apply → commit as `supabase-*.sql`.
- Git: end commit messages with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

### Task 1: Device-local per-match points banking

**Files:**
- Modify: `src/lib/freeplay/points.js`
- Test: `src/lib/freeplay/points.test.js` (create if absent)

**Interfaces:**
- Consumes: existing `recordSolve(storage, runScore)` and `loadPoints(storage)` in the same file.
- Produces: `bankMatchPoints(storage, matchId, score) => {total,best} | null` — banks `score` into the Free Play total exactly once per `matchId`; returns the new totals, or `null` if `matchId` was already banked or is nullish. Task 2 calls this.

- [ ] **Step 1: Write the failing test**

Create/append `src/lib/freeplay/points.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { bankMatchPoints, loadPoints } from './points.js';

function memStorage() {
	const m = new Map();
	return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)) };
}

test('bankMatchPoints adds a match score to the Free Play total once', () => {
	const s = memStorage();
	const r = bankMatchPoints(s, 'match-1', 250);
	assert.equal(r.total, 250);
	assert.equal(loadPoints(s).total, 250);
});

test('bankMatchPoints is a no-op the second time for the same match id', () => {
	const s = memStorage();
	bankMatchPoints(s, 'match-1', 250);
	const again = bankMatchPoints(s, 'match-1', 250); // re-observed completed board
	assert.equal(again, null);
	assert.equal(loadPoints(s).total, 250); // not 500
});

test('bankMatchPoints ignores a nullish match id', () => {
	const s = memStorage();
	assert.equal(bankMatchPoints(s, null, 100), null);
	assert.equal(loadPoints(s).total, 0);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test src/lib/freeplay/points.test.js`
Expected: FAIL — `bankMatchPoints` is not exported.

- [ ] **Step 3: Implement `bankMatchPoints`**

Append to `src/lib/freeplay/points.js` (after `recordSolve`):

```js
const K_BANKED = 'freeplay:bankedMatches';

/** @param {{getItem:(k:string)=>string|null}} storage @returns {string[]} */
function readBanked(storage) {
	try {
		const a = JSON.parse(storage.getItem(K_BANKED) ?? '[]');
		return Array.isArray(a) ? a : [];
	} catch {
		return [];
	}
}

/** Bank a friendly match's final score into the device Free Play total — ONCE per match id.
 * Returns the new totals, or null if this match was already banked or matchId is nullish.
 * @param {{getItem:(k:string)=>string|null,setItem:(k:string,v:string)=>void}} storage
 * @param {string|null|undefined} matchId @param {number} score */
export function bankMatchPoints(storage, matchId, score) {
	if (matchId == null) return null;
	const id = String(matchId);
	const banked = readBanked(storage);
	if (banked.includes(id)) return null;
	banked.push(id);
	storage.setItem(K_BANKED, JSON.stringify(banked));
	return recordSolve(storage, score);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test src/lib/freeplay/points.test.js`
Expected: PASS (3/3).

- [ ] **Step 5: Commit**

```bash
git add src/lib/freeplay/points.js src/lib/freeplay/points.test.js
git commit -m "Free Play: bankMatchPoints — bank a friendly match's ★ once per match id

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Bank friendly ★ on match completion + expose the friendly flag

**Files:**
- Modify: `src/lib/stores/GameStore.js` (`reconcileMatchBoard`, ~714-745; import at line 53)

**Interfaces:**
- Consumes: `bankMatchPoints` from Task 1; existing `fpStorage()` (line 390), `activeMatchId` (line 711), `reconcileMatchBoard(board)`.
- Produces: `matchInfo.friendly` (boolean) on the gameStore for Tasks 3's display reads; side-effect of banking `match.total_score` into the Free Play total when a friendly match is done.

- [ ] **Step 1: Import `bankMatchPoints`**

`src/lib/stores/GameStore.js:53` currently:
```js
import { loadPoints, recordSolve } from '$lib/freeplay/points.js';
```
Change to:
```js
import { loadPoints, recordSolve, bankMatchPoints } from '$lib/freeplay/points.js';
```

- [ ] **Step 2: Add the `friendly` flag to matchInfo**

In `reconcileMatchBoard` (line ~727), change the `matchInfo` object so it carries a derived friendly flag:
```js
			matchInfo: {
				...match,
				id: activeMatchId,
				standing: board.standing ?? null,
				friendly: (match.wager ?? 0) === 0
			}
```

- [ ] **Step 3: Bank the ★ when a friendly match finishes**

In the `if (done) { … }` block (line ~730), after the existing confetti/`fx('win')`, add the bank call — friendly only, deduped by match id:
```js
		if (done) {
			setTimeout(() => launchConfetti(), 250);
			fx('win');
			// Friendly (wager 0) banks its ★ into the device Free Play total — once per match.
			if ((match.wager ?? 0) === 0) {
				bankMatchPoints(fpStorage(), activeMatchId, match.total_score ?? 0);
			}
		}
```

- [ ] **Step 4: Verify build + existing unit tests still pass**

Run: `node --test src/lib/freeplay/*.test.js && npm run build`
Expected: all node tests PASS; build succeeds with no new errors.

- [ ] **Step 5: Commit**

```bash
git add src/lib/stores/GameStore.js
git commit -m "Challenges: mark friendly matches + bank their ★ into Free Play on finish

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Friendly match HUD renders ★ points, not $

**Files:**
- Modify: `src/routes/+page.svelte` (reactive block ~590; balance chip ~4386; score/beat ~4485-4499; bounty hero ~4621)
- Modify: `src/lib/components/Keyboard.svelte:125`

**Interfaces:**
- Consumes: `matchInfo.friendly` (Task 2), existing `isMatch`, `matchInfo`, `$tweenNet`, `fpPoints`, `.bp-fp-mark`, `.brc-star` styles.
- Produces: no new exports; UI-only.

- [ ] **Step 1: Add the `isFriendlyMatch` reactive**

`src/routes/+page.svelte`, immediately after the `isMatch`/`matchInfo` lines (~591), add:
```js
	$: isFriendlyMatch = isMatch && (matchInfo?.wager ?? 0) === 0;
```

- [ ] **Step 2: Balance chip → ★ points for a friendly**

At `src/routes/+page.svelte:4386`, widen the Free Play branch condition so a friendly match uses the same `★ … pts` chip (it banks into the same total):
```svelte
				{#if $gameStore.gameMode === 'freeplay' || isFriendlyMatch}
```
(Leave the chip body — `★ {fpPoints.total} pts` — unchanged. The `{:else}` real-balance branch now only runs for money matches and the solo money modes.)

- [ ] **Step 3: "Your Score" + "Beat" chips → ★ for a friendly**

At `src/routes/+page.svelte:4490`, change:
```svelte
					<span class="ms-val">${Math.round(matchInfo.total_score ?? 0).toLocaleString()}</span>
```
to:
```svelte
					<span class="ms-val">{isFriendlyMatch ? '★' : '$'}{Math.round(matchInfo.total_score ?? 0).toLocaleString()}</span>
```

At `src/routes/+page.svelte:4494-4499`, change the Beat chip's leading `$` to the same conditional:
```svelte
					{#if matchInfo.target != null}<span class="beat-chip"
							>Beat {isFriendlyMatch ? '★' : '$'}{Number(
								matchInfo.target
							).toLocaleString()}{#if matchInfo.target_kind === 'place'}
								to place{/if}</span
						>{/if}
```

- [ ] **Step 4: Bounty hero → ★ for a friendly**

At `src/routes/+page.svelte:4621-4629`, the `{:else if isMatch}` branch renders `${…$tweenNet}`. Replace its inner `$` with a conditional mark so a friendly shows the gold ★:
```svelte
							{:else if isMatch}
								<button
									class="bp-amount bp-amount-btn"
									title="What is this?"
									on:click={() => {
										fx('tap');
										showAnteInfo = true;
									}}
									>{#if isFriendlyMatch}<span class="bp-fp-mark" aria-hidden="true">★</span>{:else}${/if}{Math.max(
										0,
										Math.round($tweenNet)
									).toLocaleString()}</button
								>
```
(The `{:else}${/if}` renders a literal `$` for money matches; the `{#if}` renders the ★ span for friendlies — matching the Free Play hero at line 4630-4636.)

- [ ] **Step 5: Keyboard prices → ★ for a friendly**

`src/lib/components/Keyboard.svelte:125` currently:
```js
	$: priceMark = $gameStore.gameMode === 'freeplay' ? '★' : '$';
```
Change to (a friendly match is `gameMode==='match'` with `matchInfo.friendly`):
```js
	$: priceMark =
		$gameStore.gameMode === 'freeplay' || $gameStore.matchInfo?.friendly ? '★' : '$';
```

- [ ] **Step 6: Verify in the running app (manual/visual)**

Run: `npm run build` (must succeed). Then visually confirm on a friendly match: bounty hero shows `★`, keyboard keys show `★`, top chip shows `★ … pts`, "Your Score" shows `★`. Confirm a **money** match still shows `$` in all four spots. (A two-player friendly is exercised end-to-end in Task 5; this step is the build + spot check.)

- [ ] **Step 7: Commit**

```bash
git add src/routes/+page.svelte src/lib/components/Keyboard.svelte
git commit -m "Challenges: friendly match HUD shows ★ points instead of \$ (hero, keys, chip, score)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Server — friendly matches count nowhere (stats gating)

**Files:**
- Create: `supabase-friendly-no-stats.sql` (final applied bodies, committed for the record)
- Touches live functions: `_match_settle`, `_match_record_solve` (the per-solve category-credit caller in `supabase-challenge-opponent-notify.sql`), `get_challenge_leaderboard`, and the best-bounty function in `supabase-best-bounty.sql`.

**Interfaces:**
- Consumes: `challenge_matches.wager` (friendly ≡ 0).
- Produces: a settled friendly writes **no** `game_results` row, awards **no** `first_blood`/`hustler`, records **no** category solve; leaderboard + best-bounty additionally filter `wager > 0`. Money matches keep every one of these.

**Anchors to gate (from the current file bodies — verify against live before transforming):**
- `supabase-challenge-bounty-economy.sql:294` `_award_badge(r.user_id,'first_blood')`
- `supabase-challenge-bounty-economy.sql:313-321` `_log_game_result(...)` (currently unconditional per participant)
- `supabase-challenge-bounty-economy.sql:324-327` `hustler` award
- `supabase-challenge-opponent-notify.sql:38` `_record_category_solve(p_uid, v_cat)`
- `supabase-challenge-lb-cosmetics-fix.sql:23` `WHERE gr.game_mode = 'challenge'`
- `supabase-best-bounty.sql:39,45,58` `game_mode='challenge'` sub-selects

- [ ] **Step 1: Load env + confirm DB reachable**

```bash
cd /Users/admin/wordbankmaster
set -a; . ./.env; set +a
psql "$SUPABASE_DB_URL" -c "select count(*) from challenge_matches where wager = 0;"
```
Expected: a row count prints (connection works).

- [ ] **Step 2: Dump the live function bodies (source of truth)**

```bash
psql "$SUPABASE_DB_URL" -Atc "select pg_get_functiondef('public._match_settle'::regproc);" > /tmp/settle.sql
psql "$SUPABASE_DB_URL" -Atc "select pg_get_functiondef('public._match_record_solve'::regproc);" > /tmp/recsolve.sql
psql "$SUPABASE_DB_URL" -Atc "select pg_get_functiondef('public.get_challenge_leaderboard'::regproc);" > /tmp/lb.sql
psql "$SUPABASE_DB_URL" -Atc "select pg_get_functiondef('public.get_best_bounty'::regproc);" > /tmp/bounty.sql
```
(If a regproc name differs, resolve it: `psql "$SUPABASE_DB_URL" -Atc "select proname from pg_proc where proname ~ 'match_record_solve|best_bounty';"`. The category-solve caller is whatever function contains `_record_category_solve`.)

- [ ] **Step 3: Apply the gates by hand, into `supabase-friendly-no-stats.sql`**

Copy each dumped body into `supabase-friendly-no-stats.sql` and edit:

In `_match_settle`, wrap the three award/log statements so they only run for a paid match. `m` is the match row already in scope (guaranteed `m.wager` present):
```sql
-- first_blood (was unconditional)
if m.wager > 0 then perform public._award_badge(r.user_id, 'first_blood'); end if;
...
-- _log_game_result(...) — wrap the ENTIRE call:
if m.wager > 0 then
  perform public._log_game_result( /* …existing args verbatim… */ );
end if;
...
-- hustler (was: if v_wins >= 10 then …). Make it:
if m.wager > 0 and v_wins >= 10 then perform public._award_badge(r.user_id, 'hustler'); end if;
```
Keep `gold_duelist` as-is (already `m.wager >= 10000`).

In `_match_record_solve` (per-solve category credit), fetch the match wager and skip for friendly. Near the existing `v_budget := GREATEST(COALESCE(m.wager,0), 500);` the match row/wager is available; guard the call:
```sql
if coalesce(m.wager, 0) > 0 then
  perform public._record_category_solve(p_uid, v_cat);
end if;
```
(If `m` is not already selected in that function, add `select wager into v_wager from public.challenge_matches where id = <the match id in scope>;` and gate on `v_wager > 0`.)

In `get_challenge_leaderboard`, the wins/pot aggregate reads `game_results gr` joined to challenge rows. Add a wager backstop. Since `game_results` has no wager column, join to the match/participant to filter, OR — simplest and robust — rely on the settle gate (friendly writes no row) AND add an explicit exclusion via the `challenge_matches` join if the query already joins it. If it does not join matches, the settle gate alone suffices; add a code comment noting the write-side gate is the guarantee. Do NOT invent a join that changes row multiplicity.

In `get_best_bounty`, same reasoning: with the settle write gated, no friendly `game_results` rows exist, so the existing `game_mode='challenge'` sub-selects already exclude them. Add a one-line comment recording that the write-side gate is the source of exclusion. (No query change needed unless a friendly row can exist for another reason — it cannot once Step 3's settle gate ships.)

> Net: the **authoritative** fix is gating `_log_game_result` in settle (no friendly row is ever written). Leaderboard/best-bounty need no structural change; document that. Only add a read filter if the function already joins `challenge_matches` such that a clean `and cm.wager > 0` is safe.

- [ ] **Step 4: Rollback-test both a friendly and a money settle**

Write a throwaway test in `/tmp/verify.sql` that, inside `BEGIN … ROLLBACK`, seeds one friendly (`wager=0`) and one money (`wager>0`) match at `status='open'` with all participants `done`, runs `_match_settle` on each, and asserts:
- friendly: `select count(*) from game_results where match_id = <friendly>` = 0; no new badges rows for its users; no category-solve rows.
- money: the same counts are > 0 (unchanged behavior).

```bash
psql "$SUPABASE_DB_URL" -f supabase-friendly-no-stats.sql   # first CREATE OR REPLACE the functions
psql "$SUPABASE_DB_URL" -f /tmp/verify.sql                  # BEGIN…ROLLBACK asserts, prints PASS/FAIL
```
Expected: assertions print PASS for both. If FAIL, fix the gate and re-run — do not proceed.

> If seeding a full match graph is impractical, instead assert at the statement level: temporarily `RAISE NOTICE` the `m.wager` at each gated branch under a seeded friendly and confirm the guarded blocks are skipped. Prefer the row-count assertion when feasible.

- [ ] **Step 5: Apply to prod + commit**

The `CREATE OR REPLACE FUNCTION` statements in Step 3 were already applied in Step 4's first psql call. Confirm they're live:
```bash
psql "$SUPABASE_DB_URL" -Atc "select pg_get_functiondef('public._match_settle'::regproc);" | grep -c "m.wager > 0"
```
Expected: count reflects the added gates (≥ the number of new `m.wager > 0` guards).

```bash
git add supabase-friendly-no-stats.sql
git commit -m "Challenges: friendly (wager 0) matches award no stats/badges/leaderboard/category

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: End-to-end verification (two-player friendly)

**Files:**
- Temp: `scripts/qa-friendly.mjs` (Playwright, delete after use)

**Interfaces:** none (verification only).

- [ ] **Step 1: Write a two-player friendly harness**

Model it on the existing `scripts/qa-h2h.mjs` two-player flow (referenced in project memory). Two browser contexts: player A creates a **Friendly** challenge (ante chip = `$0` / "Friendly"), player B accepts; both play the pack to completion. Capture for player A:
- the bounty hero text, a keyboard key's price text, the top chip text, "Your Score" text — assert each contains `★` and none contains `$`.
- `localStorage.getItem('freeplay:total')` before vs after the match — assert it increased by A's final `total_score`.
- `get_challenge_leaderboard` wins for A before vs after — assert unchanged (query via the app's RPC or psql).

- [ ] **Step 2: Run it (background) against the dev server**

```bash
npm run dev &   # if not already up on :5173
node scripts/qa-friendly.mjs
```
Expected output: `★ HUD: true`, `no $: true`, `freeplay:total delta == score: true`, `leaderboard wins unchanged: true`.

- [ ] **Step 3: Sanity-check a money match is unaffected**

In the same harness (or a second pass), create a `wager > 0` match and assert the HUD still shows `$` and, after settle, the leaderboard win count DID change and a `game_results` row exists. Expected: all money-path assertions PASS.

- [ ] **Step 4: Clean up + final commit**

```bash
rm scripts/qa-friendly.mjs
node --test src/lib/freeplay/*.test.js && npm run build
```
Expected: node tests PASS, build succeeds. If the harness left any committed artifacts, remove them; otherwise nothing to commit.

---

## Self-Review notes

- **Spec coverage:** display swap (Task 3), points bank (Tasks 1–2), stats gating (Task 4), visibility "hub only" preserved (Task 4 leaves `challenge_matches`/participants intact; only `game_results`/badges/category are gated). ✔
- **Type consistency:** `bankMatchPoints(storage, matchId, score)` defined in Task 1, called identically in Task 2. `matchInfo.friendly` produced in Task 2, consumed in Task 3 (both `+page.svelte` via `isFriendlyMatch` and `Keyboard.svelte` via `$gameStore.matchInfo?.friendly`). ✔
- **The authoritative stats gate** is `_log_game_result` in settle; read-side leaderboard/best-bounty changes are documentation-only unless a safe `wager > 0` join already exists — flagged to avoid row-multiplicity bugs. ✔
