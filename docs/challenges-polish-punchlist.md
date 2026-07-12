# Challenges Polish Punch-List

Scouting audit of the **1:1 (H2H)** and **Group / Compete** Challenge flows (read-only,
2026-07-12). Ordered most-severe first. Money/correctness items were traced by the audit
but should each be **confirmed with a BEGIN/ROLLBACK test before fixing**.

Live engine is `match_*` / `_match_*` (tables `challenge_matches` + `challenge_participants`,
`econ_v = 2`). The `challenge_*` / `_challenge_*` family is dead legacy (see T5).

---

## 🔴 Tier 1 — Money & correctness bugs (fix first)

- [x] **1. `decline_match` refunds bounty, not stake** — ✅ FIXED (PR #556, supabase-decline-refund-fix.sql): refund now `COALESCE(stake, GREATEST(wager,500))`; rollback-verified 1500→500. Refund credits
      `COALESCE(start_budget, GREATEST(wager,500))`; `start_budget` is the puzzle bounty
      (~$1.2–3k) while the host was only debited `stake = wager` (min $500). Decline → host
      pockets the difference. `_match_settle` correctly uses `coalesce(stake,…)`.
      **Fix:** refund `COALESCE(stake, wager)`. _(RPC `decline_match`)_
- [x] **2. `match_fold` never updated for `econ_v=2`** — ✅ FIXED (PR #557, supabase-match-fold-econ2-fix.sql): added econ*v=2 branch (accumulate total_score + fresh next bounty, mirrors solve path); rollback-verified final keeps prior $1200 and non-final advances with fresh bounty. Uses OLD absolute-overwrite
      semantics (`total_score = v_left`), so folding a later puzzle in a multi-puzzle match
      erases earlier winnings and advances with a $0 budget. `_match_resolve_and_advance`
      accumulates + resets bounty. **Fix:** add an `econ_v=2` branch mirroring it.
      *(RPC `match_fold`; single-puzzle matches unaffected)\_
- [x] **3. Reduced-accept charges the wrong balance** — ✅ FIXED (PR #558, supabase-accept-networth-fix.sql): accept*match now gates + caps on net worth (bank − loan); rollback-verified reduced caps at net worth, full blocks when net<wager, no-loan unchanged. UI gates on `netWorth = bank − loan`
      and shows a capped buy-in, but `accept_match` checks `profiles.bank`. A loan-holder
      (bank ≥ wager, netWorth < wager) is shown "capped" yet debited the full wager.
      **Fix:** align UI + RPC on one balance definition. *(`+page.svelte:2242,2260-2277`;
      RPC `accept_match(uuid,boolean)`)\_
- [x] **4. Group owner leaving orphans the group** — ✅ FIXED (PR #559, supabase-leave-group-owner-fix.sql): owner-leave now hands ownership to the oldest remaining member; rollback-verified handoff + empty-group deletion still works. `leave_group` doesn't reassign
      `owner_id`; every management RPC gates on `owner_id = uid`, so remaining members can
      never rename / kick / approve joins. **Fix:** reassign ownership to the oldest remaining
      member on owner-leave. _(RPC `leave_group`)_
- [x] **5. Paid non-finishers forfeit invisibly** — ✅ FIXED (PR #560, supabase-settle-dnf-fix.sql): added a loop for paid `state<>'done'` players → logs a lost/tie result + sends a notification; rollback-verified DNF gets outcome='lost' spent=500 + a notif, winner still takes the pot. `_match_settle` iterates only
      `state='done'`; a player who accepted+paid but didn't finish gets no `_notify` and no
      `_log_game_result`. Money loss never appears in history/leaderboards.
      **Fix:** include paid `active` participants with a DNF/lost result + notification.
- [x] **6. No scheduled settlement** — ✅ FIXED (PR #561, supabase-scheduled-settlement.sql): added `settle_expired_matches()` + pg_cron job (every 5 min) that settles past-`settles_at` open matches server-side; enabling it immediately settled 1 real stuck match in prod. `get_my_matches` is the only sweeper (settles
      `status='open' AND settles_at < now()`); no pg_cron. Wagers stay escrowed and
      refund/settled notifications never fire until a participant next opens the list.
      **Fix:** scheduled sweeper (pg_cron or edge cron → `settle_expired_matches()`).

## 🟠 Tier 2 — Money/score shown wrong (visible, not exploitable)

- [x] **7. Multi-puzzle "spent"/"budget" inflated** — ✅ FIXED (PR #571, supabase-match-spent-fix.sql): spent now = start_budget − total_score − (bankroll unless done) in get_match + get_match_detail; rollback-verified multi-puzzle done spent 1300→700, single-puzzle unchanged. Was: — `get_match` / `get_match_detail`
      compute `spent = start_budget − bankroll`, mixing accumulated multi-puzzle budget vs
      single-puzzle bankroll. **Fix:** `sum(per-position bounty) − total_score`.
- [x] **8. Pot chip shrinks as opponents finish** — ✅ FIXED (PR #570, supabase-match-pot-fix.sql): _match_board now returns a stable `pot` (wager × non-declined players); client uses it; rollback-verified pot stays $1000 with an opponent done. Was: — `matchPot = wager × (opponents+1)`
      and `_match_board.opponents` excludes `done`. Opponent finishes → "Pot $1,000"→"$500".
      **Fix:** compute pot server-side from `sum(stake)` over all paid participants.
      _(`+page.svelte:642-643`)\_
- [x] **9. PIN confirm always "Winner takes all"** — ✅ FIXED (PR #570): create + accept confirm sheets now say "Top finishers split the pot" for group/3+ pots, "Winner takes all" for 1:1. Was: — `mbPayout='winner'` never reassigned;
      group pots actually split 70/30 or 60/30/10. **Fix:** derive from field size / reuse
      `potSummary`. _(`+page.svelte:2020,2171`)_
- [x] **10. Compete "recent matches" shows 🏆 on no-winner/ties** — ✅ FIXED (PR #568, supabase-group-standings-fix.sql): winner NULL unless a sole top scorer with score>0; client renders "🤝 Tie · no winner". Was: — `get_group_standings`
      picks `ORDER BY total_score DESC LIMIT 1` with no `>0`/tie guard; `GroupsPanel.svelte:379`
      renders it unconditionally. **Fix:** `winner=null` when top is 0 or tied.
- [x] **11. Leaderboard shows title as raw UUID + invalid color** — ✅ FIXED (PR #569, supabase-challenge-lb-cosmetics-fix.sql): join public.cosmetics, return .value like sibling boards; rollback-verified title="On Fire", color="#fbbf24". Was: —
      `get_challenge_leaderboard` returns cosmetic **ids**, not values (siblings join
      `public.cosmetics`). `LeaderboardPanel.svelte:239,328`. **Fix:** join cosmetics, return
      `.value`.
- [x] **12. Compete win-count treats tied-top as a win** — ✅ FIXED (PR #568): a win now requires being the UNIQUE top scorer (top_n=1); rollback-verified tie not counted, sole win counted. Was: — `get_group_standings` counts
      every co-leader as a win; `_match_settle` logs it as a tie. **Fix:** win only when
      uniquely top.

## 🟡 Tier 3 — Notifications & turn-flow (the async heart of Challenges)

- [x] **13. Sabotage debuffs + opponent standing not live** — ✅ FIXED (PR #567): added a realtime challenge*participants UPDATE subscription → refreshMatchMeta (meta-only, never disrupts typing); the sabotage debuff lands on the victim’s own row (RLS-visible) so the banner shows instantly. Standing still refreshes on the victim’s own actions (RLS blocks direct opponent-row reads). Was: — only realtime channel is
      `match_messages` (chat); the `sabotaged` notification never calls `reconcileMatchBoard`.
      Victim sees the "you got hit" banner only after buying a letter (i.e. after overpaying).
      **Fix:** subscribe to the victim's `challenge_participants` row / refresh board on the
      sabotaged notification. *(`+page.svelte:1315,4476`)\_
- [ ] **14. Turn notifications don't deep-link to the match** — `Toaster.svelte:12-15`
      routes only `challenge_incoming` to Challenges; `challenge_your_turn` (carries
      `match_id`) dead-ends at `/profile?tab=alerts`, and `notifNav` opens the _list_, not the
      match. **Fix:** use `data.match_id` to open the specific match.
- [x] **15. Unread bell never clears from viewing inbox** — ✅ FIXED (PR #564): alerts tab now calls markAllNotificationsRead on open. Was: — `markAllNotificationsRead`
      (`notificationStore.js:107`) has zero callers; alerts tab doesn't mark-all-read.
      **Fix:** call it on inbox open (or add a control).
- [x] **16. "Your turn" nudge only for the first finisher** — ✅ FIXED (PR #565, supabase-turnflow-notifs-fix.sql): removed the v_done<>1 gate so every finish nudges still-waiting players, deduped to one unread per match. Was: — `_match_notify_opponent_played`
      `IF v_done <> 1 THEN RETURN`. Later finishers never re-nudge stragglers.
      **Fix:** notify still-active players on each finish (deduped) / final reminder.
- [ ] **17. Early settlement blocked by an idle invited member** — ⏸️ DEFERRED (product call): naively ignoring `invited` would let a 1:1 settle before the opponent ever accepts. #6 (scheduled settlement) already prevents indefinite escrow, so this is an early-settle-vs-late-accepters tradeoff, not a clean bug. Was: — `_match_maybe_settle`
      waits until nobody is `active`/`invited`. **Fix:** gate on accepted players only.
- [x] **18. Group decline silent to host** — ✅ FIXED (PR #565): host now notified "@x declined — still on" when a decline leaves the match viable. Was: when the match survives (`decline_match` only
      notifies on void). **Fix:** optionally notify "@x declined."
- [x] **19. Possible double-toast race** — ✅ FIXED (PR #564): added an in-flight guard to notificationStore.poll(). Was: — `notificationStore.poll()` computes `fresh`
      before writing `knownIds`; concurrent polls can both flag a row. **Fix:** in-flight guard
      / add ids before the async gap.

## 🔵 Tier 4 — Permissions & membership

- [ ] **20. Roster control inconsistent** — ⏸️ DEFERRED (product call): "members invite friends, owner moderates + approves requests" is a coherent, common model (Discord-style), not a clear bug. Was: — any member can `add_group_member`, but
      remove/rename/approve are owner-only. **Fix:** pick one model.
- [x] **21. Join-request approval only via transient notification** — ✅ FIXED (PR #572, supabase-group-pending-requests.sql): get_group returns pending requests (owner-only); GroupsPanel renders a "Requests to join" section with Approve/Deny. Was: — `respond_join_request`
      is only called from `NotificationsPanel.svelte:28`; no pending-requests list in
      `GroupsPanel`. **Fix:** render pending requests in the owner view.
- [x] **22. Group leaderboard not membership-gated** — ✅ FIXED (PR #572, supabase-challenge-lb-gating-fix.sql): group scope now members-only + self-include scoped to friends; rollback-verified non-member gets []. Was: — `get_challenge_leaderboard` group
      scope lacks a membership check and always self-injects (`OR gr.user_id = v_uid`).
      **Fix:** gate on membership; drop the unconditional self-include for group scope.

## ⚪ Tier 5 — Dead code to retire

- [x] **23. Legacy `challenge_*` / `_challenge_*` engine** — ✅ FIXED (PR #562): dropped all 12 dead RPCs (supabase-drop-legacy-challenge-engine.sql), removed the GameStore engine block + statsStore wrappers + dead +page.svelte challenge UI (isChallenge/chScore/pressure HUD/result branch + unused CSS); build+check clean, QA smoke 19/19. Was 11 RPCs
      (`create_challenge`, `accept_challenge`, `get_challenge`, `challenge_buy_letter`,
      `challenge_submit_guess`, `challenge_reveal`, `challenge_check`, `_challenge_board`,
      `_challenge_resolve`, `_challenge_record_score`, `_challenge_settle`) + client wrappers
      (`statsStore.js:1255-1340`) + GameStore fns (`startChallenge`/`enterChallenge`/
      `acceptAndPlayChallenge`/`resumeChallenge`/`confirmPurchaseChallenge`/
      `submitGuessChallenge`). Unreachable; `challenges` table empty in prod. **Fix:** delete.
- [x] **24. Dead `accept_match(uuid)` overload** — ✅ FIXED (PR #563, supabase-drop-dead-overloads.sql): dropped; accept_match now unambiguously 2-arg. Was: dead `accept_match(uuid)` overload — client only calls the 2-arg form; the
      1-arg one also skips `_mark_seen_many`. **Fix:** drop it.
- [ ] **25. Join-by-code fully dead** — `create_group` generates `join_code`,
      `get_my_groups` returns it, but no UI renders it and `join_group(text)` has zero callers.
      **Fix:** surface it or drop `join_code` + `join_group`.
- [ ] **26. Blitz match paths + mismatched clock** — ⏸️ DEFERRED to the Blitz mode excision (Blitz already disabled via BLITZ*ENABLED=false). Was: Blitz match paths + mismatched clock — `mode='blitz'` branches remain in
      `create_match` / `_match_resolve_and_advance` / `_match_tick` / `match_start` /
      `_match_board`; `_match_board.clock_seconds` (whole-match) mismatches the client's
      per-puzzle countdown. Fold into the Blitz excision. *(Blitz already retired via flag)\_

## ⚪ Tier 6 — Polish

- [ ] **27. Group chat has no unread indicator** (match chat has `matchChatUnread`).
      _(`GroupsPanel.svelte:96-127`)_
- [ ] **28. ActivityPanel uses emoji icons** instead of the line-icon system.
      _(`ActivityPanel.svelte:16-22`)_
- [ ] **29. Compete tab caches standings** — doesn't refresh after a settle while open.
      _(`GroupsPanel.svelte:63`)_

---

### Recommended sequencing

Tier 1 (verify + fix money/correctness) → Tier 5 (dead-code purge simplifies everything
after) → Tier 3 (notifications = async feel) → Tier 2 → Tier 4 → Tier 6.
