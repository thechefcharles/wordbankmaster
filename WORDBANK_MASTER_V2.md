# WordBank — Master Design (v2)

> ⚠️ **SUPERSEDED by `WORDBANK_MASTER_V3.md`.** v3 removes loans, the fake play-budget,
> the reveal button, and the guess cap; makes Cash one persistent balance and the objective
> "solve spending the least." Read v3 first. This doc is kept for history.
>
> _(Originally: the authoritative spec, superseding `ECONOMY_V2.md` and `BANK_ECONOMY.md`.)_

---

## 1. Overview & North Star

WordBank is a skill word-puzzle game wrapped in a **real-stakes virtual economy.**
You deduce hidden phrases by buying as few letters as possible; doing it well earns
**Cash**; doing it badly costs you. Your **Net Worth** is the score you brag about.

**Tagline:** *Spend Less. Think More.* (Blitz flips it: *Think Fast.*)

**Legal firewall (non-negotiable, frames everything below):** Cash and Net Worth are
**virtual** — never bought with real money, never cashed out. Real money buys
**cosmetics only**. No pay-to-win. Virtual-currency wagering is legal *only* because the
currency has no real-world value; we keep it that way. (Not legal advice.)

---

## 2. Core Concepts (glossary)

- **Cash** — the single spendable currency. Buys letters, power-ups, cosmetics; wagered
  in Challenges. Floored at $0 (can't go negative).
- **Loan** — debt you take on at any time; accrues interest. Repay anytime.
- **Net Worth** — `Cash − Loans`. The headline metric and main leaderboard. Can be negative.
- **The Climb** — the Cash Game: one shared, fixed-order sequence of puzzles everyone
  advances through, forever forward, at their own pace.
- **Bounty** — the Cash a puzzle pays for solving it (Cash Game). Shown up front.
- **Heat** — a within-session multiplier in the Cash Game that grows on clean solves.
- **Pack** — a set of puzzles in a Challenge (1 = a duel, N = a gauntlet).
- **Play-budget** — fixed fake-money allowance for a Daily puzzle (not your real Cash).

---

## 3. The Economy

- **One currency: Cash.** No hidden second wallet. (The Daily is the one exception — it
  uses a fake **play-budget**, see §5.2.)
- **Net Worth = Cash − Loans.** Cosmetics/assets do **not** count — keeps it ungameable.
- **New players start with $1,000 Cash and $0 loan.** Net Worth $1,000.
- **Cash-on-hand is shown everywhere** next to Net Worth, so a leveraged player (lots of
  Cash, low/negative Net Worth) is visible at a glance.

### Faucets & sinks

| Money **in** (faucets) | Money **out** (sinks) |
|---|---|
| $1,000 sign-up | Letters spent on puzzles you don't solve |
| Daily paycheck (skill-capped, once/day) | **Loan interest** (5%/day) |
| Cash Game bounties (bounded — see below) | Cosmetics |
| Quests (small daily Cash objectives) | Power-ups (Cash Game / Blitz) |
| — | Wager **losses** (player-to-player transfer, net-zero) |

**Why it doesn't inflate:** the Cash Game is **forward-only** — you solve each puzzle
**once**, so total climb income is bounded by the length of the sequence (you can't farm
it). Daily is once/day and skill-capped. The only uncapped flows are sinks (interest,
cosmetics) and zero-sum transfers (wagers). Watch metric: **median Net-Worth growth/week.**

---

## 4. Loans & Interest

- **Borrow anytime**, including **mid-puzzle** (terms shown at the moment — no dark pattern).
- **Interest: 5%/day, simple**, on the outstanding balance (no compounding death-spiral).
  Accrued **lazily** (computed on read/action — no cron).
- **Cap: $10,000** total debt (one running balance you top up).
- **Repay** manually anytime, plus an optional **auto-repay** toggle (skims ~10% of
  Cash-Game winnings).
- **Teeth:** interest dragging your Net Worth down + a visible **"In the Red"** status.
  Core play is never locked — pressure, not a prison.
- **Broke floor:** the **Daily always pays and costs no Cash**, so a broke player can
  always climb back. No hard game-over.
- **Bankruptcy (optional, later):** wipe the debt but reset Cash to $1,000 and Net Worth
  to ~$0, with a permanent mark + cooldown.

---

## 5. Game Modes

*Every mode below answers the same checklist: what it is · how it works · cost/pay ·
scoring · losing · leaving & coming back · power-ups.*

### 5.1 Free Play — the sandbox

- **What:** stakes-free practice with fake money.
- **How:** endless random puzzles; solve, move on, repeat. Unlimited.
- **Cost/pay:** **none** — fake money, **no Cash, no Net Worth, no loans.**
- **Scoring:** none that touches the economy (optional cosmetic "practice best").
- **Losing:** nothing happens — try again.
- **Leaving/returning:** nothing to persist; always fresh.
- **Power-ups:** **earned by feats** (Blind Solve, Vowel-Free, Flawless, Clean Streak) into
  a **Free-Play-only** inventory and spent here. Teaches the tools (and the feats) with
  nothing at stake. New players are **seeded one of each** to experiment. (§6)

### 5.2 Daily — the paycheck

- **What:** one shared puzzle, same for everyone, once per day. The habit + the social score.
- **How:** play it with a fixed **$1,000 play-budget** (fake money, **not** your Cash — so
  Daily has **zero cash downside**). Spend the budget on letters; solve efficiently.
- **Cost/pay:** costs nothing real; **pays Cash** equal to your Daily Score (§11).
- **Scoring:** `leftover budget × efficiency × streak` (the "Spend Less" formula), **floor
  $100** on a solve. This single number is your **Cash paycheck *and* shareable score**
  ("beat my daily"). Once/day + skill-capped ⇒ a dependable, bounded faucet.
- **Losing:** fail to solve → **$0** and your **streak resets**. That's the only "loss."
- **Leaving/returning:** resume the same puzzle the same day; once finished you can't
  replay. Past missed days → the **Make-up calendar** (§10): play them to fill the calendar
  and earn week/month badges (no streak repair, no Cash — badges only).
- **Power-ups:** **none** — kept pure skill.

### 5.3 Cash Game — the Climb (the engine)

- **What:** poker's cash game, as a word puzzle. A **persistent, forward-only climb**
  through **one fixed-order sequence shared by all players.** You play with your **real
  Cash.** No "runs," no restart.
- **How:** you're at a saved **position** in the sequence. Play the puzzle there → **solve
  it to advance one** and earn its bounty. You **can't skip**, so "position" literally means
  "puzzles solved." Two players hit the same puzzle #13 — everyone walks the same road at
  their own pace.
- **Cost/pay (the par/bounty model):** each puzzle shows a **Bounty = 65% of its
  full-reveal cost** (§11). You spend your real Cash on letters; **you keep `Bounty × heat −
  what you spent`.** Solve cheaply → profit; over-buy or brute-force → loss.
- **Heat:** starts ×1.0, **+0.1 per clean solve up to ×2.0**, multiplies the bounty.
  **Resets to ×1.0 if you fail a puzzle, take a loan, or leave the Cash Game** — your hot
  streak *this sitting*. (Position + Cash always persist; only heat is session-local.)
- **Solve attempts:** **3 per puzzle.** A wrong guess burns one + resets heat (no direct
  Cash cost).
- **Losing:** there's no "bust." If you run out of attempts **and** can't afford the cheapest
  unrevealed letter, you're **stuck** on that puzzle — you've eaten your letter-spend (a real
  loss) and you **choose**: keep grinding it, **take a loan** to finish, or leave. Never a
  forced game-over.
- **Leaving/returning:** close the app mid-puzzle → **resume exactly there.** Leave the Cash
  Game → position + Cash saved, heat cleared; next time you continue forward. The only "end"
  is reaching the top of the sequence (we keep extending it).
- **Power-ups:** **bought with Cash**, consumable, usable **mid-puzzle** (§6).
- **Leaderboard:** **Climb** = furthest position reached (progress); Net Worth = how well you
  played it (wealth). Two players at #500 can be +$50k or −$20k.

### 5.4 Challenges — the Challenge Builder (1v1, groups, gauntlets, Blitz)

- **What:** one flexible builder that covers duels, multi-puzzle gauntlets, and group games.
- **How (host configures):**
  - **Opponent:** a person **or** a group (everyone in it is invited).
  - **Categories:** which ones the pack draws from.
  - **Pack size:** 1 (duel) → N (gauntlet).
  - **Mode:** Standard (efficiency-scored) or **Blitz** (one clock for the whole pack).
  - **Stakes:** a Cash **wager** (ante) or **$0 / friendly** (pure bragging).
  - **Payout structure:** **winner-take-all** (default) / **top-3 split** (50/30/20) / **even-on-tie**.
  - **Response window:** host picks **1h · 6h · 24h · 48h · 1 week.**
- **Cost/pay:** wagered → everyone antes into an escrowed **pot**; settle pays per structure.
  Friendly → no Cash, just the result.
- **Scoring:** everyone plays the **same pack, same order** (server-seeded = fair). Score =
  **sum of per-puzzle scores** across the pack (Daily-efficiency for Standard, speed/combo for
  Blitz). Highest total wins.
- **Losing:** lower total → you get nothing (and lose your ante in a wagered game).
- **Leaving/returning:** async — play anytime before the window closes; **no-show forfeits
  the ante** to the pot (wagered) or just counts as "didn't play" (friendly).
- **Fairness (wagered):** **answers/results locked until you've played** (and until the window
  closes) so an early finisher can't coach the group. Friendly games stay loose. (§12)
