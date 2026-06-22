# WordBank Economy v2 — "Cash, Loans & Net Worth" revamp

> **Status:** spec for sign-off (supersedes `BANK_ECONOMY.md`).
> **North star:** turn the no-stakes sandbox into a real risk/reward money game.
> One currency you actually risk (**Cash**), real **Loans** with interest, and
> **Net Worth = Cash − Loans** as the headline bragging score.
> **Legal firewall (non-negotiable):** Cash & Net Worth are virtual — never bought
> with real money, never cashed out. Real money buys cosmetics only. No pay-to-win.

---

## 1. The four modes (taxonomy)

| Mode | One-liner | Risk level | Economy role |
|---|---|---|---|
| **Free Play** | Practice puzzles, play money | None | Sandbox / onboarding (walled off) |
| **Daily** | One shared puzzle, skill score, your paycheck | None (no Cash spent) | Steady, capped **faucet** + social score |
| **Cash Game** *(was Arcade)* | Solo vs the house — risk real Cash, press your luck | High, uncapped | The **engine**: big wins/losses, where loans matter |
| **Hustle Your Friends** *(was Challenges)* | Wager Cash head-to-head + **Group games** | Player-set | PvP **transfer** + viral growth |

Tagline still holds: **"Spend Less. Think More."**

---

## 2. Currency model

