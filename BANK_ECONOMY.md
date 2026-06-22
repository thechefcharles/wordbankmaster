> **SUPERSEDED by `WORDBANK_MASTER_V2.md`** — kept for history only.

# WordBank — Bank Economy & Challenges

**Status:** 🟢 New core direction. **Supersedes the sweepstakes idea (dropped).**
Living design doc — we'll tune the Open Decisions together as we build.

> ⚠️ Not legal advice — but the legal guardrails below are load-bearing. Keep them.

## North star
WordBank is a **skill word-game with a persistent Bank you build by playing**, and
**head-to-head wagers against friends.** Grind the modes to grow your Bank, then
stake it in challenges. Pure skill + a virtual economy — **no real-money prizes,
no gambling.**

## What changed (and why it's better)
- **Dropped:** the monthly sweepstakes / cash prize. A raffle is a weak one-shot
  hook and dragged in heavy baggage (official rules, state registration, 18+ gate,
  "no purchase may improve odds").
- **Replaced with:** a self-sustaining **PvP economy**. Wagering your *earned* Bank
  against friends is a stronger, repeatable, social loop — and it's legally clean
  because the Bank is **virtual, earned-only, and never cashable.**
- Net effect: simpler legally, and a much better core loop.

## Two kinds of money (don't confuse them)
- **Bank** (persistent) — your wallet. The big number you grow over time and wager.
- **Bankroll** (per round) — the existing in-game money you spend buying letters in
  a single Daily/Arcade/challenge puzzle. Resets every game.
- **"Bank it" / cash-out** = move a finished round's winnings *into* your Bank.
  (In-game only — NOT a real-money withdrawal.)

## The Bank
- A **persistent balance** on your profile: "Your Bank: $X".
- **Earned-only. Virtual. Never cashable to real money. Never purchasable.**
- New players start with a **seed Bank** (e.g. $5,000) so they can wager day one.

## Building your Bank (the faucet)
- **Arcade = the engine** (redesign below): build a round bankroll, then **Bank it**.
- **Daily win bonus** — winning the Daily drops a little into your Bank (streak-scaled).
- **Quests** — quest rewards can pay Bank.
- **Challenge winnings** — winning a wager adds the pot.
- **Safety net** — Arcade always gives house money to rebuild, plus maybe a small
  daily stipend, so a broke player is never locked out of wagering.

## Arcade redesign: cash-out / press-your-luck
- Each run still starts with **house money** ($1,500) — *not* staked from your Bank.
  So **Arcade can only ADD to your Bank, never drain it.**