- **Power-ups:** **none in wagered** challenges (keeps the pot fair); allowed in friendly is a
  later option.
- **Result:** a shareable **ranked results card** (placement, scores, 👑 winner) for the chat.

---

## 6. Power-ups

**Two pools, by stakes:** earned-and-self-contained in **Free Play**; bought-with-real-Cash in
the **Cash Game / Blitz**. Daily and wagered Challenges: none.

### Cash Game tools (bought with Cash, consumable, usable mid-puzzle)
| Power-up | Effect | Price |
|---|---|---|
| **Free Reveal** | Reveal the most useful letter, free | $80 |
| **Half Off** | All letters this puzzle cost 50% less | $120 |
| **Extra Attempt** | +1 solve attempt this puzzle | $120 |
| **Insurance** | Fail this puzzle → refund the Cash spent on its letters | $150 |
| **Heat Shield** | A miss/fail this puzzle won't reset heat | $100 |
| **Double Down** | This puzzle's bounty **+100%** (wasted if you don't solve) | $250 |

### Blitz tools (time)
| Power-up | Effect | Price |
|---|---|---|
| **+15 Seconds** | Add 15s to the clock | $100 |
| **Freeze** | Pause the clock for 5s | $80 |
| **Skip** | Skip this puzzle, keep combo | $120 |
| **Combo Shield** | Next miss won't break combo | $100 |
| **Auto-Vowel** | Reveal all vowels instantly | $90 |

