# WordBank — Economy v3.1: the Return Multiple

> **Status: draft for review.** Supersedes WORDBANK_MASTER_V3.md §3 (Economy),
> §4 (Objective), §5 (Modes), §5.4 (Challenges) and §11 (Formulas) once approved.
> Everything else in v3 stands. This is a *simplification* — it removes wagers,
> fake budgets, and "chips" and replaces them with one number: **prize ÷ spend.**

---

## 0. North star

**The whole game is one move: solve for the highest multiple.**

```
Return multiple = Prize ÷ Spend          Net Cash = Prize − Spend
```

Spend less to crack the phrase → bigger multiple → more Cash. "Spend the least"
stops being homework and becomes the slot-pull you chase and screenshot.

One currency (Cash). Every mode is the *same skill* at a different **price tier.**

---

## 1. The core mechanic

Every puzzle has a **fixed Prize `P`**, set by its difficulty (≈ its full-reveal
cost — the sum of every letter's price). `P` is shown up front and **does not move
with how much you spend** — that's what makes the multiple real.

You solve having spent `S` (letters + any power-ups). Then:

| You spent | on a `P = $400` puzzle | Multiple | Net |
|---|---|---|---|
| $80 | cracked it cold | **5.0×** | **+$320** |
| $160 | | 2.5× | +$240 |
| $300 | grinded it out | 1.3× | +$100 |
| $400 | full reveal | 1.0× | $0 |

Both the **multiple** (the flex) and the **net** (the Cash) reward low spend. The
multiple is the headline number in the HUD and the results card.

### Guardrail — cap the multiple
`P ÷ S` explodes as `S → 0` (a one-letter lucky solve would mint a fortune). So:
- **Max multiple is capped** (open knob, ~**8–10×**), and/or
- an **effective-spend floor** (you're treated as having spent at least `P / cap`).

Below that floor a brilliant solve still pays the cap — legendary, not broken.

### What keeps free guessing honest (unchanged from v3 §4)
All-or-nothing guesses (no positional feedback), min-length competitive phrases,
and *the only way to get letter info is to buy it.* So the only path to a solve is
buying enough to deduce it — **least spend stays the real skill.**

---

## 2. One currency, modes = price tiers

A mode is now just a **price level** (how expensive letters are) and a **prize
size** (how big `P` is). Same mechanic top to bottom.

| Mode | Letter prices | Prize `P` | Payout source | Vibe |
|---|---|---|---|---|
| **Penny Play** (Free Play) | pennies (×0.1) | tiny | system-minted, capped | free entry, broke-safe grind; still flex a 6× |
| **Daily** | normal (×1) | normal + **floor** | system-minted | dependable paycheck |
| **Cash Game** (the Climb) | normal/steep (×1–2) | big, forward-only | system-minted bounty | the wealth engine |
| **Challenge / Group** | host-chosen tier | — (pot is the prize) | **zero-sum pot of spend** | real stakes vs friends |

- **Penny Play "you get less for winning"** falls out for free: small `S` → small
  absolute Cash even at a high multiple. Cheap to play, safe to lose, slow to farm.
- **No chips, no second wallet, no conversion screen.** "Cheaper mode" = a lower
  price tier of the one currency.

---

## 3. Solo modes (Penny Play, Daily, Cash Game)

You play your real Cash; **Prize is system-paid** on a solve:

```
earn = min(P, P/cap·multiple)  →  Net = earn − S
```

- **Penny Play:** ×0.1 prices, tiny prizes, **free to enter** (can't bust your
  bank — you simply don't solve if you run dry). Capped daily so it never
  cannibalizes the engines. The grind-back-from-broke floor.
- **Daily:** normal tier with a **guaranteed minimum** so a finish always nets
  positive, plus the existing attendance/streak rewards.
- **Cash Game:** normal/steep tier, **forward-only** sequence (each puzzle solved
  once → income bounded, can't be farmed). Can't afford one? Leave it (saved) and
  go earn, then come back. No bust, no loan.

Anti-inflation is unchanged: floors capped, Climb forward-only, challenges zero-sum.

---

## 4. Challenges & Groups (the competitive model)

**Host configures:** opponent (person/group), categories, **price tier**, pack
size, **buy-in `$B`**, payout shape, items-allowed toggle, rebuys on/off, response
window.

### How money moves — escrow, refund, pot-of-spend
1. **Each player escrows `$B`** of real Cash to join. `$B` is your **spend cap** for
   the whole pack — *a capped slice of the one currency, not chips.* Equal for
   everyone → a new player and a whale compete dead even.
2. You spend from `$B` to buy letters. **Whatever you don't spend refunds to your
   bank** at settlement.
3. **The pot = the total everyone spent.** Winner (or podium) takes it.

Because the winner is the *most efficient* solver, they spent the least → they take
a pot funded mostly by the people who spent more. Efficiency is rewarded twice.
It's **zero-sum**: `Σ nets = 0`, no Cash minted, none burned.

### Ranking (the multiple is the scoreboard)
1. **Puzzles solved** (desc) — solving more beats a pretty multiple on fewer.
2. **Total spend** (asc) — i.e. the **best aggregate multiple** wins ties.
3. **Time** (asc) — final tiebreak.

Payout shape: **winner-take-all** (1v1) or **podium 3·2·1** (groups, needs ≥3
finishers — 3rd recoups, 2nd ~doubles, 1st takes the rest).

### Running out of money
- Hit your `$B` cap and can't solve? **Free-guess with what's revealed; no more
  buying.** You bust that puzzle. **You only ever lose what you spent.**
- **"Withdraw more" = a rebuy:** if the host allows it, escrow another `$B` for a
  fresh cap — and it **grows the pot.** Deliberate, real-Cash, poker-style — never a
  loan or a free top-up (the pay-to-win we deleted).

### Edge cases
- **Nobody solves:** rank by furthest progress (letters short of solving); a true
  tie **refunds everyone** — no winner, no transfer.
- **Entry gate:** you must hold `$B` to join. Broke? Earn it in Penny Play/Daily.
- **Spoiler-lock** on wagered packs until you've played; **settles only when all
  finish** or the window expires (unchanged).

---

## 5. The multiple, unified

- **Solo:** the multiple *is* your payout — `Prize ÷ Spend`, system-paid (capped).
- **Challenge:** the multiple is your *rank*; the **pot of spend** is the payout
  (zero-sum). `Prize` here is only used to compute the per-puzzle multiple you show
  off — it is **not** minted (that would inflate competitive play).

One skill score, two ways to cash it: minted solo, transferred head-to-head.

---

## 6. Open knobs (tune in playtest)

- Price-tier scalars (Penny ×0.1 … Cash Game ×2) and the **prize curve** `P = f(full-reveal cost)`.
- **Multiple cap** (~8–10×) and/or effective-spend floor.
- Penny Play: pure flex (near-zero Cash) vs a tiny real trickle; daily cap.
- Challenges: **rebuys on/off**, podium thresholds, nobody-solves rule.
- Whether `$B` is a single pack budget (carry across puzzles — strategic) or
  re-grants per puzzle (friendlier). *Lean: single budget + optional rebuys.*

---

## 7. What changes in code (high level)

| Area | Today | v3.1 |
|---|---|---|
| **Letter pricing** | fixed `letterCosts` (Keyboard + server) | × **price-tier scalar** per mode |
| **Prize** | Daily `_daily_reward`, Climb bounty | generalize `_prize(puzzle, tier)` ≈ round(full-reveal × curve) |
| **Payout (solo)** | par/bounty − spend | `Prize ÷ Spend` multiple, **capped**, surfaced in HUD + results |
| **Challenge stake** | wager = stake & cap, "most stake left wins" | **escrow `$B` → spend → refund unspent → pot = spend** |
| **`_match_settle`** | antes pot, most-left | rank solved→spend→time; winner/podium takes **pot of spend**; refund unspent; nobody-solves refund |
| **Rebuys** | — | optional: escrow another `$B`, grows pot |
| **Free Play** | trickle, earned power-ups | **Penny Play**: ×0.1 tier, tiny prize, free entry |
| **HUD/results** | Worth/spent/net | lead with the **Return multiple** |

Net effect: *fewer* concepts than today — no wagers, no fake budgets, no chips.
Just **price tier + (Prize ÷ Spend)**, with challenges making the spend the pot.

---

*Draft — react/redline and I'll fold the approved version into WORDBANK_MASTER_V3.md
and map each row of §7 to concrete migrations + UI changes.*
