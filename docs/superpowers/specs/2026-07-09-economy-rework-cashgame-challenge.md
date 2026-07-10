# Cash Game + Challenge Economy Rework — Design, Impact Map & Plan

**Status:** BUILDING — decisions locked (§4). **Phase 1 (Challenge server economy) SHIPPED**
2026-07-10 → `supabase-challenge-bounty-economy.sql`, applied to prod, functionally
verified (seed/score/settle/pot/P&L/money-conservation, 1- and 2-puzzle packs),
version-gated on `challenge_matches.econ_v=2` so open matches keep old rules.
Next: Phase 2 (Challenge client HUD/copy).
**Date:** 2026-07-09
**Owner:** Charles

---

## 1. The two changes

**A — Cash Game (climb): kill the mid-puzzle cop-out.**
Today you can Deposit mid-puzzle, so being stuck = a free, penalty-free exit. Fix: you can bank **only between puzzles**. Once a puzzle is active it's **solve or bust** (no mid-puzzle deposit, no soft forfeit). Between puzzles you get a **Bank-or-Push** decision with a **peek** at the next puzzle (its bounty + category), so pushing is an informed gamble.

**B — Challenge (match): spend the bounty, not the ante.**
Today the spend budget = `GREATEST(wager, 500)` — so the wager size distorts the game. Fix: the spend budget comes from the **puzzle's bounty** (standardized, same for everyone, like Cash Game). The **ante becomes a pure stake** → both players ante into a **Pot**, highest **efficiency** (most bounty kept) takes it. Reframe the HUD number to go **up** (a Score), show the **Pot** you're playing for, and warm up the async (target/first-mover framing/reveal). Optionally trim the extras (sabotage/packs) for a clean core duel.

**Design principle:** the two modes share one skill engine (_spend the given bounty efficiently_) but stay structurally different — Cash Game = press-your-luck vs. yourself (decision: _when to bank_); Challenge = press-your-luck vs. a person (decision: _how efficient_). We are **not** turning Challenge into a solo accumulator.

---

## 2. What the code audit found (the good news)

- **Letter-spend is already off-ledger in BOTH modes.** Climb v4 (`supabase-cashgame-v4-accumulator.sql`) draws letters from a per-puzzle `budget = bounty − spent`; match draws from the participant `bankroll` escrow. Neither calls `_bank_credit`. So "spend the given budget, not real cash" is already true at the ledger level. `climb_letter` (real-cash spend) is **legacy/dead**.
- **Challenge already scores "most Cash left wins."** `_match_resolve_and_advance` sets `total_score = bankroll = cash left`; budget = `GREATEST(wager,500)` carried across the pack. So change B is _narrow_: swap the budget **source** (bounty, not wager) and **decouple** the wager into a pure stake — the "spend down, least-spend wins" mechanic already exists.
- **Credit score barely moves.** `_recompute_credit` components: U/R/B are **loan-only** (zero economy touch); Solvency's negative-days term is **inert** (`_bank_credit` floors bank at 0 so `balance_after < 0` never happens); Consistency counts any ledger row as an active day (buy-in/stake rows still count). **The only credit ripple:** bigger full-stake losses + more busts lower `bank`, which can trip Solvency's `bank < loan` net-worth cap (S→0.5) for underwater players — which is the _intended_ underwater penalty, not a bug. **No credit formula change needed.**
- **The Daily "Eff" metric IS the standardized efficiency we want.** `get_daily_board` computes `efficiency = (base_bounty − spent)/base_bounty × 100`, same base for everyone. Reuse this exact formula for Challenge instead of inventing a score. Dormant `get_efficiency_leaderboard` / `get_challenge_leaderboard` RPC wrappers already exist (unwired).
- **Cruft to reconcile:** multiple challenge settle iterations coexist (`winner-take-all` vs `pot-of-spend` vs `efficiency-scoring`); a dead legacy `gameMode:'challenge'` system; dead ledger reasons (`climb_letter`, `climb_bounty`, `challenge_payout`). No standalone economy spec exists — the "spec" lives in SQL headers.

---

## 3. Impact map — everything that must change

### 3.1 Cash Game — server (`supabase-cashgame-v4-accumulator.sql`)

- [ ] Block `cashgame_cashout` while a puzzle is **active**; allow it only at a between-puzzle decision point.
- [ ] Add a "between puzzles / awaiting decision" state after a solve (before the next puzzle is dealt).
- [ ] Expose **next-puzzle preview** in the board/advance RPC: next `bounty` + `category` (and maybe difficulty).
- [ ] Commit rule: an active puzzle can only end in **solve** (bank into Wallet, continue) or **bust** (`_cg_bust`, lose the Wallet). No mid-puzzle exit.

