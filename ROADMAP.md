# WordBank — Product Roadmap

Living plan for the game's evolution. **Update the Status column as we go.**

**Status legend:** ✅ Done · 🚧 In progress · 📋 Planned · 💡 Idea/backlog · ❓ Needs decision

---

## Vision

> **Daily** is the fair, ranked brain-teaser you keep a streak on and *share*.
> **Arcade** is the addictive high-roller *run* you grind for power-ups and bragging rights.
> Both share one clean economy.

---

## Already shipped (foundation)

| Item | Status |
|---|---|
| Server-authoritative **daily** (answer never leaves server; trustless leaderboard) | ✅ |
| Economy/leaderboard **security hardening** (auth.uid, clamps, RLS revokes) | ✅ |
| First-win **streak bug** fix + leaderboard **timezone** fix | ✅ |
| Lightweight **anomaly detection** (admin-only) | ✅ |
| Reproducible DB schema in version control | ✅ |
| **Design overhaul** — dark neon-arcade system across all screens | ✅ |
| **Motion polish** — flip-reveal tiles, reactive bankroll, confetti, aurora, stagger | ✅ |

---

## V2 design decisions (agreed)

### Shared core (Phase 0 — LOCKED)
- **Bankroll is only for information.** No more buying guesses; no "<$150" dead-end.
- **Guessing is free but limited to 3 attempts** (not purchasable). A wrong guess burns an attempt — **no money lost** (avoids the harsh cliff where a wrong guess at $70 zeroes you out).
- **Out of attempts ≠ stuck:** you can still win by buying letters until the phrase is fully revealed (expensive → low score). The economy still matters without an instant-loss gotcha.
- **"Bank Letter" → "Reveal":** reveals **all instances of the most-frequent unrevealed letter** (guaranteed useful, not random), flat **$150** (tunable). Strictly better than the old random single-tile hint.
- **Lose only when broke + unsolved** (bankroll < $30, the cheapest letter). One clean failure state.
- **Attempts start at 3.** Daily has no wager; arcade keeps its wager for now (revisit Phase 4).

### 🗓️ Daily — ranked & fair (prestige mode)
- 📋 Same puzzle for everyone, once a day. (already true)
- 📋 **Scored vs par** (golf-style) + **streak multiplier** + **efficiency bonus** — so playing the economy well beats just knowing the answer; a $0 instant-solve can't lap the field.
- 📋 **Gold/Silver/Bronze medal** vs par.
- 📋 **Shareable result card** (spoiler-free), e.g. `WordBank #142 🟩🟩⬛ $740 · 🔥12 · ⭐Gold`. ← top growth lever.
- 📋 **Streak freeze** so one missed day doesn't nuke a long streak.

### 🕹️ Arcade — daily Press-Your-Luck gauntlet (LOCKED)
- **One shared daily sequence** of puzzles (same order for everyone) → the leaderboard is a real, fair skill comparison. **No difficulty escalation.**
- **Climb the ladder.** Each puzzle = fresh $1,000 working bank, same core play (buy letters / Reveal / Solve).
- **Auto-bank:** every solve banks `leftover bankroll × multiplier`. The **multiplier rises with each clean consecutive solve** (×1 → ×1.25 → ×1.5 → ×2 …, capped).
- **Bust = setback, not game over.** Run out of money on a puzzle → **multiplier resets to ×1**, but you keep your banked total and your place; you retry that puzzle (fresh $1,000) and keep climbing.
- So a flawless 1→N run banks far more than a stop-start one over the *same* puzzles — pure execution skill.
- **Server-authoritative** (answers off the client) so the fair board is trustworthy — reuses the Daily engine. **Leaderboard = total banked today** (+ furthest reached).
- Auto-bank chosen over cash-out: in a skill puzzle you control bust risk, so a "bank or risk" gamble is a fake decision; the multiplier (skill) is the real tension. Cash-out can bolt on later if we want a casino feel.

