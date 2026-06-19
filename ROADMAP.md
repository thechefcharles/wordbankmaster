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

### Shared core
- 📋 **One currency: bankroll.** Remove guess-buying and the "0 guesses + <$150 = instant loss" dead-end.
- 📋 **Wrong guess costs money** (fixed penalty) instead of consuming a separate "guess" currency. You lose only when you can't afford to act.
- 📋 **"Bank Letter" → "Reveal"**: smart (reveals most-useful letter / a vowel), dynamically priced. Specific letters = cheap-but-risky; Reveal = pricey-but-safe.

### 🗓️ Daily — ranked & fair (prestige mode)
- 📋 Same puzzle for everyone, once a day. (already true)
- 📋 **Scored vs par** (golf-style) + **streak multiplier** + **efficiency bonus** — so playing the economy well beats just knowing the answer; a $0 instant-solve can't lap the field.
- 📋 **Gold/Silver/Bronze medal** vs par.
- 📋 **Shareable result card** (spoiler-free), e.g. `WordBank #142 🟩🟩⬛ $740 · 🔥12 · ⭐Gold`. ← top growth lever.
- 📋 **Streak freeze** so one missed day doesn't nuke a long streak.

### 🕹️ Arcade — high-roller mode
- ❓ **Direction TBD:** full **roguelike run** (escalating puzzles, power-up drafting between rounds, run ends on bust, best-run leaderboard) **vs** keep **endless** cumulative bankroll + layer power-ups/better risk. *Decide after Phase 0.*
- 📋 Replace the "free-EV when confident" wager with a real pre-commit risk decision (e.g., double-or-nothing *before* buying letters).

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
| **0 — Economy refactor** | One currency, wrong-guess-costs-money, Reveal rework/retune | Daily RPCs (server) + arcade client | 📋 |
| **1 — Daily scoring + share** | Par/efficiency/streak scoring, medals, **share card** | Server scoring + UI | 📋 |
| **2 — Streaks & badges** | Streak freeze, badge engine, leaderboard flair | Server + UI | 📋 |
| **3 — Power-up system** | Inventory + effects, earned via play/badges (no payments) | Server + UI | 📋 |
| **4 — Roguelike arcade** | Run structure, escalation, power-up drafting, best-run board (pending arcade decision) | Mostly client + leaderboard | 📋 |
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
1. Arcade direction: full roguelike run vs endless + power-ups (decide after Phase 0).
2. Power-up source: earned-only vs earned + free daily pick.
3. Daily scoring formula specifics (par definition, efficiency bonus weight, streak multiplier curve).
4. Wrong-guess penalty amount / does it scale.
5. Player fantasy to optimize for: "shrewd high-roller" vs "fast solver" vs "streak-keeper".

---

_Last updated: 2026-06-19_
