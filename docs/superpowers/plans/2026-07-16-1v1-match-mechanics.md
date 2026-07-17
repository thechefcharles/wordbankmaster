# 1v1 Challenge Mechanics Overhaul — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Ship the seven 1v1 challenge (`gameMode:'match'`) changes from the spec: fog rework, erase, in-match timer, pot relocation, sabotaged-price keyboard, broke last-stand, and usage caps.

**Architecture:** Match state lives on `challenge_participants`; the board is built by `_match_board` (returns `_daily_board(...)` + a `match` metadata object `v_minfo`). Economy/effects are enforced in SECURITY DEFINER RPCs, most of which are **DB-only** (dump the live body, transform, rollback-test, apply). The client renders whatever the board reports; `_match_board.v_minfo` already exposes `used_powerups` (=`active_powerups`) and `my_debuffs` (=`debuffs`).

**Tech Stack:** SvelteKit 2.16 (Svelte 5), Supabase Postgres, `psql "$SUPABASE_DB_URL"` direct-to-prod migrations, `node:test`, Playwright (`scripts/qa-h2h.mjs` two-player harness).

## Global Constraints

- **Scoped to `gameMode:'match'` only.** Daily, Cash Game, Free Play behavior must not change.
- **Server is authoritative.** Every new effect/cap is enforced in the RPC; the client only reflects the board. Never gate an effect client-only.
- **DB migration pattern:** `set -a; . ./.env; set +a`; dump live body with `pg_get_functiondef`; transform (perl/hand-edit into a committed `supabase-*.sql`); rollback-test with `BEGIN…ROLLBACK` on a seeded match; apply; commit. Repo files lag prod — always dump live first.
- **Cost stack order (must be preserved exactly, server + client):** `Half Off (×0.5) → Tax (×1.5) → Vowel Block (×3 on vowels) → Toll (×3, then removed)`; `CEIL()` after ×0.5 and ×1.5.
- **Reset-on-advance:** the new per-puzzle columns reset in `_match_resolve_and_advance` alongside the existing `revealed_positions/incorrect_letters/active_powerups/debuffs` resets (BOTH the `econ_v=2` and the old branch).
- Git commit messages end with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## Current-state anchors (from live prod bodies)

- `_match_board` clue line: `'clue', CASE WHEN 'fog' = ANY(COALESCE(cp.debuffs,'{}')) THEN NULL ELSE v_clue END`. `v_minfo` already has `used_powerups`, `my_debuffs`, `opponents` (id+name), `pot`, `target`. No `started_at`, no `must_guess`, opponents carry no `position`.
- `match_buy_letter`: applies the cost stack (`half_off`/`tax`/`vowel_block`/`toll`), then reveals — `IF v_positions IS NULL THEN incorrect_letters := append ELSE revealed_positions := DISTINCT sorted END`.
- `match_sabotage`: `lock` branch picks a **random** revealed letter (`ORDER BY random() LIMIT 1`) and rebuilds `revealed_positions` excluding it; the `ELSE` branch appends `v_debuff` to `debuffs[]` + `debuff_by`.
- `match_use_powerup`: one-of-each gate is `IF v_eff = ANY(cp.active_powerups) THEN RETURN ...`.
- `match_submit_guess`: wrong guess penalizes budget (`v_pen := GREATEST(10, round(0.2*bankroll/10)*10)`), never folds.
- `_match_resolve_and_advance`: on advance (non-final), resets `revealed_positions='{}', incorrect_letters='{}', active_powerups='{}', debuffs='{}', p_vowels=0, p_reveals=0, p_wrong_guesses=0` in BOTH branches.

---

### Task 1: Schema foundation + advance reset

**Files:** Create `supabase-match-mechanics-schema.sql`. Touches live `_match_resolve_and_advance`.

**Interfaces — Produces:** new `challenge_participants` columns consumed by all later tasks:
`pending_fog boolean`, `fog_buys_left int`, `reveal_order text[]`, `sabotaged_targets uuid[]`.

- [ ] **Step 1: Add columns + seed/reset logic**

Write `supabase-match-mechanics-schema.sql`:
```sql
ALTER TABLE public.challenge_participants
  ADD COLUMN IF NOT EXISTS pending_fog boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS fog_buys_left int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS reveal_order text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS sabotaged_targets uuid[] NOT NULL DEFAULT '{}';
```

- [ ] **Step 2: Update `_match_resolve_and_advance` reset**

