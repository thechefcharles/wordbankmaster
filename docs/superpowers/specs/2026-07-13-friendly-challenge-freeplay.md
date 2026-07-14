# Friendly Challenges as Free Play — Design Spec

**Date:** 2026-07-13

## Goal

Make **friendly** challenge matches (wager = $0) present and behave like **Free Play**:
show the ★ points unit instead of `$`, and keep friendly matches out of all global
stats, leaderboards, and badges. The ★ points a player earns in a friendly still bank
into their (cash-convertible) Free Play points total.

## Background (current state)

- "Friendly" is **not** a column — it is derived from `challenge_matches.wager = 0`.
  `challenge_participants.paid = (wager > 0)`.
- A challenge match plays under `gameMode: 'match'` (`reconcileMatchBoard`,
  `GameStore.js:723`). Letters are bought from a per-puzzle **bounty** budget
  (`_match_bounty = _climb_bounty(pid, 2.0)`), **not** the real bank. Real cash only
  moves at wager escrow (accept/create) and settle payout — both already gated on
  `wager > 0`, so a friendly match already spends no real money.
- The HUD, however, still renders that bounty in `$`: bounty hero (`+page.svelte:4621-4629`),
  keyboard prices (`Keyboard.svelte:125`), the top balance chip shows the real account
  balance (`+page.svelte:4392-4403`), and "Your Score" is `$…` (`4488-4491`).
- `_match_settle` writes a `game_results` row (`game_mode='challenge'`, null money for
  friendly) and awards `first_blood` / `hustler` badges + category-solve credit for
  **every** participant regardless of wager. So friendly matches currently DO feed the
  challenge leaderboard, best-bounty, category badges, and play-log/history.

## Design decisions (locked)

1. **Points bank.** ★ earned in a friendly match banks into the player's Free Play points
   total (`freeplay:total`, the balance that converts to cash). Friendly is an earning
   path — no more exploitable than Free Play, which is already unlimited.
2. **Visibility.** A finished friendly still shows in the Challenges hub with its winner
   (bragging rights). It appears in NO global stats, leaderboards, badges, or play-log.

## Scope

### A. Client display — friendly match reads as ★ points

Add a derived `isFriendlyMatch = isMatch && (matchInfo?.wager ?? 0) === 0` in
`+page.svelte` (near `isMatch`, line ~590). Then, wherever the Free Play (`isFreeplay`)
branch already swaps `$`→`★`, extend the condition to also fire for `isFriendlyMatch`:

- **Bounty hero** (`+page.svelte:4621-4636`): render `★` + value for a friendly match.
- **Keyboard prices** (`Keyboard.svelte:125`): `priceMark = '★'` when freeplay **or**
  friendly match. Requires the friendly flag to reach the Keyboard — expose it via the
  gameStore (e.g. a `friendlyMatch` field set in `reconcileMatchBoard`) so `Keyboard.svelte`
  can read it the same way it reads `gameMode`.
- **Top balance chip** (`+page.svelte:4386-4403`): for a friendly match, show the match ★
  score (or the Free Play `★ … pts` treatment) instead of the real account balance — the
  real balance is meaningless in a no-money game.
- **"Your Score"** (`4488-4491`) and **"Beat ★…"** chip (`4494-4499`): render in ★.
- Pot chip already hides at `wager = 0` — no change.

No changes to the money-match rendering path; the money match keeps `$` everywhere.

### B. Points banking — friendly ★ → Free Play total

On the client, when a friendly match completes for this player (their leg is done /
settled and `total_score` is final), add their final `total_score` to the Free Play points
total via `recordSolve(fpStorage(), score)` semantics.

- **Dedup:** bank once per match. Track banked match ids in localStorage
  (`freeplay:bankedMatches`) so re-observing a completed board never double-counts (mirror
  the earlier Free Play double-count guard).
- Hook this in `GameStore.js` where the friendly match board is reconciled and observed as
  complete for the player. Only fires for friendly (`wager === 0`) matches.

### C. Server — friendly does not count (stats gating)

In `_match_settle` (`supabase-challenge-bounty-economy.sql:226-330`), gate the following on
`m.wager > 0` so friendly participants get none of it:

- `_log_game_result(...)` (`:313-321`) — the source of leaderboard wins, best-bounty,
  play-log/history. Skipping it for friendly keeps friendlies out of all of those.
- `first_blood` (`:294`) and `hustler` (`:324-327`) badge awards. (`gold_duelist` is
  already wager-gated.)
- `_record_category_solve` (`challenge-opponent-notify.sql:38`) — category badge credit.

Backstop the read side even though `game_results` won't have friendly rows once the write
is gated:

- `get_challenge_leaderboard` (`challenge-lb-cosmetics-fix.sql`) — add `wager > 0` filter.
- `best-bounty.sql` — add `wager > 0` filter.

Migrations are built from the **live** function bodies (many files note `Full body applied
via MCP`), transformed, rollback-tested with `BEGIN…ROLLBACK` + a seeded friendly match,
then applied to prod and committed as `supabase-*.sql`.

## What stays the same

- The friendly match still resolves a winner from each player's ★ `total_score` and still
  appears in the Challenges hub with its result.
- Money matches (`wager > 0`) are entirely unaffected — same `$` HUD, same stats, same
  payout.

## Testing

- **Engine/points:** unit-cover the dedup guard (banking the same completed friendly twice
  adds the score once).
- **Server:** rollback-test that a settled friendly match writes **no** `game_results` row,
  awards no badges, no category-solve; a `wager > 0` match still does all of it.
- **E2E (Playwright, two-player harness `qa-h2h.mjs` style):** play a friendly to
  completion — verify ★ on the bounty hero + keyboard, no `$`; verify the Free Play total
  increased by the earned score; verify the challenge leaderboard win count did **not**
  change.

## Out of scope

- Renaming "Friendly" or changing how friendlies are created.
- Any change to money-wager matches.
- Offline / "Airplane Mode".