### Free Play — earned by feats (stays in Free Play)
| Feat | Earns |
|---|---|
| Blind Solve (0 letters bought) | Double Down |
| Vowel-Free solve | Half Off |
| Flawless (no wrong letters/guesses) | Free Reveal |
| Clean Streak ×3 | Extra Attempt / Heat Shield |
| Big Combo (Blitz practice) | +15 Seconds / Combo Shield |

**The loop:** discover them free in Free Play → buy them with real Cash to gamble on a hard
Climb puzzle → never in a money match.

---

## 7. Friends & Groups

- **Friends:** add by **@username** (typeahead search; built).
- **Groups:** create a named group, invite by username/link. Persistent crew/league.
- **Group leaderboards = the normal boards filtered to members** (Wealth / Daily / Climb) +
  a **group challenge record.** No new metric — a *scope*. Generalizes the old Friends toggle.
- **Fire a Challenge at a whole group** in one tap (built for the group chat).

---

## 8. Leaderboards

Gutted from ~24 views to **3 boards × a scope toggle.** Rankings only — personal stats live
on the Profile (§9).

- **Boards** (each one metric, no sort menu):
  1. **💰 Wealth** *(default)* — Net Worth. Sub-toggle **This Week** (gained — fair to
     newcomers, default) / **All-Time** (hall of fame).
  2. **📅 Daily** — today's shared-puzzle score.
  3. **⚡ Climb** — furthest Cash Game position reached.
