import { writable } from 'svelte/store';
import { supabase } from '$lib/supabaseClient';

/**
 * @typedef {{ id: string, [key: string]: unknown }} AppUser
 * @typedef {{ id?: string, current_bankroll?: number, bank?: number, [key: string]: unknown }} ProfileData
 */

// 🧑 Authenticated Supabase user store
/** @type {import('svelte/store').Writable<AppUser | null>} */
export const user = writable(/** @type {AppUser | null} */ (null));

// 🧾 Player profile store (stats & bankroll)
/** @type {import('svelte/store').Writable<ProfileData>} */
export const userProfile = writable({
  current_bankroll: 1000,
  total_games_played: 0,
  total_games_won: 0,
  total_games_lost: 0,
  win_percentage: 0,
  highest_cash_streak: 0,
  most_puzzles_completed: 0,
  total_cash_accrued: 0,
  total_cash_spent: 0,
});

/**
 * 📥 Fetch the user profile from Supabase by userId
 * @param {string} userId - Supabase user ID
 * @returns {Promise<{ data: ProfileData | null, error: Error | { message?: string } | null }>} - User profile data or error
 */
export async function fetchUserProfile(userId) {
  try {
    console.log("🔄 Fetching profile for userId:", userId);

    const { data, error } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .maybeSingle();

    if (error) {
      console.error("❌ Failed to fetch profile:", error.message);
      return { data: null, error };
    }

    if (!data) {
      const errMsg = `❌ No profile found for userId: ${userId}`;
      console.error(errMsg);
      return { data: null, error: new Error(errMsg) };
    }

    console.log("✅ Profile loaded:", data);
    userProfile.set(data);
    return { data, error: null };
  } catch (err) {
    console.error("❌ Error in fetching user profile:", err instanceof Error ? err.message : String(err));
    return { data: null, error: err instanceof Error ? err : new Error(String(err)) };
  }
}

/**
 * 💾 Ensure a profile row exists for the user (creation fallback for the DB trigger).
 * INSERT-only: a duplicate (row already created by the on-signup trigger) is treated as success.
 * Bankroll and stats are never written from the client — those go through SECURITY DEFINER RPCs.
 * @param {string} userId - Supabase user ID
 * @returns {Promise<null | Error | { message?: string }>} - Returns error if creation truly failed
 */
export async function ensureProfileExists(userId) {
  try {
    const { error } = await supabase
      .from('profiles')
      .insert({ id: userId, bank: 2000 });

    // 23505 = unique_violation: the profile already exists (created by the on-signup trigger).
    // That's the expected happy path, not an error.
    if (error && error.code !== '23505') {
      console.error("❌ Failed to create profile:", error.message);
      return error;
    }

    return null;
  } catch (err) {
    console.error("❌ Error ensuring user profile:", err instanceof Error ? err.message : String(err));
    return err instanceof Error ? err : new Error(String(err));
  }
}