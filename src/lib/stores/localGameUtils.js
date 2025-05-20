import { get } from 'svelte/store';
import { gameStore } from '$lib/stores/GameStore.js'; // adjust path if needed

// 🔁 LOCAL STORAGE UTILITIES

export function saveGameToLocalStorage() {
  const state = get(gameStore);
  localStorage.setItem('wordbank_game_state', JSON.stringify(state));
}

export function loadGameFromLocalStorage() {
  const saved = localStorage.getItem('wordbank_game_state');
  if (saved) {
    try {
      const parsed = JSON.parse(saved);
      gameStore.set(parsed);
      console.log('✅ Game state restored from localStorage');
      return true;
    } catch (e) {
      console.warn('⚠️ Failed to parse saved game:', e);
    }
  }
  return false;
}

export function clearSavedGame() {
  localStorage.removeItem('wordbank_game_state');
}
