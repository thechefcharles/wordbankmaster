# Challenges Polish Punch-List

Scouting audit of the **1:1 (H2H)** and **Group / Compete** Challenge flows (read-only,
2026-07-12). Ordered most-severe first. Money/correctness items were traced by the audit
but should each be **confirmed with a BEGIN/ROLLBACK test before fixing**.

Live engine is `match_*` / `_match_*` (tables `challenge_matches` + `challenge_participants`,
`econ_v = 2`). The `challenge_*` / `_challenge_*` family is dead legacy (see T5).

---

## 🔴 Tier 1 — Money & correctness bugs (fix first)

- [ ] **1. `decline_match` refunds bounty, not stake** — exploit. Refund credits
  `COALESCE(start_budget, GREATEST(wager,500))`; `start_budget` is the puzzle bounty
  (~$1.2–3k) while the host was only debited `stake = wager` (min $500). Decline → host
  pockets the difference. `_match_settle` correctly uses `coalesce(stake,…)`.
  **Fix:** refund `COALESCE(stake, wager)`. *(RPC `decline_match`)*
- [ ] **2. `match_fold` never updated for `econ_v=2`** — uses OLD absolute-overwrite
  semantics (`total_score = v_left`), so folding a later puzzle in a multi-puzzle match
  erases earlier winnings and advances with a $0 budget. `_match_resolve_and_advance`
  accumulates + resets bounty. **Fix:** add an `econ_v=2` branch mirroring it.
  *(RPC `match_fold`; single-puzzle matches unaffected)*
- [ ] **3. Reduced-accept charges the wrong balance** — UI gates on `netWorth = bank − loan`
  and shows a capped buy-in, but `accept_match` checks `profiles.bank`. A loan-holder
  (bank ≥ wager, netWorth < wager) is shown "capped" yet debited the full wager.
  **Fix:** align UI + RPC on one balance definition. *(`+page.svelte:2242,2260-2277`;
  RPC `accept_match(uuid,boolean)`)*
- [ ] **4. Group owner leaving orphans the group** — `leave_group` doesn't reassign
  `owner_id`; every management RPC gates on `owner_id = uid`, so remaining members can
  never rename / kick / approve joins. **Fix:** reassign ownership to the oldest remaining
  member on owner-leave. *(RPC `leave_group`)*
- [ ] **5. Paid non-finishers forfeit invisibly** — `_match_settle` iterates only
  `state='done'`; a player who accepted+paid but didn't finish gets no `_notify` and no
  `_log_game_result`. Money loss never appears in history/leaderboards.
  **Fix:** include paid `active` participants with a DNF/lost result + notification.
- [ ] **6. No scheduled settlement** — `get_my_matches` is the only sweeper (settles
  `status='open' AND settles_at < now()`); no pg_cron. Wagers stay escrowed and
  refund/settled notifications never fire until a participant next opens the list.
  **Fix:** scheduled sweeper (pg_cron or edge cron → `settle_expired_matches()`).

## 🟠 Tier 2 — Money/score shown wrong (visible, not exploitable)

- [ ] **7. Multi-puzzle "spent"/"budget" inflated** — `get_match` / `get_match_detail`
  compute `spent = start_budget − bankroll`, mixing accumulated multi-puzzle budget vs
  single-puzzle bankroll. **Fix:** `sum(per-position bounty) − total_score`.
- [ ] **8. Pot chip shrinks as opponents finish** — `matchPot = wager × (opponents+1)`
  and `_match_board.opponents` excludes `done`. Opponent finishes → "Pot $1,000"→"$500".
  **Fix:** compute pot server-side from `sum(stake)` over all paid participants.
  *(`+page.svelte:642-643`)*
- [ ] **9. PIN confirm always "Winner takes all"** — `mbPayout='winner'` never reassigned;
  group pots actually split 70/30 or 60/30/10. **Fix:** derive from field size / reuse
  `potSummary`. *(`+page.svelte:2020,2171`)*
- [ ] **10. Compete "recent matches" shows 🏆 on no-winner/ties** — `get_group_standings`
  picks `ORDER BY total_score DESC LIMIT 1` with no `>0`/tie guard; `GroupsPanel.svelte:379`
  renders it unconditionally. **Fix:** `winner=null` when top is 0 or tied.
- [ ] **11. Leaderboard shows title as raw UUID + invalid color** —
  `get_challenge_leaderboard` returns cosmetic **ids**, not values (siblings join
  `public.cosmetics`). `LeaderboardPanel.svelte:239,328`. **Fix:** join cosmetics, return
  `.value`.
- [ ] **12. Compete win-count treats tied-top as a win** — `get_group_standings` counts
  every co-leader as a win; `_match_settle` logs it as a tie. **Fix:** win only when
  uniquely top.

## 🟡 Tier 3 — Notifications & turn-flow (the async heart of Challenges)

