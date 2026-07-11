# Single-Focus HUD — Implementation Plan

**Date:** 2026-07-11
**Goal:** Every mode's in-game HUD shows **one unlabeled number** (the bounty you spend down), taught live by a prominent **−$X spend floater**. The account balance is demoted from the prime top slot to a small ambient **bankroll chip** in the corner. Daily loses the pure/leveler complexity; Challenge shows a **fresh per-puzzle bounty** with **Score** promoted to the top slot.

## The vision

| Mode          | Corner chip | Top (prominent)      | Center — the one number (no label) |
| ------------- | ----------- | -------------------- | ---------------------------------- |
| **Daily**     | 🪙 bankroll | _(mode pill only)_   | bounty → your day's score          |
| **Cash Game** | 🪙 bankroll | _(mode pill only)_   | bounty → cumulative, cash out      |
| **Challenge** | 🪙 bankroll | **Score** + Pot/Beat | fresh per-puzzle bounty            |

**Why this works:** the center number is the same everywhere (bounty − spent), it moves _down_ as you buy letters, and the **−$X floater** makes that subtractive behavior legible on every purchase — which is what lets us drop the label entirely. The account is static during play in all modes, so it becomes ambient status, not a competing number.

## ⚠️ Open decision (blocks Phase 5 only)

**Daily win-streak Interest — keep or drop?** Recommendation: **DROP from the score.** Score = `bounty − spent`, deposited flat, so the daily leaderboard is a fair skill comparison (not streak-inflated). Streak rewards still exist via the **attendance** milestones. If kept, Phase 5 removal is smaller but the score stays streak-dependent.

---

## Phases (each = its own PR: prettier → check → lint → build → ship)

### Phase 1 — Rebuild the −$X spend floater _(foundational, decision-independent — start here)_

**Current state (`+page.svelte`):** `trackSpend` (~925) watches `$gameStore.bankroll`, fires `spendFloaters` only for `daily/makeup/climb`, caps at `$300`, renders `.spend-float` (~4540) in the panel's **top-right corner** in **Orbitron**.
**Bugs it has now:** watches the wrong value for Cash Game (`bankroll` = secured pile, unchanged on a letter-buy → **floats nothing in Cash Game**); **excludes Challenge**; `$300` cap hides high-tier ($20× stake) spends.
**Change:**

- Trigger off the **displayed center value** (`soloHero.net`) decreasing, guarded against `introBuilding` and non-spend jumps → fires correctly in all three modes.
- Remove the `$300` cap.
- Render the floater **at the center number** so it flies up-and-off it (not the corner).
- Restyle: `var(--font-display)`, larger, a scale-pop so it reads as a satisfying "that cost me" beat.
- Optional: a positive lock-in flash on the number at solve.
  **Files:** `src/routes/+page.svelte` (trackSpend, render slot, `.spend-float` CSS).

### Phase 2 — Corner bankroll chip; remove in-game "My Account" strip

- Remove the `.acct-strip` (My Account) from the in-game top bar (~4264).
- Add a small, muted **bankroll chip** (coin glyph + amount, tappable → `/bank`) in a corner, consistent across all modes. Reads as ambient status, not a game number.
  **Files:** `src/routes/+page.svelte` (top-bar block + CSS).

### Phase 3 — Strip the center labels

- Remove the `bp-label` text (currently "Payout" / "Score" / "Balance Remaining"). Center = the number + its badge only.
  **Files:** `src/routes/+page.svelte` (~4439).

### Phase 4 — Challenge: fresh per-puzzle bounty + Score up top

- `soloHero` match branch: `matchEarnings` (accumulated) → `matchLeft` (this puzzle's leftover) so the center **resets each puzzle**.
- Promote **Score** (`total_score`, already tracked server-side) to the prominent top slot; keep the **Pot** + **Beat $X** + standing chips as the scoreboard.
- Between-puzzle beat: **"Kept +$X → Score $Y → next fresh bounty."**
  **Files:** `src/routes/+page.svelte` (soloHero ~626, match HUD ~4366, between-puzzle transition). No server change (score already accumulates).

### Phase 5 — Daily: remove pure/leveler, Twist always-on, apply Interest decision

- **Remove the pure/×1.5 leveler** everywhere: the Use/Pure UI + `twist_used` flag + the ×1.5 bonus. The daily **Twist/modifier applies to everyone, always**.
- **Server:** strip pure/leveler from `daily_start` / `_finalize_daily` / `_daily_resolve_and_return`; drop `twist_used` if fully unused. **If dropping Interest:** `winnings = kept` (no `×mult`); remove the streak-multiplier logic.
- **Client:** remove Use/Pure UI + leveler; **if dropping Interest:** remove the Daily Interest badge, the receipt Interest line, the `mult` info modal, and `dlMult`/`bountyMult` plumbing.
  **Files:** `supabase-*.sql` (daily fns) + `+page.svelte` + `statsStore.js`/`GameStore.js`.
  **Verify:** `BEGIN…ROLLBACK` money-conservation + `qa-e2e.mjs` (Daily is the biggest, most SQL-heavy phase).

---

## Sequencing & rationale

**1 → 2 → 3 → 4 → 5.** Floater first (feel-first, and it fixes real Cash Game/Challenge bugs regardless of the rest). Labels come off only after the floater proves it carries the meaning. Daily last — it's the largest surface and the only one touching prod SQL.
