import { supabase } from '$lib/supabaseClient';

/**
 * Fetch today's daily puzzle (same for everyone)
 */
export async function fetchTodaysPuzzle() {
  const { data, error } = await supabase.rpc('get_todays_puzzle').maybeSingle();
  if (error) {
    console.error('❌ Error fetching daily puzzle:', error);
    return null;
  }
  if (!data) return null;
  /** @type {{ phrase?: string, category?: string, subcategory?: string }} */
  const puzzle = data;
  return {
    phrase: puzzle.phrase,
    category: puzzle.category,
    subcategory: puzzle.subcategory ?? ''
  };
}

/**
 * Check if user has already played the daily puzzle today
 * @param {string} userId
 */
export async function hasPlayedDailyToday(userId) {
  const { data, error } = await supabase.rpc('has_played_daily_today', {
    p_user_id: userId
  });
  if (error) {
    console.error('❌ Error checking daily play status:', error);
    return false;
  }
  return !!data;
}

/**
 * Get daily status and bankrolls for select page
 * @param {string} userId
 */
export async function getDailyStatus(userId) {
  const { data, error } = await supabase.rpc('get_daily_status', {
    p_user_id: userId
  });
  if (error) {
    console.error('❌ Error fetching daily status:', error);
    return { has_played_today: false, last_daily_won: null, daily_bankroll: 0, arcade_bankroll: 1000, current_streak: 0, streak_freezes: 0, today_score: 0, win_streak: 0 };
  }
  const row = Array.isArray(data) ? data[0] : data;
  return {
    has_played_today: !!row?.has_played_today,
    last_daily_won: row?.last_daily_won ?? null,
    daily_bankroll: row?.daily_bankroll ?? 0,
    arcade_bankroll: row?.arcade_bankroll ?? 1000,
    current_streak: row?.current_streak ?? 0, // PLAY streak (attendance / showing up)
    streak_freezes: row?.streak_freezes ?? 0,
    today_score: row?.today_score ?? 0,
    win_streak: row?.win_streak ?? 0 // WIN streak (consecutive solves)
  };
}


/** My Cash: balance (= Net Worth) and recent ledger. (v3: loans removed.)
 * @returns {Promise<{ bank:number, net_worth:number, ledger:any[] }>} */
export async function getBank() {
  const { data, error } = await supabase.rpc('get_bank');
  if (error || !data) { if (error) console.error('❌ get_bank:', error); return { bank: 0, net_worth: 0, ledger: [] }; }
  return { bank: data.bank ?? 0, net_worth: data.net_worth ?? data.bank ?? 0,
    ledger: Array.isArray(data.ledger) ? data.ledger : [] };
}

/** Lowest winning spend per mode (e.g. { daily: 20, climb: 60 }) — powers the
 *  solo "beat your best" goal line. @returns {Promise<Record<string, number>>} */
export async function getPersonalBests() {
  const { data, error } = await supabase.rpc('get_personal_bests');
  if (error) { console.error('❌ get_personal_bests:', error); return {}; }
  return data && typeof data === 'object' ? data : {};
}

/** My chosen username (null until claimed). @returns {Promise<string|null>} */
export async function getMyUsername() {
  const { data, error } = await supabase.rpc('get_my_username');
  if (error) { console.error('❌ get_my_username:', error); return null; }
  return data ?? null;
}

/** Claim / change my username. @param {string} name @returns {Promise<{ok:boolean, reason?:string, username?:string}>} */
export async function setUsername(name) {
  const { data, error } = await supabase.rpc('set_username', { p_username: name });
  if (error || !data) { if (error) console.error('❌ set_username:', error); return { ok: false }; }
  return data;
}

/** Username typeahead search. @param {string} query @returns {Promise<{username:string,is_friend:boolean}[]>} */
export async function searchUsers(query) {
  const { data, error } = await supabase.rpc('search_users', { p_query: query });
  if (error) { console.error('❌ search_users:', error); return []; }
  return Array.isArray(data) ? data : [];
}