Dump the live body. In BOTH advance branches (the `econ_v=2` non-final `UPDATE ... position = position + 1` and the old-econ non-final `UPDATE`), extend the reset SET-list to also seed fog + clear the new per-puzzle columns:
```sql
        revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}',
        reveal_order = '{}', sabotaged_targets = '{}',
        fog_buys_left = CASE WHEN pending_fog THEN 3 ELSE 0 END, pending_fog = false,
        p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0
```
(The `fog_buys_left = 3 on pending_fog` seeding on advance is what makes fog land on the player's NEXT puzzle, never puzzle 1 — advances only happen after puzzle 1.) Add the full `CREATE OR REPLACE FUNCTION` for `_match_resolve_and_advance` to the SQL file.

- [ ] **Step 3: Rollback-test**

`BEGIN; <apply schema + fn>; ` seed a match participant on puzzle 1 with `pending_fog=true`, advance them (call `match_submit_guess` with a full correct solve, or directly simulate the advance UPDATE), assert the new puzzle row has `fog_buys_left=3, pending_fog=false, reveal_order='{}', sabotaged_targets='{}'`. `ROLLBACK;`. If seeding a full match is impractical, at minimum apply inside `BEGIN…ROLLBACK` to prove it compiles, and assert the SET-list contains the new columns.

- [ ] **Step 4: Apply + commit**

```bash
set -a; . ./.env; set +a; psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase-match-mechanics-schema.sql
git add supabase-match-mechanics-schema.sql
git commit -m "Match: add fog/erase/cap columns to challenge_participants + reset on advance"
```

---

### Task 2: Fog → queued next-puzzle curse (3 buys)

**Files:** Create `supabase-match-fog.sql`. Touches live `match_sabotage`, `_match_board`, `match_buy_letter`.

**Interfaces — Consumes:** Task 1 columns. **Produces:** `matchInfo.opponents[].position`/`pack_size` for client castability; clue hidden while `fog_buys_left>0`.

- [ ] **Step 1: `match_sabotage` fog branch → set `pending_fog`, guard next-puzzle**

Dump live `match_sabotage`. Currently `fog` falls into the `ELSE` (debuffs[]) branch. Split it out: before the debuff `ELSE`, add a `fog` branch that sets `pending_fog` on the target **only if the target has an un-started next puzzle** (`tcp.position < m.pack_size`); otherwise reject (no charge). Move the inventory-decrement to AFTER validation so a rejected fog doesn't consume the item:
```sql
  ELSIF v_debuff = 'fog' THEN
    IF tcp.position >= m.pack_size THEN
      RETURN public._match_board(p_id, v_uid) || jsonb_build_object('sabotage_reason','no_next_puzzle');
    END IF;
    UPDATE public.challenge_participants SET pending_fog = true WHERE match_id = p_id AND user_id = p_target;
```
(Keep the `tax/toll/vowel_block` path in the remaining `ELSE`. Ensure the `user_powerups_v2` decrement only runs once validation passes — reorder if needed. Keep the existing `_notify` for fog: "your next puzzle starts foggy".)

- [ ] **Step 2: `_match_board` — clue-hide by `fog_buys_left`; expose castability**

Dump live `_match_board`. Change the clue line:
```sql
    'clue', CASE WHEN cp.fog_buys_left > 0 THEN NULL ELSE v_clue END
```
In the `opponents` sub-select inside `v_minfo`, add each opponent's `position` and the match `pack_size` so the client can tell whether Fog is castable:
```sql
      FROM public.challenge_participants o ... jsonb_build_object('id', o.user_id, 'name', public._display_name(o.user_id),
        'position', o.position, 'pack_size', m.pack_size, 'can_fog', o.position < m.pack_size)
```
Also add `'fog_buys_left', cp.fog_buys_left` to `v_minfo` (client shows a "foggy — N buys left" hint).

- [ ] **Step 3: `match_buy_letter` — decrement `fog_buys_left`**

Dump live `match_buy_letter`. In the final `UPDATE public.challenge_participants SET bankroll = ...`, add:
```sql
    fog_buys_left = GREATEST(0, cp.fog_buys_left - 1),
```
(Decrement on every buy, correct or wrong, so the clue reveals after the target's 3rd purchase.)

- [ ] **Step 4: Rollback-test**

Seeded 2-puzzle match: cast fog on a target on puzzle 1 → assert `pending_fog=true`; advance target to puzzle 2 → `fog_buys_left=3`, `_match_board.clue IS NULL`; 3 buys → `fog_buys_left=0`, clue non-null. Cast fog on a target on the last puzzle → rejected (`sabotage_reason=no_next_puzzle`, item not consumed). `ROLLBACK`.

- [ ] **Step 5: Client — fog label + castable state**

`src/routes/+page.svelte`: the sabotage picker (fog is a `kind:'sabotage'` item) must (a) label fog "Fog {opponent} — their next puzzle starts blind (3 buys)", (b) disable/grey the fog action when the chosen opponent's `can_fog === false`, with a tooltip "Nothing left to fog." Use `matchInfo.opponents[].can_fog`. Update the fog copy at the existing label map (`~:1243`, `:1249`).

- [ ] **Step 6: Apply + commit** (`supabase-match-fog.sql`, message "Match: fog is a queued next-puzzle curse (3-buy clue hide)").

---

### Task 3: Lock → Erase (most-recently-revealed letter)

**Files:** Create `supabase-match-erase.sql`. Touches live `match_buy_letter`, `match_use_powerup`, `match_sabotage`, and the `powerups` catalog row.

**Interfaces — Consumes:** Task 1 `reveal_order`.

- [ ] **Step 1: Track reveal order on reveal**

Dump live `match_buy_letter`; in the reveal branch (`ELSE cp.revealed_positions := ...`), also append the letter to `reveal_order` when it's newly revealed, and persist it in the final UPDATE:
```sql
    -- in the reveal (v_positions not null) path:
    cp.reveal_order := CASE WHEN v_letter = ANY(cp.reveal_order) THEN cp.reveal_order ELSE array_append(cp.reveal_order, v_letter) END;
    -- add to the UPDATE SET: reveal_order = cp.reveal_order,
```
Dump live `match_use_powerup`; after a powerup reveals positions (`v_positions IS NOT NULL`), append the revealed letters to `reveal_order` (derive the distinct letters at those positions from `v_phrase`) so powerup-revealed letters are erasable too. Keep order stable.

- [ ] **Step 2: `match_sabotage` lock branch → erase last-revealed**

Dump live `match_sabotage`. Replace the random-letter `lock` branch: take the **last** element of the target's `reveal_order`, remove all its positions from `revealed_positions`, and pop it from `reveal_order`. No-op with a message if `reveal_order` is empty:
```sql
  IF v_debuff = 'lock' THEN
    SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = public._match_pid(p_id, tcp.position);
    v_lockletter := tcp.reveal_order[array_length(tcp.reveal_order,1)];  -- most recently revealed
    IF v_lockletter IS NOT NULL THEN
      UPDATE public.challenge_participants SET
        revealed_positions = ARRAY(SELECT DISTINCT p FROM unnest(revealed_positions) p WHERE substr(v_phrase, p+1, 1) <> v_lockletter ORDER BY 1),
        reveal_order = reveal_order[1:array_length(reveal_order,1)-1]
      WHERE match_id = p_id AND user_id = p_target;
    END IF;
```
Keep the `_notify` ("they wiped your {letter}s").

- [ ] **Step 3: Rename catalog item to "Erase"**

Update the `powerups` row for `sabotage_lock` (DB-only INSERT): `name='Erase'`, description "Wipe the opponent's most-recently-revealed letter." Include the `UPDATE public.powerups SET name='Erase', description='...' WHERE id='sabotage_lock';` in the SQL file. Client label/copy: `src/routes/+page.svelte` (`~:1239` icon/label map) and `src/routes/shop/+page.svelte:56` → "Erase" naming.

- [ ] **Step 4: Rollback-test** — seed a target who reveals letters C, then A, then T (via buys); erase → asserts T's positions gone, `reveal_order` = {C,A}; erase again → A gone; erase on empty reveal_order → no-op. `ROLLBACK`.

- [ ] **Step 5: Apply + commit** (`supabase-match-erase.sql`, "Match: Lock→Erase (wipe opponent's most-recently-revealed letter) + reveal-order tracking").

---

### Task 4: Usage caps (one power-up, one sabotage/opponent per puzzle)

**Files:** Create `supabase-match-caps.sql`. Touches live `match_use_powerup`, `match_sabotage`.

- [ ] **Step 1: `match_use_powerup` → one power-up total per puzzle**

Dump live. Replace the one-of-each gate `IF v_eff = ANY(cp.active_powerups) THEN RETURN ...` with a one-total gate that returns a reason:
```sql
  IF COALESCE(array_length(cp.active_powerups,1),0) >= 1 THEN
    RETURN public._match_board(p_id, v_uid) || jsonb_build_object('powerup_reason','one_per_puzzle'); END IF;
```

- [ ] **Step 2: `match_sabotage` → one sabotage per opponent per puzzle**

Dump live. After validating the target but BEFORE applying the effect / decrementing inventory, reject a repeat against the same target this puzzle and otherwise record it:
```sql
  IF p_target = ANY((SELECT sabotaged_targets FROM public.challenge_participants WHERE match_id=p_id AND user_id=v_uid)) THEN
    RETURN public._match_board(p_id, v_uid) || jsonb_build_object('sabotage_reason','already_sabotaged'); END IF;
  -- ...after the effect applies and inventory is decremented:
  UPDATE public.challenge_participants SET sabotaged_targets = array_append(sabotaged_targets, p_target)
    WHERE match_id = p_id AND user_id = v_uid;
```
(`sabotaged_targets` resets on the attacker's own advance — Task 1. Fog, which lands next puzzle, still consumes the attacker's one-sabotage for their current puzzle.)

- [ ] **Step 3: Rollback-test** — second `match_use_powerup` same puzzle → `powerup_reason=one_per_puzzle`, inventory unchanged; second `match_sabotage` same target → `sabotage_reason=already_sabotaged`, inventory unchanged; a *different* target still allowed. `ROLLBACK`.

- [ ] **Step 4: Client — surface the notices**

`src/routes/+page.svelte`: after a match powerup/sabotage RPC returns, if the board carries `powerup_reason`/`sabotage_reason`, show a toast ("One power-up per puzzle" / "You've already sabotaged {name} this puzzle"). Also proactively grey the power-up tray when `matchInfo.used_powerups.length >= 1` (mirror the server cap; the existing filter is at `~:1200-1204`).

- [ ] **Step 5: Apply + commit** (`supabase-match-caps.sql`).

---

### Task 5: Broke = danger screen + one final guess + timer (server)

**Files:** Create `supabase-match-broke.sql`. Touches live `_match_board`, `match_submit_guess`; dump `match_fold` to reuse its fold semantics.

- [ ] **Step 1: `_match_board` — `must_guess` when broke**

Dump live. Compute whether the player can afford the cheapest still-buyable letter under their active debuffs, and add `'must_guess', <bool>` to `v_minfo`. Cheapest buyable = min effective cost over letters not in `incorrect_letters` and not fully revealed; apply the same cost stack (`half_off`/`tax`/`vowel_block`; ignore one-shot `toll` for the floor). If no letter is affordable and the puzzle is unsolved → `must_guess=true`. (Model on Daily's `_daily_cheapest_buyable`; add a `_match_cheapest(cp, phrase)` helper if cleaner.)

- [ ] **Step 2: `match_submit_guess` — broke + wrong ⇒ fold**

Dump live `match_submit_guess` and `match_fold`. In the wrong-guess branch, if the player is broke (same `must_guess` predicate as Step 1), instead of just applying `v_pen`, **fold the puzzle** (end it as a loss and advance) reusing `match_fold`'s core path — i.e. set `last_score`/`total_score` from the current bankroll, `solved` unchanged, advance `position` (or `state='done'` + `_match_maybe_settle` on the last puzzle), resetting per-puzzle columns like the advance path. Extract the fold body into a shared internal (e.g. `_match_do_fold(p_id, p_uid)`) called by both `match_fold` and the broke-wrong path to avoid duplication.

- [ ] **Step 3: Rollback-test** — broke player, wrong guess → puzzle folds (advances / done), not just penalized; solvent player, wrong guess → still just the `v_pen` penalty (unchanged). `must_guess` true only when nothing is affordable. `ROLLBACK`.

- [ ] **Step 4: Apply + commit** (`supabase-match-broke.sql`).

---

### Task 6: Broke last-stand + timer (client)

**Files:** Modify `src/routes/+page.svelte`, and the `SolveTimer` usage.

**Interfaces — Consumes:** Task 5 `matchInfo.must_guess`; Task 2's board; `matchInfo.started_at` (add it in Step 1).

- [ ] **Step 1: Server — expose `started_at` for the timer**

In `_match_board`'s `v_minfo` (fold this small edit into `supabase-match-broke.sql` or a tiny `supabase-match-minfo-timer.sql`), add `'started_at', cp.started_at`. Apply + commit.

- [ ] **Step 2: In-match count-up timer**

`src/routes/+page.svelte`: relax the Daily-only timer gate (`~:4404`, `dailyTimerActive` at `~:638`) so the `SolveTimer` (count-up) also renders in the match HUD (`~:4518-4551`), driven by `matchInfo.started_at`. Match Daily's treatment.

- [ ] **Step 3: Danger screen + single guess**

Add `match` to `dangerMode` (`~:543-546`): `|| (isMatch && !!matchInfo?.must_guess)`. When `dangerMode` in a match, show the same danger vignette + "OUT OF MONEY — last guess" cue used by Daily/Free Play, plus the countdown. Replace the silent broke path (`brokeMode`/`isBroke`/`manageBrokeTimer` at `~:1062, 1091-1132`, broke bar `~:4589-4592`): the player gets ONE guess; a wrong guess (server folds via Task 5) or the timer expiring (`doFold(true)`) ends the puzzle. Keep the timer visible.

- [ ] **Step 4: Verify** — `npm run build`; visual/functional check via the Task 8 harness (broke → danger + one guess + timer; wrong guess folds). Commit.

---

### Task 7: Move the Pot to the top bar (client only)

**Files:** Modify `src/routes/+page.svelte`.

- [ ] **Step 1: Relocate the pot chip**

Remove the `.pot-chip` from `.match-meta` (`~:4526`). Find the top bar's WORDBANK title + chat control (grep the top-bar markup for the app title / chat button) and render the pot chip **to the left of the WORDBANK title**, opposite the chat control, only when `isMatch && matchPot > 0`. Reuse `matchPot` (`~:668-672`) and `.pot-chip` styling; adjust for the top-bar context.

- [ ] **Step 2: Verify** — `npm run build`; confirm in the harness screenshot the pot sits top-left in a match and money/other modes are unaffected. Commit ("Match: pot moves to the top bar, left of the title").

---

### Task 8: Keyboard reflects sabotaged prices + E2E

**Files:** Modify `src/lib/components/Keyboard.svelte`, `src/routes/+page.svelte`. Temp `scripts/qa-match-mechanics.mjs`.

**Interfaces — Consumes:** `matchInfo.my_debuffs` + `matchInfo.used_powerups` (already on the board).

- [ ] **Step 1: Real prices on the keyboard**

`src/lib/components/Keyboard.svelte`: `effCosts` (`~:87-103`) gains a `gameMode==='match'` branch applying the exact cost stack from `$gameStore.matchInfo`: `half_off` if in `used_powerups` (×0.5, CEIL), `tax` if in `my_debuffs` (×1.5, CEIL), `vowel_block` ×3 on AEIOU, `toll` ×3 (show on all letters as the "next letter" surcharge). `disabledKeys` (`~:128-130`) and `affordPool` (`~:117-123`, match uses `bankroll`) must compare against these real costs. Add a "taxed" visual (tint/▲) on any key whose effective cost exceeds base. Consolidate so the broke detector `isBroke` (`+page.svelte:1091-1108`) uses the same effective-cost helper (single source of truth).

- [ ] **Step 2: Build** — `npm run build` clean.

- [ ] **Step 3: Two-player E2E harness** (adapt `scripts/qa-h2h.mjs` → `scripts/qa-match-mechanics.mjs`)

Drive a 2-player, ≥2-puzzle match and assert:
- Fog cast on the opponent hides their **next** puzzle's clue until their 3rd buy; never puzzle 1; greyed when they're on the last puzzle.
- Erase removes the opponent's **most-recently-revealed** letter (deterministic).
- The count-up timer is visible in-match; the pot renders top-left.
- Under `tax`, the keyboard prices + disabled keys match the server charge (buy a taxed letter, compare bankroll delta to the displayed price).
- Broke → danger screen + one guess + timer; a wrong guess folds.
- Second power-up and second sabotage-vs-same-opponent are rejected with the notices.

- [ ] **Step 4: Run, screenshot, clean up**

`npm run dev` (background) then `node scripts/qa-match-mechanics.mjs`; save screenshots; assert all PASS. Delete the temp harness. Final `npm run build`. Commit any client fixes.

---

## Self-Review notes

- **Spec coverage:** Fog (T1 seed + T2), Erase (T1 col + T3), timer (T6), pot (T7), keyboard costs (T8), broke (T5 server + T6 client), caps (T4). ✔
- **Foundation first:** T1 adds all columns + the advance reset; every later task depends on it. ✔
- **_match_board edited by T2/T5/T6** — safe because each task dumps the *live* body (which includes prior tasks' edits) and applies a fresh `CREATE OR REPLACE`; sequential composition, not git-file merges. ✔
- **Type/name consistency:** `pending_fog`, `fog_buys_left`, `reveal_order`, `sabotaged_targets` used identically across T1–T5; board fields `must_guess`, `started_at`, `opponents[].can_fog`, `*_reason` produced server-side and consumed client-side by the named tasks. ✔
- **No money-mode leakage:** all server predicates key on the match participant; all client changes gate on `isMatch`/`gameMode==='match'`. ✔
