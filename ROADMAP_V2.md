# WordBank v2 — Build Roadmap (detailed)

> The execution plan for `WORDBANK_MASTER_V2.md`. Each phase lists Goal · Depends-on ·
> Server/DB · Client · Reuses/Replaces · Acceptance, and slices the big ones into PRs.
> Conventions: branch → PR → squash-merge; `svelte-check` + `npm run build` gate every PR;
> MCP migrations synced to a repo `supabase-*.sql` note; verify via JWT-impersonation SQL +
> Playwright smoke; clean up all test data.

## Dependency graph (build order)
```
P1 (identity) ─┬─ P2 (loans) ── P4 (Cash Game/Climb) ── P5 (power-ups) ── P7 (Blitz)
               ├─ P3 (Daily revamp)                         │
               ├─ P6 (Challenge Builder + Groups) ──────────┘ (P7 also needs P6)
               ├─ P8 (Leaderboards + Profile)  (Climb board needs P4)
               ├─ P9 (Streaks + Badges)
               └─ P10 (Anti-cheat + balance)  [last]
```
P2, P3, P6, P9 can run in parallel after P1. P4 is the critical path.

---

## Phase 1 — Cash identity & baseline  ✅ (PR #136 + copy sweep)

**Goal:** every surface speaks "Cash / Net Worth"; new + existing users on $1,000 / $0.
**Done:** `_ensure_bank` → $1,000/$0; migrated all users; Bank screen + home chip relabeled;
negative Net Worth red. (PR #136)
**Remaining (1 slice):**
- **Client lexical sweep** — replace remaining "Bank" copy: result modals, quests page,
  the arcade "Bank it" button, My Account, tutorial. Keep the verb "bank it" only where it
  means *stash* (it'll change anyway in P4).
- Grep gate: `grep -rin "\bbank\b" src` → only intentional uses remain.
**Acceptance:** no stray "Bank" in player-facing copy; chip + Bank screen read "Cash"/"Net Worth".

---

## Phase 2 — Loans v2  ✅

**Goal:** borrow anytime, interest accrues, repay/auto-repay, $10k cap, "In the Red."
**Depends on:** P1.
**Server/DB (migration `loans_v2`):**
- `profiles`: add `loan_accrued_at timestamptz`, `auto_repay boolean default false`.
- `_accrue_interest(uid)` — lazy: `days = floor(now()::date − loan_accrued_at::date)`;
  `loan += round(loan × 0.05 × days)`; set `loan_accrued_at = now()`. Cap loan at $10,000.
  Call it at the top of `get_bank`, `_bank_credit`, `repay_loan`, leaderboard reads.
- `take_loan(amount)` — `amount` clamped so `loan + amount ≤ 10000`; `_bank_credit(uid, +amount,
  'loan_taken')`; `loan += amount`. Returns `get_bank()`.
- `repay_loan` (exists) — accrue first, then pay min(amount, loan, cash).
- `set_auto_repay(bool)`; in `_bank_credit`, if delta>0 and reason is a winning reason and
  `auto_repay`, skim `min(loan, round(delta×0.10))` toward the loan.
- `get_bank` returns `in_the_red = (net_worth < 0)` + `loan_accrued_at`.
**Client:**
- Bank/Cash screen: **Take a loan** (amount input + "you'll owe ~$X/day interest" preview),
  **auto-repay** toggle, **In the Red** badge; ledger reasons already updated in P1.
- statsStore: `takeLoan`, `setAutoRepay`.
**Reuses:** `repay_loan`, `_bank_credit`, `bank_ledger`, Bank screen.
**Acceptance (SQL sim):** borrow $2k → cash +2k, loan 2k; advance clock 7 days via
`loan_accrued_at` backdate → loan ≈ 2,700; repay clears it; cap blocks borrowing past $10k;
auto-repay skims a win. Playwright: loan UI + In-the-Red badge render.

---

## Phase 3 — Daily revamp (efficiency paycheck)

**Goal:** Daily pays the efficiency **Daily Score** (= shareable score), retire `500×streak`.
**Depends on:** P1.
**Server/DB (migration `daily_v2_scoring`):**
- `daily_sessions`: add `p_vowels int`, `p_reveals int`, `p_clean boolean` (no wrong letters),
  `p_first_solve boolean`. Track them in `daily_buy_letter` (vowel/wrong counters),
  `daily_reveal` (reveal counter), `daily_submit_guess` (first-attempt flag).
- Rewrite the win path in `_finalize_daily`:
  `eff = 1 + 0.25·clean + 0.25·(p_vowels=0) + 0.25·first_solve + 0.15·(p_reveals=0)`;
  `streak_mult = 1 + min(streak−1,10)×0.05`;
  `DailyScore = max(100, round(bankroll_left × eff × streak_mult))`;
  `_bank_credit(uid, DailyScore, 'daily_reward')` (replaces the `500×streak` 'daily_win').
  `game_results.score = DailyScore`.
- Keep streak/badges logic; only the payout changes. (Streak-break rule → P9.)
**Client:** Daily result modal shows the **score breakdown** (which bonuses hit) + share;
"+$X to your Cash." Update `reasonLabel` ('daily_reward').
**Reuses:** daily engine, `_finalize_daily`, `_daily_resolve_and_return`, result modal.
**Acceptance (SQL sim):** clean vowel-free first-solve with $700 left + 2-day streak →
≈ $1,347; messy solve → ~floor; fail → $0 + streak reset. Share string correct.

---

## Phase 4 — Cash Game / the Climb  ★ critical path

**Goal:** replace Arcade with the persistent forward-only **Climb** (par/bounty + heat, real Cash).
**Depends on:** P1, P2 (mid-puzzle loans).
**Server/DB:**
- `climb_sequence(position int PK, puzzle_id uuid)` — a fixed shuffle of all 720 puzzles
  (seed once, deterministic). `_climb_puzzle_at(pos)` reads it; auto-extends as puzzles are added.
- `profiles.climb_position int default 1`.
- `climb_state(user_id PK, position, puzzle_id, revealed_positions int[], incorrect_letters
  text[], attempts_remaining int default 3, heat_x100 int default 100, spent int default 0,
  active_powerups text[], state text 'active'|'stuck'|'done', updated_at)`.
- `_climb_bounty(puzzle)` = `round_to_10(0.65 × Σ distinct letter_cost)`.
- `climb_start()` → ensure state at current position; `_climb_board()` returns masked board +
  `{bounty, heat, attempts, spent, position, stuck}`.
- `climb_buy_letter(letter)` → debit real Cash via `_bank_credit(-cost,'climb_letter')`,
  `spent += cost`, reveal/incorrect; if can't afford & 0 attempts → `state='stuck'`.
- `climb_reveal()` (paid), and the power-up hooks land in P5.
- `climb_submit_guess(guess)` → on solve: `payout = round(bounty × heat)`,
  `_bank_credit(+payout,'climb_bounty')`, `climb_position++`, `heat = min(200, heat+10)`,
  load next puzzle, fresh state; on wrong: `attempts−−`, `heat=100`; if 0 attempts & broke →
  `stuck`.
- `climb_leave()` → clears heat (keeps position + cash).
- `get_climb_leaderboard(scope)` → rank by `climb_position` (Global / Group).
**Client:** new **Cash Game** screen (GameStore `climb` mode: reconcile/buy/reveal/guess),
showing **Bounty · Heat ×N · Attempts · Cash**; **mid-puzzle Take-a-loan** button when low;
"Stuck — borrow to finish / leave" panel; Climb position header. Retire arcade UI.
**Reuses/Replaces:** mirrors the arcade engine (arcade_runs → climb_state) and `_daily_board`;
**replaces** Arcade entirely (keep arcade tables until cutover, then drop).
**Slices:** (4a) sequence + state + start/board; (4b) buy/reveal/guess + bounty + heat +
position; (4c) stuck/loan + leave; (4d) client screen; (4e) Climb leaderboard.
**Acceptance (SQL sim):** solve cheaply → net positive, position++, heat ×1.1; brute-force →
net negative; wrong guess → attempt−1 + heat reset; out of attempts + broke → stuck → loan →
finish; leave → heat cleared, position persists; two users share puzzle #N.

---

## Phase 5 — Power-ups economy

**Goal:** the catalog — bought-with-Cash in Climb (mid-puzzle), earned-by-feats in Free Play.
**Depends on:** P4 (Climb hooks).
**Server/DB (migration `powerups_v2`):**
- `powerups(id, name, kind 'climb'|'blitz', effect_key, price)` seeded from the §6 catalog.
- `user_powerups(user_id, powerup_id, qty, pool 'cash'|'freeplay')` (rework existing table).
- `buy_powerup(id)` → `_bank_credit(-price,'powerup_buy')`, qty++ in `cash` pool.
- `climb_use_powerup(id)` → consume from `cash` pool; apply effect in `climb_state`:
  Half Off (cost×0.5 flag), Free Reveal (reveal best, no charge), Extra Attempt (+1),
  Insurance (refund `spent` on stuck), Heat Shield (no heat reset this puzzle),
  Double Down (bounty×2 this puzzle).
- Free Play: on feat (Blind Solve / Vowel-Free / Flawless / Clean Streak) award to `freeplay`
  pool; `freeplay_use_powerup` consumes there.
**Client:** power-up **shop** (Cash) + in-Climb **tray**; Free Play earn toast + FP tray;
seed new users 1 of each (freeplay pool).
**Reuses:** `user_powerups`, `_award_badge` pattern, climb engine.
**Acceptance:** buy Half Off → next letters half price; Insurance refunds on stuck; Double
Down doubles bounty; Free-Play feat awards to FP pool only (never spendable in Climb).

---

## Phase 6 — Challenge Builder + Groups

**Goal:** one configurable challenge (1v1/group, packs, wager/friendly, payouts, response
window) + persistent Groups with scoped leaderboards.
**Depends on:** P1 (P3 scoring reused).
**Server/DB (migration `challenges_v2` — replaces 1v1 schema):**
- `challenges(id, host_id, mode 'standard'|'blitz', category_filter text[], pack_size,
  wager, payout 'winner'|'top3'|'even', window_seconds, status 'open'|'settled'|'void',
  created_at, settles_at)`.
- `challenge_pack(challenge_id, position, puzzle_id)` — the shared seeded pack.
- `challenge_participants(challenge_id, user_id, paid bool, total_score, state, joined_at)`.
- `create_challenge_v2(...)`, `accept_challenge_v2(id)` (escrow ante), per-puzzle play
  (`challenge_play_*` over the pack, scored by the P3 efficiency formula or P7 blitz),
  `_settle_v2` (rank → payout structure; no-show forfeits ante to pot).
- **Groups:** `groups(id, name, owner_id, join_code)`, `group_members(group_id, user_id)`;
  `create_group`, `join_group(code)`, `get_my_groups`; group-scoped variants of the boards.
- **Spoiler-lock:** challenge board hides scores/answers until you've played (wagered).
- Notifications: reuse `_notify` for invite + settle (extend to N participants).
**Client:** **Challenge Builder** form (opponent person/group · categories · pack size · Blitz
toggle · wager/friendly · payout · response window); **Groups** create/join + group leaderboard
views; ranked **results card** (shareable).
**Reuses/Replaces:** generalizes the current 1v1 `challenges`/`challenge_plays` + escrow +
notifications; **replaces** the old create/accept/settle.
**Slices:** (6a) groups + group leaderboards; (6b) builder schema + create/accept + pack;
(6c) play + settle + payouts + spoiler-lock; (6d) builder UI + results card.
**Acceptance (SQL sim):** 3-player group pack, winner-take-all → pot to winner; top-3 split
math; no-show forfeits ante; friendly pays nothing; spoiler-lock hides until played.

---

## Phase 7 — Blitz

**Goal:** timed variant (one clock per pack) in Challenges + a Free-Play practice; time tools.
**Depends on:** P5 (time-tool power-ups), P6 (challenge packs).
**Server/DB:** blitz scoring `prize = base × combo × speed`; one pack clock (server start-ts,
client countdown, server validates like PvP Pressure); time-tool effects (+Time, Freeze, Skip,
Combo Shield, Auto-Vowel).
**Client:** countdown HUD, combo meter; Blitz toggle already in the Builder (P6); Free-Play
Blitz practice entry.
**Reuses:** the PvP-Pressure timer infra already built; combo idea from arcade `p_combo`.
**Acceptance:** pack clock counts down, combo grows/decays, miss = −time, total = Σ prizes;
time tools work; server rejects an over-time score.

---

## Phase 8 — Leaderboards & Profile

**Goal:** rebuild to 3 boards × Global/Group; move personal stats to a Profile page.
**Depends on:** P4 (Climb board), P6 (Group scope).
**Server/DB:** `get_wealth_leaderboard(scope, period 'week'|'all')` (week = net-worth gained —
track a weekly snapshot or diff `bank−loan` vs a Monday baseline); reuse `get_daily_leaderboard`,
`get_climb_leaderboard`; `get_profile_stats(uid)` (streak, win%, puzzles, climb pos, challenge
W/L, badges).
**Client:** rewrite `/leaderboard` to **3 boards (Wealth/Daily/Climb) × Friends-group/Global**,
Wealth defaults to This-Week; remove periods + sort menu + Arcade board; new **/profile** page;
contextual **"You placed #N today"** card after the Daily.
**Reuses:** `get_networth_leaderboard` (becomes Wealth), `get_daily_leaderboard`, badges.
**Acceptance:** boards render, scope toggle filters to a group, weekly Net-Worth-gained ranks
correctly, stats live on Profile (not the board), daily placement card shows.

---

## Phase 9 — Streaks & Badges

**Goal:** v2 streak rule + the new badge set.
**Depends on:** P3 (Daily payout) — can run parallel.
**Server/DB:** `_finalize_daily` — **break the streak only on a *missed* day, not a played
loss** (loss keeps the streak, just no win bonus); confirm freeze logic. Add badges:
`climb_50/100/500` (in `climb_submit_guess` on position milestones), `debt_free` (in
`repay_loan` when loan hits 0), `hustler` (10 challenge wins in `_settle_v2`).
**Client:** add the new badges to `badges.js`; surface on Profile.
**Reuses:** `_award_badge`, `user_badges`, `badges.js`, make-up calendar (built).
**Acceptance:** a played loss doesn't reset the streak; clearing a loan grants Debt-Free; #50
climb grants the milestone.

---

## Phase 10 — Anti-cheat, balance & polish

**Goal:** keep wagers fair, tune the economy, ship legal copy, optional bankruptcy.
**Depends on:** everything.
**Server/DB:** enforce spoiler-locks on wagered boards (P6); anomaly queries (impossible
efficiency/timing → flag); `declare_bankruptcy()` (wipe loan, reset Cash $1,000, mark +
cooldown); full constant tuning pass against telemetry (median Net-Worth growth/week).
**Client:** legal/firewall copy on the Cash + Shop screens; "flagged" handling; bankruptcy UI.
**Acceptance:** spoiler-lock holds on wagered packs; bankruptcy resets correctly; tuning notes
recorded; no real-money path to Cash exists.

---

## Cutover notes
- Arcade tables/functions stay live until **P4** ships, then are dropped.
- Old 1v1 challenge schema stays until **P6** ships, then replaced.
- `bank`/`loan` DB column names are kept throughout (UI says "Cash"); never renamed.
- Each phase ends with: migration synced to a `supabase-*.sql` note, memory updated if the
  player-facing model changed.
