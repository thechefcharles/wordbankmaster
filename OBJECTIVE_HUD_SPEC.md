# Objective & Standing HUD — Spec

**Goal:** A first-time player should always know two things while playing **any** mode:
1. **What am I trying to do?** (the objective)
2. **How am I doing right now?** (my progress, and — in challenges — my standing vs others)

…without the design slowing play down or killing the end-game reveal.

---

## The one decision that shapes everything

We show **direction, not the number.**

- Players always see their **objective** and their **live rank / ahead-or-behind** state.
- Players never see the **exact spend they need to beat** mid-game (that's what causes grinding/stalling).
- Exact standings are revealed only on the **results screen**.

This is already safe to build because the match data layer is **spoiler-locked**: during an active match, `matchInfo.opponents[]` exposes only `{ id, name, solved, state }` — never opponent spend or score (`get_match`, supabase-challenge-builder.sql:19–20). We add a *derived* directional rank server-side so the raw threshold never reaches the client.

---

## The universal metric: **Spent**

Every mode secretly scores the same way — *solve the puzzle, spend as little cash as possible.* We surface that one idea everywhere instead of the harder-to-grok "leftover bankroll = score."

> **Lower spend = better. Always.** That's the whole game, and it's literally the tagline ("Spend Less. Think More.").

---

## Three UI pieces

### A. Pre-game "How to win" card
A short, dismissable card shown the moment a mode starts, before the first puzzle. 3 lines: **Goal · How you win · The bar** (personal best for solo, "see if you're ahead" for challenges). New component, patterned on `Tutorial.svelte` (overlay + backdrop + Play button).

- **Solo modes** (daily, cash game, arcade, free play, makeup): shown **once per mode** (localStorage `wb_obj_seen_<mode>`), re-openable via a small **ⓘ** button on the board.
- **Challenges** (1v1 / group): shown **every time** you open a challenge to play (it carries the opponent/stakes context), with a "Got it" to start.

### B. In-game objective/standing strip
A compact, always-visible strip at the top of the board (extends the existing live-HUD area, +page.svelte:1590–1597). Two variants:

- **Solo:** `🎯 Solve cheap · Spent $X` + a faint **goal line** = your personal best where we have one.
- **Challenge:** the **directional standing strip**:

```
┌─────────────────────────────────────┐
│  🥈 2nd of 3   ·   Spent: $80        │   ← amber when behind
│  ▲ Spend less to take the lead        │
└─────────────────────────────────────┘
        …buy fewer letters, flips to…
┌─────────────────────────────────────┐
│  🥇 1st of 3   ·   Spent: $40        │   ← green + soft chime on the flip
│  ✓ You're in the lead                 │
└─────────────────────────────────────┘
```

You see **where you stand**, never the exact dollar to beat. The lead-flip is the reward moment. No number to grind to → no stalling.

### C. Spend meter + result tie-back
- The **Spent $X** readout becomes the hero metric on the board, shifting **gold → red** as it grows (makes "buying = costly" visceral). A small marker shows the goal line where one exists (solo personal best).
- The **results screen** (`MatchDetailModal.svelte`) gets a one-line banner that ties back to the goal: *"You solved for **$20** — that beat @bob's $100. You win **$120**."* (This is where exact numbers finally appear.)

---

## Per-mode behavior

| Mode | Objective card copy (Goal · Win · Bar) | In-game strip | Standing |
|---|---|---|---|
| **Daily** | Solve today's puzzle · Spend the least, leftover is your score · Beat your best ($X) | `🎯 Solve cheap · Spent $X` + goal line | Solo (personal best) |
| **Cash Game** | Keep climbing · Solve cheaply to grow your bankroll · Don't go broke | `Spent $X · Bankroll $Y` | Solo (bankroll growth) |
| **Arcade** | Survival run · Solve to keep your streak alive · Bigger streak = bigger payout | `Streak N · Spent $X` | Solo (best streak) |
| **Free Play** | Practice — no stakes · Just solve · — | `Spent $X` | None |
| **Makeup** | Make up <date>'s daily · Same rules — solve cheap · — | `🎯 Solve cheap · Spent $X` | Solo |
| **1v1** | Beat @bob · Whoever solves spending **less** wins the pot ($Y) · You'll see if you're ahead | directional strip | **Live rank + ahead/behind** |
| **Group** | Top the group · Least spent to solve ranks 1st · Pot = everyone's spend | directional strip | **Live rank of N** |

---

## Back-end changes

### 1. Directional standing for matches (spoiler-safe)
Add a `standing` object to the match board payload returned by `_match_board` / `get_match` (consumed in `reconcileMatchBoard`, GameStore.js:694–710). Computed **server-side**, exposing only direction — never opponent raw numbers:

```jsonc
standing: {
  field_size: 3,            // total players in the match
  finished: 1,              // opponents who've locked in (state='done')
  rank: 2,                  // my projected rank among (me + finished rivals); null if nobody finished yet
  state: "behind",          // "lead" | "behind" | "tied" | "first_to_play"
}
```

- Comparison basis = the same efficiency score `_match_settle` uses (total_score / spend).
- **Phase 1** computes this cleanly for `pack_size = 1` (1v1 and single-puzzle groups): my spend-so-far vs each *finished* rival's locked spend → rank + state.
- **Phase 2** extends to multi-puzzle packs: projected rank by current `total_score` across solved puzzles, labelled "so far."
- If no rival has finished yet → `state: "first_to_play"` → strip shows *"🚩 You're first — set the bar."*
- Raw opponent spend/score stays hidden (existing spoiler-lock unchanged).

### 2. Personal best for solo goal line (Phase 2, optional)
A lightweight `get_personal_best(mode, category)` (or fold into the existing `daily_start`/`climb_start` payloads) returning the player's lowest winning spend, to render the solo goal-line marker. Derivable from the Play Log (`game_results.spent` where outcome='won'). If absent, the strip simply omits the goal line.

---

## Front-end changes

| Artifact | Change | Ref |
|---|---|---|
| `ObjectiveCard.svelte` (new) | Pre-game card; props `{ mode, ctx }`; pattern from `Tutorial.svelte` | render before board after start RPC resolves |
| `StandingStrip.svelte` (new) | Directional strip; props `{ standing, spent }`; color + flip animation + chime | board top, in the `isMatch` block (+page.svelte:1596–1597) |
| `+page.svelte` | Mount ObjectiveCard on each mode start (handlers at :620 daily, :653 climb, :683 freeplay, :713 match); make `Spent $X` the hero in live HUD (:1590–1597); add ⓘ re-open button | |
| `GameStore.js` | Surface `standing` from match board into `$gameStore` (reconcileMatchBoard :694–710) | |
| `MatchDetailModal.svelte` | Add the "you solved for $X — beat $Y" tie-back banner | :1–111 |
| `sound.js` | Add a `lead` cue for the rank-flip (reuse `fx`) | |

---

## Build sequence

1. **Objective cards (all modes)** + the **Spent-as-hero** spend meter with gold→red. Pure front-end, immediate clarity win. *(No back-end.)*
2. **1v1 directional standing**: add `standing` to `_match_board` (pack_size=1), build `StandingStrip`, wire the lead-flip + chime. *(The headline feature.)*
3. **Group / multi-puzzle packs**: extend `standing` to projected rank "so far"; results tie-back banner.
4. **Solo goal line**: personal-best lookup + marker. *(Polish.)*

---

## Edge cases

- **You play first (async):** no rival finished → `first_to_play` → "set the bar," no rank shown.
- **Everyone already finished:** show your final projected rank live; nothing leaks (their numbers still hidden until results).
- **Ties:** `state: "tied"` → "Dead even — spend less to pull ahead."
- **Solo modes / Free Play:** no standing; objective card + spend meter only. Free Play shows no goal line (no stakes).
- **Spoiler safety:** the client only ever receives `{rank, state, field_size, finished}` for opponents mid-game — never a spendable number. The lead-flip reveals the threshold only *after* you've already crossed it, so there's nothing to grind toward.