### 3.2 Cash Game — client (`src/routes/+page.svelte`, `ObjectiveCard.svelte`)

- [ ] Remove the anytime Deposit button (`.solve-deposit`, just added in PR #468) — superseded.
- [ ] New **Bank-or-Push** between-puzzle screen: shows banked Wallet, next bounty + category, [Bank it] / [Push →].
- [ ] Repurpose the `showDepositConfirm` modal into that decision screen.
- [ ] Rewrite `ObjectiveCard` `climb` copy ("Deposit anytime to bank it" → "Bank between puzzles; once you start, it's solve or bust").
- [ ] `climbInfo` modals (heat/streak/earn): "Deposit anytime", "Yield climbs with deposit streak" → between-puzzle framing.
- [ ] "Cash Advance depleted / must-guess" HUD: remove the "Deposit your $X now" option.
- [ ] Cash Game tier-select copy: "Invest your Principal, grow it, Deposit — or VOID" → new framing.

### 3.3 Challenge — server (budget/stake/settle)

- [ ] Confirm the **live** settle path in prod (winner-take-all vs pot-of-spend) — introspect first.
- [ ] Seed participant spend budget from **puzzle bounty** (standardized), NOT `GREATEST(wager,500)`.
- [ ] Escrow the **wager as pure stake** into the pot; do not seed the spend budget from it.
- [ ] Winner = **highest efficiency** (most bounty kept). Store `total_score` as bounty-kept (or efficiency %); keep it monotonic-up for HUD.
- [ ] Settle: pot = Σ wagers; winner-take-all / podium unchanged structurally; **no unspent refund** (the bounty was never the player's money); safety refund (no-contest) still refunds **wagers**.
- [ ] `_match_board`: `spent = bounty − bankroll`; expose `pot`; keep `standing` spoiler-safe.

### 3.4 Challenge — client HUD & copy

- [ ] Top bar `👛 Wallet` → **Score** (accumulates up across the pack; = your banked cash-kept).
- [ ] Center hero `👛 Wallet` / "Left to Spend" → **Balance Remaining** (this puzzle's bounty allowance, ticks down). Drop 👛/⏱️.
- [ ] Add a small persistent **"Pot $X"** chip near the mode label / standing strip (the prize, moved off the headline).
- [ ] Show a **"beat $Y"** target once the opponent has played (or "you set the bar" for first mover).
- [ ] `ObjectiveCard` `match` copy: "spend the least / winner takes all" → "solve efficiently — highest score takes the pot; your ante is the stake."
- [ ] Rewrite the ante-info modal (drop "your buy-in is your spend pool / wallet up top is safe").
- [ ] `Tutorial.svelte`: "spend the least to take the pot" → new framing.

### 3.4b Async duel — make it feel alive (the "cold wait" fix)

Today you finish and then wait — maybe hours — with zero feedback. Warm it up:

- [ ] **Second mover sees the target + pot:** "Beat **$850** to win the **$2,000 pot**." ⚠️ conflicts with today's deliberately spoiler-safe `StandingStrip` (directional lead/behind, never the exact number) — see **Decision #8**.
- [ ] **First mover "sets the bar":** frame the first player as _issuing_ a challenge, not waiting — "You banked a Score of **$850** — @friend has to beat it."
- [ ] **Notify on opponent completion:** when your opponent finishes their side, ping the waiting player ("@friend played your challenge — result pending / you're up"). Not just the existing settle notify. Ties into the push-notification launch plan.
- [ ] **Head-to-head reveal on settle:** a real win/loss moment in the result screen — "You kept **$850** · they kept **$700** · you take the **$2,000 pot**." (Today settle only sends a text `_notify`; make the in-app result show the H2H comparison.)

### 3.5 Stats / History / Profile

- [ ] **`game_results` semantics change**: `spent` = letters bought from bounty (not the stake); stake = `wager`; `net` = pot_share − wager. Update `_log_game_result` call in settle.
- [ ] `HistoryList` challenge rows, `MatchDetailModal` "you spent $X / you solved for $X" tieback, H2H `u/[username]` "spent/net", `profile` `get_profile_stats` — verify each reads the new `spent`/`net` correctly.
- [ ] H2H win/loss (rank-based) is unaffected; only the $ display shifts.

### 3.6 Leaderboard — DEFERRED (decision #6)

- Keep the standardized bounty-efficiency _metric_ server-side (reuse the Daily `Eff` formula), but **do not** build a Challenge leaderboard UI now. Revisit post-launch.

### 3.7 Credit score

- [ ] **No formula change.** Watch-item only: underwater players (bank < loan) after full-stake losses/busts get Solvency capped at 0.5 (intended). Re-run `qa-e2e.mjs` credit checks after the change to confirm no surprise swings.

### 3.8 Badges

- [ ] Cash Game badges (`cg_bronze/silver/gold` "Cashed out a X run", `cg_run_5` "5 profitable cash-outs in a row", `cg_multiple_10`, `gold_shark`) still fire (you still cash out a run, just between puzzles) — mostly copy-safe; review wording.
- [ ] Challenge badges (`first_blood`, `gold_duelist` @ wager≥10000, `hustler` @ 10 wins) still fire on rank-1 wins — logic unaffected; confirm `gold_duelist`'s wager-tier threshold still makes sense once wager is a pure stake.
- [ ] **(decision #5) Add `_record_category_solve`** to the climb solve path AND the match solve/advance path so **Cash Game + Challenge solves count toward category badges** (they don't today).

### 3.9 Cleanup & docs

- [ ] **Cut Blitz (decision #4):** remove the dead Blitz paths — solo Blitz menu tile, the challenge-builder Blitz mode toggle, `matchBlitz` HUD + blitz combo/speed scoring, `blitz_buyin`/`blitz_payout`, and the `BLITZ_ENABLED` flag itself. Keep Sabotage + Packs.
- [ ] Reconcile the duplicate challenge settle SQL; document the ONE live path; retire dead SQL/reasons (`climb_letter`, `climb_bounty`, `challenge_payout`).
- [ ] Remove the dead legacy `gameMode:'challenge'` system (`startChallenge`/`enterChallenge`/`isChallenge` + dead result branch).
- [ ] Promote THIS doc to the canonical economy spec; sync the Notion Launch V1 doc.
- [ ] Update `scripts/qa-e2e.mjs` for the new Cash Game bank flow + Challenge HUD.

---

## 4. Decisions — RESOLVED (Charles, 2026-07-09)

1. **Challenge HUD numbers:** ✅ **Top = "Score"** (accumulates up across the pack), **bottom (center hero) = "Balance Remaining"** (this puzzle's bounty allowance, ticks down). Mirrors Cash Game's Potential-Payout/Balance-Remaining layout.
   - Knock-on: the **Pot** (prize) moves off the headline → show it as a small persistent **"Pot $X"** chip near the mode label / standing strip. _(placement pending final ok)_
2. _(folded into #1)_ — top bar is **Score**, not Pot or Available Balance.
3. **Cash Game peek:** ✅ reveal **bounty + category** only (no difficulty/length).
4. **Challenge complexity:** ✅ **KEEP Sabotage + multi-puzzle Packs. CUT Blitz** (it's flag-hidden today via `BLITZ_ENABLED=false`; remove the dead Blitz paths in cleanup — solo Blitz tile, challenge Blitz mode, blitz scoring).
5. **Category badges:** ✅ **Yes — Cash Game AND Challenge solves now count.** Add `_record_category_solve` to the climb solve path and the match solve/advance path.
6. **Challenge efficiency leaderboard:** ✅ **Deferred (my call, Charles concurs).** H2H record + Match Detail already cover competition; a separate board is complexity without clear payoff. Keep the standardized efficiency _metric_ server-side; skip the leaderboard UI. Revisit post-launch.
7. **Settle model:** confirm winner-take-all is the live/intended one — I'll introspect prod (Phase 0).
8. **Spoiler-safe vs. show-the-target (async, §3.4b):** today the `StandingStrip` is intentionally spoiler-safe — directional only (lead/behind), never the exact number to beat. Showing "Beat $850" breaks that on purpose. Options: (a) show the exact target to the **second mover** (they need the number — that's the tension), (b) keep it directional, (c) show exact only in the post-settle reveal. **My rec: (a)** — exact target for the second mover, first mover's number stays hidden from any live spectator, full H2H numbers in the reveal. _(Needs Charles's call.)_

---

## 5. Gaps & edge cases surfaced pre-build (resolve or explicitly punt before Phase 1)

**Migration / rollout — highest risk:**

- **In-flight games at deploy.** Open `challenge_matches` (old budget=wager, carried across pack) and mid-run `climb_state` rows will exist when the new code ships. A match started under old rules but settled under new math = wrong/confusing payout; a mid-puzzle cash-game run suddenly loses its deposit option. **Plan:** before migrating, drain/settle open matches (or version-stamp so only new matches use new logic) and let mid-run cash games finish on old rules. Decide the transition per mode.
- Virtual money is at stake — a bad settle mis-pays real balances. Verify one full settle end-to-end (via `qa-e2e.mjs` + a manual match) before ship; PITR first.

**Challenge mechanic clarity:**

- **Budget now resets PER PUZZLE.** Today it's ONE pool carried across the whole pack. For "Score banks up across the pack," each puzzle must hand a fresh bounty allowance whose leftover banks into Score (exactly like Cash Game). Real change to `_match_resolve_and_advance`, not a relabel — make it explicit.
- **Sabotage + power-up funding.** In the bounty model, what do sabotage/debuffs and power-ups cost? If they draw from your per-puzzle bounty allowance, they trade your Score to hurt an opponent (good tension) — but that must be _designed_, not inherited. Decide: bounty-funded / free / separate currency.
- **Groups (>2 players).** The async target framing ("beat $X") needs an N-player answer (beat the current leader / "2nd of 4"). Podium payout is handled; the live target + reveal for groups is not.

**Cash Game mechanic clarity:**

- **First-puzzle commit = the buy-in.** Starting a run pays Principal → you're committed to puzzle 1; bust = lose Principal. Make explicit in copy.
- **The peek must reserve the REAL next puzzle.** To show next bounty+category, the server must pick the actual next puzzle (respecting the per-user no-repeat pool) _before_ the decision — so the peek isn't a lie.
- **Skip:** if `climb` has a skip action, it must collapse into "forfeit = bust" (no free skip). Confirm/remove in Phase 3.

**Score presentation:**

- **Is "Score" dollars or points?** Bounty-kept is $-denominated but it's a skill score, not cash you own (the Pot is the payout). "Score $850" could read as "money I have." Decide: keep `$` (simplest/consistent) vs. points vs. explicit "efficiency" framing.

**Data hygiene:**

- **Blitz removal must not break history/badges.** Leave already-earned `bz_*` badges and old blitz `game_results` rows intact; just stop awarding/routing new ones. Don't delete historical data.
- **Vocabulary sync:** if we rename ante→stake / Wallet→Score in copy, update `bankReasons.js` labels (`wager_stake`, `wager_win`) so the bank statement matches.

## 5b. Considered & parked: press-your-luck in Challenge

Idea: give Challenge Cash Game's **bank-or-push** — after each pack puzzle, bank your Score or risk it (bust = lose it), highest banked Score wins.

**Why it's parked (not chosen):** it collides with the "show the target" async-warming (§3.4b). Under bank-or-push in an _async_ duel, the **second mover exploits a shown target** — they push just past it and bank, while the first mover guesses when to stop. So press-your-luck forces either (a) hide the target (kills the "Beat $850" tension we want) or (b) show it and be unfair on a wager.

The **efficiency-duel we specced avoids this**: everyone plays the whole pack, so a shown target _can't_ be gamed by stopping early → we keep the tension fairly. Conclusion: **Cash Game owns press-your-luck (no opponent → no asymmetry); Challenge stays the efficiency-duel with a live target.**

If we ever want the flavor in Challenge: do a **blind** head-to-head press-your-luck as a _separate mode_, or reuse the existing **Double-or-Nothing** lever for one contained beat. Not in scope for this rework.

## 6. Phased execution (each phase: PITR → migrate via MCP → gates → `qa-e2e.mjs` → ship)

- **Phase 0 — Lock it down.** Confirm live prod RPCs (settle model, is `climb_letter` live), resolve Open Decisions (§4) + gaps (§5 — esp. the **in-flight migration/transition plan**, per-puzzle budget reset, sabotage funding), finalize this spec, sync Notion.
- **Phase 1 — Challenge server economy.** Budget = bounty, ante = pure pot, efficiency scoring, settle, `game_results` semantics, `_record_category_solve` on solve, **opponent-completion notification**. Verify credit unaffected + QA.
- **Phase 2 — Challenge client.** HUD (Score + Balance Remaining + Pot chip), **async: target-to-beat / first-mover "set the bar" / H2H settle reveal (§3.4b)**, ObjectiveCard/ante-modal/MatchDetail/Tutorial copy, de-emoji.
- **Phase 3 — Cash Game server.** Block mid-puzzle cashout, between-puzzle decision state, next-puzzle preview data.
- **Phase 4 — Cash Game client.** Bank-or-Push screen + peek, remove anytime Deposit, rewrite copy.
- **Phase 5 — Stats/leaderboard + badges.** game_results display fixes, optional efficiency board, badge copy review.
- **Phase 6 — Cleanup + docs.** Kill dead challenge SQL + legacy gameMode, prune dead reasons, QA harness, Notion.

**Sequencing note:** Challenge first (Phases 1–2) — it's the bigger conceptual change and it validates the shared bounty-efficiency engine that Cash Game already uses. Cash Game (3–4) is then a smaller, self-contained flow change.