/* ===== Groups ===== */
/** @returns {Promise<any[]>} */
export async function getMyGroups() {
  const { data, error } = await supabase.rpc('get_my_groups');
  if (error) { console.error('❌ get_my_groups:', error); return []; }
  return Array.isArray(data) ? data : [];
}
/** @param {string} id @returns {Promise<any|null>} */
export async function getGroup(id) {
  const { data, error } = await supabase.rpc('get_group', { p_id: id });
  if (error) { console.error('❌ get_group:', error); return null; }
  return data;
}
/** @param {string} name @returns {Promise<{ok:boolean, reason?:string, group?:any}>} */
export async function createGroup(name) {
  const { data, error } = await supabase.rpc('create_group', { p_name: name });
  if (error || !data) { if (error) console.error('❌ create_group:', error); return { ok: false }; }
  return data;
}
/** @param {string} code @returns {Promise<{ok:boolean, reason?:string, group?:any}>} */
export async function joinGroup(code) {
  const { data, error } = await supabase.rpc('join_group', { p_code: code });
  if (error || !data) { if (error) console.error('❌ join_group:', error); return { ok: false }; }
  return data;
}
/** @param {string} id @returns {Promise<{ok:boolean}>} */
export async function leaveGroup(id) {
  const { data, error } = await supabase.rpc('leave_group', { p_id: id });
  if (error || !data) { if (error) console.error('❌ leave_group:', error); return { ok: false }; }
  return data;
}
/** Add one of your friends to a group. @param {string} groupId @param {string} username @returns {Promise<{ok:boolean, reason?:string, group?:any}>} */
export async function addGroupMember(groupId, username) {
  const { data, error } = await supabase.rpc('add_group_member', { p_group_id: groupId, p_username: username });
  if (error || !data) { if (error) console.error('❌ add_group_member:', error); return { ok: false }; }
  return data;
}
/** Owner removes a member. @param {string} groupId @param {string} username @returns {Promise<{ok:boolean, reason?:string, group?:any}>} */
export async function removeGroupMember(groupId, username) {
  const { data, error } = await supabase.rpc('remove_group_member', { p_group_id: groupId, p_username: username });
  if (error || !data) { if (error) console.error('❌ remove_group_member:', error); return { ok: false }; }
  return data;
}
/** Owner renames a group. @param {string} groupId @param {string} name @returns {Promise<{ok:boolean, reason?:string, group?:any}>} */
export async function renameGroup(groupId, name) {
  const { data, error } = await supabase.rpc('rename_group', { p_group_id: groupId, p_name: name });
  if (error || !data) { if (error) console.error('❌ rename_group:', error); return { ok: false }; }
  return data;
}
/** @param {string} groupId @returns {Promise<any[]>} */
export async function getGroupMessages(groupId) {
  const { data, error } = await supabase.rpc('get_group_messages', { p_group_id: groupId });
  if (error) { console.error('❌ get_group_messages:', error); return []; }
  return Array.isArray(data) ? data : [];
}
/** @param {string} groupId @param {string} body @returns {Promise<{ok:boolean, reason?:string}>} */
export async function sendGroupMessage(groupId, body) {
  const { data, error } = await supabase.rpc('send_group_message', { p_group_id: groupId, p_body: body });
  if (error || !data) { if (error) console.error('❌ send_group_message:', error); return { ok: false }; }
  return data;
}

/* ===== Notifications ===== */
/** @returns {Promise<{items:any[], unread_count:number}>} */
export async function getNotifications() {
  const { data, error } = await supabase.rpc('get_notifications');
  if (error || !data) { if (error) console.error('❌ get_notifications:', error); return { items: [], unread_count: 0 }; }
  return { items: Array.isArray(data.items) ? data.items : [], unread_count: data.unread_count ?? 0 };
}
/** Mark notifications read — all, one challenge (matchId), or one friend request (fromId).
 *  @param {string|null} [matchId] @param {string|null} [fromId] */
export async function markNotificationsRead(matchId = null, fromId = null) {
  const { error } = await supabase.rpc('mark_notifications_read', { p_match_id: matchId, p_from_id: fromId });
  if (error) console.error('❌ mark_notifications_read:', error);
}

/** Send a friend request by username (auto-accepts if they already requested you). @param {string} username @returns {Promise<{ok:boolean, reason?:string, status?:string, friend_name?:string}>} */
export async function addFriend(username) {
  const { data, error } = await supabase.rpc('add_friend', { p_username: username });
  if (error || !data) { if (error) console.error('❌ add_friend:', error); return { ok: false }; }
  return data;
}

/** Accept or decline an incoming request, by requester id. @param {string} requesterId @param {boolean} accept @returns {Promise<{ok:boolean, reason?:string, status?:string}>} */
export async function respondFriendRequest(requesterId, accept) {
  const { data, error } = await supabase.rpc('respond_friend_request', { p_requester: requesterId, p_accept: accept });
  if (error || !data) { if (error) console.error('❌ respond_friend_request:', error); return { ok: false }; }
  return data;
}

/** Unfriend by user id. @param {string} otherId @returns {Promise<{ok:boolean}>} */
export async function removeFriend(otherId) {
  const { data, error } = await supabase.rpc('remove_friend', { p_other: otherId });
  if (error || !data) { if (error) console.error('❌ remove_friend:', error); return { ok: false }; }
  return data;
}

/** My accepted friends. @returns {Promise<{username:string,name:string}[]>} */
export async function listFriends() {
  const { data, error } = await supabase.rpc('list_friends');
  if (error) { console.error('❌ list_friends:', error); return []; }
  return data ?? [];
}

/** Pending requests. @returns {Promise<{incoming:{username:string,name:string}[], outgoing:{username:string,name:string}[]}>} */
export async function listFriendRequests() {
  const { data, error } = await supabase.rpc('list_friend_requests');
  if (error) { console.error('❌ list_friend_requests:', error); return { incoming: [], outgoing: [] }; }
  return data ?? { incoming: [], outgoing: [] };
}

/** Count of incoming friend requests (menu badge). @returns {Promise<number>} */
export async function getFriendRequestCount() {
  const { data, error } = await supabase.rpc('get_friend_request_count');
  if (error) { console.error('❌ get_friend_request_count:', error); return 0; }
  return data ?? 0;
}

/** Me + friends ranked by today's Daily score. @returns {Promise<any[]>} */
export async function getFriendsDailyLeaderboard() {
  const { data, error } = await supabase.rpc('get_friends_daily_leaderboard');
  if (error) { console.error('❌ get_friends_daily_leaderboard:', error); return []; }
  return Array.isArray(data) ? data : [];
}

/** Net Worth leaderboard (= Cash). @param {'friends'|'global'} scope @returns {Promise<any[]>} */
export async function getNetworthLeaderboard(scope = 'friends') {
  const { data, error } = await supabase.rpc('get_networth_leaderboard', { p_scope: scope });
  if (error) { console.error('❌ get_networth_leaderboard:', error); return []; }
  return Array.isArray(data) ? data : [];
}

