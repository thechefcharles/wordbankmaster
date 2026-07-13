# Daily Solve Timer + Leaderboard Column Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the already-recorded Daily solve time in the UI — a sortable "Time" column on the Daily leaderboard and a subtle server-timed count-up timer on the Daily game screen.

**Architecture:** The data already exists (`daily_sessions.created_at`→`finished_at`, and `game_results.time_ms` per daily result, clamped to 30 min server-side). Phase 1 exposes `solve_seconds` from `get_daily_board` (with a plausibility band) and renders a sortable column in `LeaderboardPanel`. Phase 2 exposes `opened_at` on the daily game board and adds a `SolveTimer.svelte` that displays `now − opened_at − reveal_offset` as a count-up, anchored to the server so it's quit-proof and un-gameable. The two phases are independently shippable; ship Phase 1 first.

**Tech Stack:** SvelteKit 2.16 (mixed Svelte 4 `$:` / Svelte 5 runes), Supabase Postgres SECURITY DEFINER RPCs, migrations applied directly to prod via `psql "$SUPABASE_DB_URL"` and rollback-tested first.

## Global Constraints

- Solve time is measured **server-side, continuous, never pauses** — `finished_at − created_at`. Away time (menu, quit, phone off) counts. This is the un-gameable model the design settled on.
- **Plausibility band** on any *surfaced* time: floor `PLAUSIBILITY_FLOOR_MS = 2000` (2s — below this is physically implausible to type a multi-word phrase; reject as anti-cheat), ceiling `CEILING_MS = 1800000` (30 min — already enforced on `game_results.time_ms` and via `daily_sessions`). Outside the band → show `—`, never a raw number. A too-slow/too-fast solve still counts as solved for earnings/streak; it just doesn't rank on speed.
- **Reveal offset:** the count-up must not charge the player for the once-per-day opening reveal animation. Discount a fixed `REVEAL_OFFSET_MS` constant (≈ the daily reveal duration). Verify the actual duration in `src/lib/components/PhraseDisplay.svelte` (`🎰 Daily opening reveal` keyframes) and `src/routes/+page.svelte` intro timing; default `REVEAL_OFFSET_MS = 1800` and adjust to match.
- **Scope:** Daily only for the leaderboard column and the on-screen timer. Do NOT add a timer to Cash Game (resumable endless run breaks it). A Challenge timer is optional and out of scope here.
- Migrations are applied to **prod** (`set -a; . ./.env; set +a; psql "$SUPABASE_DB_URL" ...`), rollback-tested first (`BEGIN; ...; ROLLBACK`). Committed as `.sql` artifacts at repo root, named `supabase-<topic>.sql`.
- Gate every client change: `npx prettier --write <files>` → `npm run check` (baseline 0 errors / 1 pre-existing a11y warning) → `npm run build`.
- Reuse the existing `fmtSecs` pattern already in `src/lib/components/MatchDetailModal.svelte:38` and `src/routes/profile/+page.svelte` (`"12s"` / `"1m 05s"`). Extract it to `src/lib/time.js` (Task 1) so all three call sites share one copy (DRY).

---

## File Structure

- `src/lib/time.js` — **new**, one export `fmtSecs(seconds)`. Single source of truth for `"12s"`/`"1m 05s"` formatting. Replaces the two inline copies.
- `supabase-daily-board-solve-seconds.sql` — **new** migration: add `solve_seconds` (banded) to `get_daily_board`.
- `src/lib/components/LeaderboardPanel.svelte` — **modify**: add sortable "Time" column + legend entry to the Daily board.
- `supabase-daily-board-opened-at.sql` — **new** migration: add `opened_at` (ms) + `best_solve_seconds` to the daily game board (`daily_start` / `_daily_board` wrapper) and `get_daily_status`.
- `src/lib/components/SolveTimer.svelte` — **new**: the subtle count-up timer component.
- `src/routes/+page.svelte` — **modify**: mount `<SolveTimer>` on the Daily game screen; show final solve time in the win result.
- `src/lib/stores/GameStore.js` — **modify**: thread `openedAt` / `bestSolveSeconds` from the daily board into the store.

