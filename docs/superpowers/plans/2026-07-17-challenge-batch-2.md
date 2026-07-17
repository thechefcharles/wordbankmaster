# Challenge Batch 2 — Implementation Plan

> REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Ship the full slate discussed: vowel-block nerf, payout toggle, collapsible profile items, store-gate-during-games, realtime social layer + group-add notification, and configurable timed challenges.

**Tech:** SvelteKit 2.16 (Svelte 5), Supabase Postgres (dump→transform→rollbacktest→apply), Supabase Realtime, `npm run check` + `npm run build`.

## Global Constraints
- Match/challenge-scoped where relevant; Daily/Cash Game/Free Play unchanged unless a task says otherwise (the store-gate touches all real modes by design).
- **Verify with `npm run check` (svelte-check) AND `npm run build`** — Vite misses reactive ReferenceErrors. Known-OK pre-existing: `points.test.js:31`, `profile/+page.svelte:408`.
- Server changes: dump live body, transform, rollback-test (BEGIN…ROLLBACK on seeded data), apply to prod, commit `supabase-*.sql`. Keep everything else byte-identical.
- Commit messages end with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- Ground: `payout` and `mode` are already columns on `challenge_matches`; `_match_tick(p_id,p_uid)` exists as a no-op called atop `match_buy_letter`/`match_submit_guess`; `_match_do_fold(p_id,p_uid)` is the shared fold internal; participants have `started_at`; `challenge_participants` recently gained `fog_buys_left`/`reveal_order`/`sabotaged_targets`/`solved_positions`/`pending_fog` (patterns to mirror).

---

### Task 1: Vowel Block → lasts 3 buys
**Files:** `supabase-vowel-block-buys.sql`. Live: `match_sabotage`, `match_buy_letter`, `_match_board`; column on `challenge_participants`.
Mirror the Fog mechanism.
- [ ] `ALTER TABLE challenge_participants ADD COLUMN IF NOT EXISTS vowel_block_left int NOT NULL DEFAULT 0;` (reset in the per-puzzle reset lists of `_match_resolve_and_advance` and `_match_do_fold`, like `fog_buys_left`).
- [ ] `match_sabotage` vowel_block branch: instead of adding `'vowel_block'` to `debuffs[]`, set `vowel_block_left = 3` on the target (keep it OUT of the persistent debuffs path). Keep the `already_sabotaged`/inventory ordering intact.
- [ ] `match_buy_letter`: apply the vowel ×3 when `cp.vowel_block_left > 0` (replace the `'vowel_block' = ANY(debuffs)` check), and decrement `vowel_block_left = GREATEST(0, vowel_block_left - 1)` on every buy (any letter). Keep the rest of the cost stack (half_off/tax/toll) unchanged.
- [ ] `_match_board`: the client keyboard reads debuffs; expose `vowel_block_left` in `v_minfo` (or keep `vowel_block` in `my_debuffs` while `vowel_block_left>0`) so `Keyboard.svelte`'s vowel ×3 display still fires. Simplest: in `v_minfo.my_debuffs`, include `'vowel_block'` when `cp.vowel_block_left>0` (synthesize it) so the existing client cost logic is unchanged.
- [ ] Rollback-test: cast vowel_block → `vowel_block_left=3`; 3 buys → 0, vowels normal again; resets on advance. Apply + commit.
Note: "3 buys" = any 3 purchases (Fog model). Client copy (shop/inventory META) → "Vowels cost 3× for their next 3 buys."

