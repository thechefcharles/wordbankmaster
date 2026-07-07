# Bank Account + Loans UI redesign

Date: 2026-07-07

## Goal

Money and loans are scattered across three inconsistent surfaces today (a read-only
in-game modal, the full `/bank` page, and a buy-in prompt that dumps you onto `/bank`).
Unify them into one **Bank Account hub** reachable from the top money chip, add an
**inline borrow flow** at the buy-in wall, rename the two money concepts, and fix stale
ledger labels.

No DB changes — the loan RPCs (`take_loan`, `repay_loan`, `get_bank`) already exist.

## Naming

| Concept                      | Old        | New                 |
| ---------------------------- | ---------- | ------------------- |
| Persistent money / net worth | "Cash" 💰  | **Bank Account** 💰 |
| Cash Game run number         | "Stack" 🪙 | **Wallet** 👛       |

Mental model: your **Bank Account** is safe savings; you move money into a **Wallet** to
gamble in Cash Game; cashing out drops it back into your Bank Account. The Challenge ante
also reads "Wallet" (same idea — in-play money).

Scope of rename: prominent **labels/headers and clear references** to the balance become
"Bank Account". `$`-denominated amounts and incidental shorthand are left as-is (avoid
awkward "Not enough in your Bank Account" phrasing — those stay "Not enough Cash" or use
`$`). The compact top chip keeps `💰 $12,340`; the word "Bank Account" appears in the hub.

## Components

- **`LoanPanel.svelte`** (new): the borrow/repay UI extracted from `bank/+page.svelte` —
  dial + slider + PIN confirm, both the no-debt (borrow) and in-debt (repay) states.
  Props: `bank` (the `get_bank` payload) + `on:changed` to trigger a reload. Reused by
  both the hub sheet and the `/bank` page (single source of truth).
- **Bank Account hub sheet** (extend the existing in-page `showBank` modal): big balance
  labelled "Bank Account", `<LoanPanel>`, recent activity (8 rows), and a "See full
  ledger" link → `/bank`.
- **Menu money chip**: opens the hub sheet (was `goto('/bank')`).
- **`/bank` page**: stays as the deep "full ledger + items" view; reuses `LoanPanel`;
  labels renamed to "Bank Account".

## Buy-in wall → inline borrow

When starting a Cash Game / challenge with too little Bank Account:

- Compute `shortfall = buy_in − bank`.
- If `shortfall > loan_cap` → block with "You can only borrow up to $X" (can't cover it).
- Else prompt: shows shortfall, pre-fills `borrow = shortfall` (fee = 25%), `requirePin`,
  `take_loan(borrow)`; on `ok` → immediately proceed with `cashgame_start`/challenge start.

## Ledger label fixes

Rebuild `reasonLabel` against live reason strings: `cashgame_buyin` → "Cash Game buy-in",
`cashgame_cashout` → "Cash Game cash-out", `climb_bounty` → "Cash Game bounty",
`climb_letter` → "Cash Game letter", `blitz_buyin`/`blitz_payout`, `loan_take`/
`loan_repay`/`loan_skim`, `quest_reward`, `wager_*`, `attendance`, `daily_reward`,
`cosmetic_buy`, `powerup_buy`, `challenge_payout`, `makeup_reward`. Removed-feature
reasons (`arcade_cashout`, `freeplay_*`, `buy_credits`) keep a readable historical label.

## Out of scope

- Any DB migration (loans already shipped).
- Micro-tier economics (penalty > buy-in) — tracked separately.