---

## Phase 1 — Daily leaderboard "Time" column (ship first)

### Task 1: Shared `fmtSecs` helper

**Files:**
- Create: `src/lib/time.js`
- Modify: `src/lib/components/MatchDetailModal.svelte` (remove local `fmtSecs`, import shared)
- Modify: `src/routes/profile/+page.svelte` (remove local `fmtSecs`, import shared)

**Interfaces:**
- Produces: `fmtSecs(s: number | null | undefined): string` — `null`/`undefined` → `"—"`; `<60` → `"12s"`; else `"1m 05s"`.

- [ ] **Step 1: Create the helper**

```javascript
// src/lib/time.js
/** Human solve time: null → "—", <60s → "12s", else "1m 05s". @param {any} s */
export function fmtSecs(s) {
	if (s == null) return '—';
	const n = Math.round(Number(s));
	return n < 60 ? `${n}s` : `${Math.floor(n / 60)}m ${String(n % 60).padStart(2, '0')}s`;
}
```

- [ ] **Step 2: Replace the two inline copies**

In `src/lib/components/MatchDetailModal.svelte`, delete the local `const fmtSecs = ...` (around line 38) and add to the script imports:

```javascript
import { fmtSecs } from '$lib/time.js';
```

In `src/routes/profile/+page.svelte`, delete the local `const fmtSecs = ...` (added earlier for the 1v1 chips) and add to imports:

```javascript
import { fmtSecs } from '$lib/time.js';
```

- [ ] **Step 3: Verify gates pass (no behavior change)**

Run: `npx prettier --write src/lib/time.js src/lib/components/MatchDetailModal.svelte src/routes/profile/+page.svelte && npm run check && npm run build`
Expected: `svelte-check found 0 errors and 1 warning`; build `✔ done`.

- [ ] **Step 4: Commit**

```bash
git add src/lib/time.js src/lib/components/MatchDetailModal.svelte src/routes/profile/+page.svelte
git commit -m "refactor: extract shared fmtSecs to src/lib/time.js"
```

---

### Task 2: `get_daily_board` returns banded `solve_seconds`

**Files:**
- Create: `supabase-daily-board-solve-seconds.sql`

**Interfaces:**
- Produces: each row of `get_daily_board(p_scope, p_group)` gains `"solve_seconds": <int|null>` — today's solve time in seconds, or `null` when not a valid ranked time (not won, or outside the plausibility band). The Daily board already joins `game_results` per player as subquery alias `g` (which exposes `g.score`, `g.kept`, `g.won`); this task adds `g.time_ms` and derives `solve_seconds`.

- [ ] **Step 1: Build the migration by transforming the live function**

The function is large; do not retype it. Dump it, add `gr.time_ms` to the per-player `game_results` subquery, and add the `solve_seconds` output field:

```bash
set -a; . ./.env; set +a
{
  echo "-- Add banded solve_seconds (today's Daily solve time) to get_daily_board."
  psql "$SUPABASE_DB_URL" -tA -c "SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname='get_daily_board' LIMIT 1;" \
   | perl -0pe 's/SELECT gr\.score, gr\.kept, gr\.won FROM public\.game_results gr/SELECT gr.score, gr.kept, gr.won, gr.time_ms FROM public.game_results gr/' \
   | perl -0pe "s/'efficiency', efficiency, 'credit', credit,/'efficiency', efficiency, 'credit', credit,\n    'solve_seconds', (CASE WHEN g.won AND g.time_ms BETWEEN 2000 AND 1800000 THEN round(g.time_ms\/1000.0)::int ELSE NULL END),/"
  echo ";"
} > supabase-daily-board-solve-seconds.sql
grep -c "time_ms" supabase-daily-board-solve-seconds.sql   # expect >= 2
grep -c "solve_seconds" supabase-daily-board-solve-seconds.sql  # expect 1
```