/* ===== Cosmetics shop (Bank spending sink; earned-Bank-only, no pay-to-win) ===== */
/** Shop catalog + owned/equipped flags + my Bank. @returns {Promise<{bank:number, items:any[]}>} */
export async function getShop() {
  const { data, error } = await supabase.rpc('get_shop');
  if (error || !data) { if (error) console.error('❌ get_shop:', error); return { bank: 0, items: [] }; }
  return { bank: data.bank ?? 0, items: Array.isArray(data.items) ? data.items : [] };
}
/** Buy a cosmetic with Bank. @param {string} id @returns {Promise<{ok:boolean, reason?:string}>} */
export async function buyCosmetic(id) {
  const { data, error } = await supabase.rpc('buy_cosmetic', { p_id: id });
  if (error || !data) { if (error) console.error('❌ buy_cosmetic:', error); return { ok: false }; }
  return data;
}
/** Equip an owned cosmetic. @param {string} id @returns {Promise<{ok:boolean, reason?:string}>} */
export async function equipCosmetic(id) {
  const { data, error } = await supabase.rpc('equip_cosmetic', { p_id: id });
  if (error || !data) { if (error) console.error('❌ equip_cosmetic:', error); return { ok: false }; }
  return data;
}
/** Unequip the current title or color. @param {'title'|'color'} kind @returns {Promise<{ok:boolean}>} */
export async function unequipCosmetic(kind) {
  const { data, error } = await supabase.rpc('unequip_cosmetic', { p_kind: kind });
  if (error || !data) { if (error) console.error('❌ unequip_cosmetic:', error); return { ok: false }; }
  return data;
}

/**
 * Streak overview: current/longest streak, freezes, and per-day daily outcomes
 * (last ~10 weeks) for the calendar heatmap.
 * @returns {Promise<{ current_streak:number, highest_streak:number, freezes:number, days:{d:string,won:boolean}[] }>}
 */
export async function getStreakOverview() {
  const { data, error } = await supabase.rpc('get_streak_overview');
  if (error || !data) {
    if (error) console.error('❌ Error fetching streak overview:', error);
    return { current_streak: 0, highest_streak: 0, freezes: 0, days: [] };
  }
  return {
    current_streak: data.current_streak ?? 0,
    highest_streak: data.highest_streak ?? 0,
    freezes: data.freezes ?? 0,
    days: Array.isArray(data.days) ? data.days : []
  };
}

/**
 * Fetch daily leaderboard
 * @param {string} period - 'daily' | 'weekly' | 'monthly' | 'yearly'
 * @param {string} orderBy - 'bankroll' | 'streak' | 'puzzles' | 'win_pct'
 */
export async function fetchDailyLeaderboard(period = 'daily', orderBy = 'score') {
  const { data, error } = await supabase.rpc('get_daily_leaderboard', {
    p_period: period,
    p_order_by: orderBy
  });
  if (error) {
    console.error('❌ Error fetching daily leaderboard:', error);
    return [];
  }
  return data ?? [];
}

/**
 * All-time per-category solve counts for the caller.
 * @returns {Promise<{category: string, solves: number}[]>}
 */
export async function getCategoryStats() {
  const { data, error } = await supabase.rpc('get_category_stats');
  if (error) { console.error('❌ get_category_stats error:', error); return []; }
  return data ?? [];
}

/* ===== Free Play (unranked, pick-a-category) — return a masked board ===== */
/** @param {string} category @returns {Promise<object|null>} */
export async function freeplayStart(category) {
  const { data, error } = await supabase.rpc('freeplay_start', { p_category: category });
  if (error) { console.error('❌ freeplay_start error:', error); return null; }
  return data;
}
/** @returns {Promise<object|null>} */
export async function freeplayNext() {
  const { data, error } = await supabase.rpc('freeplay_next');
  if (error) { console.error('❌ freeplay_next error:', error); return null; }
  return data;
}
/** Resume an in-progress Free Play puzzle (null if none active). @returns {Promise<object|null>} */
export async function freeplayResume() {
  const { data, error } = await supabase.rpc('freeplay_resume');
  if (error) { console.error('❌ freeplay_resume error:', error); return null; }
  return data ?? null;
}
/** @param {string} letter @returns {Promise<object|null>} */
export async function freeplayBuyLetter(letter) {
  const { data, error } = await supabase.rpc('freeplay_buy_letter', { p_letter: letter });
  if (error) { console.error('❌ freeplay_buy_letter error:', error); return null; }
  return data;
}
/** @returns {Promise<object|null>} */
export async function freeplayReveal() {
  const { data, error } = await supabase.rpc('freeplay_reveal');
  if (error) { console.error('❌ freeplay_reveal error:', error); return null; }
  return data;
}
/** @param {Record<string,string>} guess @returns {Promise<object|null>} */
export async function freeplaySubmitGuess(guess) {
  const { data, error } = await supabase.rpc('freeplay_submit_guess', { p_guess: guess });
  if (error) { console.error('❌ freeplay_submit_guess error:', error); return null; }
  return data;
}
/** @returns {Promise<string|null>} */
export async function getFreeplayClue() {
  const { data, error } = await supabase.rpc('freeplay_clue');
  if (error) { console.error('❌ freeplay_clue error:', error); return null; }
  return data ?? null;
}

/** Witty clue for the caller's current daily puzzle. @returns {Promise<string|null>} */
export async function getDailyClue() {
  const { data, error } = await supabase.rpc('daily_clue');
  if (error) { console.error('❌ daily_clue error:', error); return null; }
  return data ?? null;
}

