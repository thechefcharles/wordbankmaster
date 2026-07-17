# Challenge Results Modal + Builder Tweaks — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Ship the three approved challenge changes: an "All Categories" builder chip, removal of the yellow spending bar, and a redesigned results modal (verdict + single pot line + kept-score head-to-head + per-puzzle ✓/✗, cutting the gold band).

**Architecture:** All client except one small server add (`solved_positions` for the ✓/✗ strip). The results modal is `MatchDetailModal.svelte`, fed by `get_match_detail`. Per-participant `score` (=`total_score`=kept bounty) is ALREADY in the payload (just unused); only per-puzzle solve status is new.

**Tech Stack:** SvelteKit 2.16 (Svelte 5); Supabase Postgres (dump→transform→rollbacktest→apply); svelte-check + build.

## Global Constraints

- Match-mode only. Daily / Cash Game / Free Play unchanged; every change gated on `isMatch`/match data.
- Verify with `npm run check` (svelte-check — catches reactive ReferenceErrors that `npm run build`/Vite miss) AND `npm run build`. Known-pre-existing-OK: `points.test.js:31`, `profile/+page.svelte:408` a11y warning. No NEW errors.
- Server change follows the dump→transform→rollbacktest→apply pattern; commit as `supabase-*.sql`.
- Commit messages end with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

### Task 1: "All Categories" chip in the builder

**Files:** Modify `src/routes/+page.svelte` (category picker `~3944-3968`; state `mbCategories` `~2031`; `toggleCategory` `~2157`).

- [ ] **Step 1: Add the chip + logic**

Render an "All Categories" chip as the FIRST option in the picker (`~3944-3968`), styled like the existing `.ch-catrow` toggles. Selected state = `mbCategories.length === 0` (empty = any = all). Behavior:
- Tapping "All Categories" sets `mbCategories = []` (clears individual picks).
- Tapping an individual category continues to use `toggleCategory` (which adds/removes it); when any are selected, "All Categories" renders unselected; when the list empties, it renders selected.
- Keep the hint line (`~3965-3967`) or fold its meaning into the chip. Do NOT change the submit flow — empty `mbCategories` already = all via `_pick_casual_pack`.

- [ ] **Step 2: Verify** — `npm run check` (zero new) + `npm run build`. Confirm empty selection shows the chip active and picking a category deactivates it. Commit: "Challenges: explicit All Categories chip in the builder".

---

### Task 2: Remove the yellow spending bar

**Files:** Modify `src/routes/+page.svelte` (markup `4778-4787`; CSS `.ante-bar`/`.ante-fill` `~8480-8496`; `class:ante-empty` `:4664`).

- [ ] **Step 1: Remove the bar**

