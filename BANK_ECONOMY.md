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
1. **Create:** pick a friend, a **category**, a **mode** (Score / Pressure), a **wager**.
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

## Build phases
- [ ] **A — Persistent Bank:** `profiles.bank`, seed new users, show on menu/profile,
      earn from Daily win + quest bonus.
- [ ] **B — Arcade cash-out:** "Bank it" + press-your-luck; route winnings to the Bank.
- [ ] **C — Challenges (Score mode + wager):** matches table, seeded puzzle sets,
      escrow, accept/play/settle, surface pending challenges.
- [ ] **D — Pressure mode** variant.
- [ ] **E — Polish:** challenge history, notifications, friends "richest" flex,
      username search (the friend *code* already covers adding people).

## Open decisions 🔒 (let's settle these as we build)
1. **Naming:** persistent = "Bank", per-round = "bankroll"? Or rename one (e.g. "Vault")
   to avoid confusion?
2. **Arcade cash-out amount:** full round bankroll, or profit only (above the $1,500 seed)?
3. **Starting Bank** for new players (e.g. $5,000) + **min/max wager** limits.
4. **Challenge no-show:** void+refund vs forfeit to whoever finished.
5. **Daily / quest Bank bonus** sizes.
6. **Pressure mode** specifics: clock per puzzle vs whole set; speed×bankroll scoring.
7. **Bankruptcy floor / stipend** so broke players can re-enter.

## Notes / decisions log
- 2026-06: pivoted from sweepstakes → bank economy + friend wagering. Async-first
  challenges. Bank = earned-only virtual, never sold/cashed. Friends (codes +
  daily head-to-head) already shipped as the social base.
