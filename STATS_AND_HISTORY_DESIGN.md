# WordBank — Stats, Results, History & Leaderboards (design)

> Status: design draft for review. Goal: decide WHAT we track, HOW results are
> shown + revisited, and WHAT pages/flows we need — across the whole app and per
> game mode. Builds on what already exists (don't rebuild settled gameplay).

---

## 0. The one foundational decision

Almost everything below hinges on **one change**: turn the thin `game_results`
table (today: `won, bankroll_left, game_mode, score`) into a **rich, unified Play
Log** — one row per completed game, any mode, with the same columns everywhere.

That single table becomes the engine for: career stats, the History page + all its
filters, 1v1 records, and most leaderboards. Get this right and the rest is UI.

### Proposed `game_results` (v2) columns
| Column | Meaning |
|---|---|
| `id, user_id, mode, played_at, finished_at` | who/when. mode ∈ daily/climb/arcade/freeplay/challenge |
| `puzzle_id, category` | what was played (null/array for multi-puzzle packs) |
| `outcome` | won / lost / tie |
| `solved_count, puzzle_count` | 1/1 for solo; e.g. 3/5 for a pack |
| `spent` | total Cash spent (letters + reveals + power-ups) |
| `earned` | bounty/reward/pot-share paid out |
| `net` | earned − spent (the Cash result) |
| **`multiple_x100`** | **return multiple = earned ÷ spent ×100 — the headline flex stat** |
| `time_ms` | solve time (for tiebreaks + "fastest" stats) |
| `clean, first_try, no_reveals, no_vowels` | quality flags (already computed for Daily) |
| `match_id, opponent_id, group_id, rank, field_size, pot, wager` | competitive context (null for solo) |

> Today the per-mode session tables (`daily_sessions`, `arcade_runs`,
> `challenge_participants`, etc.) already hold most of these numbers at settlement
> — we just need each mode's `_finalize/_settle` to write one enriched row here
> instead of the current 4-field stub.

---

## 1. Overall (career / player-level) stats

Surfaced on **your profile** + the new **History** page. Pulled from the Play Log
aggregate + `profiles`.

- **Identity/wealth:** Net Worth (Cash − loan), lifetime Cash earned, lifetime spent.
- **Volume:** games played, puzzles solved, win %, days active.
- **Efficiency (the brand):** **average return multiple**, best-ever multiple,
  lifetime "cleanest solve" (lowest spend on a hard puzzle).
- **Streaks:** current/longest daily streak (have), current/longest arcade streak (have).
- **Competitive:** challenge W-L-T, win %, biggest pot won, current rival (most-played opponent).
- **Collection:** badges earned / total, categories mastered, titles unlocked.
- **Per-category:** solves + win% + best multiple per category (have `category_stats`, extend it).

---

## 2. Per-game-type stats

### Daily (the paycheck)
- Per play: bounty, spent, **net (profit)**, multiple, time, quality flags, streak day #.
- Aggregate: streak, perfect weeks/months (have calendar), avg daily profit, daily win %,
  "ghost" percentile vs field (have), best daily multiple.
- **Archive:** every past daily — date, answer, your result — revisitable (gap today).

### Climb / Cash Game (the wealth engine)
- Per session: furthest position, bounty earned, spent, net, peak heat, power-ups used.
- Aggregate: best position ever, total Climb earnings, longest heat streak, avg multiple.
- **Climb log:** position-by-position history of a run (gap today).

### Arcade / Gauntlet (survival)
- Per run: peak bankroll (banked), furthest rung, puzzles solved, multiplier reached, power-ups earned.
- Aggregate: best run ever, total banked, avg furthest. (Leaderboard exists; **run archive is a gap**.)

### Free Play (broke-safe grind)
- Light: puzzles solved, trickle earned today (capped $300), categories practiced.
- Mostly excluded from competitive stats by design — keep it that way.

### Challenges / Matches (PvP)
- Per match: opponent/group, pack size, your solved/spent/rank, pot, payout, **per-puzzle breakdown**.
- Aggregate: W-L-T overall, by opponent (H2H), by group, win %, avg finish rank, biggest pot.
- **Per-challenge detail must persist and be revisitable** (data persists; UI is the gap).

### Groups
- Member standings (have: Net Worth) **+ group-scoped competitive stats** (gap):
  group challenges played, per-member W-L within the group, "group MVP," group activity feed.

---

## 3. Results display + tracking

### Daily result
- **Immediately:** keep the current result modal (medal, profit, ghost-vs-yesterday, friend placement).
- **Add:** "Saved to History" affordance; one-line "today's multiple Nx" headline; share card.
- **Later:** appears in History → Daily, tappable to re-see the answer + your breakdown.

### Challenge result — the big one
- **Right when it finishes (you're done):** immediate "you're in — settling when everyone
  plays" card (have) → once settled, a **rich result card**: final standings, your rank,
  pot won, per-puzzle head-to-head (you vs them: spent/solved/time per puzzle).
- **Revisit later:** two doors —
  1. **Challenge inbox** "Results" button (have the button → upgrade to the rich detail view).
  2. **History → Challenges** → tap any past match → same detail view, forever.
- **Notification:** "Your challenge vs @X settled — you won $Y" (new notification type).

---

## 4. History + filters (the missing hub)

New page **`/history`** — the unified Play Log, reverse-chronological, infinite scroll.

**Each row:** mode icon · title (puzzle/opponent/group) · result chip (won/lost/tie) ·
net ±$ · multiple · date. Tap → detail view (solo breakdown or challenge head-to-head).

**Filters (stackable):**
- **Mode:** Daily / Climb / Arcade / Challenges / (Free Play hidden by default)
- **Result:** Won / Lost / Tie
- **Category:** any category
- **Opponent / Group:** specific friend or group (this is also how you reach a H2H view)
- **Date range:** this week / month / all-time / custom
- **Sort:** newest · biggest net · highest multiple · fastest

Backed by `get_history(filters, cursor)` over the enriched `game_results`.

---

## 5. Leaderboards / personal / group / 1v1 — tracking, storage, management

| Scope | Source | Where shown | Status |
|---|---|---|---|
| **Global / Friends / Group leaderboards** (Wealth, Daily, Climb, Arcade) | existing leaderboard RPCs over profiles + game_results | `/leaderboard` (3 tabs + scope) | ✅ exists |
| **Personal stats** | Play Log aggregate + profiles | `/profile` | ✅ exists, enrich with multiple + H2H summary |
| **1v1 head-to-head** | `get_head_to_head(opponent_id)` over competitive Play Log rows | friend's public profile + History filter | ❌ new |
| **Group competition** | `get_group_standings(id)` + group challenge rows | `/groups/[id]` new "Compete" tab | ❌ new (only net-worth standings today) |
| **Challenge leaderboard** | aggregate challenge W/pot from Play Log | new `/leaderboard` "Challenges" tab | ❌ optional |

**1v1 (head-to-head):** derive from competitive Play Log rows filtered by `opponent_id`.
`get_head_to_head(uid, opponent)` → `{ wins, losses, ties, win_pct, avg_multiple_each,
biggest_pot, last5[] }`. No new table needed — it's a query over the Play Log.

**Group:** add a `/groups/[id]` **Compete tab**: in-group challenge standings (W-L per
member vs the group), recent group matches, group MVP. Net-worth standings stay as the
"Wealth" tab.

**Management/storage notes:** Play Log is append-only (never mutated post-settlement) →
clean audit + cheap history. Leaderboards stay as aggregate RPCs (no materialized tables
yet; revisit if slow). `bank_ledger` remains the money audit trail (separate concern).

---

## 6. Activity feed (optional, high-engagement)

New `activity` events table + `/` feed strip or `/activity` page: "@friend won the Daily
(4.2x)", "your challenge vs @X settled", "@Y joined the group", "you unlocked a badge",
"@Z beat your daily score." Powers richer notifications too (today only friend-req +
challenge-invite exist). Lower priority than History + Challenge detail.

---

## 7. Pages / components — what we need

**New pages**
- `/history` — unified Play Log + filters (§4). **Highest value.**
- `/history/[id]` (or modal) — game/challenge detail; challenge = per-puzzle head-to-head. **Highest value.**
- `/u/[username]` — public profile (others' stats + your H2H vs them + challenge button).
- `/activity` (optional) — feed.

**Upgrades to existing**
- `/profile` — add avg/best multiple, challenge W-L-T, "rivals" row.
- `/groups/[id]` — add **Compete tab** (challenge standings, group history, MVP).
- `/leaderboard` — optional Challenges tab; link rows → public profiles.
- Challenge inbox "Results" → open the new rich detail view.
- Result modals — "Saved to History" + multiple headline + better share card.

**New RPCs**
- `get_history(filters, cursor)`, `get_game_detail(id)`, `get_match_detail(id)`,
  `get_head_to_head(opponent)`, `get_group_standings(id)`, `get_public_profile(username)`.

**Schema work**
- Enrich `game_results` (§0) + make every `_finalize/_settle` write one row.
- Extend `category_stats` with best multiple + win%.
- (Optional) `activity` events table.

---

## 8. Suggested build order

1. **Enrich the Play Log** (§0) + backfill writers — unlocks everything. *(foundation)*
2. **`/history` + filters** (§4) — the hub players will ask for first.
3. **Challenge detail view** (§3) revisitable from inbox + History — closes the most-felt gap.
4. **Head-to-head** (§5) + **public profile** (§7).
5. **Group Compete tab** (§5).
6. **Activity feed** (§6) — last, highest-engagement polish.

*Draft — react/redline and I'll turn the approved slice into migrations + pages.*
