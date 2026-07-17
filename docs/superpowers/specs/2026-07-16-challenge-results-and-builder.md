# Challenge Results Modal + Builder Tweaks — Design Spec

**Date:** 2026-07-16
**Source:** Playtest feedback + approved redesign discussion.

## Goal

Three approved changes to 1v1 challenge (`gameMode:'match'`) UX:
1. Add an explicit **"All Categories"** option to the challenge builder's category picker.
2. Remove the **yellow spending bar** (`.ante-fill`) that recedes during match play.
3. **Redesign the challenge results modal** (`MatchDetailModal.svelte`) to fix money-confusion + redundancy.

## Global constraints

- Scoped to match mode. Daily / Cash Game / Free Play unchanged.
- Server authoritative; the modal only reflects `get_match_detail` data.
- svelte-check must be clean (no new errors); build passes.

---

## 1. "All Categories" button (builder)

**Current:** Builder Step 2 (`+page.svelte:3944-3968`) shows a multi-select of the 12 `CATEGORIES` labeled "Categories (optional)". Selecting **none** = "Any category" (draws the pack from all categories via `_pick_casual_pack` with `p_categories='{}'`). The all-categories behavior exists but is invisible/implicit; the hint only reads "Any category" when zero are selected.

**New:** Add an explicit **"All Categories"** chip at the TOP of the picker.
- It represents the "any/all" state (empty `mbCategories`), selected/highlighted by default.
- Tapping it clears any individual selections (back to "all").
- Tapping an individual category deselects "All Categories" (and adds that category, as today).
- When ≥1 individual category is selected, "All Categories" is unselected; when the selection is empty, "All Categories" shows selected.
- No change to the underlying flow (`mbCategories` → `createMatch({categories})` → `create_match(p_categories)` → `_pick_casual_pack`); empty array already = all.

## 2. Remove the yellow spending bar

**Current:** `+page.svelte:4778-4787` renders `.ante-bar` > `.ante-fill` (gold gradient `#fbbf24→#fde047`, `width = matchLeft/budget %`) — a bar that shrinks as bounty is spent, match-only. CSS at `~8480-8496`. The bounty-panel also carries `class:ante-empty={isMatch && matchLeft <= 0}` (`:4664`).

**New:** Remove the `.ante-bar`/`.ante-fill` markup block and its CSS. Review `ante-empty` — if it only styled the bar's empty state, remove it too; if it also does something else useful on the panel, keep that behavior. No other mode touches these (match-gated).

## 3. Results modal redesign (`MatchDetailModal.svelte`)

**Problems today:** (a) two different "moneys" blurred — the ±$500 pot P&L (real cash) vs the per-puzzle bounty "spent" (play-money, less = better); (b) it leads with **spent** (inverted: lower is better) instead of the **score** that actually ranks players (score = `total_score` = leftover bounty, higher = better; ties broken by time); (c) it buries the real reason (solve count); (d) it repeats "you spent $X" three times (hero, gold band, row).

**New layout (top→bottom):**
1. **Header** (keep): `⚔ @opponent` + "N puzzles · winner-take-all". (Drop the "$500 buy-in" from here — the pot line below carries it.)
2. **Verdict block**: big **VICTORY / DEFEAT** (color-coded, replaces the raw −$500 hero), with a one-line reason derived from the standings (e.g. "Flactivate solved 3 — you got 2", or on equal solves "Flactivate kept more" / "faster on the tiebreaker").
3. **Pot line**: the ONLY real-money line — `+$500` / `−$500` clearly labeled ("Pot won" / "Buy-in lost"). For a friendly (wager 0) show nothing or "Friendly — no stakes".
4. **Head-to-head scoreboard**: two rows, winner marked (👑/rank medal), each showing `name · solved X/N · Score $KEPT · m:ss`. Frame the money as **Kept** (= `score`/`total_score`, higher = better), NOT "spent". Optional subtle score-comparison bar. Keep the current `.md-row.me` highlight but DROP the gold summary band entirely (kills the redundancy + the "yellow line under money").
5. **Per-puzzle strip**: `# · category-icon · "phrase"` with a **✓/✗ per player** (who solved each). Requires per-puzzle solve data (see server change). When that data is absent (pre-existing matches), fall back to the current phrase list with no marks.
6. **Actions** (keep whatever exists): Rematch / Close.

**Cut:** the gold `.md-tieback` summary band (lines 50-75 compute + 119-121 render + 250-260 CSS); the "spent" framing as the headline; the triple-repeat of spent.

**Copy:** "Kept" for the score (leftover bounty). Keep solve time (tiebreaker). "Spent" may appear as a de-emphasized secondary detail if useful, but is not the headline.

### Server support for the ✓/✗ strip

`get_match_detail` currently returns per-participant totals + a `pack` (position/category/phrase) but no per-puzzle solve status. Add:
- `challenge_participants.solved_positions int[] default '{}'` — a **match-level accumulator** (NOT reset per puzzle): append `position` in `_match_resolve_and_advance`'s win path (every solve, both econ branches, final + non-final). Never reset mid-match (only defaults at match start).
- Expose `'solved_positions', t.solved_positions` per participant in `get_match_detail`.
- Client renders ✓ when a pack position ∈ that player's `solved_positions`, else ✗; when all participants' `solved_positions` are empty (old match), render the plain phrase list (no marks).

## Testing

- svelte-check + build clean for all client changes.
- Server: rollback-test that solving pack puzzles appends the right positions to `solved_positions`; `get_match_detail` returns them; a folded puzzle's position is NOT appended.
- Visual: the redesigned modal shows verdict + single pot line + kept-score head-to-head + per-puzzle ✓/✗; no gold band; builder shows an "All Categories" chip selected by default; no spending bar during match play.

## Out of scope

- Daily / Cash Game / Free Play.
- Group (3+) results layout beyond what generalizes (rows already support N participants).
- Any economy/scoring change (only the *presentation* of score changes: spent → kept).
