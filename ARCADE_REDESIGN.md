# Arcade Redesign — Rolling Bankroll + Earned Power-ups

**Status:** 🔒 Design locked · Phases 1–2 shipped. Living doc — update phase
checkboxes as we ship.

Arcade moves from "per-puzzle reset + banked × multiplier, endless" to a
**rolling-bankroll survival run**: one bankroll that carries over, solving pays
you, and the run ends when you go broke. The whole economy rewards the brand —
**Spend Less. Think More.** Daily and Free Play are barely touched (§5–6).

---

## 1. Core loop (survival)
- Start a run with **$1,500** (tunable). One bankroll, **carries over** between
  puzzles — unspent money is never reset.
- **Solve payout = $500 × streak multiplier**, added to bankroll. Shown up front.
- **Streak multiplier:** +0.25× per clean solve (cap ~×5). A **wrong guess
  resets it to ×1**.
- **Guess pool (carries over):** start a run with **5 guesses** for the whole
  run. A **wrong** guess costs one *and* resets the streak; a **correct** guess
  is free and unlimited. (Per-run, not per-puzzle.)
- **Run ends** when you can't finish a puzzle — **broke AND out of guesses,
  unsolved.** Score = **peak bankroll** reached.

## 2. Money economy — every way to earn
| Source | Detail |
|---|---|
| Carryover | Unspent bankroll rolls over (saving = banking) |
| Solve payout | **$500 × streak multiplier** per solve |
| 💰 Hot Hand | **+$250** per **3 correct letters in a row** (resets on a dud / each puzzle; below the cost of 3 letters so it's a rebate) |
| 💎 Double Payout | power-up that doubles one solve's payout |

## 3. Power-ups — 3 only, earned by special feats (MOST SOLVES EARN NOTHING)
Power-ups are rare rewards for a standout solve — not a per-solve drop. An
ordinary or messy solve earns nothing.

| Power-up | Effect | Earned by — the special move |
|---|---|---|
| ⚡ **Multiplier Boost** | +0.5× streak | **Blind Solve** — won buying **0 letters** (clue + guesses only) |
| 💎 **Double Payout** | next solve pays 2× | **Consonant King** — clean solve buying **only consonants, no vowels** |
| ❤️ **Extra Guess** | +1 to the guess pool (soft-capped) | **Hot Streak** — **3 solves in a row** with no wrong guess |

**Definitions:**
- **Blind** = no letter revealed by paying (no buy, no Reveal). Won on your guesses.
- **Consonant King** = flawless (no dud buys, no wrong guesses) AND bought ≥1
  letter AND zero vowels purchased.
- **Hot Streak** = 3 consecutive solves with no wrong guess (duds OK); a wrong
  guess resets the counter.
- Otherwise → no power-up.

**Cut:** Free Reveal, Vowel Reveal, Discount, Shield, Skip, Insurance, +$250
(now Hot Hand), letters-bought buckets.

## 4. Infrastructure
- **No cron.** Daily + arcade order are deterministic per date, picked lazily on
  first access.
- **Arcade = daily-fresh shared gauntlet:** same order for everyone today, your
  own pace, resets automatically tomorrow.
- **Daily-pool recycle fallback:** when every puzzle has been used as a daily,
  reuse the oldest so the daily never runs dry.

## 5. Daily — barely changed
- **One guess** per daily (down from 3): deduce, narrow with letters, commit
  once. Miss it and you can still win by revealing the rest (lower score).
- Keep the existing **shared Daily Modifier** (one effect for all, rotates by
  date: discount / vowels-half / +$250-start / first-wrong-free). No earning.

## 6. Free Play — no change
Power-up-free; 3 guesses per puzzle; progression is the category badges.

## 7. UI
- **Arcade HUD:** Bankroll (big) · Puzzle N · Streak ×N · "Solve +$X." Hot Hand
  combo flashes when it pops.
- **Power-up tray:** 3 items; armed effects show "ON."
- **Earned line:** on a qualifying solve, "Earned ⚡ Multiplier Boost — Blind
  Solve!" (so players learn the feats).
- **Run-over screen:** peak bankroll + puzzles solved → "New Run."
- **Leaderboard:** rank arcade by **peak bankroll / furthest survived**.

---

## Build phases
- [ ] **Phase 1 — Rolling economy + run-end + guess pool.** Server ✅ (rolling
      bankroll, $500 × streak, run-over on broke, applied). Client ✅ (HUD,
      run-over modal). TODO: carry-over guess pool (start 5) + daily 1-guess.
- [x] **Phase 2 — Earned power-ups + Hot Hand.** ✅ Solve counters (p_buys /
      p_vowels / p_reveals / p_wrong_guess / p_combo per-puzzle, clean_streak
      run-level); the 3 feat-based earns wired in `_arcade_resolve` (Blind→⚡,
      Hot Streak→❤️, Consonant King→💎; most solves earn nothing); Hot Hand
      +$250 per 3 correct letters in `arcade_buy_letter`; `arcade_use_powerup`
      reworked to the 3 effects; tray + `powerups.js` trimmed to 3; "Earned …"
      line in the solve modal.
- [ ] **Phase 3 — UI polish.** HUD payout/streak, Hot Hand flash, run-over
      screen, leaderboard rename to peak/furthest.
- [ ] **Phase 4 — Daily-pool recycle fallback.**

## Tunable values (revisit in playtest)
- Starting bankroll **$1,500** · solve base **$500** · streak step/cap
  **+0.25× / ×5** · Multiplier Boost **+0.5×** · Hot Hand **+$250** · guess pool
  start **5** · Extra Guess **+1** (cap ~8) · daily guesses **1** · free-play **3**
