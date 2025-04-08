// src/lib/stores/userStore.js

import { writable } from 'svelte/store';
import { supabase } from '$lib/supabaseClient';

// 🧑 Authenticated Supabase user
export const user = writable(null);

// 🧾 Player profile (stats & bankroll)
export const userProfile = writable({
  bankroll: 1000,
  games_played: 0,
  games_won: 0
});

// src/lib/stores/userStore.js

// src/lib/stores/userStore.js

/**
 * Fetch user profile from Supabase
 * @param {string} userId - Supabase user ID
 * @returns {Promise<{ data: object, error: object }>}
 */
export async function fetchUserProfile(userId) {
  console.log("Fetching profile for userId:", userId);  // Log the userId to check if it's correct

  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', userId)
    .single();

  if (error) {
    console.error("❌ Failed to fetch profile:", error.message);
    return { data: null, error };
  }

  if (!data) {
    console.error("❌ No profile found for user:", userId);
    return { data: null, error: new Error("No profile found.") };
  }

  console.log("✅ Profile loaded:", data);  // Log the fetched data to ensure the profile is correct
  userProfile.set(data);  // Store the user profile
  return { data, error: null };
}

/**
 * 💾 Save updated profile data to Supabase
 * @param {object} updatedProfile - Updated profile object
 * @returns {Promise<object>} error if any
 */
export async function saveUserProfile(updatedProfile) {
  console.log('Saving updated profile:', updatedProfile); // Log the profile to ensure it contains updated data

  const { error } = await supabase
    .from('profiles')
    .update(updatedProfile)
    .eq('id', updatedProfile.id);

  if (error) {
    console.error("❌ Failed to save profile:", error.message);
    return error;  // Return the error if it occurred
  } else {
    console.log("✅ Profile updated:", updatedProfile); // Log success
    return null;  // Return null if there were no errors
  }
}