If either grep count is 0, the anchor strings drifted — open the dumped function, find the `game_results gr` subquery and the output `jsonb_build_object(...)`, and apply the two edits by hand (add `gr.time_ms` to the subquery SELECT; add the `'solve_seconds', (CASE ...)` line to the output object). The `g.time_ms` reference in the CASE must match the subquery alias (`g`).

- [ ] **Step 2: Rollback-test that the field appears and is banded**

Run:

```bash
set -a; . ./.env; set +a
psql "$SUPABASE_DB_URL" 2>&1 <<'SQL' | grep -iP 'solve_seconds|ERROR'
begin;
\i supabase-daily-board-solve-seconds.sql
do $B$
declare v_uid uuid; v_res jsonb; r jsonb;
begin
  select user_id into v_uid from public.game_results where game_mode='daily' and time_ms is not null limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid)::text, true);
  v_res := public.get_daily_board('global', null);
  for r in select * from jsonb_array_elements(v_res) loop
    if (r->>'is_me')::boolean then raise notice 'me: solve_seconds=% score=%', r->>'solve_seconds', r->>'score'; end if;
  end loop;
end $B$;
rollback;
SQL
```

Expected: a `NOTICE me: solve_seconds=<int or empty> score=<int>` line, no `ERROR`. (The value may be null if that user has no *today* result — that's fine; the point is the field renders without error.)

- [ ] **Step 3: Apply to prod**

Run: `set -a; . ./.env; set +a; psql "$SUPABASE_DB_URL" -f supabase-daily-board-solve-seconds.sql`
Expected: `CREATE FUNCTION`.

- [ ] **Step 4: Commit**

```bash
git add supabase-daily-board-solve-seconds.sql
git commit -m "Daily leaderboard: get_daily_board returns banded solve_seconds"
```

---

### Task 3: "Time" column in the Daily leaderboard

**Files:**
- Modify: `src/lib/components/LeaderboardPanel.svelte`

**Interfaces:**
- Consumes: `get_daily_board` rows with `solve_seconds` (Task 2); `fmtSecs` (Task 1).
- The Daily board is the sortable table branch. Existing sort keys are the `SortKey` union `'place'|'name'|'score'|'efficiency'|'play_streak'|'win_streak'`; sorting is handled by `setSort(k)` / `sortedRows` / the `arrow(k)` indicator.

- [ ] **Step 1: Add `'time'` to the sort machinery**

In `src/lib/components/LeaderboardPanel.svelte`, extend the `SortKey` typedef and the null-handling in `sortedRows`:

```javascript
/** @typedef {'place'|'name'|'score'|'efficiency'|'play_streak'|'win_streak'|'time'} SortKey */
```

In `sortedRows` (the `$derived.by` block), `time` sorts ascending (fastest first), nulls last — mirror the existing `nullLast` handling but inverted direction. Add before the generic numeric branch:

```javascript
if (sortKey === 'time') {
	const av = a.solve_seconds ?? Infinity;
	const bv = b.solve_seconds ?? Infinity;
	return dir * (av - bv) || a._place - b._place;
}
```

And in `setSort`, make `time` default to ascending like `place`:

```javascript
sortDir = k === 'name' || k === 'place' || k === 'time' ? 'asc' : 'desc';
```

- [ ] **Step 2: Add the column header + cell (Daily table only)**

Import the shared helper in the script:

```javascript
import { fmtSecs } from '$lib/time.js';
```

In the Daily table's `<thead>`, add a sortable header next to Efficiency (match the existing sortable-header pattern that calls `setSort('efficiency')` and renders `arrow('efficiency')`):

```svelte
<th class="num sortable" onclick={() => setSort('time')}>Time{arrow('time')}</th>
```

In the matching `<tbody>` row, add the cell (same column position):

```svelte
<td class="num">{fmtSecs(r.solve_seconds)}</td>
```

- [ ] **Step 3: Add the legend entry**

In the Daily branch of the `legend` `$derived` array, add:

```javascript
{ term: 'Time', desc: "How fast you solved today's Daily — same puzzle for everyone. Fastest wins. Blank if you haven't solved yet." }
```

- [ ] **Step 4: Verify gates**

Run: `npx prettier --write src/lib/components/LeaderboardPanel.svelte && npm run check && npm run build`
Expected: `0 errors and 1 warning`; build `✔ done`.

- [ ] **Step 5: Visual check**

Run the app (`PORT=5174 npm run dev -- --port 5174`), open `/leaderboard`, Daily tab. Expected: a **Time** column showing `fmtSecs` values (or `—`), sortable ascending (tap header → fastest solver rises to top), the info key explains it. Take a screenshot to confirm.

- [ ] **Step 6: Commit**

```bash
git add src/lib/components/LeaderboardPanel.svelte
git commit -m "Daily leaderboard: sortable Time (fastest-solve) column"
```

---

## Phase 2 — On-screen count-up timer

### Task 4: Expose `opened_at` + `best_solve_seconds` on the daily board

**Files:**
- Create: `supabase-daily-board-opened-at.sql`

**Interfaces:**
- Produces: `daily_start(...)` and `get_daily_status()` return `"opened_at": <epoch_ms int>` (= `daily_sessions.created_at`, the server anchor for the counter) and `"best_solve_seconds": <int|null>` (the player's fastest valid Daily solve ever, for the PB ghost).
- `best_solve_seconds` query (banded, only real timing data):

```sql
(SELECT round(min(time_ms)/1000.0)::int FROM public.game_results
 WHERE user_id = v_uid AND game_mode = 'daily' AND won AND time_ms BETWEEN 2000 AND 1800000)
```

- [ ] **Step 1: Build the migration**

`daily_start` returns `_daily_board(...) || jsonb_build_object('live', ...) || CASE WHEN v_new ...`. Add a `jsonb_build_object` with the two fields to its RETURN. Dump + transform:

```bash
set -a; . ./.env; set +a
{
  echo "-- Expose opened_at (session created_at, ms) + best_solve_seconds on the daily board."
  psql "$SUPABASE_DB_URL" -tA -c "SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname='daily_start' LIMIT 1;" \
   | perl -0pe "s/\|\| CASE WHEN v_new THEN/|| jsonb_build_object('opened_at', (extract(epoch from s.created_at)*1000)::bigint, 'best_solve_seconds', (SELECT round(min(time_ms)\/1000.0)::int FROM public.game_results WHERE user_id = v_uid AND game_mode = 'daily' AND won AND time_ms BETWEEN 2000 AND 1800000))\n    || CASE WHEN v_new THEN/"
  echo ";"
  psql "$SUPABASE_DB_URL" -tA -c "SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname='get_daily_status' LIMIT 1;"
  echo ";"
} > supabase-daily-board-opened-at.sql
grep -c "opened_at" supabase-daily-board-opened-at.sql   # expect >= 1
```

If the `get_daily_status` dump does not already surface `opened_at`/`best_solve_seconds`, add the same two fields to its RETURN object by hand (it reads the same `daily_sessions` row — reference its session variable for `created_at`). If `daily_start`'s anchor string drifted, add the `jsonb_build_object('opened_at', ...)` to its RETURN by hand.

- [ ] **Step 2: Rollback-test opened_at is present and sane**

```bash
set -a; . ./.env; set +a
psql "$SUPABASE_DB_URL" 2>&1 <<'SQL' | grep -iP 'opened_at|best_solve|ERROR'
begin;
\i supabase-daily-board-opened-at.sql
do $B$
declare v_uid uuid; v_res jsonb;
begin
  select user_id into v_uid from public.daily_sessions order by created_at desc limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid)::text, true);
  v_res := public.daily_start('{}'::text[]);
  raise notice 'opened_at=% best_solve_seconds=%', v_res->>'opened_at', v_res->>'best_solve_seconds';
end $B$;
rollback;
SQL
```

Expected: `NOTICE opened_at=<13-digit ms> best_solve_seconds=<int or empty>`, no `ERROR`.

- [ ] **Step 3: Apply to prod**

Run: `set -a; . ./.env; set +a; psql "$SUPABASE_DB_URL" -f supabase-daily-board-opened-at.sql`
Expected: `CREATE FUNCTION` (×1 or ×2).

- [ ] **Step 4: Commit**

```bash
git add supabase-daily-board-opened-at.sql
git commit -m "Daily board: expose opened_at (ms) + best_solve_seconds for the on-screen timer"
```

---

### Task 5: Thread `openedAt` / `bestSolveSeconds` into the store

**Files:**
- Modify: `src/lib/stores/GameStore.js`

**Interfaces:**
- Consumes: `board.opened_at` (ms), `board.best_solve_seconds` from Task 4.
- Produces: `gameStore` gains `dailyOpenedAt: number|null` and `dailyBestSeconds: number|null`, set in `reconcileDailyBoard`.

- [ ] **Step 1: Add store fields**

In the initial state object in `src/lib/stores/GameStore.js` (near `dailyIntro: 0`), add:

```javascript
dailyOpenedAt: null, // epoch ms the server stamped for today's Daily (counter anchor)
dailyBestSeconds: null, // player's fastest valid Daily solve (PB ghost)
```

- [ ] **Step 2: Populate them in `reconcileDailyBoard`**

In `reconcileDailyBoard(board)`, thread the fields through the `gameStore.update`/`set`:

```javascript
dailyOpenedAt: board.opened_at ?? get(gameStore).dailyOpenedAt ?? null,
dailyBestSeconds: board.best_solve_seconds ?? get(gameStore).dailyBestSeconds ?? null,
```

(Use `??` fallback to the previous value so a board refresh that omits the field doesn't clear it.)

- [ ] **Step 3: Verify gates**

Run: `npx prettier --write src/lib/stores/GameStore.js && npm run check && npm run build`
Expected: `0 errors and 1 warning`; build `✔ done`.

- [ ] **Step 4: Commit**

```bash
git add src/lib/stores/GameStore.js
git commit -m "GameStore: thread dailyOpenedAt + dailyBestSeconds from the daily board"
```

---

### Task 6: `SolveTimer.svelte` count-up component

**Files:**
- Create: `src/lib/components/SolveTimer.svelte`

**Interfaces:**
- Consumes: `fmtSecs` (Task 1). Props: `openedAt: number|null` (epoch ms), `bestSeconds: number|null`, `active: boolean` (running only while the puzzle is unsolved and on-screen), `revealOffsetMs?: number` (default 1800).
- Renders a subtle `mm:ss` count-up = `max(0, now − openedAt − revealOffsetMs)` with an optional muted `PB m:ss` ghost. Ticks once per second via an interval that is cleared on unmount / when `active` is false. Respects `prefers-reduced-motion` (no pulse).

- [ ] **Step 1: Create the component**

```svelte
<!-- src/lib/components/SolveTimer.svelte -->
<script>
	import { onDestroy } from 'svelte';
	import { fmtSecs } from '$lib/time.js';

	/** @type {number|null} */ export let openedAt = null;
	/** @type {number|null} */ export let bestSeconds = null;
	export let active = false;
	export let revealOffsetMs = 1800;

	let now = Date.now();
	/** @type {ReturnType<typeof setInterval>|undefined} */ let timer;

	$: if (active && openedAt && !timer) {
		timer = setInterval(() => (now = Date.now()), 1000);
	} else if ((!active || !openedAt) && timer) {
		clearInterval(timer);
		timer = undefined;
	}
	onDestroy(() => timer && clearInterval(timer));

	$: elapsed = openedAt ? Math.max(0, Math.round((now - openedAt - revealOffsetMs) / 1000)) : 0;
	$: mmss = `${Math.floor(elapsed / 60)}:${String(elapsed % 60).padStart(2, '0')}`;
</script>

{#if openedAt}
	<div class="solve-timer" aria-label="Solve time">
		<span class="st-val">{mmss}</span>
		{#if bestSeconds != null}<span class="st-pb">PB {fmtSecs(bestSeconds)}</span>{/if}
	</div>
{/if}

<style>
	.solve-timer {
		display: inline-flex;
		align-items: baseline;
		gap: 8px;
		font-family: 'Orbitron', var(--font-display, monospace);
		font-variant-numeric: tabular-nums;
		color: var(--text-faint, #8090a0);
		font-size: 0.8rem;
		letter-spacing: 0.04em;
	}
	.st-val {
		font-weight: 700;
		color: var(--text-muted, #b0bcca);
	}
	.st-pb {
		font-size: 0.68rem;
		opacity: 0.7;
	}
</style>
```

- [ ] **Step 2: Verify gates (component compiles standalone)**

Run: `npx prettier --write src/lib/components/SolveTimer.svelte && npm run check && npm run build`
Expected: `0 errors and 1 warning`; build `✔ done`.

- [ ] **Step 3: Commit**

```bash
git add src/lib/components/SolveTimer.svelte
git commit -m "Add SolveTimer: subtle server-anchored count-up with PB ghost"
```

---

### Task 7: Mount the timer on the Daily game screen

**Files:**
- Modify: `src/routes/+page.svelte`

**Interfaces:**
- Consumes: `SolveTimer` (Task 6); `gameStore.dailyOpenedAt` / `dailyBestSeconds` (Task 5).
- Runs only on the Daily game screen, only while unsolved, and not during the intro reveal.

- [ ] **Step 1: Import + derive active state**

In the `<script>` of `src/routes/+page.svelte`, import the component:

```javascript
import SolveTimer from '$lib/components/SolveTimer.svelte';
```

Add a derived flag near the other daily reactives (e.g. by `soloHero`):

```javascript
// Timer runs on the Daily board while the puzzle is unsolved and past the intro reveal.
$: dailyTimerActive =
	$gameStore.gameMode === 'daily' &&
	!showMainMenu &&
	!introBuilding &&
	$gameStore.gameState !== 'won' &&
	$gameStore.gameState !== 'lost';
```

- [ ] **Step 2: Render it under the mode pill (Daily only)**

Place `<SolveTimer>` near the mode label / score header (the `modeLabel` area around `+page.svelte:4150`), gated to Daily:

```svelte
{#if $gameStore.gameMode === 'daily' && modeLabel}
	<div class="daily-timer-wrap">
		<SolveTimer
			openedAt={$gameStore.dailyOpenedAt}
			bestSeconds={$gameStore.dailyBestSeconds}
			active={dailyTimerActive}
		/>
	</div>
{/if}
```

Add the wrapper style in the component's `<style>`:

```css
.daily-timer-wrap {
	display: flex;
	justify-content: center;
	margin-top: 2px;
}
```

- [ ] **Step 3: Verify gates**

Run: `npx prettier --write src/routes/+page.svelte && npm run check && npm run build`
Expected: `0 errors and 1 warning`; build `✔ done`.

- [ ] **Step 4: Manual behavior check (the design's core guarantees)**

Run the app; sign up; open the Daily. Verify, taking screenshots at each step:
1. The counter reads ~`0:00` right when the board becomes playable (not during the reveal) and ticks up.
2. Go to the menu and back → the counter shows the **elapsed real time** (it kept running; did not reset or pause).
3. Solve → the counter stops.

- [ ] **Step 5: Commit**

```bash
git add src/routes/+page.svelte
git commit -m "Daily: mount server-anchored SolveTimer on the game screen"
```

---

### Task 8: Show final solve time in the Daily win result

**Files:**
- Modify: `src/routes/+page.svelte`

**Interfaces:**
- Consumes: `gameStore.dailyOpenedAt`; the daily win/result flow. On solve, compute `solvedSeconds = round((finishedAtMs − openedAt − revealOffset)/1000)` and display it in the deposit-slip / result as a "Solved in {fmtSecs}" line (only when within the plausibility band).

- [ ] **Step 1: Derive the final solve time**

In the daily result section of `src/routes/+page.svelte`, add (reuse `fmtSecs` — import it if not already: `import { fmtSecs } from '$lib/time.js';`):

```javascript
// Final Daily solve time (banded): shown on the result. Uses the server anchor.
$: dailySolveSeconds = (() => {
	const opened = $gameStore.dailyOpenedAt;
	if (!opened || $gameStore.gameState !== 'won' || $gameStore.gameMode !== 'daily') return null;
	const secs = Math.round((Date.now() - opened - 1800) / 1000);
	return secs >= 2 && secs <= 1800 ? secs : null;
})();
```

- [ ] **Step 2: Render it in the result**

In the daily deposit-slip / result block, add a line where the other result stats render:

```svelte
{#if dailySolveSeconds != null}
	<div class="rcpt-line"><span>Solved in</span><b>{fmtSecs(dailySolveSeconds)}</b></div>
{/if}
```

- [ ] **Step 3: Verify gates**

Run: `npx prettier --write src/routes/+page.svelte && npm run check && npm run build`
Expected: `0 errors and 1 warning`; build `✔ done`.

- [ ] **Step 4: Manual check**

Solve a Daily → the result shows a "Solved in {time}" line matching what the on-screen counter read at solve.

- [ ] **Step 5: Commit**

```bash
git add src/routes/+page.svelte
git commit -m "Daily result: show final Solved-in time"
```

---

## Self-Review

**Spec coverage:**
- Daily leaderboard "Time" column → Tasks 2 + 3. ✓
- On-screen count-up timer (server-anchored, quit-proof, reveal-discounted, PB ghost) → Tasks 4–7. ✓
- Plausibility band (floor 2s / ceiling 30 min) → applied in Tasks 2, 4, 8 (the `BETWEEN 2000 AND 1800000` / `secs >= 2 && secs <= 1800` guards). ✓
- "Away time counts / never pauses" → guaranteed structurally: the counter is `now − server.opened_at`, computed from a server timestamp, so navigation/quit can't reset or pause it (Task 6). ✓
- Reveal not charged → `revealOffsetMs` discount (Tasks 6–8), with a Global Constraint to verify the real duration. ✓
- Scope Daily-only → no Cash Game / Challenge timer tasks. ✓
- Ship Phase 1 before Phase 2 → phases are independent; Task 3 delivers a working column without any Phase 2 work. ✓

**Placeholder scan:** No TBD/TODO; every code step has concrete code; migration steps include the exact transform + a hand-edit fallback with the precise anchor to find.

**Type consistency:** `solve_seconds` (server) / `r.solve_seconds` (client) match (Tasks 2/3). `opened_at`→`dailyOpenedAt`, `best_solve_seconds`→`dailyBestSeconds` mappings are consistent across Tasks 4/5/6/7. `fmtSecs` signature is identical everywhere (Task 1). The band constants (2000ms floor / 1800000ms ceiling; 1800ms reveal offset) are used consistently.

**Note on TDD:** this repo has no unit-test framework; verification is rollback-SQL tests for RPCs, `npm run check`/`build` for client, and manual/Playwright for UI behavior — the plan's "test" steps use those, per the codebase's established pattern.
