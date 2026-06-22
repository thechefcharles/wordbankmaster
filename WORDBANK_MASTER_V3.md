# WordBank — Master Design (v3)

> **The authoritative spec.** Supersedes `WORDBANK_MASTER_V2.md` (kept for history).
> Anything that contradicts this doc is out of date.
>
> **What changed from v2 → v3 (the big teardown):**
> - **Loans removed entirely.** No debt, interest, auto-repay, bankruptcy, In-the-Red.
> - **No more fake play-budget.** Every mode spends your *one persistent Cash balance* —
>   the arbitrary "$1,000 per game" reset is gone.
> - **No reveal button.** Revealing a letter is now a *power-up* (Free Reveal).
> - **Guesses are free and unlimited.** The 3-guess cap is gone.
> - **One objective everywhere: solve spending the least Cash.** Efficiency is the game.
> - **Net Worth = Cash** (no loan subtraction).
> - **Power-ups reworked:** one-of-each, pre-committed *before* the puzzle, and their
>   cost counts toward your spend.

---

## 1. Overview & North Star

WordBank is a skill word-puzzle game wrapped in a **real-stakes virtual economy.**
You deduce hidden phrases by buying as few letters as possible. **Doing it cheaply is the
entire game** — solo it grows your Cash, head-to-head it beats your opponent. Your
**Cash balance is your Net Worth**, and that's the number you brag about.

**Tagline:** *Spend Less. Think More.*

**Legal firewall (non-negotiable, frames everything below):** Cash and Net Worth are
**virtual** — never bought with real money, never cashed out. Real money buys
**cosmetics only**. No pay-to-win. Virtual-currency wagering is legal *only* because the
currency has no real-world value; we keep it that way. (Not legal advice.)

---

## 2. Core Concepts (glossary)

