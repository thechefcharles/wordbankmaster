# 1v1 Challenge Mechanics Overhaul — Design Spec

**Date:** 2026-07-16
**Source:** Playtest feedback (1v1 with a friend). Seven changes to how challenge matches play.

## Goal

Make 1v1 challenge (`gameMode:'match'`) power-ups, sabotages, timing, and the broke
state feel fair, legible, and deliberate — fixing the current invisible/timing-dependent
behaviors surfaced in playtesting.

## Background — current state (verified)

- Challenge matches are **async**: both players play the same puzzle pack on their own
  clocks (there are no literal turns). Play runs under `gameMode:'match'`; the board comes
  from `_match_board`, and per-puzzle state lives on `challenge_participants`.
- The authoritative RPCs `match_buy_letter` and `match_use_powerup` are **DB-only** (no
  `CREATE FUNCTION` in the repo). `match_sabotage` is in `supabase-match-debuff-attribution.sql`;
  `_match_board`/`_match_tick` in `supabase-blitz-removal-server.sql`; `match_start` /
  `_match_resolve_and_advance` / `_match_settle` / `match_fold` in
  `supabase-match-speed-tiebreak.sql`. **Implementation must dump the live bodies and
  transform them** (repo files may lag prod).
- Per-puzzle state on `challenge_participants` resets on advance: `debuffs='{}'`,
  `active_powerups='{}'` (`supabase-match-speed-tiebreak.sql:59`).
- `revealed_positions` is stored as a **sorted DISTINCT int array** — no reveal-order memory.

## Global constraints

- **Money mode unaffected elsewhere:** these changes are scoped to `gameMode:'match'`. Daily,
  Cash Game, and Free Play behavior must not change.
- Client letter-cost math is currently duplicated in `Keyboard.svelte` (`letterCosts`) and
  `+page.svelte` (`LETTER_COSTS`, `isBroke`). Any cost change must be applied consistently to
  all consumers (keyboard prices, affordability/`disabledKeys`, and the broke detector).
- Server is authoritative for all economy/effects; the client only reflects what the board
  reports. New effects must be enforced server-side, not just shown client-side.

---

## The seven changes

### 1. Fog → a queued "next-puzzle" curse, 3-buy duration

**Current:** `fog` sabotage hides the target's **clue** for their entire current puzzle
(persistent debuff, cleared on advance). Applied instantly to the current puzzle, so it only
does anything if it lands before the target reads the clue — whoever opens first is immune.
Not discoverable; timing-dependent coin-flip.

**New:** Fog is a **queued curse on the opponent's next un-started puzzle**.
- **Cast anytime** (including while the opponent is mid-puzzle). It does not affect the
  opponent's current puzzle at all — it attaches to the next puzzle they open that they have
  **not started yet**.
- On the fogged puzzle, the **clue is hidden until the opponent has made 3 letter purchases**,
  then the clue appears. ("Letter purchase" = any `match_buy_letter` call, correct or wrong.)
- **Never affects puzzle 1** — both players always open the match with their clue. (Naturally
  enforced: fog only applies on an *advance*, and advances happen after puzzle 1.)
- **Only castable when the opponent has an un-started next puzzle to attach to.** If they have
  none (e.g., already on the last puzzle, or already opened their next puzzle before the cast),
  the Fog action is **disabled/greyed with a tooltip** ("nothing left to fog"). If the cast
  succeeds but the opponent races ahead and opens the intended puzzle first, the pending fog
  attaches to their *next still-un-started* puzzle instead — it never lands on a puzzle they've
  already seen.