/** Witty clue for the caller's current arcade puzzle. @returns {Promise<string|null>} */
export async function getArcadeClue() {
  const { data, error } = await supabase.rpc('arcade_clue');
  if (error) { console.error('❌ arcade_clue error:', error); return null; }
  return data ?? null;
}

/** Witty clue for the caller's current Cash Game (climb) puzzle. @returns {Promise<string|null>} */
export async function getClimbClue() {
  const { data, error } = await supabase.rpc('climb_clue');
  if (error) { console.error('❌ climb_clue error:', error); return null; }
  return data ?? null;
}

/**
 * Today's shared Daily Modifier id (same for every player; rotates by date).
 * @returns {Promise<string|null>}
 */
export async function getDailyModifier() {
  const { data, error } = await supabase.rpc('get_daily_modifier');
  if (error) { console.error('❌ get_daily_modifier error:', error); return null; }
  return data ?? null;
}

/**
 * "Ghost of yesterday" — today's daily result vs the caller's own result
 * yesterday, plus the share of today's field they beat.
 * @returns {Promise<null | { yesterday_played: boolean, yesterday_banked: number|null, yesterday_won: boolean, yesterday_score: number|null, today_banked: number|null, today_score: number|null, today_players: number, today_percentile: number|null }>}
 */
export async function getDailyGhost() {
  const { data, error } = await supabase.rpc('get_daily_ghost');
  if (error) { console.error('❌ get_daily_ghost error:', error); return null; }
  return data;
}

/**
 * Fetch the arcade gauntlet leaderboard (best banked run + furthest reached).
 * @param {string} period - 'daily' | 'weekly' | 'monthly' | 'yearly' | 'all'
 */
export async function fetchArcadeLeaderboard(period = 'daily') {
  const { data, error } = await supabase.rpc('get_arcade_gauntlet_leaderboard', { p_period: period });
  if (error) {
    console.error('❌ Error fetching arcade leaderboard:', error);
    return [];
  }
  return data ?? [];
}

/* ============================================================
   Server-authoritative DAILY mode (the answer never reaches the client).
   Each call returns a masked board:
   { state, bankroll, guesses_remaining, category, subcategory,
     word_lengths[], revealed{pos:letter}, incorrect_letters[],
     locked_letters[], phrase|null }
   phrase is null until the game is over.
============================================================ */

/**
 * Start or resume today's daily session, activating any pre-game power-ups.
 * @param {string[]} [powerups] - pre-game power-ups to activate (only applied on a fresh session)
 * @returns {Promise<object|null>} board
 */
export async function dailyStart(powerups = []) {
  const { data, error } = await supabase.rpc('daily_start', { p_powerups: powerups });
  if (error) { console.error('❌ daily_start error:', error); return null; }
  return data;
}
/** Use today's Daily Twist power-up (applies its effect; bounty drops to ×1.0). */
export async function dailyUseTwist() {
  const { data, error } = await supabase.rpc('daily_use_twist');
  if (error) { console.error('❌ daily_use_twist error:', error); return null; }
  return data;
}

/** Spend an owned Bounty Boost on today's Daily (adds to the bounty multiplier). */
export async function dailyUseBoost(id) {
  const { data, error } = await supabase.rpc('daily_use_boost', { p_id: id });
  if (error) { console.error('❌ daily_use_boost error:', error); return null; }
  return data;
}

/** Your rank on today's global Daily leaderboard → { rank, total, score }. */
export async function getMyDailyRank() {
  const { data, error } = await supabase.rpc('get_my_daily_rank');
  if (error) { console.error('❌ get_my_daily_rank:', error); return null; }
  return data;
}

/** Boosts available to use in today's Daily (snapshot at start) → { id: remaining }. */
export async function getDailyAvailBoosts() {
  const { data, error } = await supabase.rpc('get_daily_avail_boosts');
  if (error) { console.error('❌ get_daily_avail_boosts:', error); return {}; }
  return data ?? {};
}

/* ===== Make-up daily (play a past missed day in the current month) =====
   No streak repair, no Bank deposit — fills the calendar + earns week/month badges.
   Each returns a daily board with an extra { makeup: { date } } marker. */
/** @param {string} date YYYY-MM-DD @returns {Promise<any>} */
export async function makeupStart(date) {
  const { data, error } = await supabase.rpc('makeup_start', { p_date: date });
  if (error) { console.error('❌ makeup_start error:', error); return null; }
  return data;
}
/** @param {string} date @param {string} letter @returns {Promise<any>} */
export async function makeupBuyLetter(date, letter) {
  const { data, error } = await supabase.rpc('makeup_buy_letter', { p_date: date, p_letter: letter });
  if (error) { console.error('❌ makeup_buy_letter error:', error); return null; }
  return data;
}