Delete the `{#if isMatch && matchLive}<div class="ante-bar"><span class="ante-fill" .../></div>{/if}` block (`4778-4787`) and the `.ante-bar` + `.ante-fill` CSS rules (`~8480-8496`). Check `class:ante-empty={isMatch && matchLeft <= 0}` on `.bounty-panel` (`:4664`): if `.ante-empty` CSS only dimmed/styled the now-removed bar, remove the class binding and its rule; if it also styles the panel meaningfully (e.g. a low-bounty warning tint that's still wanted), keep it. Report which.

- [ ] **Step 2: Verify** — `npm run check` (zero new) + `npm run build`; confirm no dangling `.ante-*` references (grep). Confirm Daily/Cash Game/Free Play unaffected (the bar was match-gated). Commit: "Challenges: remove the yellow bounty-spend bar during match play".

---

### Task 3: Server — per-puzzle solve tracking for the ✓/✗ strip

**Files:** Create `supabase-match-solved-positions.sql`. Touches live `_match_resolve_and_advance`, `get_match_detail`.

**Interfaces — Produces:** `get_match_detail().participants[].solved_positions int[]` consumed by Task 4.

- [ ] **Step 1: Column + append-on-solve**

`ALTER TABLE public.challenge_participants ADD COLUMN IF NOT EXISTS solved_positions int[] NOT NULL DEFAULT '{}';`
This is a MATCH-LEVEL accumulator — do NOT add it to any per-puzzle reset list. Dump live `_match_resolve_and_advance`; in its WIN path (`v_won` true), in BOTH econ branches AND both final/non-final sub-branches, append the just-solved `cp.position` to `solved_positions` in the participant UPDATE:
`solved_positions = array_append(solved_positions, cp.position),`
(A folded puzzle goes through `_match_do_fold`, which does NOT append — so folds correctly stay ✗.)

- [ ] **Step 2: Expose in get_match_detail**

Dump live `get_match_detail`; in the `participants` jsonb_agg, add `'solved_positions', t.solved_positions` and include `cp.solved_positions` in the inner `SELECT ... FROM challenge_participants cp` subquery. Purely additive.

- [ ] **Step 3: Rollback-test** — seed a 3-puzzle match; solve puzzles 1 and 3, fold puzzle 2; assert `solved_positions = {1,3}` and `get_match_detail` returns it; a fully-solved player → `{1,2,3}`. `BEGIN…ROLLBACK`. (If full seeding impractical, compile-in-transaction + structural assertion the append is in the win path only; say so.)

- [ ] **Step 4: Apply + commit** — `psql -f supabase-match-solved-positions.sql`; confirm live greps. Commit: "Challenges: track solved puzzle positions + expose in match detail".

---

### Task 4: Redesign the results modal

**Files:** Modify `src/lib/components/MatchDetailModal.svelte` (whole file, 344 lines).

**Interfaces — Consumes:** existing `participants[].{is_me,name,rank,solved,score,spent,net,elapsed_seconds,state}`, `match.{pack_size,wager,status}`, `pack[].{position,category,phrase}`, and Task 3's `participants[].solved_positions`.

- [ ] **Step 1: Rework the template + reason logic**

Redesign per the spec (verdict → pot line → kept-score head-to-head → per-puzzle ✓/✗), match-only. Concretely:
- **Header** (`~94-107`): keep `⚔ {title}` + "{pack_size} puzzles · winner-take-all/podium". Remove the "$X buy-in" fragment from the sub-line (the pot line carries money).
- **Verdict block** (replaces `.md-outcome` `~109-117`): a big **VICTORY / DEFEAT / TIE** headline, color-coded from `iWon`/`isTie`/`winner`, with a one-line reason. Reuse/repurpose the existing derived flags. Prefer a solve-count reason when solves differ (`me.solved` vs `winner.solved`), else a kept/speed reason (you already have `sameSpend`/`speedGap` — reframe to kept). This REPLACES the `tieback` gold band's role.
- **Pot line** (new, only when `wagered && status==='settled' && !noSolve`): a single clearly-labeled real-money line from `me.net` — `+$500` "Pot won" / `−$500` "Buy-in lost". Friendly (`!wagered`) → "Friendly — no stakes" or omit.
- **Head-to-head** (`.md-standings` `~123-146`): keep two rows + the `.md-row.me` highlight, but change the meta (`~135-143`) to lead with **Kept ${p.score}** (higher = better) instead of "${p.spent} spent"; keep `solved X/N` and `fmtSecs(elapsed_seconds)`; keep the per-row `net` only if you want it secondary (the pot line already shows it — consider dropping from the row to avoid repeat). Winner gets the medal/crown (existing `.md-rank`).
- **Per-puzzle strip** (`.md-pack` `~148-163`): for each `pk`, after the phrase add a ✓/✗ per participant: ✓ when `pk.position` ∈ that player's `solved_positions`, else ✗. Show `me` then `opp` (label with initials or the medal color). GRACEFUL FALLBACK: when every participant's `solved_positions` is empty/absent (pre-existing match), render the current plain phrase list with NO marks.
- **Cut** the gold summary band: remove the `.md-tieback` render (`~119-121`); either delete the `tieback` computed (`~50-75`) or repurpose its logic into the verdict reason. Remove `.md-tieback` CSS (`~250-260`).
- Keep the close/overlay/actions.

- [ ] **Step 2: CSS**

Add styles for the verdict block (large, color-coded win/loss/tie), the pot line, the ✓/✗ marks (green check / dim cross). Remove the now-dead `.md-tieback` rule and the `you spent` label styling if orphaned. Keep the dark neon-arcade token palette; do not introduce the removed amber "underline" look under the money.

- [ ] **Step 3: Verify** — `npm run check` (zero new) + `npm run build`. Read through: verdict shows correct win/loss/tie + reason; single pot line; head-to-head shows Kept (not spent as headline); per-puzzle ✓/✗ when data present, plain list when not; no gold band; friendly matches render sensibly (no pot line). Commit: "Challenges: redesign results modal — verdict, single pot line, kept-score, per-puzzle ✓/✗".

---

## Self-Review notes

- **Spec coverage:** All Categories (T1), remove spending bar (T2), results redesign (T4) with its server data (T3). ✔
- **`score` already in payload** → head-to-head kept-score needs no server change; only ✓/✗ does (T3). ✔
- **solved_positions is a match-level accumulator** (never per-puzzle-reset) — appended only on solve, so folds stay ✗. ✔
- **Graceful fallback** for pre-existing matches (empty solved_positions → plain phrase list). ✔
- **No mode leakage:** every change gated on match data / `isMatch`. ✔
