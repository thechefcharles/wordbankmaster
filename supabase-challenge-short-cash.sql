-- "Short on Cash" challenge handling: when you can't afford a challenge's buy-in,
-- you can either play with what you have (a capped budget) or decline (refunds the
-- host if the match can no longer happen). Fair because challenges are pot-of-spend
-- — you only ever lose what you SPEND, so a smaller budget is just a self-handicap.
--
-- Applied to prod via MCP migrations:
--   participant_start_budget                          (per-participant budget column)
--   create_match_startbudget_and_mymatches_declined   (host budget + hide declined)
--   accept_match_reduced_and_decline                  (p_reduced + decline_match)
--   match_settle_per_participant_budget               (settle uses each player's budget)
--
-- Key change: challenge_participants.start_budget stores each player's own buy-in/
-- budget, so a reduced player's spend/refund is computed against THEIR budget, not the
-- match's. Verified (rolled back): reduced player settle (host +600 / reduced +200,
-- reduced spent $100 vs their $300 budget); decline voids + refunds the host $500.
--
-- See migrations in Supabase for the full bodies. Frontend: respondToMatch shows a
-- play-or-decline sheet when netWorth < wager; acceptAndPlayMatch(id, reduced) and
-- declineMatch(id) call accept_match(p_reduced)/decline_match.

-- accept_match: stake your remaining Cash when short (p_reduced), else require full wager.
-- (body applied via migration accept_match_reduced_and_decline)

-- decline_match: mark me 'declined'; if < 2 players remain, void the match + refund buy-ins.
-- (body applied via migration accept_match_reduced_and_decline)

-- _match_settle: spend/refund/spent now use coalesce(start_budget, greatest(wager,500))
-- per participant instead of one match-level budget.
-- (body applied via migration match_settle_per_participant_budget)

-- End-to-end fix (migrations match_board_per_participant_budget +
-- getmatch_detail_per_participant_budget): _match_board, get_match and
-- get_match_detail also computed the budget/spent against the match wager, so a
-- reduced player's board showed "Spent $200 of $500" and standings compared the
-- wrong budgets. All three now use each participant's start_budget. match_buy_letter
-- already caps spending at the live bankroll, so the reduced budget is enforced.
-- Verified live: a $300 player accepts a $500 challenge → board shows "$0 of $300",
-- stakes $300 (bank→0), bankroll=start_budget=300.