/* ===== Cash Game / the Climb (real-Cash forward-only climb) ===== */
/** @returns {Promise<any>} */
export async function climbStart() {
  const { data, error } = await supabase.rpc('climb_start');
  if (error) { console.error('❌ climb_start:', error); return null; }
  return data;
}
/** @param {string} letter @returns {Promise<any>} */
export async function climbBuyLetter(letter) {
  const { data, error } = await supabase.rpc('climb_buy_letter', { p_letter: letter });
  if (error) { console.error('❌ climb_buy_letter:', error); return null; }
  return data;
}
/** @returns {Promise<any>} */
export async function climbReveal() {
  const { data, error } = await supabase.rpc('climb_reveal');
  if (error) { console.error('❌ climb_reveal:', error); return null; }
  return data;
}
/** @param {Record<string,string>} guess @returns {Promise<any>} */
export async function climbSubmitGuess(guess) {
  const { data, error } = await supabase.rpc('climb_submit_guess', { p_guess: guess });
  if (error) { console.error('❌ climb_submit_guess:', error); return null; }
  return data;
}
/** @returns {Promise<any>} */
export async function climbNext() {
  const { data, error } = await supabase.rpc('climb_next');
  if (error) { console.error('❌ climb_next:', error); return null; }
  return data;
}
/** @returns {Promise<any>} */
export async function climbLeave() {
  const { data, error } = await supabase.rpc('climb_leave');
  if (error) { console.error('❌ climb_leave:', error); return null; }
  return data;
}
/** @param {string} scope @param {string|null} [group] @returns {Promise<any[]>} */
export async function getClimbLeaderboard(scope = 'friends', group = null) {
  const { data, error } = await supabase.rpc('get_climb_leaderboard', { p_scope: scope, p_group: group });
  if (error) { console.error('❌ get_climb_leaderboard:', error); return []; }
  return Array.isArray(data) ? data : [];
}

/* ===== Leaderboards v2 (3 boards × scope) ===== */
/** @param {string} scope @param {'week'|'all'} period @param {string|null} [group] @returns {Promise<any[]>} */
export async function getWealthLeaderboard(scope = 'friends', period = 'week', group = null) {
  const { data, error } = await supabase.rpc('get_wealth_leaderboard', { p_scope: scope, p_period: period, p_group: group });
  if (error) { console.error('❌ get_wealth_leaderboard:', error); return []; }
  return Array.isArray(data) ? data : [];
}
/** @param {string} scope @param {string|null} [group] @returns {Promise<any[]>} */
export async function getDailyBoard(scope = 'friends', group = null) {
  const { data, error } = await supabase.rpc('get_daily_board', { p_scope: scope, p_group: group });
  if (error) { console.error('❌ get_daily_board:', error); return []; }
  return Array.isArray(data) ? data : [];
}
/** Best return-multiple board (the brand metric). @param {string} scope @param {string|null} group @param {'week'|'all'} period */
export async function getEfficiencyLeaderboard(scope = 'friends', group = null, period = 'week') {
  const { data, error } = await supabase.rpc('get_efficiency_leaderboard', { p_scope: scope, p_group: group, p_period: period });
  if (error) { console.error('❌ get_efficiency_leaderboard:', error); return []; }
  return Array.isArray(data) ? data : [];
}
/** Challenge wins / pot-won board. @param {string} scope @param {string|null} group @param {'week'|'all'} period */
export async function getChallengeLeaderboard(scope = 'friends', group = null, period = 'week') {
  const { data, error } = await supabase.rpc('get_challenge_leaderboard', { p_scope: scope, p_group: group, p_period: period });
  if (error) { console.error('❌ get_challenge_leaderboard:', error); return []; }
  return Array.isArray(data) ? data : [];
}
/** @returns {Promise<any|null>} */
export async function getProfileStats() {
  const { data, error } = await supabase.rpc('get_profile_stats');
  if (error) { console.error('❌ get_profile_stats:', error); return null; }
  return data;
}
/** Stat-heavy profile: per-mode sections + records. @returns {Promise<any|null>} */
export async function getProfileDetail() {
  const { data, error } = await supabase.rpc('get_profile_detail');
  if (error) { console.error('❌ get_profile_detail:', error); return null; }
  return data;
}

/* ===== Play Log: history, head-to-head, challenge detail ===== */
/**
 * Unified game history (the Play Log) with stackable filters.
 * @param {{ mode?:string|null, result?:string|null, category?:string|null,
 *   opponent?:string|null, group?:string|null, since?:string|null, until?:string|null,
 *   sort?:'recent'|'net'|'multiple'|'fastest', limit?:number, offset?:number }} [f]
 * @returns {Promise<any[]>}
 */
export async function getHistory(f = {}) {
  const { data, error } = await supabase.rpc('get_history', {
    p_mode: f.mode ?? null, p_result: f.result ?? null, p_category: f.category ?? null,
    p_opponent: f.opponent ?? null, p_group: f.group ?? null,
    p_since: f.since ?? null, p_until: f.until ?? null,
    p_sort: f.sort ?? 'recent', p_limit: f.limit ?? 30, p_offset: f.offset ?? 0
  });
  if (error) { console.error('❌ get_history:', error); return []; }
  return Array.isArray(data) ? data : [];
}
/** @param {string} opponentId @returns {Promise<any|null>} */
export async function getHeadToHead(opponentId) {
  const { data, error } = await supabase.rpc('get_head_to_head', { p_opponent: opponentId });
  if (error) { console.error('❌ get_head_to_head:', error); return null; }
  return data;
}
/** @param {string} matchId @returns {Promise<any|null>} */
export async function getMatchDetail(matchId) {
  const { data, error } = await supabase.rpc('get_match_detail', { p_match_id: matchId });
  if (error) { console.error('❌ get_match_detail:', error); return null; }
  return data;
}
/** Public profile by username + viewer's head-to-head + relationship flags.
 * @param {string} username @returns {Promise<any|null>} */
export async function getPublicProfile(username) {
  const { data, error } = await supabase.rpc('get_public_profile', { p_username: username });
  if (error) { console.error('❌ get_public_profile:', error); return null; }
  return data;
}
/** In-group challenge standings (W/played per member) + recent matches.
 * @param {string} groupId @returns {Promise<any|null>} */