- [ ] **13. Sabotage debuffs + opponent standing not live** — only realtime channel is
  `match_messages` (chat); the `sabotaged` notification never calls `reconcileMatchBoard`.
  Victim sees the "you got hit" banner only after buying a letter (i.e. after overpaying).
  **Fix:** subscribe to the victim's `challenge_participants` row / refresh board on the
  sabotaged notification. *(`+page.svelte:1315,4476`)*
- [ ] **14. Turn notifications don't deep-link to the match** — `Toaster.svelte:12-15`
  routes only `challenge_incoming` to Challenges; `challenge_your_turn` (carries
  `match_id`) dead-ends at `/profile?tab=alerts`, and `notifNav` opens the *list*, not the
  match. **Fix:** use `data.match_id` to open the specific match.
- [ ] **15. Unread bell never clears from viewing inbox** — `markAllNotificationsRead`
  (`notificationStore.js:107`) has zero callers; alerts tab doesn't mark-all-read.
  **Fix:** call it on inbox open (or add a control).
- [ ] **16. "Your turn" nudge only for the first finisher** — `_match_notify_opponent_played`
  `IF v_done <> 1 THEN RETURN`. Later finishers never re-nudge stragglers.
  **Fix:** notify still-active players on each finish (deduped) / final reminder.
- [ ] **17. Early settlement blocked by an idle invited member** — `_match_maybe_settle`
  waits until nobody is `active`/`invited`. **Fix:** gate on accepted players only.
- [ ] **18. Group decline silent to host** when the match survives (`decline_match` only
  notifies on void). **Fix:** optionally notify "@x declined."
- [ ] **19. Possible double-toast race** — `notificationStore.poll()` computes `fresh`
  before writing `knownIds`; concurrent polls can both flag a row. **Fix:** in-flight guard
  / add ids before the async gap.

## 🔵 Tier 4 — Permissions & membership

- [ ] **20. Roster control inconsistent** — any member can `add_group_member`, but
  remove/rename/approve are owner-only. **Fix:** pick one model.
- [ ] **21. Join-request approval only via transient notification** — `respond_join_request`
  is only called from `NotificationsPanel.svelte:28`; no pending-requests list in
  `GroupsPanel`. **Fix:** render pending requests in the owner view.
- [ ] **22. Group leaderboard not membership-gated** — `get_challenge_leaderboard` group
  scope lacks a membership check and always self-injects (`OR gr.user_id = v_uid`).
  **Fix:** gate on membership; drop the unconditional self-include for group scope.

## ⚪ Tier 5 — Dead code to retire

- [ ] **23. Legacy `challenge_*` / `_challenge_*` engine** — 11 RPCs
  (`create_challenge`, `accept_challenge`, `get_challenge`, `challenge_buy_letter`,
  `challenge_submit_guess`, `challenge_reveal`, `challenge_check`, `_challenge_board`,
  `_challenge_resolve`, `_challenge_record_score`, `_challenge_settle`) + client wrappers
  (`statsStore.js:1255-1340`) + GameStore fns (`startChallenge`/`enterChallenge`/
  `acceptAndPlayChallenge`/`resumeChallenge`/`confirmPurchaseChallenge`/
  `submitGuessChallenge`). Unreachable; `challenges` table empty in prod. **Fix:** delete.
- [ ] **24. Dead `accept_match(uuid)` overload** — client only calls the 2-arg form; the
  1-arg one also skips `_mark_seen_many`. **Fix:** drop it.
- [ ] **25. Join-by-code fully dead** — `create_group` generates `join_code`,
  `get_my_groups` returns it, but no UI renders it and `join_group(text)` has zero callers.
  **Fix:** surface it or drop `join_code` + `join_group`.
- [ ] **26. Blitz match paths + mismatched clock** — `mode='blitz'` branches remain in
  `create_match` / `_match_resolve_and_advance` / `_match_tick` / `match_start` /
  `_match_board`; `_match_board.clock_seconds` (whole-match) mismatches the client's
  per-puzzle countdown. Fold into the Blitz excision. *(Blitz already retired via flag)*

## ⚪ Tier 6 — Polish

- [ ] **27. Group chat has no unread indicator** (match chat has `matchChatUnread`).
  *(`GroupsPanel.svelte:96-127`)*
- [ ] **28. ActivityPanel uses emoji icons** instead of the line-icon system.
  *(`ActivityPanel.svelte:16-22`)*
- [ ] **29. Compete tab caches standings** — doesn't refresh after a settle while open.
  *(`GroupsPanel.svelte:63`)*

---

### Recommended sequencing
Tier 1 (verify + fix money/correctness) → Tier 5 (dead-code purge simplifies everything
after) → Tier 3 (notifications = async feel) → Tier 2 → Tier 4 → Tier 6.
