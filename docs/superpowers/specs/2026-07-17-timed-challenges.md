# Timed Challenges — Design Spec

**Date:** 2026-07-17

## Goal

Make challenge (`gameMode:'match'`) timing **creator-configurable**, identically for 1v1 and
group (both are async, both rank by score→time). The creator picks a **clock scope** and
whether **time affects score**.

## Decisions (locked)

**Two independent creator choices, set in the builder:**
1. **Clock mode** — `none` (default, today's behavior) · `puzzle` (a countdown per puzzle) ·
   `match` (one countdown for the whole pack).
2. **Time affects score** (`time_scores`) — off (clock is a hard limit only; score stays
   bounty-based, time only breaks ties as today) · on (a **speed bonus**: leftover time when
   you solve adds points).

Durations offered (live-play clocks, distinct from the existing async "respond-within"
deadline):
- Per-puzzle: **30s / 1m / 2m / 5m**.
- Whole-match: **3m / 10m / 30m**.

**1v1 == group:** the same system applies to both. No mode-specific timing.

## Data model

`challenge_matches` (new columns):
- `clock_mode text NOT NULL DEFAULT 'none'` — 'none'|'puzzle'|'match'
- `clock_seconds int` — the limit (per-puzzle if 'puzzle', total if 'match'); NULL when 'none'
- `time_scores boolean NOT NULL DEFAULT false`

`challenge_participants` (new column):
- `puzzle_started_at timestamptz` — when the player opened their CURRENT puzzle (for the
  per-puzzle clock). Set at `match_start` (puzzle 1) and re-stamped on every advance in
  `_match_resolve_and_advance` and `_match_do_fold`. (The match-level `started_at` already
  exists — used for the whole-match clock.)

## Mechanics

**Clock enforcement — repurpose `_match_tick(p_id,p_uid)`** (already a no-op called at the top
of `match_buy_letter` and `match_submit_guess`; it has `cp` + `m` loaded). Make it authoritative:
- `clock_mode='puzzle'`: if `now() - cp.puzzle_started_at > m.clock_seconds` and the puzzle is
  unsolved → **force-fold the current puzzle** (call `_match_do_fold`) and return `true` (caller
  returns the board). Folding advances/ends per existing rules; the folded puzzle scores its
  current bankroll-kept like any fold.
- `clock_mode='match'`: if `now() - cp.started_at > m.clock_seconds` → **end the match for this
  player** — fold every remaining puzzle (loop `_match_do_fold` until `state='done'`) and return
  `true`.
- `clock_mode='none'`: unchanged (returns false).

`_match_tick` fires on the player's own actions (buy/guess); the **client** is the live driver
(countdown hits 0 → it calls a guess/fold so the server tick resolves it), with the server tick
as the quit-proof backstop (mirrors the broke-timer pattern). Also call `_match_tick` inside
`_match_board` reads for the acting player so an expired clock resolves when they reopen.

**Speed bonus (`time_scores=true`)** — in `_match_resolve_and_advance`'s WIN path, add a bonus to
the puzzle's kept-score:
- `clock_mode='puzzle'`: `bonus = GREATEST(0, m.clock_seconds - elapsed_this_puzzle) * RATE`
  where `elapsed_this_puzzle = extract(epoch from now() - cp.puzzle_started_at)`.
- `clock_mode='match'`: apply the same formula against the **whole-match** remaining at each
  solve (`m.clock_seconds - (now - started_at)`), so early solves in the match bank more.
- `RATE` = **3 points/second** — a single tunable constant (documented; expect to tune after
  playtest). Bonus is added into `total_score` alongside kept bounty, so it flows through the
  existing rank-by-`total_score` (→ time tiebreak) unchanged.
- When `time_scores=false`, no bonus; ranking is exactly as today.

## Builder UI

New "Timing" block in the builder (Step 2, "The match"), shared by 1v1 and group:
- A 3-way selector: **No timer** (default) / **Per-puzzle timer** / **Whole-match timer**.
- When a timer is chosen: a duration segmented control (the values above).
- When a timer is chosen: a **"Speed bonus"** toggle → "Solve faster to earn bonus points."
- Confirm-step copy summarizes it ("Per-puzzle · 1m · speed bonus").
- State: `mbClockMode`, `mbClockSeconds`, `mbTimeScores`; passed through `createMatch` →
  `create_match(p_clock_mode, p_clock_seconds, p_time_scores)`; stored on the match row.

## Client display

- Reuse the in-match timer slot. When `matchInfo.clock_mode !== 'none'`, render a **countdown**
  (from `puzzle_started_at` for 'puzzle', `started_at` for 'match') instead of the count-up.
  Expose `clock_mode`, `clock_seconds`, and the relevant anchor in `matchInfo` via `_match_board`.
- On client-side expiry (countdown reaches 0), the client calls the existing fold/guess path so
  the server resolves it; show the danger/last-stand treatment as it hits the final seconds.
- Speed-bonus, when on, is surfaced in the results modal as part of the kept-score (a small
  "+N speed" note is optional polish, not required v1).

## Testing

- Rollback-test `_match_tick`: puzzle clock expiry force-folds the current puzzle; match clock
  expiry ends the match (all remaining folded); `clock_mode='none'` is a no-op.
- Speed bonus: solving with time left adds `remaining*RATE` to `total_score`; `time_scores=false`
  adds nothing.
- `puzzle_started_at` is re-stamped on advance and fold; `create_match` stores the config.
- Two-player E2E (with a short 30s per-puzzle clock): the countdown shows, expiry folds, and a
  fast solve banks a visible bonus.

## Out of scope / notes

- Daily / Cash Game / Free Play unchanged.
- The async "respond-within" deadline (24h etc.) is a SEPARATE existing mechanic (forfeit your
  turn), not this live clock — untouched here.
- `RATE` and the duration options are the obvious tuning knobs post-playtest.
