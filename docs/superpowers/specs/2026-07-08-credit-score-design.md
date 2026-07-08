# Credit Score — Design Spec

**Date:** 2026-07-08
**Status:** Approved shape, pending spec review
**Decisions locked:** Hardcore teeth · rewards financial discipline

## 1. Overview

Add a **credit score** to WordBank — a 300–850 reputation number that reflects how
responsibly a player manages their money, and that **hard-gates the loan system** (cap +
interest rate + lockouts) and becomes a **leaderboard stat + badge tier**.

It introduces a second status axis orthogonal to net worth: today the only flex is _how
much Cash you have_; credit score rewards _how disciplined you are_. A careful player who
never gets rich can top the credit leaderboard; a reckless whale can tank their score.

**Why hardcore is safe here:** loans are a _booster_, not a necessity — the core loop
(solve puzzles → earn Cash in Daily / Cash Game) never requires credit. So a low score
that locks borrowing removes a tool, it doesn't brick the account. And because the score
rewards discipline, the recovery path is simply _play clean and stay solvent_ — which a
broke player can always do, without needing the thing that's locked.

## 2. Goals / non-goals

**Goals**

- A legible 300–850 score driven mainly by financial discipline (utilization, solvency,
  restraint), computed server-side from data we already have.
- Hardcore effects: score bands set loan cap, interest rate, and lockouts.
- Big, recoverable swings — brutal slope, no permanent cliff from a single day.
- Surfaced as a gauge on My Account, on the Loans page, as a leaderboard column, and as
  badge tiers.

**Non-goals (v1)**

- Real-money anything (score is virtual, like all WordBank Cash — see
  `wordbank-virtual-currency`).
- Gating non-loan systems (Daily, Cash Game stakes, Store) on score. Loans only, for now.
- A separate "loan shark character"/animation (tracked separately on `/loans`).

## 3. The score model (300–850)

Everyone starts at a neutral **650**. Range **[300, 850]**. Recent behavior is weighted
heavily so the score is volatile _and_ recoverable.