- Casting Fog spends the attacker's **one sabotage** for the puzzle the attacker is currently
  on (see #7).

**Data / mechanics:**
- Add `pending_fog boolean default false` on `challenge_participants` — set on the target when
  Fog is cast.
- Add `fog_buys_left int default 0` — the active countdown on the current puzzle. On advance to
  an un-started puzzle (not puzzle 1), if `pending_fog` then set `fog_buys_left := 3` and clear
  `pending_fog`.
- `_match_board`: return `clue = NULL` when `fog_buys_left > 0` (replaces the old
  `'fog' = ANY(debuffs)` clue-hide).
- `match_buy_letter`: `fog_buys_left := GREATEST(0, fog_buys_left - 1)` on each buy.
- `match_sabotage` (`fog` branch): set target's `pending_fog := true`; reject (with a reason)
  if the target has no un-started next puzzle.
- Client: the match HUD must know whether Fog is castable (needs the target's position /
  pack_size / started state, exposed via `matchInfo`), and label it clearly ("Fog Pat's next
  puzzle — he starts it blind for 3 buys").

### 2. Lock → **Erase** (wipe the most-recently-revealed letter)

**Current:** `lock` sabotage instantly wipes a **random** revealed letter (all its positions)
off the opponent's board (`supabase-match-debuff-attribution.sql:35-43`). Already an "erase,"
just random. No reveal-order tracked.

**New:**
- Rename the item to **Erase** (display name + description; shop copy already says "Wipe a
  letter an opponent revealed").
- Erase the opponent's **most-recently-revealed letter** (all positions of it) instead of a
  random one. Instant; hits the current puzzle.

**Data / mechanics:**
- **Track reveal order:** add `reveal_order text[] default '{}'` on `challenge_participants` —
  the distinct letters in the order the player first revealed them. `match_buy_letter` appends
  the bought letter (if it revealed ≥1 new position and isn't already in the array). Reset on
  advance. (This ordering "may come in handy" for future features, per the ask.)
- `match_sabotage` (`erase`/`lock` branch): take the **last** element of the target's
  `reveal_order`, remove all its positions from `revealed_positions`, and pop it from
  `reveal_order`. No-op with a clear message if the target has nothing revealed yet.

### 3. Show the solve timer in 1v1

**Current:** On-screen `SolveTimer` is gated to Daily only (`+page.svelte:4404`,
`dailyTimerActive` at `:638`). The server already stamps `started_at` and computes
`_match_elapsed()` for the fastest-solve tiebreaker, but never surfaces it.

**New:** Show a **count-up** clock in the match HUD (same component/treatment as Daily), so the
speed tiebreaker is visible.
- Server: include `started_at` (and/or `elapsed`) in `_match_board`'s match payload
  (`v_minfo`).
- Client: render the timer in the match HUD block (`+page.svelte:4518-4551`) and relax the
  Daily-only gate; drive it from the match's `started_at` like Daily's does.

### 4. Move the Pot to the top bar

**Current:** Pot renders as a `.pot-chip` inside `.match-meta`, under "Your Score"
(`+page.svelte:4526`).

**New:** Move the Pot to the **top bar, to the left of the WORDBANK title** (opposite the chat
control). Client-only layout change; value source (`matchPot`) unchanged. Remove it from
`.match-meta`.

### 5. Keyboard shows the real (sabotaged) letter prices

**Current:** Cost-raising sabotages exist — `tax` (+50%, persistent), `toll` (×3 next letter,
one-shot), `vowel_block` (vowels ×3, persistent). The **keyboard shows base prices** while the
server charges the raised amount, and affordability (`disabledKeys`) is computed on base cost —
so a key can look affordable and cost more. The multipliers flow only through the DB
`match_buy_letter`.

**New:** The keyboard reflects the **real** current price per letter under active debuffs, and
affordability uses those real prices.
- Server: expose the player's own active cost debuffs in `_match_board`'s match payload (e.g.
  `my_debuffs` with tax/toll/vowel_block flags, or a per-letter effective-cost multiplier
  descriptor). Must mirror the exact server cost stack: `Half Off → Tax(+50%) → Vowel
  Block(×3 vowels) → Toll(×3, then removed)`.
- Client: `Keyboard.svelte` `effCosts` gains a `gameMode==='match'` branch that applies the
  reported debuffs; `disabledKeys` and the `isBroke` detector (`+page.svelte`) use the same
  real prices. Add a visual cue on taxed keys (e.g. a "taxed" tint / up-arrow) so the raise is
  legible.
- Consolidate the duplicated letter-cost math so keyboard price, affordability, and broke-
  detection all read one source of truth.

### 6. Broke = danger screen + one final guess + timer

**Current:** When broke (`bankroll < cheapest buyable`), match starts a **silent 60-second
auto-fold clock** with unlimited free guesses; `match` is deliberately excluded from
`dangerMode` (`+page.svelte:543-546`). Solve within 60s or auto-fold.

**New:** When broke, show the **Daily-style danger screen** with **exactly one final guess** and
a **visible countdown**. A wrong guess **or** the timer expiring → you **fold** the puzzle.
- Server: `_match_board` reports a must-guess/broke flag when the player can't afford the
  cheapest letter. `match_submit_guess` (DB-only) enforces: while broke, a **wrong** guess folds
  the puzzle (loss); guessing is the last action. The timer expiring folds the puzzle
  (existing broke-timer path, but now surfaced).
- Client: add `match` to `dangerMode`; reuse the danger vignette + last-stand cue (mirroring
  Daily/Free Play's "OUT OF MONEY — last guess"); show the countdown; wire the single guess.

### 7. Usage caps (with "already used" notifications)

**Current:** Self power-ups are capped **one-of-each per puzzle** (client filters
`used_powerups`). Sabotages have **no cap and no cooldown** — spammable (lock especially).

**New:**
- **One power-up per puzzle, total** (any type — tighter than one-of-each). Enforced server-side
  in `match_use_powerup` (reject if `active_powerups` already non-empty this puzzle) and
  reflected client-side. Trying a second shows a notification ("One power-up per puzzle").
- **One sabotage per opponent per puzzle.** Enforced server-side in `match_sabotage`. Trying a
  second against the same opponent shows "You've already sabotaged {name} this puzzle."
- **Data:** add `sabotaged_targets uuid[] default '{}'` on `challenge_participants` (the
  attacker's targets sabotaged during their current puzzle); reset on advance. `match_sabotage`
  appends the target and rejects a repeat with a `reason`. Power-up cap reuses the existing
  `active_powerups`.
- The attacker's cap is keyed to **the attacker's current puzzle position** (casting Fog, which
  lands on the opponent's next puzzle, still consumes the attacker's one-sabotage for the
  attacker's current puzzle).

---

## Data model summary (`challenge_participants` additions)

| Column | Purpose | Reset on advance |
|---|---|---|
| `pending_fog boolean` | queued fog for the player's next un-started puzzle | consumed → `fog_buys_left`, then false |
| `fog_buys_left int` | active fog countdown on current puzzle (clue hidden while >0) | seeded from `pending_fog` (3), else 0 |
| `reveal_order text[]` | letters in first-reveal order (for Erase; future use) | yes → `'{}'` |
| `sabotaged_targets uuid[]` | opponents sabotaged during the attacker's current puzzle | yes → `'{}'` |

Existing `active_powerups` (power-up cap) and `debuffs` (tax/toll/vowel_block) reset on advance
as today.

## Server functions touched (dump live, transform, rollback-test, apply)

`match_sabotage`, `match_buy_letter` (DB-only), `match_use_powerup` (DB-only),
`match_submit_guess` (DB-only), `_match_board`, `_match_resolve_and_advance`. Follow the repo's
dump-transform-assert-rollbacktest-apply migration pattern.

## Testing

- **Two-player E2E** (adapt `scripts/qa-h2h.mjs`): play a pack and assert —
  - Fog cast on the opponent hides their **next** puzzle's clue until their 3rd buy, never
    touches puzzle 1, and is disabled when they have no un-started next puzzle.
  - Erase removes the opponent's **last-revealed** letter (deterministic, not random).
  - The count-up timer is visible in-match; the Pot renders in the top bar.
  - Under a tax/toll/vowel_block debuff, the keyboard prices and disabled keys match what the
    server actually charges.
  - Going broke shows the danger screen + one guess + timer; a wrong guess folds.
  - Second power-up and second sabotage-on-same-opponent are rejected with the right notices.
- **Server rollback tests** for each RPC change (seeded match, `BEGIN…ROLLBACK`).

## Out of scope

- Any change to Daily, Cash Game, or Free Play.
- New power-ups/sabotages beyond the Fog/Erase reworks.
- Group (3+) challenge-specific balancing (rules apply per-opponent, which generalizes, but
  group tuning is not a goal here).
- The economic/anti-abuse audit items (separate track).
