// src/lib/stores/userStore.js
import { writable } from 'svelte/store';
import { supabase } from '$lib/supabaseClient';

export const user = writable(null); // Supabase auth user

export const userProfile = writable({
  bankroll: 1000,
  games_played: 0,
  games_won: 0,
});

// 🔄 Fetch profile data from Supabase
export async function fetchUserProfile(userId) {
  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', userId)
    .single();

  if (data) {
    userProfile.set(data);
  }

  return { data, error };
}

// 💾 Save updated profile data
export async function saveUserProfile(updatedProfile) {
  const { error } = await supabase
    .from('profiles')
    .update(updatedProfile)
    .eq('id', updatedProfile.id);

  if (!error) {
    userProfile.set(updatedProfile); // 🔄 Sync store
  }

  return error;
}
