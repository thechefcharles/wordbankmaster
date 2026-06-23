# WordBank — Stats & Leaderboards reference

Canonical map of every stat + leaderboard, how each is computed, and how the game
modes feed them. (No loans — Net Worth = your Cash balance = `profiles.bank`.)

## Data sources
1. **`game_results` (Play Log)** — one rich row per completed game, every mode. The spine.
   Columns: outcome, game_mode, solved_count, spent, earned, net, multiple_x100, category,
   match_id, opponent_id, group_id, rank, pot, wager.
2. **`profiles`** — `bank` (your Cash / Net Worth), `current_win_streak`, `highest_win_streak`,
   equipped_title/color. (`loan`, `total_games_*`, `total_cash_*`, `total_puzzles_correct` are
   DEAD columns — not written; all live stats are computed from the Play Log.)
3. **`climb_state`** — Cash Game position + heat.
4. **`category_stats` / `user_badges`** — collection.

## Profile stats (`get_profile_stats` / `get_public_profile`)
| Stat | Calc | Source | Modes |
|---|---|---|---|
| Net Worth / Cash | `bank` | profiles | all |
| Day / Best streak | consecutive daily wins | profiles | Daily |
| Daily win rate | daily won ÷ daily played (Play Log) | Play Log | Daily |
| Puzzles solved | `Σ solved_count` | Play Log | daily, cash game, challenge, makeup |
| Furthest | `climb_state.position` | climb_state | Cash Game |
| Challenge W-L-T | count by outcome (mode=challenge) | Play Log | Challenges |
| Avg / Best multiple | avg/max `multiple_x100` | Play Log | daily, cash game, challenge |
| Lifetime earned / spent | `Σ earned` / `Σ spent` | Play Log | all paid |
| Badges / Category levels | user_badges / category_stats | — | all |

## Leaderboards
| Board | Ranks by | Source | Scope |
|---|---|---|---|
| **Daily** | today's daily score (= net) | Play Log (daily, today) | friends/global/group |
| **Efficiency** | best multiple (week/all) | Play Log multiple_x100 | ↑ |
| **Cash Game** | furthest position | climb_state | ↑ |
| **Challenges** | wins + pot won (week/all) | Play Log challenge rows | ↑ |
| **Wealth** | Cash (week = gain via networth_snapshots) | profiles.bank | ↑ |
| Group → Compete | in-group challenge W / played | challenge_participants | one group |
| Head-to-head | W-L-T vs an opponent | Play Log by opponent_id | per-player |

Legacy/unused: `get_daily_leaderboard` (period/order-by) — superseded by `get_daily_board`.

## How modes feed the system
- **Daily** → Daily board, streak, puzzles_solved, reward→Wealth, multiple→Efficiency.
- **Cash Game** → position→Cash Game board + "Furthest", bounty→Wealth, multiple→Efficiency. Forward-only, not farmable.
- **Challenges** → W-L-T + pot→Challenges board + group Compete + H2H, net→Wealth, multiple→Efficiency.
- **Make-up** → puzzles_solved + History + Efficiency; EXCLUDED from Daily board & streak.
- **Arcade / Free Play** → arcade has its own board; Free Play = broke-safe trickle (self-contained).

## Cash Game seeding
- `climb_sequence(position, puzzle_id)` — a **fixed shuffle of 720 puzzles** (`ORDER BY md5(id)`),
  **identical for everyone**, forward-only. `_climb_puzzle_at(position)` returns the rung.
- Everyone starts at **position 1**; each puzzle solved once (income bounded).
- Pool is now **1,200** puzzles but the ladder snapshot is **720** → ~480 unused; ladder ends at 720.
  KNOB: re-seed to the full pool / loop for longer runs.