---

## Power-ups
Earned (not paid — for now): from streaks, badges, leaderboard placement, arcade drafts. ❓ Possibly a free daily pick to drive return visits.

| Power-up | Effect |
|---|---|
| Free Reveal | One free smart reveal |
| +$250 Start | Begin a puzzle with extra bank |
| Insurance | One wrong guess is free |
| Vowel Vision | All vowels cheap this puzzle |
| 50/50 | Eliminate some impossible letters |
| Discount | Letters −25% this puzzle |
| Streak Shield | Protect daily streak (freeze) |
| Double Payout | Double a puzzle's winnings |

Status: 📋 Planned (Phase 3)

---

## Streaks & badges
- 📋 Daily streak (with **freeze**); arcade best-run streak.
- 📋 **Badges/achievements**: *Flawless* (0 wrong letters), *Under Par*, *Comeback* (won from <$100), *Category Master*, *Iron Streak* (30/100 days).
- 📋 Badges show as **flair on the leaderboard** (cheap status, strong motivation).

---

## Build plan (phases — each ships independently)

| Phase | Scope | Touches | Status |
|---|---|---|---|
| **0 — Economy refactor** | 3 free attempts, free guessing, win-by-reveal, Reveal rework, broke-only loss | Daily RPCs (server) + arcade client | ✅ |
| **1 — Daily scoring + share** | Share card ✅ + medals ✅. Daily **score = bankroll × streak multiplier** (server), leaderboard ranks by score ✅ | Server scoring + UI | ✅ |
| **2 — Streaks & badges** | Badges ✅ (4 daily, My Account, 🔥 flair). Streak **freeze** ✅ (auto-bridge a missed day, earn 1 per 7-day milestone, cap 3; shown in My Account). | Server + UI | ✅ |
| **3 — Power-up system** | Inventory, earning (random on win), display ✅; Free Reveal (in-game) ✅; pre-game picker ✅; effects: +$250 Start, Discount, Insurance, Vowel Vision ✅. (Double Payout = arcade, Phase 4.) | Server + UI | ✅ |
| **4 — Arcade gauntlet** | Server engine ✅ (4a); client ✅ (4b: arcade=gauntlet, HUD banked/multiplier/position, solve→Continue / bust→Try Again); leaderboard ✅ (4c: best banked run + furthest reached, day/week/month/all). | Server + client | ✅ |
| **5 — Polish** | Guided tutorial, sound + haptics, "ghost of yesterday" compare | Client | 📋 |

Recommended order de-risks: economy first → cheap-high-impact share → retention (streaks/badges) → big arcade swing.

---

## Idea backlog (💡)
- 💡 Guided first-game **tutorial** (rules are non-trivial).
- 💡 **Sound + haptics** to match the new motion.
- 💡 **"Ghost of yesterday's you"** spoiler-free comparison.
- 💡 Weekly **themed events** / category mastery progression / unlockable categories.
- 💡 **Seasons** with seasonal leaderboards + rewards.
- 💡 **Friends / head-to-head** daily; friends leaderboard.
- 💡 **Profile progression** — XP, levels, cosmetics (tile skins, themes, victory effects), title flair.
- 💡 Tiered hints (category clue → reveal vowel → reveal letter).
- 💡 Real-money/crypto prizes only via **draw-among-qualifiers + KYC** (see security notes); foreknowledge/AI-solving can't be fully prevented.

---

## Open decisions (❓)
1. ✅ Arcade direction: daily Press-Your-Luck gauntlet (shared sequence, auto-bank, server-authoritative). LOCKED.
2. Power-up source: earned-only vs earned + free daily pick.
3. Daily scoring formula specifics (par definition, efficiency bonus weight, streak multiplier curve).
4. Wrong-guess penalty amount / does it scale.
5. Player fantasy to optimize for: "shrewd high-roller" vs "fast solver" vs "streak-keeper".

---

_Last updated: 2026-06-19_
