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

/**
 * 🔄 Fetch user profile from Supabase
 * @param {string} userId - Supabase user ID
 * @returns {Promise<{ data: object, error: object }>}
 */
export async function fetchUserProfile(userId) {
  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', userId)
    .single();

  if (error) {
    console.error("❌ Failed to fetch profile:", error.message);
  } else {
    userProfile.set(data);
    console.log("✅ Profile loaded:", data);
  }

  return { data, error };
}

/**
 * 💾 Save updated profile data to Supabase
 * @param {object} updatedProfile - Updated profile object
 * @returns {Promise<object>} error if any
 */
export async function saveUserProfile(updatedProfile) {
  const { error } = await supabase
    .from('profiles')
    .update(updatedProfile)
    .eq('id', updatedProfile.id);

  if (error) {
    console.error("❌ Failed to save profile:", error.message);
  } else {
    userProfile.set(updatedProfile);
    console.log("✅ Profile updated:", updatedProfile);
  }

  return error;
}