### Task 2: Payout creator toggle
**Files:** `src/routes/+page.svelte` (builder Step 3 + confirm copy + `mbPayout`); `supabase-payout-choice.sql` (`_match_settle` respects `m.payout`; `create_match` stores it).
- [ ] Client: in Step 3 ("The stakes"), for a GROUP (3+ possible) show a toggle: **Winner takes all** vs **Top finishers split**. Set `mbPayout = 'winner' | 'podium'`. For a 1v1 (friend target) force `'winner'` (hide the toggle — WTA only). Pass `payout: mbPayout` (already wired at ~2203) and update the confirm copy (~2184-2187, 2239-2243) to reflect the CHOICE, not the auto rule.
- [ ] Server: `create_match` — dump live; store `p_payout` on the match (`payout` column already exists; ensure it's written from the param, defaulting by count if null for back-comat). `_match_settle` — dump live; where it currently derives podium-vs-winner by participant count, honor `m.payout` when set ('winner' → winner-take-all even for 3+; 'podium' → split). Rollback-test both a 'winner' and 'podium' group settle. Apply + commit.

### Task 3: Collapsible items in profile
**Files:** `src/routes/profile/+page.svelte` (~270-276, the "My Items" block).
- [ ] Wrap the `<InventoryList>` block in a collapse (a `<details>`/`<summary>` or a toggle+`{#if}`), collapsed or expanded by default (default expanded, remembers via a local `let` is fine). Keep the "My Items" header; add a chevron. `npm run check` + build. Commit.

### Task 4: Store — gate gameplay-item buying during active games
**Files:** `supabase-store-active-game-gate.sql` (`buy_powerup`); `src/routes/+page.svelte` / shop (grey the mid-game store button).
- [ ] `buy_powerup`: dump live. For gameplay items only (`v_kind IN ('climb','daily','sabotage')` — NOT cosmetics), reject with `reason='in_game'` when the user has an active real game: an active Cash Game run (`climb_state` state='active'), an in-progress Daily today (a `daily_sessions`/daily row unsolved for the current day), OR an active challenge (`challenge_participants` state='active'). Cosmetics always allowed. Rollback-test: buying a power-up with an active challenge participant → `in_game`; buying a cosmetic → allowed; buying with no active game → allowed. Apply + commit.
- [ ] Client: grey/hide the in-game store button (`.bag-store` → `/shop`, ~+page.svelte:2775) while `gameActive`, and show the `in_game` rejection reason as a toast if hit. `npm run check` + build. Commit.

### Task 5: Realtime social layer (friend requests + notifications)
**Files:** `supabase-realtime-enable.sql` (publication/RLS); client subscriptions in the friends/notifications components (grep for the friends panel + notifications bell + `friend_requests`/`notifications` tables and their stores).
- [ ] **Enable Realtime**: confirm/add `friend_requests` and `notifications` to the `supabase_realtime` publication (`ALTER PUBLICATION supabase_realtime ADD TABLE ...` — idempotent-guard). Verify RLS SELECT policies let a user see their own rows (needed for realtime delivery). Commit the SQL.
- [ ] **Friend-request live flips**: in the friends UI, subscribe via `supabase.channel(...).on('postgres_changes', {event:'*', table:'friend_requests', filter for me as sender or recipient}, cb)` and re-derive pending/accepted state on change (sender sees "Pending" flip to accepted/disappear; recipient's incoming list updates). Unsubscribe on unmount.
- [ ] **Notifications live + self-clearing**: subscribe to `notifications` where `user_id = me`; on INSERT show it live (badge/list), on UPDATE/DELETE remove dismissed ones. When a user ACCEPTS a friend request, mark/delete the corresponding "friend_request" notification (server-side in the accept RPC, or client dismiss) so it disappears for them. Ensure the accept flow removes the actioned notification.
- [ ] `npm run check` + build. Commit. (If Realtime isn't reachable in the QA/headless env, verify subscription wiring compiles + a manual note; realtime is validated live by the user.)

### Task 6: "Added to a group" notification
**Files:** `supabase-group-add-notify.sql` (the add-member RPC).
- [ ] Find the group add-member RPC (grep `group_members` insert / `add_group_member`/`add_to_group`). Dump live; after a successful add, `PERFORM public._notify(new_member_uid, 'group_added', 'Added to a group', <adder> || ' added you to ' || <group name>, jsonb_build_object('group_id', ...))`. Don't notify on self-join/creation. Rollback-test the notify row is written. Apply + commit. (Delivered live via Task 5's realtime.)

### Task 7: Timed challenges — schema + config
**Files:** `supabase-timed-schema.sql`. Per `docs/superpowers/specs/2026-07-17-timed-challenges.md`.
- [ ] `ALTER TABLE challenge_matches ADD COLUMN IF NOT EXISTS clock_mode text NOT NULL DEFAULT 'none', ADD COLUMN IF NOT EXISTS clock_seconds int, ADD COLUMN IF NOT EXISTS time_scores boolean NOT NULL DEFAULT false;`
- [ ] `ALTER TABLE challenge_participants ADD COLUMN IF NOT EXISTS puzzle_started_at timestamptz;`
- [ ] `create_match`: dump live; accept `p_clock_mode text default 'none'`, `p_clock_seconds int default null`, `p_time_scores boolean default false`; store on the match. `match_start`: stamp `puzzle_started_at = now()` for the starter. Rollback-test config stored + puzzle_started_at set. Apply + commit.

### Task 8: Timed challenges — clock enforcement + speed bonus (server)
**Files:** `supabase-timed-engine.sql`. Live: `_match_tick`, `_match_resolve_and_advance`, `_match_do_fold`, `_match_board`.
- [ ] `_match_tick`: implement per the spec — `clock_mode='puzzle'` & `now()-cp.puzzle_started_at > m.clock_seconds` & unsolved → `_match_do_fold` + return true; `clock_mode='match'` & `now()-cp.started_at > m.clock_seconds` → loop `_match_do_fold` until done + return true; else false.
- [ ] `_match_resolve_and_advance` + `_match_do_fold`: re-stamp `puzzle_started_at = now()` on every advance (both, all branches), alongside the existing per-puzzle resets.
- [ ] Speed bonus in `_match_resolve_and_advance` WIN path: when `m.time_scores`, add `GREATEST(0, m.clock_seconds - elapsed)*3` to the banked `total_score` (elapsed from puzzle_started_at for 'puzzle', from started_at for 'match'). `RATE=3` as a documented constant.
- [ ] `_match_board`: expose `clock_mode`, `clock_seconds`, `time_scores`, and `puzzle_started_at` in `v_minfo` for the client countdown.
- [ ] Rollback-test: puzzle-clock expiry folds; match-clock expiry ends match; speed bonus adds `remaining*3`; `none` unaffected. Apply + commit.

### Task 9: Timed challenges — builder UI + client countdown
**Files:** `src/routes/+page.svelte`.
- [ ] Builder (Step 2): a "Timing" block — 3-way No timer / Per-puzzle / Whole-match; when set, a duration segmented control (per-puzzle 30s/1m/2m/5m; match 3m/10m/30m) + a "Speed bonus" toggle. State `mbClockMode`/`mbClockSeconds`/`mbTimeScores`; pass through `createMatch` (add the params in `statsStore.js createMatch` wrapper). Confirm-copy summary.
- [ ] Client display: when `matchInfo.clock_mode !== 'none'`, render a **countdown** in the match timer slot (from `puzzle_started_at` for 'puzzle', `started_at` for 'match') instead of the count-up; drive the danger treatment near 0; on reaching 0 call the fold/guess path so the server tick resolves it. `npm run check` + build. Commit.

### Task 10: E2E + final verification
**Files:** temp `scripts/qa-batch2.mjs` (delete after).
- [ ] Two-player harness (adapt qa-h2h): a short 30s per-puzzle timed match — countdown shows, expiry folds, a fast solve banks a visible speed bonus; vowel-block lasts 3 buys; payout choice honored (create a group 'winner' match, verify settle pays one winner); store buy blocked mid-game. Screenshot. Delete harness. Final `npm run check` + build.

## Self-Review notes
- Vowel-block + fog share the "N-buys counter reset on advance" pattern. ✔
- Payout: column exists; task wires create→store→settle-respect + client toggle. ✔
- Store-gate is the only intentionally cross-mode change (Daily/Cash Game/challenge active-check). ✔
- Timed: `_match_tick` is the enforcement hook; `puzzle_started_at` re-stamped on every advance/fold; speed bonus flows through existing `total_score` ranking. ✔
- Realtime needs publication + RLS; validated live by the user. ✔