- **Cash** — the single spendable pool. Buys letters in Cash Game, wagers friends,
  buys power-ups & cosmetics. Floored at $0 (can't go negative).
- **Loan** — debt you take on **at any time** (including mid-game). Always accrues
  **interest**. Repay anytime.
- **Net Worth = Cash − Loans** — the wealth/bragging metric and the main leaderboard.
- **Cash-on-hand is shown everywhere** next to Net Worth, so a player with lots of
  Cash but low/negative Net Worth is visibly *leveraged on loans*. Transparency is
  the point.

---

## 3. The 20 questions — decisions

**Currency**
1. **One Cash pool, no hidden second wallet** — yes. Cash Game spends real Cash.
   (Daily is the one exception, see Q3.)
2. **Net Worth = Cash − Loans only.** Cosmetics/assets do **not** count — keeps the
   metric ungameable; cosmetics are pure flex/sink.
3. **Daily uses a separate fixed play-budget, NOT real Cash.** Daily is the welcoming
   habit; it must have no cash downside (avoids the "beginner tax" trap). Real-cash
   risk lives in the Cash Game.

**Sign-up & Daily faucet**
4. **Sign-up bonus = $1,000 Cash** (a gift, not a loan). Loan starts at **$0**.
5. **No flat "$100 for playing."** Folded into the Daily reward as a **$100 floor**
   (finishing always pays ≥ $100). One payout, once/day.
6. **Daily also grants:** streak progress (multiplies the payout), the occasional
   streak-freeze, the shareable daily score, and — crucially — it's the
   **un-loseable income floor** (your lifeline when broke; see Q11).

**Loans & interest**
7. **Interest = ~5%/day, simple, on the outstanding balance** (tunable 3–5%).
   Non-compounding so it can't death-spiral; accrues on a daily tick.
8. **One running loan balance you top up. Cap = $10,000** debt (later: scale the cap
   with level/lifetime earnings).
9. **Repayment: manual anytime**, plus an optional **"auto-repay" toggle** that skims
   ~10% of Cash-Game winnings toward the balance. Interest keeps accruing until paid.
10. **Teeth:** the interest drag on Net Worth is the primary pressure, plus a visible
    **"In the Red"** status on your profile/leaderboard row. We do **not** lock core
    fun (you can still play & wager in debt) — pressure, not a prison.

**Bankruptcy & the floor**
11. **The Daily is the lifeline** — it costs no Cash and always pays, so a broke
    player can always grind back. No separate stipend needed at launch.
12. **Optional "Declare Bankruptcy"** (v2): wipes loan debt but resets Cash to the
    $1,000 floor and Net Worth to ~$0, and stamps a permanent **Bankruptcy** mark +
    cooldown. A real escape hatch with a pride cost.
13. **Show negative Net Worth** ("−$3,200"). Honest, and it powers comeback arcs. No
    dedicated "most in debt" board (feels bad), but individual negatives are visible.

**Cash Game (the engine)**
14. **No fixed seed, no buy-in slider — your Cash on hand funds it directly.** You
    control exposure by how aggressively you buy letters and how deep you push.
    (Optional guardrail: a per-run "max I'll spend" cap.)
15. **Payout = press-your-luck pot** (see §5). Each solve adds a house **prize** to an
    unbanked **pot** with a rising **multiplier**. A clean, well-judged run is
    net-positive vs the Cash you spend on letters; pushing too far and busting is
    net-negative.
16. **Unlimited play.** The competitive surface is the **weekly Net-Worth-gained**
    board (Q20b), so grinding doesn't permanently warp the rankings. A per-day soft
    cap on house prizes is held in reserve as a safety valve if telemetry runs hot.
17. **Inflation control:** real sinks = letter-spend lost on busts, **loan interest**,
    and cosmetics. Faucets = sign-up, daily paycheck, Cash-Game pots, quests. The
    weekly board + bust variance keep it balanced; soft cap is the backstop.

**Power-ups**
18. **Mostly bought, consumable (one run/use), only rarely earned.** Buy with Cash
    before/during a Cash Game run. This is the recurring risk/sink loop you wanted.
19. **Strategic payoff** — each is a real bet, e.g.:
    - **Insurance** ($X): refund your letter-spend if you bust *this* puzzle.
    - **Double or Nothing**: 2× the next prize, but a miss busts the pot.
    - **Vowel Vision**: vowels half-price this puzzle.
    - **Pot Lock**: bank a % of the pot so a bust can't wipe all of it.
    You borrow, buy power-ups, and gamble on out-earning the loan. (See §6.)

**Wagering, leaderboard & firewall**
20a. **Wager limits / tiers** — ante caps relative to the *poorer* player (or fixed
     tiers: $100 / $500 / $2k rooms) so whales can't bully newcomers.
20b. **Two boards: weekly Net-Worth-gained is the headline** (everyone competes fresh
     each week); **all-time Net Worth is the hall of fame.** Plus the **daily score**
     board and **group results** cards.
20c. **Hard firewall, committed:** Cash & Net Worth can **never** be purchased with
     real money or cashed out. Real money = cosmetics only. This is what keeps the
     loans + risk model out of gambling/social-casino classification.

---

## 4. Daily — design & reward formula

One shared puzzle/day, played with a fixed **play-budget** (e.g. $1,000, scaled to
phrase difficulty) that is **not** your Cash. The skill is spending less.

```
base            = leftover budget on solve            (spend less → more)
efficiency_mult = 1.00
   + 0.25  no wrong letters bought      (clean)
   + 0.25  no vowels bought
   + 0.25  solved on the first solve    (no wasted guesses)
   + 0.15  no reveals used
streak_mult     = 1 + min(streak-1, 10) × 0.05         (→ 1.5× at a 10-day streak)

DAILY SCORE = round(base × efficiency_mult × streak_mult)
```

- **Floor:** finishing pays **≥ $100**. **Fail to solve:** $0 + streak resets (the only "loss").
- **DAILY SCORE = your Cash paycheck AND your shareable number** ("beat my daily").
- Once/day + skill ceiling → a **bounded, dependable faucet** (~a couple thousand on a
  great day). Optional hard cap $2,000/day.
- Replaces the old flat "$500 × streak" Bank bonus.
- *Knob:* scale the play-budget to phrase length so hard/easy days pay comparably.

---

## 5. Cash Game — design & payout math

Poker cash-game energy: your **chips are your Cash**, you can bust and re-buy (loan),
and you sit down / leave whenever.

**Loop**
1. Enter with your **Cash on hand** as letter-buying funds (no seed).
2. Each puzzle: spend Cash on letters to solve. On solve → add a **prize** to the
   **pot**, step up the **multiplier**; on a miss → **bust**.
3. **Bank it** anytime → pot → Cash, run ends, multiplier resets.
4. **Bust** → lose the **unbanked pot** (keep your remaining Cash), multiplier resets.
5. Low on Cash mid-run → **take a loan** (terms shown at the moment — no dark pattern).

**Payout curve (starting values — TUNE in playtest)**
```
prize_N      = base_prize × multiplier_N
base_prize   ≈ $250  (scales a bit with puzzle difficulty)
multiplier   = ×1.0, ×1.3, ×1.6, ×2.0, ×2.5, ×3.0, … (per consecutive solve)
pot          = Σ prize_i for solves since the run/last bank
difficulty   rises with depth (longer phrases, costlier letters)
```

**Why it self-balances:** deeper = bigger prizes *and* costlier/harder puzzles, so
expected value eventually turns negative — the skill is **knowing when to bank.**
Double tension: the Cash you sink into letters (gone on a bust) **and** the unbanked
pot (gone on a bust). Banked pot > letters spent ⇒ you grew Net Worth and can repay.

---

## 6. Power-ups — strategic sink

- **Bought with Cash, consumable, per-run.** Only a rare few are earned.
- The intended loop: **borrow → buy power-ups → gamble in the Cash Game → out-earn the
  loan (or dig deeper).**
- Starter set: Insurance, Double-or-Nothing, Vowel Vision, Pot Lock, Reveal (paid).
- Priced so each is a genuine risk/reward bet, not a flat tax.

---

## 7. Hustle Your Friends — 1v1 + Group

**1v1 (exists, rename + retune):** wager Cash, same puzzle, higher score wins the pot;
ante caps/tiers (Q20a); Score & Pressure variants.

**Group challenges (new — the growth engine):**
- **Async with a window** (e.g. 24h) — fits text group chats.
- **Shareable join link/code** dropped in the chat; **open roster** by default.
- **One shared puzzle**, scored by the **Daily efficiency formula** (fair, fast).
- **Two flavors:** **Friendly** (no ante, pure brag — *default, max virality*) and
  **Pot** (everyone antes, winner-take-all, capped ante).
- **Spoiler lock:** results/scores hidden until *you've* played; answer locked until
  settlement (critical for async + group chats).
- **Settle → ranked results card** (placement, scores, 👑 winner) built to be
  screenshotted back into the chat. Reuses the **notifications** system already built.

---

## 8. Free Play — walled-off sandbox

Fake/practice money, **no Cash spent or won, no Net Worth impact, no loans, unlimited.**
Its own per-round practice bankroll. No real-board ranking (optional cosmetic
"practice best"). The safe room for learning and casual play.

---

## 9. Faucets & sinks (economy balance)

| Faucets (money in) | Sinks (money out) |
|---|---|
| Sign-up $1,000 | Letter-spend lost on Cash-Game busts |
| Daily paycheck (capped) | **Loan interest** (~5%/day) |
| Cash-Game banked pots | Cosmetics (real flex sink) |
| Quests | Power-ups (consumable) |
| — | Wager *losses* (player-to-player transfer, net-zero) |

Watch metric: **median Net Worth growth/week.** If it runs away → enable the Cash-Game
per-day prize soft cap and/or steepen difficulty scaling.

---

## 10. Leaderboards

- **Weekly Net-Worth Gained** — *headline*, resets weekly (newcomers compete).
- **All-time Net Worth** — hall of fame.
- **Daily Score** — today's shared puzzle (fair skill comparison + sharing).
- **Group results cards** — per group game.
- All rows show **Cash-on-hand + Net Worth** (+ "In the Red" flag), title/color flair.

---

## 11. What changes from the current build

- `Bank` → **Cash** (rename throughout UI + ledger reasons).
- New accounts: **$1,000 Cash, $0 loan** (was $5,000 / $5,000 auto-loan). Loans become
  opt-in. **Migration:** at revamp launch, reset everyone to $1,000 Cash / $0 loan
  (small pre-launch base — consistent with the earlier light reset).
- Daily payout: efficiency formula replaces `500 × streak`.
- Arcade → **Cash Game**: real-Cash play + pot/multiplier (was free $1,500 seed).
- Challenges → **Hustle Your Friends** (+ groups).
- Power-ups: shift from earned to bought/consumable.
- Net Worth leaderboard gains a **weekly** sibling and becomes the headline.

---

## 12. Build roadmap

- **Phase 0 — Spec sign-off** (this doc). ☐
- **Phase 1 — Currency & identity.** Rename Bank→Cash; Net Worth = Cash − Loans as
  headline; show Cash-on-hand everywhere; sign-up $1,000/$0; migrate existing users. ☐
- **Phase 2 — Loans v2.** Borrow anytime (incl. mid-game), interest accrual + daily
  tick, repay (+ auto-repay toggle), $10k cap, "In the Red" status. ☐
- **Phase 3 — Daily revamp.** Play-budget model, efficiency reward formula, Daily
  Score = paycheck + shareable, $100 floor; retire `500 × streak`. ☐
- **Phase 4 — Cash Game.** Rename Arcade; real-Cash play; pot + multiplier press-your-
  luck; bank/bust; loan mid-game; payout tuning. ☐
- **Phase 5 — Power-ups economy.** Buy-with-Cash, consumable, strategic set + shop. ☐
- **Phase 6 — Hustle Your Friends.** Rename Challenges; ante caps/tiers; then **Group
  challenges** (async link, friendly + pot, spoiler lock, results card). ☐
- **Phase 7 — Free Play wall-off.** Fake money, zero economy ties. ☐
- **Phase 8 — Leaderboards.** Weekly Net-Worth-gained (headline) + all-time + daily
  score + group cards; Cash/Net-Worth/In-the-Red on every row. ☐
- **Phase 9 — Balance & polish.** Bankruptcy option, anti-inflation telemetry + soft
  caps, full tuning pass, legal-copy review. ☐

---

## 13. Open knobs to playtest (not blockers)

- Daily play-budget size + difficulty scaling; daily hard cap.
- Interest rate (3–5%/day) + debt cap.
- Cash-Game base prize, multiplier curve, depth difficulty.
- Power-up prices & effect magnitudes.
- Wager tiers; weekly-board reset timing.
- Whether to ship the bankruptcy option at launch or in v2.

---

## 14. Legal guardrails (carry over, now more important)

Loans + interest + real-risk Cash Game make the firewall **more** important:
- ❌ Never sell Cash/Net Worth for real money; ❌ never cash out; ❌ no pay-to-win.
- ✅ Real money = **cosmetics only** (firewall).
- Virtual-currency wagering is fine **only** because the currency has no real-money
  value. Keep it that way. (Not legal advice — review before any real-money product.)