- Solve to grow the round bankroll (today's rules: +$500 × streak, Hot Hand, etc.).
- **"Bank it"** at any time → cash the current round bankroll into your Bank, end the run.
- **Bust** before banking → lose the round bankroll, Bank unchanged (house-money risk only).
- The new tension: *"I'm holding $4,200 — bank it, or risk one more puzzle?"*
  That keep-or-bank decision is what makes Arcade addictive and ties it to the meta.

## Challenges (the headline)
**Async, friend-vs-friend, same puzzles, winner takes the pot.**
1. **Create:** pick a friend **by username** (typeahead search), a **category**, a
   **mode** (Score / Pressure), a **wager**.
2. Both stakes are **escrowed** up front (can't bet money you don't have).
3. Both get the **exact same puzzle set** (deterministic seed from the match id —
   same category, puzzles, order).
4. Each plays **whenever** (async).
5. **Higher score wins the pot (2× stake).** Tie → refund.
6. **Expiry** (~48h): a no-show voids/refunds (or forfeits — Open Decision).

### Modes
- **Score mode** (untimed, "chill"): score = total **banked** across the set. Best total wins.
- **Pressure mode** (timed, "twitch"): a clock — solve fast; score blends speed + bankroll.

## Legal guardrails (still matter without the sweepstakes)
Wagering virtual currency is fine **only if the currency has no real-money value**:
- ❌ **Never sell the Bank** for real money — selling a wagerable currency can trigger
  "social casino" gambling scrutiny (cf. WA *Big Fish* ruling) even with no prize.
- ❌ **Never let the Bank cash out** to real money / gift cards.
- ✅ **Monetize with cosmetics only** (themes, tile skins, avatars), bought with real
  money — never the Bank, never pay-to-win.
- Keep UI language game-y ("your Bank") — no "deposit/withdraw cash."

## Leaderboards now
- **Daily** stays the pure **skill** board (score = round bankroll × streak; no Bank).
- **Arcade** board can rank by **biggest single cash-out** and/or **total Bank** (wealth flex).
- **Friends** board (shipped) = today's Daily head-to-head; add a "richest" view later.

## Monetization (future, optional)
- **Cosmetics** for real money (skins/themes/avatars) — pure cosmetic.
- Maybe a **premium tier** (stats, cosmetics) — never a competitive edge, never Bank.
- The Bank itself stays **100% earned**, forever.

## Locked decisions (2026-06)
- ✅ **Loan + Net Worth confirmed.** Start with a **$5,000 loan**; **Net Worth = Bank − loan**
  is the headline number and the front-page leaderboard.
- ✅ One account / one Bank. Daily stays free/fair/clean. Two-currency firewall
  (Bank earned-only/virtual; real money = cosmetics only). Wagered challenges = clean.
- Defaults (tune in playtest): starting loan **$5,000**, min wager **$100**, daily-win
  bonus **$500 × streak**, quest reward **$1,000**, Arcade cash-out = **full round bankroll**.

## Build roadmap
### Phase A — Persistent Bank + loan + Net Worth  ✅ (PR #124)
- [x] `profiles.bank` + `profiles.loan`; lazy-seed new/existing users (bank 5000, loan 5000 → Net Worth 0).
- [x] `bank_ledger` table (auditable history) + `_bank_credit(uid, delta, reason)` helper.
- [x] `get_bank()` (balance + loan + net worth + recent ledger) and `repay_loan(amount)`.
- [x] First earn source: **quest reward pays Bank** (+$1,000) instead of a freeze.
- [x] Menu **Net Worth chip** → **/bank** screen: Bank, Loan, Net Worth, "pay back loan", history.
      (`supabase-bank.sql`.)
### Phase B — Earn faucets + Arcade cash-out  ✅ (PR #125)
- [x] **Daily-win bonus → Bank** ($500 × streak), in `_finalize_daily`.
- [x] **Arcade "Bank it"** (press-your-luck): banks your **winnings = bankroll − $1,500 house
      stake** into your Bank and ends the run; **bust before banking = $0**. `arcade_cashout()` +
      a "Bank $X" button on the arcade HUD + a "Cashed Out!" result modal (vs "Run Over").
- [ ] (later) Achievements/milestone payouts · optional daily "interest"/stipend.
      NOTE: cash-out banks *winnings above the house stake*, not the full bankroll
      (prevents free-money from instant cashouts; supersedes the earlier default).
### Phase C — Challenges (Score mode + wager)  ✅ (PR #126)
- [x] `challenges` + `challenge_plays`; **create** (escrow + you play) / **accept**
      (escrow + play); both play the **same puzzle**; **score = bankroll left on
      solve** (0 if unsolved); higher score **wins the pot**, tie refunds; 48h
      **expiry** auto-voids+refunds. Play mirrors the daily engine. Menu
      **Challenges** modal (new challenge + inbox). (`supabase-challenges.sql`.)
      Verified: create+escrow, drop-into-play, full play→settle→payout (zero-sum).
### Phase D — Pressure mode  ✅ (PR #127)
- [x] Timed challenge variant. `mode='pressure'`: a **60s per-player, server-authoritative
      clock** (`challenge_plays.started_at`). Solve in time → **score = bankroll +
      floor(60 − elapsed)×10** (blends speed + thrift); run out → **lost, score 0**.
      Create form has a **Score / Pressure** toggle; play screen shows a live countdown
      HUD (red-pulse under 10s) that calls `challenge_check` on expiry to settle.
      Settles vs Score plays exactly the same (higher score wins the pot).
      Verified by SQL sim: fast-solve 1350, timeout lost/0, settle creator-wins.
### Phase E — Spending + leaderboards + polish  ◑ (PR #128)
- [x] **Usernames replace friend codes:** claimable `@username` (set in Friends tab
      + My Account), add friends by **username typeahead search**, challenge by
      username. `_display_name()` (username → full_name → email) used everywhere.
      (`supabase-social.sql`.)
- [x] **Cosmetics shop** (`/shop`) — the Bank's first spend sink. Titles + name
      colors, **earned-Bank-only** (firewall) & **no pay-to-win**; auto-equip on
      buy, equip/unequip; they flex on the boards. (`supabase-shop.sql`.)
- [x] **Net Worth leaderboard** (Bank − Loan), Friends + Global scopes, with
      equipped title/color flair. New tab on the Leaderboard page.
- [ ] Deferred: avatars/accessories, high-stakes rooms, power-up shop (Arcade),
      challenge history/notifications, real-money cosmetics, Net-Worth medals.

## Open decisions 🔒 (let's settle these as we build)
1. **Naming:** persistent = "Bank", per-round = "bankroll"? Or rename one (e.g. "Vault")
   to avoid confusion?
2. **Arcade cash-out amount:** full round bankroll, or profit only (above the $1,500 seed)?
3. **Starting Bank** for new players (e.g. $5,000) + **min/max wager** limits.
4. **Challenge no-show:** void+refund vs forfeit to whoever finished.
5. **Daily / quest Bank bonus** sizes.
6. ~~**Pressure mode** specifics~~ ✅ settled: single-puzzle 60s clock; score = bankroll + (60−elapsed)×10.
7. **Bankruptcy floor / stipend** so broke players can re-enter.
8. ~~**Friend identity**~~ ✅ settled: claimable **@username** + typeahead search (codes retired).

---

# Expanded economy — loan, faucets/sinks, accounts, leaderboards (2026-06)

### One account, one Bank
**ONE account per player, ONE persistent Bank, used across every mode.** No
per-mode wallets, no alt accounts. Your identity + Bank are the spine of the game.

### Daily stays clean (the skill anchor) — answers "same experience for everyone?"
Split the modes instead of compromising the Daily:
- **Daily = free, identical for all, no pay-to-win, pure skill.** Small Bank reward
  for winning. This is the fair competitive anchor — *protect it.*
- **Arcade / Free Play / Challenges = the economy sandbox** — personalized puzzles,
  buy power-ups, spend money. (A *challenge* still uses the same puzzles for its two
  opponents; different pairs get different sets — that's fine.)

### Starting capital: the loan (keep it friendly)
- New players take a **$5,000 loan from "The House"** — flavor for starting capital +
  an early goal.
- **No spiraling interest, no lockout** — you can always earn for free (Daily/Arcade);
  pay it back whenever. Paying it off is a satisfying milestone.
- **Net Worth = Bank − outstanding loan** → the headline wealth number.

### Two-currency firewall (the legal + fairness backbone)
- **Bank ($)** — earned-only, virtual. Runs the whole in-game economy (wagers,
  power-ups, cosmetics, entry). **Never purchasable with real money. Never cashable.**
- **Real money** — buys **cosmetics only** (skins / avatars / accessories) and maybe a
  premium tier. **Never buys Bank, never an edge.**
- This firewall is what keeps it both **non-gambling** and **non-pay-to-win.**

### Full economy map
**Faucets (earn Bank)**
| Source | Notes |
|---|---|
| Starting loan | one-time $5,000 (owed back) |
| Arcade cash-out | the main grind (press-your-luck) |
| Daily win bonus | small, streak-scaled |
| Quest rewards | daily quests pay Bank |
| Achievements | one-time milestone payouts |
| Daily interest / stipend | small daily "your Bank earns interest" — also the broke-player safety net |
| Challenge winnings | **redistributes** between players, not new money |

**Sinks (spend Bank)**
| Sink | Notes |
|---|---|
| Wagers | stake in challenges (can lose) — redistributes |
| Power-ups | buy/pre-stock for **Arcade** (NOT Daily, NOT wagered challenges) |
| Cosmetics | avatars, accessories, themes, tile skins, win animations — the big sink |
| High-stakes entry | optional premium rooms with a buy-in |
| Loan payback | clears your debt |
| Streak freeze | buy protection (currently earned) |

⚠️ **Economy health:** wagers *redistribute* money but don't destroy it, so the true
sinks are **cosmetics + power-up consumption + entry fees + loan payback.** Those have
to keep pace with the faucets (arcade/interest) or balances inflate to meaninglessness.

### Power-ups & fairness in wagers
- **Wagered challenges = CLEAN** (no bought power-ups) → the bet is pure skill on the
  same puzzles. Otherwise the richer player just buys the win (snowball).
- **Arcade = power-ups allowed** (your solo grind).
- (Optional later: a separate "powered" challenge type both players opt into.)

### Entry fees (answers "pay to enter each mode?")
- **Daily = free** (the fair anchor — never paywalled).
- **Arcade = free** (it's the faucet; it *gives* house money).
- **Challenges:** the **wager IS the entry fee** (the natural sink).
- **High-stakes rooms:** optional premium variants with a buy-in (extra sink for the skilled).

### Leaderboards, restructured (expect big changes — that's fine)
- **Daily** — pure skill (today's daily score). Unchanged anchor.
- **Net Worth** — total Bank − loan. The new headline "richest" board.
- **Challenge record** — wins / total winnings (PvP).
- **Arcade** — biggest single cash-out / longest run.
- Friends versions of each.

### Don't-overwhelm rollout
Layer it in: **Bank + arcade cash-out + clean wager** first; then loan framing,
power-up shop, cosmetics/avatars, interest, and the new leaderboards over time.

### Open decisions (expanded)
- Loan: interest-free? amount? required or optional?
- Daily interest: flat stipend vs % of balance (% makes the rich richer — careful)?
- Power-ups in challenges at all, or strictly Arcade?
- Cosmetics: buyable with Bank, real money, or both?
- Headline leaderboard: **Net Worth** vs raw Bank?
- Does the loan/debt framing feel fun or stressful for a word game? (gut-check with testers)

## Notes / decisions log
- 2026-06: pivoted from sweepstakes → bank economy + friend wagering. Async-first
  challenges. Bank = earned-only virtual, never sold/cashed. Friends (codes +
  daily head-to-head) already shipped as the social base.
- 2026-06: leaned harder into banking theme — one account/one Bank; $5,000 starting
  **loan** (Net Worth = Bank − loan); two-currency firewall (Bank earned-only vs real
  money = cosmetics only); Daily kept free/fair/clean while Arcade/Free Play/Challenges
  are the economy sandbox; full faucet/sink map; wagered challenges stay clean (no
  power-ups). Leaderboards add a Net Worth board.