**New-player grace (locked):** for the first **7 days** after account creation (or until
the player's first loan, whichever comes first) the score is **pinned at 650** and the
player is treated as the **Good** band — so newcomers aren't punished before they've had a
chance to learn the system. After grace, normal recompute takes over.

### 3.1 Components (each normalized to 0..1, higher = better)

Discipline-weighted:

| Component           | Weight | Signal                                                                                   | Source                                                           |
| ------------------- | ------ | ---------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| **Utilization** `U` | 35%    | `1 − avg(loan/cap)` over the last 14 days. No debt → 1. Sitting maxed → 0.               | daily util from `profiles.loan` / `_loan_cap`, or ledger-derived |
| **Solvency** `S`    | 25%    | fraction of last 14 days **not in the red** (net_worth ≥ 0).                             | red-day counter / net_worth checks                               |
| **Repayment** `R`   | 20%    | self-repaid vs defaulted loans in window; defaults drag hard.                            | `bank_ledger` reasons `loan_repay` vs `loan_skim`                |
| **Restraint** `B`   | 10%    | penalize serial borrowing (many `loan_take` in window) + always grabbing near-max loans. | `bank_ledger` `loan_take` count + sizes                          |
| **Consistency** `C` | 10%    | play streak / attendance over window.                                                    | existing streak fields                                           |

**Behavioral target:**

```
T = 300 + 550 × (0.35·U + 0.25·S + 0.20·R + 0.10·B + 0.10·C)
```

All-perfect → 850, all-zero → 300.

### 3.2 Movement (ease-to-target + event jolts)

The stored score **eases toward `T`** rather than snapping, giving controllable volatility
and a per-day floor:

```
Δ_daily = clamp(T − score, −DROP_CAP, +RISE_CAP)
score  += Δ_daily
```

- `DROP_CAP = 120` / day — brutal but not a cliff.
- `RISE_CAP = 40` / day — climbing is a grind (hardcore); ~8 clean days to climb a full tier.

**Catastrophic events** apply an _immediate_ extra penalty on top of the eased drop (this
is the intended "cliff" the daily cap otherwise smooths):

- **Default** (`loan_skim` forced / loan auto-collected while unpaid): **−100** and set a
  **derogatory mark** that decays over 30 days (repo-man style) — while active it caps the
  Repayment component and prevents reaching Good+.
- **Bankruptcy** (`supabase-bankruptcy.sql`): **−150**, floor the score into the Poor band.

Per-event penalties are bounded; the worst realistic single day ≈ eased −120 plus one
capped event penalty. Constants above are **tunable** and finalized during implementation.

### 3.3 Recompute strategy — lazy, no cron dependency

Store `credit_updated_at`. Recompute is triggered:

- **On loan lifecycle events** — `take_loan`, `repay_loan`, `_accrue_loan` (default path),
  bankruptcy → recompute + apply any event jolt.
- **Lazily on read** — `get_bank()` (and login) checks elapsed days since
  `credit_updated_at`; if ≥ 1 day, applies up to N daily eases toward `T` (catch-up) and
  decays the derogatory mark. This avoids needing a scheduled cron job.

All computation lives in a single `SECURITY DEFINER` function
`_recompute_credit(p_uid, p_event text default null, p_event_delta int default 0)`.

## 4. Bands & hardcore effects

| Tier          | Range   | Loan cap             | Interest rate           | Notes                               |
| ------------- | ------- | -------------------- | ----------------------- | ----------------------------------- |
| **Excellent** | 780–850 | `_loan_cap × 1.25`   | base − 300bp (softened) | unlocks black card skin (Phase 4)   |
| **Good**      | 670–779 | `_loan_cap × 1.0`    | base                    | the neutral baseline                |
| **Fair**      | 580–669 | `_loan_cap × 0.5`    | base + 300bp            | reduced access                      |
| **Poor**      | 400–579 | floor $250 only      | max rate (1500bp)       | "the shark barely trusts you"       |
| **Bad**       | 300–399 | **borrowing LOCKED** | —                       | `take_loan` returns `credit_locked` |

Integration:

- `_loan_cap(uid)` result is multiplied by `_credit_cap_factor(score)` → new effective cap
  surfaced in `get_bank` as `loan_cap`.
- `_loan_daily_rate_bp(amount, cap)` gets `+ _credit_rate_adjust(score)` added to the base
  curve (existing loans keep their locked rate; only new loans use it).
- `take_loan` checks the band up front: Bad → reject `credit_locked`; Poor → clamp to floor
  cap + max rate.

## 5. Anti-abuse

- **Utilization uses a rolling average**, not the instantaneous value, so "borrow → repay
  right before the calc" doesn't farm a clean utilization reading.
- **Restraint penalizes serial borrowing** so many tiny take/repay cycles hurt rather than
  help.
- Rewards are QoL + cosmetic-leaning (cap/rate/status), consistent with
  `wordbank-prize-direction` — not worth botting.
- `RISE_CAP` throttles how fast a score can be pumped.

## 6. Data model

**`profiles`** (new columns):

- `credit_score INT NOT NULL DEFAULT 650`
- `credit_updated_at TIMESTAMPTZ`
- `credit_derog_until TIMESTAMPTZ` (derogatory-mark expiry; null = clean)
- `credit_red_days INT DEFAULT 0` / rolling solvency counter (or derive)

**`credit_history`** (new table, for the gauge trend + audit):
`(user_id uuid, at timestamptz, score int, target int, tier text, components jsonb)` —
one row per recompute; the gauge shows the last ~30 for a sparkline.

Components that need a daily signal (utilization, solvency) are derived from a rolling
window over `bank_ledger` + a lightweight per-day solvency check; **no new heavy snapshot
table required for v1** (revisit if derivation proves too coarse).

## 7. Server functions (SQL)

- `_credit_tier(score int) → text` — band name.
- `_credit_cap_factor(score int) → numeric` — 1.25 / 1.0 / 0.5 / (250 floor) / 0.
- `_credit_rate_adjust(score int) → int` — bp added to base curve.
- `_recompute_credit(p_uid, p_event, p_event_delta)` — the core: compute components →
  target → ease → clamp → write `profiles.credit_score`, `credit_updated_at`, append
  `credit_history`.
- Modify: `_loan_cap` (apply cap factor), `_loan_daily_rate_bp` (apply rate adjust),
  `take_loan` (band gate), `_accrue_loan` (default jolt), `get_bank` (lazy recompute + add
  `credit_score`, `credit_tier`, `credit_delta` to payload).
- `get_credit_detail()` → full breakdown (each component's 0..1 + human status + pts hint +
  the recent `credit_history` sparkline). Powers the detail view.
- `get_credit_leaderboard(p_limit)` → ranked by `credit_score` (mirrors existing board
  RPCs, e.g. `get_daily_board`).

All `SECURITY DEFINER`, keyed on `auth.uid()`; PITR point logged before each apply per the
DB workflow (`wordbank-db-management`).

## 8. UI surfaces

- **My Account (`/bank`)** — a new `<CreditGauge>`: SVG arc dial 300–850, needle/fill to
  score, tier label (color-coded), ▲/▼ delta since last recompute. Tap → detail view with
  the Credit-Karma-style breakdown ("Utilization: High — repay your loan to regain ~40
  pts") + a sparkline of recent history. Legibility is non-negotiable in a hardcore system.
- **Loans (`/loans`)** — show current tier → your cap + rate right now; if Fair/Poor/Bad,
  show _why_ and the concrete way to recover.
- **Leaderboard** — add a **Credit** sortable column / mode via `get_credit_leaderboard`.
- **Badges** — 700 / 800 / 850 "club" milestones + an Excellent-tier badge.

## 9. Phasing

1. **Score + visibility (read-only):** columns, `_recompute_credit`, lazy recompute in
   `get_bank`, `<CreditGauge>` + detail on My Account. **No effects yet** — let players
   learn what moves it before it bites.
2. **Loan effects:** cap factor, rate adjust, band lockouts, Loans-page tie-in.
3. **Leaderboard stat + badge tiers.**
4. **Tier card-skin cosmetics** (black card for Excellent).

Each phase is its own PR(s) with the standard gates + QA smoke.

## 10. Risks & open questions

- **Death spiral** — mitigated by: loans are optional, recovery = play clean, `DROP_CAP`
  floor, recent-weighting, and the **7-day new-player grace** (locked, §3).
- **Derogatory-mark decay** — **locked at 30 days** (repo-man style): a default caps the
  Repayment component and blocks Good+ until it decays.
- **Constants** (weights, caps, band cutoffs, jolt sizes) are first-draft; will be tuned
  against real ledgers during Phase 1–2.
- **Utilization derivation** — if a rolling ledger derivation is too coarse, add a daily
  `credit_snapshots` table.

## 11. Testing

- Simulate users via `set_config('request.jwt.claims', …)`; feed fixture `bank_ledger`
  rows and assert `_recompute_credit` produces expected target/score.
- Assert band → cap/rate/lockout mapping; assert `DROP_CAP`/`RISE_CAP` bound movement;
  assert lazy catch-up over multiple elapsed days; assert default jolt + derog decay.
- Preview-build screenshot the gauge across tiers; run `scripts/qa-e2e.mjs` before shipping
  each phase (`wordbank-qa-harness`).
