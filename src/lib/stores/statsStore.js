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
    return { has_played_today: false, last_daily_won: null, daily_bankroll: 0, arcade_bankroll: 1000, current_streak: 0, streak_freezes: 0 };
  }
  const row = Array.isArray(data) ? data[0] : data;
  return {
    has_played_today: !!row?.has_played_today,
    last_daily_won: row?.last_daily_won ?? null,
    daily_bankroll: row?.daily_bankroll ?? 0,
    arcade_bankroll: row?.arcade_bankroll ?? 1000,
    current_streak: row?.current_streak ?? 0,
    streak_freezes: row?.streak_freezes ?? 0
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
 * Fetch arcade leaderboard
 * @param {string} period - 'all' | 'daily' | 'weekly' | 'monthly' | 'yearly'
 * @param {string} orderBy - 'bankroll' | 'highest_bankroll' | 'streak' | 'highest_streak' | 'puzzles' | 'win_pct'
 */
export async function fetchArcadeLeaderboard(period = 'all', orderBy = 'bankroll') {
  const { data, error } = await supabase.rpc('get_arcade_leaderboard', {
    p_period: period,
    p_order_by: orderBy
  });
  if (error) {
    console.error('❌ Error fetching arcade leaderboard:', error);
    return [];
  }
  return data ?? [];
}

/**
 * Record arcade game result (call when arcade game ends - won or lost)
 * @param {string} userId
 * @param {boolean} won
 * @param {number} bankrollLeft
 */
export async function recordArcadeResult(userId, won, bankrollLeft) {
  const { error } = await supabase.rpc('record_arcade_result', {
    p_user_id: userId,
    p_won: won,
    p_bankroll_left: bankrollLeft
  });
  if (error) {
    console.error('❌ Error recording arcade result:', error);
  }
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

/**
 * Persist the caller's arcade bankroll between/within games.
 * Goes through a SECURITY DEFINER RPC (auth.uid() + clamp) instead of writing the
 * profiles table directly, so a client can't set an arbitrary bankroll on any row.
 * @param {number} bankroll
 */
export async function saveArcadeBankroll(bankroll) {
  const { error } = await supabase.rpc('save_arcade_bankroll', {
    p_bankroll: bankroll
  });
  if (error) {
    console.error('❌ Error saving arcade bankroll:', error);
  }
}

/**
 * Record daily game result (call when daily game ends - won or lost)
 * @param {string} userId
 * @param {boolean} won
 * @param {number} bankrollLeft
 */
export async function recordDailyResult(userId, won, bankrollLeft) {
  const { error } = await supabase.rpc('record_daily_result', {
    p_user_id: userId,
    p_won: won,
    p_bankroll_left: bankrollLeft
  });
  if (error) {
    console.error('❌ Error recording daily result:', error);
  }
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
