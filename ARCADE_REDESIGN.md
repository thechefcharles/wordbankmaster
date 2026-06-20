# Arcade Redesign — Rolling Bankroll + Earned Power-ups

**Status:** 🔒 Design locked · build not started. Living doc — update the phase
checkboxes as we ship.

The arcade moves from "per-puzzle reset + banked × multiplier, endless" to a
**rolling-bankroll survival run**. Core idea: one bankroll that carries over;
solving pays you; the run ends when you go broke. The whole economy rewards the
brand — **Spend Less. Think More.**

Daily and Free Play are mostly unaffected (see §5–6).

---

## 1. Core loop (survival)
- Start a run with **$1,500** (tunable). One bankroll, **carries over** between
  puzzles — unspent money is never reset.
- **Solve payout = $500 × streak multiplier**, added to bankroll. Shown up front.
- A **wrong guess** resets the streak multiplier to ×1 **and** costs one of your
  3 guess attempts.
- **Run ends** when you can't finish a puzzle (broke + out of guesses, unsolved).
  Score = **peak bankroll** reached.

## 2. Money economy — every way to earn
| Source | Detail |
|---|---|
| Carryover | Unspent bankroll rolls over (saving = banking) |
| Solve payout | **$500 × streak multiplier** per solve |
| Streak multiplier | +0.25× per clean solve, cap ~×5; **reset to ×1 on a wrong guess** |
| 💰 Hot Hand | **+$250** per **3 correct letters in a row** (resets on a dud / each puzzle; set below the cost of 3 letters so it's a rebate, not free money) |
| 💎 Double Payout | power-up that doubles one solve's payout |

## 3. Power-ups — 5, earned by **letters bought** (exactly one per solve, no overlap)
Single-axis earn = a solve can only land in one bucket → impossible to double-earn.
Accuracy is rewarded separately via the streak multiplier.

| Letters bought | Earn | Effect | Type |
|---|---|---|---|
| **0** (blind solve) | ⚡ Multiplier Boost | +0.5× streak multiplier | instant |
| **1–2** | 💎 Double Payout | 2× this puzzle's payout | armed |
| **3–4** | 🎟️ Free Reveal | reveal the most useful letter, free | instant |
| **5–6** | 🅰️ Vowel Reveal | reveal **all vowels**, free | instant |
| **7+** | 🏷️ Discount | letters −50% this puzzle | armed |

**Cut:** Extra Try, Shield, Skip, Insurance, +$250 (now the Hot Hand mechanic),
Vowel Vision (reworked into Vowel Reveal).

## 4. Infrastructure
- **No cron.** Daily + arcade order are deterministic per date, picked lazily on
  first access (already how it works).
- **Arcade = daily-fresh shared gauntlet (model A):** same puzzle order for
  everyone today, your own pace, resets automatically tomorrow.
- **Daily-pool recycle fallback:** when every puzzle has been used as a daily,
  reuse the oldest so the daily never runs dry.

## 5. Daily — keep the shared modifier, refresh the vocab
- One shared **Daily Modifier**, same for everyone, rotates by date. No earning,
  no inventory (keeps the ranked daily fair).
- Pool refreshed to effects that fit a single puzzle: 🏷️ Discount · 🅰️ Vowel
  Reveal · 🎟️ Free Reveal · 💰 Big Bank (+$250 start). (Drop Double Payout /
  Multiplier Boost — they need the arcade streak.)

## 6. Free Play — no change
Stays power-up-free; its progression is the category badges.

## 7. UI
- **Arcade HUD:** Bankroll · Streak ×N · "Solve for +$500 × N." Hot Hand combo
  flashes when it pops.
- **Power-up tray:** 5 items; armed ones show "ON."
- **Run-over screen:** peak bankroll + puzzles solved → "New Run."
- **Leaderboard:** rank arcade by **peak bankroll / furthest survived** (rename
  from "best banked run").

---

## Build phases
- [ ] **Phase 1 — Rolling economy + run-end.** Server: arcade_runs rolling
      bankroll (carryover, no reset), $500 × streak payout, streak reset on wrong
      guess, run-over on broke. Client: reconcile + result/run-over flow.
- [ ] **Phase 2 — Power-ups + Hot Hand.** Slim to 5; earn by letters-bought
      spectrum; rework effects (Vowel Reveal, Multiplier Boost on streak, Double
      Payout on payout, Discount, Free Reveal); Hot Hand +$250 combo.
- [ ] **Phase 3 — UI.** HUD (bankroll/streak/payout + Hot Hand flash), 5-item
      tray, run-over screen, leaderboard rename to peak bankroll/furthest.
- [ ] **Phase 4 — Daily refresh + recycle.** Daily modifier pool update +
      daily-pool recycle fallback.

## Tunable values (revisit in playtest)
- Starting bankroll: **$1,500**
- Solve payout base: **$500**
- Streak step / cap: **+0.25× / ~×5**
- Multiplier Boost step: **+0.5×**
- Hot Hand: **+$250** per 3-correct-in-a-row
- Discount: **−50%** · letter-count power-up buckets: **0 / 1–2 / 3–4 / 5–6 / 7+**