export async function getGroupStandings(groupId) {
  const { data, error } = await supabase.rpc('get_group_standings', { p_group_id: groupId });
  if (error) { console.error('❌ get_group_standings:', error); return null; }
  return data;
}
/** Activity feed — you + friends + your groups (games, badges, joins).
 * @param {number} [limit] @param {number} [offset] @returns {Promise<any[]>} */
export async function getActivityFeed(limit = 30, offset = 0) {
  const { data, error } = await supabase.rpc('get_activity_feed', { p_limit: limit, p_offset: offset });
  if (error) { console.error('❌ get_activity_feed:', error); return []; }
  return Array.isArray(data) ? data : [];
}

/* ===== Power-ups (catalog + buy + use-in-Climb) ===== */
/** @returns {Promise<{cash:number, items:any[]}>} */
export async function getPowerups() {
  const { data, error } = await supabase.rpc('get_powerups');
  if (error || !data) { if (error) console.error('❌ get_powerups:', error); return { cash: 0, items: [] }; }
  return { cash: data.cash ?? 0, items: Array.isArray(data.items) ? data.items : [] };
}
/** @param {string} id @returns {Promise<{ok:boolean, reason?:string}>} */
export async function buyPowerup(id) {
  const { data, error } = await supabase.rpc('buy_powerup', { p_id: id });
  if (error || !data) { if (error) console.error('❌ buy_powerup:', error); return { ok: false }; }
  return data;
}
/* ===== Free Play cash-out (credits → real Cash, 40:1, $50/day cap) ===== */
/** @returns {Promise<{credits:number,cashable_credits:number,max_cash:number,rate:number,floor:number,daily_cap:number,cap_remaining:number}|null>} */
export async function getFreeplayCashoutStatus() {
  const { data, error } = await supabase.rpc('freeplay_cashout_status');
  if (error || !data) { if (error) console.error('❌ freeplay_cashout_status:', error); return null; }
  return data;
}
/** Cash out credits (null = the max allowed). @param {number|null} amount @returns {Promise<any>} */
export async function freeplayCashout(amount = null) {
  const { data, error } = await supabase.rpc('freeplay_cashout', { p_amount: amount });
  if (error || !data) { if (error) console.error('❌ freeplay_cashout:', error); return { ok: false }; }
  return data;
}
/** Use a power-up in the Climb. @param {string} id @returns {Promise<any>} */
export async function climbUsePowerup(id) {
  const { data, error } = await supabase.rpc('climb_use_powerup', { p_id: id });
  if (error) { console.error('❌ climb_use_powerup:', error); return null; }
  return data;
}
/** @param {string} date @returns {Promise<any>} */
export async function makeupReveal(date) {
  const { data, error } = await supabase.rpc('makeup_reveal', { p_date: date });
  if (error) { console.error('❌ makeup_reveal error:', error); return null; }
  return data;
}
/** @param {string} date @param {Record<string,string>} guess @returns {Promise<any>} */
export async function makeupSubmitGuess(date, guess) {
  const { data, error } = await supabase.rpc('makeup_submit_guess', { p_date: date, p_guess: guess });
  if (error) { console.error('❌ makeup_submit_guess error:', error); return null; }
  return data;
}

/* ===== Arcade Press-Your-Luck gauntlet (server-authoritative) =====
   Each returns { board, run } where run = { state, banked, multiplier, position,
   total, furthest, last_gain }. */
/** @returns {Promise<any>} */
export async function arcadeStart() {
  const { data, error } = await supabase.rpc('arcade_start');
  if (error) { console.error('❌ arcade_start error:', error); return null; }
  return data;
}
/** @param {string} letter @returns {Promise<any>} */
export async function arcadeBuyLetter(letter) {
  const { data, error } = await supabase.rpc('arcade_buy_letter', { p_letter: letter });
  if (error) { console.error('❌ arcade_buy_letter error:', error); return null; }
  return data;
}
/** @returns {Promise<any>} */
export async function arcadeReveal() {
  const { data, error } = await supabase.rpc('arcade_reveal');
  if (error) { console.error('❌ arcade_reveal error:', error); return null; }
  return data;
}
/** @param {Record<string,string>} guess @returns {Promise<any>} */
export async function arcadeSubmitGuess(guess) {
  const { data, error } = await supabase.rpc('arcade_submit_guess', { p_guess: guess });
  if (error) { console.error('❌ arcade_submit_guess error:', error); return null; }
  return data;
}
/** Advance after a solve / retry after a bust. @returns {Promise<any>} */
export async function arcadeNext() {
  const { data, error } = await supabase.rpc('arcade_next');
  if (error) { console.error('❌ arcade_next error:', error); return null; }
  return data;
}
/** Spend an earned power-up during the current run. @param {string} powerup @returns {Promise<any>} */
export async function arcadeUsePowerup(powerup) {
  const { data, error } = await supabase.rpc('arcade_use_powerup', { p_powerup: powerup });
  if (error) { console.error('❌ arcade_use_powerup error:', error); return null; }
  return data;
}
/** Cash out the current arcade run's winnings into your Bank. @returns {Promise<any>} */
export async function arcadeCashout() {
  const { data, error } = await supabase.rpc('arcade_cashout');
  if (error) { console.error('❌ arcade_cashout error:', error); return null; }
  return data;
}

/* ===== Challenge Builder (configurable N-player packs) ===== */
/**
 * @param {{ opponent?:string|null, group_id?:string|null, categories?:string[], pack_size?:number,
 *   mode?:string, wager?:number, payout?:string, window_seconds?:number, items_allowed?:boolean }} opts
 * @returns {Promise<{ok:boolean, reason?:string, match?:any}>}
 */