- **Cash** — the single, persistent, spendable currency. Buys letters, power-ups,
  cosmetics; staked in Challenges. Floored at $0 (can't go negative — there are no loans).
- **Net Worth** — simply your **Cash**. The headline metric and main leaderboard.
- **Spend** — total Cash you commit to a puzzle: letters bought **+ power-up costs**.
  Lowest spend to solve = best. *This is the score.*
- **The Climb** — the Cash Game: one shared, fixed-order sequence of puzzles everyone
  advances through, forever forward, at their own pace, spending their real Cash.
- **Bounty** — the Cash a Climb puzzle pays for solving it. Shown up front.
- **Stake** — in a Challenge, the wager you ante. It doubles as your **spending cap** for
  that match (you can't spend more than you bet).
- **Pack** — a set of puzzles in a Challenge (1 = a duel, N = a gauntlet).
- **Loadout** — the power-ups you own (max one of each), pre-committed before a puzzle.

---

## 3. The Economy

- **One currency: Cash. One balance. Always your real balance — no resets, no fake
  budgets, no second wallet.**
- **Net Worth = Cash.** Cosmetics/assets do **not** count — keeps it ungameable.
- **New players start with $2,000 Cash.** (Runway to learn without instantly busting.)
- **Cash can't go negative.** No loans. If you're broke, you fall back to the safe floors
  (below) and earn your way back up.

### The two-layer money model

**Safe floors — you can never get stuck at zero:**
| Floor | How it pays | Guardrail |
|---|---|---|
| **Daily** | Guaranteed payout for finishing + **attendance rewards** for showing up | Once/day, capped |
| **Free Play** | Small Cash trickle per solve | **Intentionally low & capped** (~$25–50/solve, ~$300/day) |

**Risk engines — where wealth is actually built (need Cash, bigger swings):**
| Engine | Spend model |
|---|---|
| **Cash Game (the Climb)** | Open spend from your full balance; solve for bounties |
| **Challenges / Groups** | Spend capped at your wager; most stake left wins the pot |

So **"broke" is a demotion, not a death** — you drop to the floors, grind back, and step
back up to the risk engines. That demotion *is* the pressure to keep Cash. Cash is your
reach and your safety; running low throttles you.

### Faucets & sinks

| Money **in** (faucets) | Money **out** (sinks) |
|---|---|
| $2,000 sign-up | Letters spent on puzzles you don't solve efficiently |
| Daily paycheck + attendance milestones (capped) | Power-ups (cost counts as spend) |
| Free Play trickle (capped, low) | Cosmetics |
| Cash Game bounties (bounded — forward-only) | — |
| Challenge winnings (zero-sum transfer between players) | — |

**Why it doesn't inflate:** the Climb is **forward-only** (each puzzle solved once → income
bounded by sequence length, can't be farmed). Daily and Free Play are capped. Challenges
are zero-sum transfers. Sinks (letters, power-ups, cosmetics) are uncapped.
Watch metric: **median Cash growth/week.**

---

## 4. The Objective (the heart of v3)

**Across every mode, the goal is the same: solve the phrase having spent the least Cash.**

- **Solo (Climb, Daily):** your take = `Bounty − Spend`. Spend less → keep more.
- **Competitive (Challenges, Groups):** lowest spend to solve **wins the pot.**
  Ties broken by time.

Why this is the right objective: it makes **wealth irrelevant.** A broke player who cracks
a phrase spending $40 beats a whale who spent $300. The skill is *deducing from as little
information as possible* — identical solo and head-to-head. One skill, every mode, no
pay-to-win.

### Guessing is free and unlimited — and the rules that keep that honest

You may submit as many full-phrase guesses as you want, for free, forever. Because "free
guesses + spend-the-least" could otherwise be gamed by *buy-nothing-and-spam*, three rules
hold:

1. **Min-length phrases in competitive packs.** Challenge/Group puzzles are long enough
   that you cannot blind-guess them. (Short phrases live in casual Free Play.)
2. **A guess is all-or-nothing — no positional feedback.** Submit the whole phrase; wrong
   just means wrong. No per-letter "these are right" hints, or guessing becomes a free
   information source and the economy collapses.
3. **The only way to get letter info is to buy it** (or use a free-info power-up). No free
   "guess a letter" side-channel.

With those, the only path to a solve is buying enough letters to deduce it — so **least
spend stays the real skill**, while you're never locked out by a guess cap.

---

## 5. Game Modes

### 5.1 Free Play — the sandbox & safety net
- Free to play. Uses your **earned** power-ups (won by feats in Free Play), not Cash.
- Pays a **small, capped Cash trickle** for solving (~$25–50/solve, ~$300/day cap) — the
  grind-back-from-broke faucet. **Deliberately minimum-wage** so it never cannibalizes the
  risk engines.
- Short/easy phrases allowed; relaxed, no stakes.

### 5.2 Daily — the paycheck
- One shared puzzle per day, same for everyone. Played with your **real Cash** (buy letters
  to solve efficiently), but with a **guaranteed minimum payout** so a finish always nets
  positive — your dependable income.
- **Attendance rewards** for showing up, tied to the play-streak (which survives losses, so
  *attempting* counts): base ~$50/day, milestones **Day 3 → $100, Day 7 → $250,
  Day 14 → $500, Day 30 → $1,500**, then loops.
- Feeds the Daily leaderboard. Make-up calendar (play past days for badges) unchanged from
  v2 — badges/score only, never streak-repair or Cash.

### 5.3 Cash Game — the Climb (the engine)
- One shared, fixed-order sequence; everyone advances forward forever, at their own pace.
- **Open spend** from your full Cash balance. Each puzzle shows its **Bounty** up front.
- Solve → earn `Bounty`; your net is `Bounty − Spend`. Buy too many letters and you can
  *lose* money on a puzzle. No bust, no loan — if you can't afford to crack one, you
  **leave it (saved) and go earn** in the Daily/Free Play, then come back.
- Each puzzle is solved **once** → income is bounded (anti-inflation).
- **Heat** (optional, solo-only): a within-Climb multiplier that grows on clean solves and
  resets on a fail/leave. *Decision pending — keep or cut.* If kept, it's the one place the
  Heat Shield power-up survives.

### 5.4 Challenges — the Challenge Builder (1v1, groups, gauntlets, Blitz)
- Host configures: opponent (person or group), categories, pack size, Blitz toggle,
  **wager**, payout shape (winner-take-all / top-3 / even-split-on-tie), response window.
- **Your wager is your stake AND your spending cap.** Both sides ante equally into the pot;
  during play you spend that stake on letters/power-ups. **Most stake left when you solve
  takes the pot.** Can't spend more than you bet → no whale bulldozing → fair.
- Shared seeded pack; **spoiler-lock** on wagered matches until you've played.
- **A match settles only when everyone has finished** (or the response window expires) —
  never the instant the host finishes. (Fixed in v2.x.)
- **Blitz:** speed variant; clock-based, combos. (*Spend-cap interplay TBD in build.*)

### 5.5 Groups
- Named groups you create/join; group challenges + a group leaderboard. (Unchanged from v2.)

---

## 6. Power-ups

**Universal rules (v3 — STORE-INVENTORY model, supersedes the earlier pre-commit model):**
- **Bought in the STORE only** (never on the puzzle screen). Buy ahead with Cash, carry an
  inventory, bring them to games. The **store price IS the cost** — using one is free
  (economically identical to the old "counts as spend", just paid up front).
- **One of each, max.** Hold ≤1 of each; after you use one, re-buy it. Consumed on use.
- **Used on the puzzle from your inventory** — a small "your items" tray, *use anytime*
  (no pre-commit lock; you already paid in the store). One of each *effect* per puzzle.
- Every power-up either **reduces your spend** or **gives free info.**
- **Where they're allowed:** ✅ Cash Game (Climb), ✅ Challenges *if the host toggles items
  on*. ❌ **Daily stays power-up-free** (the one shared, identical fair-fight; only the
  shared daily Modifier applies). This keeps the per-puzzle leaderboards honest.
- **Social layer (group games):** using a power-up notifies the group ("Sam used X").
  Future: **sabotage** power-ups (target an opponent) and **group chat.**

### Cash catalog (bought with Cash; in Cash Game / Challenges)
| Power-up | Effect | Serves objective by |
|---|---|---|
| **Half Off** | Letters cost 50% less this puzzle | Reduces spend |
| **Free Reveal** | Reveal one letter free (replaces the old reveal button) | Free info |
| **Vowel Vision** | Reveal all vowels free | Free info (big) |
| **Extra Hint** | Show an additional clue | Free info |

**Cut from v2** (built for the old heat/pot/bust/attempts model): **Extra Attempt** (dead —
guesses are unlimited), **Insurance** (no bust), **Double Down** (no pot multiplier),
**Heat Shield** (only survives if Climb heat is kept, Cash-Game-solo only).

### Free Play — earned by feats (stays in Free Play)
- Won through Free Play accomplishments, not bought. New users seeded one of each. Used only
  in Free Play. (Self-contained pool, unchanged in spirit from v2.)

---

## 7. Friends & Groups
- Username-based (`@handle`) friends with typeahead search. Friend codes retired.
- Groups: create/join/leave; group challenges and leaderboard. (Unchanged from v2.)

---

## 8. Leaderboards
- **Net Worth (= Cash)** — the headline board. Friends / Global / Group. Weekly-gained +
  all-time (via `networth_snapshots`).
- **Daily** — today's efficiency on the shared puzzle. Friends / Global / Group.
- **Climb** — how far you've climbed. Friends / Global / Group.

---

## 9. Profile & Stats
- Net Worth, Climb position, win/loss on challenges, badges, equipped cosmetics, streaks.
  (Unchanged from v2; loan/debt stats removed.)

---

## 10. Streaks & Badges
- **Play-streak survives losses** — attempting the Daily keeps it alive (drives attendance
  rewards, §5.2).
- Badges: Climb milestones (Climber/Mountaineer/Summit), Hustler (challenge wins), Flawless,
  Perfect Week/Month (make-up calendar), streak milestones.
- **Removed:** Debt-Free badge (no loans).

---

## 11. Scoring & Formulas (reference)
- **Spend** = `Σ letter costs + Σ power-up costs` for a puzzle.
- **Climb take** = `Bounty − Spend` (can be negative). Bounty = ~65% of full-reveal letter
  cost (tune in playtest).
- **Challenge result** = lowest `Spend` to solve wins; tiebreak by solve time. Spend is
  capped at the wager.
- **Daily payout** = `max(guaranteed floor, efficiency reward)`; floor ~$100. Efficiency
  reward from leftover-vs-spend (carry v2 multipliers: clean / no-vowel / first-try / no
  power-up). + attendance milestones.
- **Free Play** = small flat per-solve, daily-capped.
- *(All constants are tuning knobs — see §15.)*

---

## 12. Anti-cheat & Fairness
- Server-authoritative engines; spend/reveal/guess validated server-side.
- No positional feedback on guesses (§4) — closes the free-info exploit.
- Min-length phrases in competitive packs (§4).
- Anomaly-detection flags on superhuman efficiency/speed (deferred, as v2).

---

## 13. Monetization & Legal Firewall
- Cash/Net Worth **never** bought with real money or cashed out. Real money = **cosmetics
  only.** No pay-to-win (the power-up spend-counts rule reinforces this in-game too).
- Sweepstakes plan (if pursued): no-purchase-necessary; paying must **never** improve rank.
  (See iOS roadmap; lawyer review before real prizes. Not legal advice.)

---

## 14. Migration: v2 → v3 (the teardown)

**Remove / retire:**
- Loan system: `take_loan`, `repay_loan`, `set_auto_repay`, `_accrue_interest`,
  `declare_bankruptcy`, In-the-Red UI, loan columns, Debt-Free badge.
- Fake play-budget everywhere; the per-game $1,000 reset.
- The base reveal button (becomes Free Reveal power-up).
- The 3-guess cap (`guesses_remaining` logic) — guesses now unlimited.
- Obsolete power-ups (Extra Attempt, Insurance, Double Down; Heat Shield pending).

**Change:**
- `Net Worth = Cash` everywhere (drop `− Loans`).
- Every engine spends the **persistent Cash balance** (Daily, Climb, Challenges).
- New accounts start **$2,000** (was $1,000).
- Challenge play: spend capped at wager; settle = lowest-spend-to-solve.
- Power-up acquisition/use: one-of-each, pre-committed, cost-counts-as-spend.

**Existing-player reset:** light economy-baseline reset to $2,000 Cash, $0 (no loan
concept) + refreshed re-shown tutorial covering the v3 rules. (No full wipe.)

---

## 15. Open knobs (tune in playtest — not blockers)
- Starting Cash ($2,000), Daily floor (~$100) + attendance amounts.
- Free Play per-solve ($25–50) + daily cap ($300).
- Bounty fraction (~65% of full-reveal cost).
- Competitive phrase min-length threshold.
- **Keep or cut Climb heat** (and with it, Heat Shield).
- Blitz × spend-cap interplay.
- Cash power-up prices.

---

## 16. Build roadmap

> Sequenced so the teardown happens before the rebuild, and the game stays playable.

- **R1 — Identity & teardown.** Net Worth = Cash; start $2,000; rip out loans
  (functions, columns, UI, badge, bankruptcy). Light reset existing players to $2,000.
- **R2 — Free guesses + no reveal button.** Remove the 3-guess cap everywhere; remove the
  base reveal action; enforce all-or-nothing guesses (no positional feedback).
- **R3 — Persistent-Cash engines.** Daily, Climb, Challenges all spend the real balance;
  remove the fake play-budget. Daily guaranteed floor + attendance rewards.
- **R4 — The efficiency objective.** Challenges: wager = spending cap; settle =
  lowest-spend-to-solve; min-length competitive phrases.
- **R5 — Power-up rework.** One-of-each, pre-commit-before-puzzle, cost-counts-as-spend;
  rebuild the Cash catalog (Half Off / Free Reveal / Vowel Vision / Extra Hint); drop the
  obsolete ones.
- **R6 — Free Play as safety net.** Capped Cash trickle + earned power-ups.
- **R7 — Tutorial & polish.** Refreshed re-shown tutorial for v3 rules; leaderboards/profile
  cleanup (drop loan stats); copy pass.
- **R8 — Tuning pass (deferred).** Set the §15 knobs from real play data.
