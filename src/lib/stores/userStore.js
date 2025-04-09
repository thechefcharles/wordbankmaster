import { writable } from 'svelte/store';
import { supabase } from '$lib/supabaseClient';

// 🧑 Authenticated Supabase user store
export const user = writable(null);

// 🧾 Player profile store (stats & bankroll)
export const userProfile = writable({
  bankroll: 1000,
  games_played: 0,
  games_won: 0,
  games_lost: 0,
  highest_streak: 0,
});

/**
 * 📥 Fetch the user profile from Supabase by userId
 * @param {string} userId - Supabase user ID
 * @returns {Promise<{ data: object, error: object }>} - User profile data or error
 */
export async function fetchUserProfile(userId) {
  try {
    console.log("🔄 Fetching profile for userId:", userId);

    const { data, error } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .single();

    // Error handling
    if (error) {
      console.error("❌ Failed to fetch profile:", error.message);
      return { data: null, error };
    }

    // If no profile found for the given userId
    if (!data) {
      const errMsg = `❌ No profile found for userId: ${userId}`;
      console.error(errMsg);
      return { data: null, error: new Error(errMsg) };
    }

    // Successfully fetched profile
    console.log("✅ Profile loaded:", data);
    userProfile.set(data);  // Update the userProfile store with the fetched data
    return { data, error: null };
  } catch (err) {
    console.error("❌ Error in fetching user profile:", err.message);
    return { data: null, error: err };
  }
}

/**
 * 💾 Save (insert or update) user profile data to Supabase
 * @param {object} updatedProfile - Updated profile object to insert or update
 * @returns {Promise<null | object>} - Returns error if any occurs during saving
 */
export async function saveUserProfile(updatedProfile) {
  try {
    console.log("🔄 Saving updated profile:", updatedProfile);

    const { error } = await supabase
      .from('profiles')
      .upsert(updatedProfile); // ✅ Handles both insert and update

    // Error handling
    if (error) {
      console.error("❌ Failed to save profile:", error.message);
      return error;
    }

    // Successfully saved the profile
    console.log("✅ Profile saved (inserted or updated):", updatedProfile);
    return null; // No error
  } catch (err) {
    console.error("❌ Error in saving user profile:", err.message);
    return err;  // Return the error if something goes wrong
  }
}