export async function createMatch(opts) {
  const { data, error } = await supabase.rpc('create_match', {
    p_opponent: opts.opponent ?? null, p_group_id: opts.group_id ?? null,
    p_categories: opts.categories ?? [], p_pack_size: opts.pack_size ?? 1,
    p_mode: opts.mode ?? 'standard', p_wager: opts.wager ?? 0,
    p_payout: opts.payout ?? 'winner', p_window_seconds: opts.window_seconds ?? 172800,
    p_items_allowed: opts.items_allowed ?? false
  });
  if (error || !data) { if (error) console.error('❌ create_match:', error); return { ok: false }; }
  return data;
}
/** @param {string} id @returns {Promise<{ok:boolean, reason?:string, match?:any}>} */
export async function acceptMatch(id, reduced = false) {
  const { data, error } = await supabase.rpc('accept_match', { p_id: id, p_reduced: reduced });
  if (error || !data) { if (error) console.error('❌ accept_match:', error); return { ok: false }; }
  return data;
}
/** Decline an invited challenge (voids + refunds if it can no longer happen). @param {string} id */
export async function declineMatch(id) {
  const { data, error } = await supabase.rpc('decline_match', { p_id: id });
  if (error || !data) { if (error) console.error('❌ decline_match:', error); return { ok: false }; }
  return data;
}
/** @param {string} id @returns {Promise<any|null>} */
export async function getMatch(id) {
  const { data, error } = await supabase.rpc('get_match', { p_id: id });
  if (error) { console.error('❌ get_match:', error); return null; }
  return data;
}
/** @returns {Promise<any[]>} */
export async function getMyMatches() {
  const { data, error } = await supabase.rpc('get_my_matches');
  if (error) { console.error('❌ get_my_matches:', error); return []; }
  return Array.isArray(data) ? data : [];
}
/** @param {string} id @returns {Promise<any|null>} */
export async function matchStart(id) {
  const { data, error } = await supabase.rpc('match_start', { p_id: id });
  if (error) { console.error('❌ match_start:', error); return null; }
  return data;
}
/** @param {string} id @param {string} letter @returns {Promise<any|null>} */
export async function matchBuyLetter(id, letter) {
  const { data, error } = await supabase.rpc('match_buy_letter', { p_id: id, p_letter: letter });
  if (error) { console.error('❌ match_buy_letter:', error); return null; }
  return data;
}
/** @param {string} id @returns {Promise<any|null>} */
export async function matchReveal(id) {
  const { data, error } = await supabase.rpc('match_reveal', { p_id: id });
  if (error) { console.error('❌ match_reveal:', error); return null; }
  return data;
}
/** Use an owned power-up in a match (if items are allowed). @param {string} id @param {string} powerup @returns {Promise<any|null>} */
export async function matchUsePowerup(id, powerup) {
  const { data, error } = await supabase.rpc('match_use_powerup', { p_id: id, p_powerup: powerup });
  if (error) { console.error('❌ match_use_powerup:', error); return null; }
  return data;
}
/** Sabotage an opponent in a match. @param {string} id @param {string} target @param {string} powerup @returns {Promise<any|null>} */
export async function matchSabotage(id, target, powerup) {
  const { data, error } = await supabase.rpc('match_sabotage', { p_id: id, p_target: target, p_powerup: powerup });
  if (error) { console.error('❌ match_sabotage:', error); return null; }
  return data;
}
/** @param {string} matchId @returns {Promise<any[]>} */
export async function getMatchMessages(matchId) {
  const { data, error } = await supabase.rpc('get_match_messages', { p_match_id: matchId });
  if (error) { console.error('❌ get_match_messages:', error); return []; }
  return Array.isArray(data) ? data : [];
}
/** @param {string} matchId @param {string} body @returns {Promise<{ok:boolean, reason?:string}>} */
export async function sendMatchMessage(matchId, body) {
  const { data, error } = await supabase.rpc('send_match_message', { p_match_id: matchId, p_body: body });
  if (error || !data) { if (error) console.error('❌ send_match_message:', error); return { ok: false }; }
  return data;
}
/** @param {string} id @param {Record<string,string>} guess @returns {Promise<any|null>} */
export async function matchSubmitGuess(id, guess) {
  const { data, error } = await supabase.rpc('match_submit_guess', { p_id: id, p_guess: guess });
  if (error) { console.error('❌ match_submit_guess:', error); return null; }
  return data;
}
/** Fold (forfeit) the current match puzzle → advances without a solve. @param {string} id */
export async function matchFold(id) {
  const { data, error } = await supabase.rpc('match_fold', { p_id: id });
  if (error) { console.error('❌ match_fold:', error); return null; }
  return data;
}
/** Force the server to settle a Blitz match when its clock expires. @param {string} id */
export async function matchCheck(id) {
  const { data, error } = await supabase.rpc('match_check', { p_id: id });
  if (error) { console.error('❌ match_check:', error); return null; }
  return data;
}

