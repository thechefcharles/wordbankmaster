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
    return { has_played_today: false, last_daily_won: null, daily_bankroll: 0, arcade_bankroll: 1000 };
  }
  const row = Array.isArray(data) ? data[0] : data;
  return {
    has_played_today: !!row?.has_played_today,
    last_daily_won: row?.last_daily_won ?? null,
    daily_bankroll: row?.daily_bankroll ?? 0,
    arcade_bankroll: row?.arcade_bankroll ?? 1000
  };
}

/**
 * Fetch daily leaderboard
 * @param {string} period - 'daily' | 'weekly' | 'monthly' | 'yearly'
 * @param {string} orderBy - 'bankroll' | 'streak' | 'puzzles' | 'win_pct'
 */
export async function fetchDailyLeaderboard(period = 'daily', orderBy = 'bankroll') {
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