- **Scope:** **Global / [each Group you're in]** (default a Friends/group view).
- Every row: rank · name + title/color flair · the metric · **Cash-on-hand + 🔴 "In the Red".**
- **Default landing:** Wealth · This Week · your group.
- **Contextual daily placement:** after the Daily, show *"You placed #3 today 🥉"* + share —
  most players never open the board.
- **Challenge results** = their own shareable cards, not a persistent board.

---

## 9. Profile & Stats

The home for everything personal (pulled off the leaderboard):
current streak · longest streak · win % · puzzles solved · **Climb position** ·
**challenge W/L record** · badges · equipped cosmetics · Cash / Loan / Net Worth.

---

## 10. Streaks & Badges

- **Daily streak:** consecutive days you **win** the Daily. Multiplies the Daily payout
  (`+0.05/day to ×1.5 at 10 days`). **Breaks only on a *missed* day** — a played-but-lost day
  doesn't break it.
- **Streak freezes:** earn one every 7-day streak (max 3); auto-protects one missed day.
- **Make-up calendar (built):** play a past **missed** day this month to fill the calendar
  and earn **🗓️ Perfect Week / 📅 Perfect Month** — **no streak repair, no Cash** (badges only).
- **Heat** (Cash Game) is a separate, session-local multiplier (§5.3) — not a streak.

**Badges** (existing + v2 additions):
- Existing: 🎯 Flawless · 💎 Gold Bank · 🔥 Week Warrior (7) · 👑 Iron Will (30) ·
  🗓️ Perfect Week · 📅 Perfect Month.
- New: **Climb milestones** (reach #50 / #100 / #500), **Debt-Free** (clear a loan),
  **Hustler** (win 10 challenges), group badges.

---

## 11. Scoring & Formulas (reference)

> Everything calculable in one place. `letter_cost` = the standard table
> (Q $30 … A $130, E $140, etc.). Tunable constants in **bold**.

**Net Worth** = `Cash − Loan`.

**Daily Score** (fake $1,000 play-budget):
```
base   = leftover budget on solve
eff    = 1.00 + 0.25·(no wrong letters) + 0.25·(no vowels)
              + 0.25·(solved first attempt) + 0.15·(no reveals)      → up to ~1.90
streak = 1 + min(streak−1, 10) × 0.05                                 → up to 1.50
DailyScore = max( 100 , round( base × eff × streak ) )                (fail → 0, streak resets)
```
*Knob: scale the budget to phrase length so hard/easy days pay comparably. Optional daily cap.*

**Cash Game** (real Cash):
```
full_cost = Σ letter_cost(c) over DISTINCT letters in the phrase
Bounty    = round_to_$10( 0.65 × full_cost )
net_on_solve = Bounty × heat − (Cash spent on letters this puzzle)
heat = ×1.0, +0.1 per clean solve, cap ×2.0; resets on fail / loan / leaving
attempts = 3 per puzzle
```

**Blitz** (one clock per pack):
```
prize_per_solve = base × combo_mult × speed_bonus
combo_mult : grows per consecutive solve, decays on stall/miss
wrong guess: −time penalty (not an end)
PackScore = Σ prize_per_solve over the pack
```

**Challenge** = `Σ per-puzzle score across the pack` → rank → payout structure
(winner-take-all / top-3 50·30·20 / even-on-tie).

**Loan interest** (daily, lazy): `loan += round(0.05 × loan)` per elapsed day. Cap $10,000.

---

## 12. Anti-cheat & Fairness

Real Cash on a wager creates an incentive to cheat (AI-solve, look up answers, spoiler a
group). Stance:
- **Wagered matches:** answers/results **locked until you've played** + until the window
  closes (kills the spoiler/coach exploit).
- **Anomaly detection** on impossible efficiency/timing flags suspicious wins.
- We accept **AI-solving can't be fully stopped** — which is exactly why prizes are virtual
  Cash/cosmetics (no real cash-out), keeping the incentive low and the legal risk contained.
- **Non-wagered modes (Daily, Climb)** don't need spoiler-locks — like Wordle, a friend
  spoiling you only hurts your own fun.

---

## 13. Monetization & Legal Firewall

- **Real money = cosmetics only** at launch (titles, name colors; later avatars/accessories).
- **Never:** sell Cash/Net Worth, allow cash-out, or let payment improve rank (pay-to-win).
- This firewall is what keeps loans + wagering + real-risk play out of gambling /
  social-casino classification. Review with counsel before any real-money product.

---

## 14. Migration & Current State

- **Bank → Cash** (UI label; the DB column stays `bank`, no risky rename). *Done.*
- **Sign-up $1,000 / $0 loan**; existing players migrated to that baseline. *Done.*
- **Arcade → Cash Game (Climb):** rebuild the per-day press-your-luck run into the persistent
  forward-only climb + par/bounty + heat.
- **Challenges → Challenge Builder** (+ Groups); generalize 1v1 escrow to N players.
- **Power-ups:** retire auto-earn in the real game; earn-in-Free-Play + buy-in-Cash-Game.
- **Leaderboard:** rebuild to the 3-board model; move personal stats to a Profile page.
- **Climb content:** **launch on the existing 720 puzzles in a fixed shuffled order;** extend
  over time.

---

## 15. Open knobs (tune in playtest — not blockers)

- Cash Game **bounty fraction (0.65)**, **solve attempts (3)**, **heat curve (×1→×2 / 10)**.
- Daily **play-budget size**, difficulty scaling, optional daily cap.
- **Interest rate (5%/day)**, debt cap.
- **Power-up prices** & effect magnitudes.
- **Wager tiers** / ante caps; weekly-board reset timing.
- **Blitz** clock length, combo growth/decay, time penalty.
- Ship the bankruptcy option at launch or v2.

---

## 16. Build roadmap

- **Phase 1 — Cash identity & baseline.** Bank→Cash, Net Worth headline, $1,000/$0, migrate
  users. ◑ *(identity + migration done; finish the lexical sweep)*
- **Phase 2 — Loans v2.** Borrow anytime incl. mid-puzzle, interest, repay/auto-repay, cap,
  "In the Red," broke-floor. ☐
- **Phase 3 — Daily revamp.** Play-budget + efficiency Daily Score = paycheck + shareable;
  retire `500×streak`. ☐
- **Phase 4 — Cash Game (Climb).** Persistent forward-only shared sequence; par/bounty + heat;
  3 attempts; get-stuck-not-bust + mid-puzzle loans; Climb board. ☐
- **Phase 5 — Power-ups.** Cash Game tools (bought, mid-puzzle) + shop; Free-Play earned set. ☐
- **Phase 6 — Challenge Builder + Groups.** Configurable packs, wager/friendly, payout
  structures, host response window, spoiler-lock; N-player escrow; Groups + group leaderboards. ☐
- **Phase 7 — Blitz.** Timed variant (pack clock, speed/combo) in Challenges + Free-Play
  practice; time-tool power-ups. ☐
- **Phase 8 — Leaderboards & Profile.** 3-board model × Global/Group; Profile/Stats page;
  contextual daily placement. ☐
- **Phase 9 — Streaks & Badges.** Streak-break rule, freezes, make-up (built); v2 badge set. ☐
- **Phase 10 — Anti-cheat & balance.** Wager spoiler-locks, anomaly flags, full economy
  tuning pass, legal-copy review, optional bankruptcy. ☐