/* ===== Challenges (friend wagers) ===== */
/** @param {string} username @param {string} category @param {number} wager @param {string} [mode] */
export async function createChallenge(username, category, wager, mode = 'score') {
  const { data, error } = await supabase.rpc('create_challenge', { p_username: username, p_category: category, p_wager: wager, p_mode: mode });
  if (error || !data) { if (error) console.error('❌ create_challenge:', error); return { ok: false }; }
  return data;
}
/** Force the server to re-check a challenge play (used when a Pressure timer expires). @param {string} id */
export async function challengeCheck(id) {
  const { data, error } = await supabase.rpc('challenge_check', { p_id: id });
  if (error) { console.error('❌ challenge_check:', error); return null; }
  return data;
}
/** @param {string} id */
export async function acceptChallenge(id) {
  const { data, error } = await supabase.rpc('accept_challenge', { p_id: id });
  if (error || !data) { if (error) console.error('❌ accept_challenge:', error); return { ok: false }; }
  return data;
}
/** @param {string} id */
export async function getChallengeBoard(id) {
  const { data, error } = await supabase.rpc('get_challenge', { p_id: id });
  if (error) { console.error('❌ get_challenge:', error); return null; }
  return data;
}
/** My challenges inbox. @returns {Promise<any[]>} */
export async function getMyChallenges() {
  const { data, error } = await supabase.rpc('get_my_challenges');
  if (error) { console.error('❌ get_my_challenges:', error); return []; }
  return Array.isArray(data) ? data : [];
}
/** @param {string} id @param {string} letter */
export async function challengeBuyLetter(id, letter) {
  const { data, error } = await supabase.rpc('challenge_buy_letter', { p_id: id, p_letter: letter });
  if (error) { console.error('❌ challenge_buy_letter:', error); return null; }
  return data;
}
/** @param {string} id */
export async function challengeReveal(id) {
  const { data, error } = await supabase.rpc('challenge_reveal', { p_id: id });
  if (error) { console.error('❌ challenge_reveal:', error); return null; }
  return data;
}
/** @param {string} id @param {Record<string,string>} guess */
export async function challengeSubmitGuess(id, guess) {
  const { data, error } = await supabase.rpc('challenge_submit_guess', { p_id: id, p_guess: guess });
  if (error) { console.error('❌ challenge_submit_guess:', error); return null; }
  return data;
}

/** Whether the caller already has a session for today (drives the pre-game picker). */
export async function dailySessionExists() {
  const { data, error } = await supabase.rpc('daily_session_exists');
  if (error) { console.error('❌ daily_session_exists error:', error); return false; }
  return !!data;
}

/** Buy a letter. @param {string} letter @returns {Promise<object|null>} board */
export async function dailyBuyLetter(letter) {
  const { data, error } = await supabase.rpc('daily_buy_letter', { p_letter: letter });
  if (error) { console.error('❌ daily_buy_letter error:', error); return null; }
  return data;
}

/**
 * Fetch a user's earned badge ids (defaults to the caller).
 * @param {string} [userId]
 * @returns {Promise<string[]>}
 */
export async function getUserBadges(userId) {
  const { data, error } = await supabase.rpc('get_user_badges', userId ? { p_user_id: userId } : {});
  if (error) { console.error('❌ get_user_badges error:', error); return []; }
  return (data ?? []).map((/** @type {{ badge: string }} */ r) => r.badge);
}

/**
 * Fetch the caller's power-up inventory.
 * @returns {Promise<{powerup: string, count: number}[]>}
 */
export async function getUserPowerups() {
  const { data, error } = await supabase.rpc('get_user_powerups');
  if (error) { console.error('❌ get_user_powerups error:', error); return []; }
  return data ?? [];
}

/** Use a Free Reveal power-up (free smart reveal). @returns {Promise<object|null>} board */
export async function dailyUseFreeReveal() {
  const { data, error } = await supabase.rpc('daily_use_free_reveal');
  if (error) { console.error('❌ daily_use_free_reveal error:', error); return null; }
  return data;
}

/** Reveal ($150): all instances of the most-useful unrevealed letter. @returns {Promise<object|null>} board */
export async function dailyReveal() {
  const { data, error } = await supabase.rpc('daily_reveal');
  if (error) { console.error('❌ daily_reveal error:', error); return null; }
  return data;
}

/**
 * Submit a full guess.
 * @param {Record<string, string>} guess - map of absolute position -> guessed letter
 * @returns {Promise<object|null>} board
 */
export async function dailySubmitGuess(guess) {
  const { data, error } = await supabase.rpc('daily_submit_guess', { p_guess: guess });
  if (error) { console.error('❌ daily_submit_guess error:', error); return null; }
  return data;
}
/** Fold (give up) today's Daily → marks it lost and reveals the answer. */
export async function dailyFold() {
  const { data, error } = await supabase.rpc('daily_fold');
  if (error) { console.error('❌ daily_fold error:', error); return null; }
  return data;
}

/**
 * Fetch weekly leaderboard (limited)
 */
export async function fetchWeeklyLeaderboard(limit = 10) {
  const { data, error } = await supabase.rpc('get_weekly_leaderboard', { p_limit: limit });
  if (error) {
    console.error('❌ Error fetching leaderboard:', error);
    return [];
  }
  return data ?? [];
}

/**
 * Fetch ALL users with all stats (zeros when no record)
 */
export async function fetchAllUsersLeaderboard() {
  const { data, error } = await supabase.rpc('get_all_users_leaderboard');
  if (error) {
    console.error('❌ Error fetching all users leaderboard:', error);
    return [];
  }
  return data ?? [];
}

/**
 * Fetch leaderboard filtered by period: 'daily' | 'weekly' | 'monthly' | 'yearly'
 */
export async function fetchLeaderboardByPeriod(period = 'weekly') {
  const { data, error } = await supabase.rpc('get_leaderboard_by_period', {
    p_period: period
  });
  if (error) {
    console.error('❌ Error fetching leaderboard by period:', error);
    return [];
  }
  return data ?? [];
}
