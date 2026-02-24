import { writable, get } from 'svelte/store';
import { supabase } from '$lib/supabaseClient';

/**
 * @typedef {{ id: string, [key: string]: unknown }} AppUser
 * @typedef {{ id?: string, current_bankroll?: number, arcade_bankroll?: number, [key: string]: unknown }} ProfileData
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
 * 💾 Save (insert or update) user profile data to Supabase
 * @param {ProfileData & { id: string }} updatedProfile - Updated profile object to insert or update
 * @returns {Promise<null | Error | { message?: string }>} - Returns error if any occurs during saving
 */
export async function saveUserProfile(updatedProfile) {
  try {
    console.log("🔄 Saving updated profile:", updatedProfile);

    const { error } = await supabase
      .from('profiles')
      .upsert(updatedProfile);

    if (error) {
      console.error("❌ Failed to save profile:", error.message);
      return error;
    }

    console.log("✅ Profile saved (inserted or updated):", updatedProfile);
    return null;
  } catch (err) {
    console.error("❌ Error in saving user profile:", err instanceof Error ? err.message : String(err));
    return err instanceof Error ? err : new Error(String(err));
  }
}

/**
 * 📊 Save daily stats (called after each puzzle or at end of session)
 */
export async function saveDailyStats({ puzzlesCompleted = 0, highestBankroll = 0, cashSpent = 0 }) {
  const currentUser = get(user);

  if (!currentUser?.id) {
    console.warn('⛔ No user found when trying to save daily stats.');
    return;
  }

  const today = new Date().toISOString().split('T')[0];

  const { data, error } = await supabase
    .from('daily_stats')
    .upsert({
      user_id: currentUser.id,
      date: today,
      puzzles_completed: puzzlesCompleted,
      highest_bankroll: highestBankroll,
      cash_spent: cashSpent
    }, {
      onConflict: 'user_id,date'
    });

  if (error) {
    console.error("❌ Error saving daily stats:", error.message);
  } else {
    console.log("✅ Daily stats saved:", data);
  }
}