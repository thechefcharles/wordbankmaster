import { get } from 'svelte/store';
import { gameStore } from '$lib/stores/GameStore.js';

export function saveGameToLocalStorage() {
  const state = get(gameStore);
  localStorage.setItem('wordbank_game_state', JSON.stringify(state));
  console.log('💾 Game saved:', state); // optional debug
}

export function loadGameFromLocalStorage() {
    const saved = localStorage.getItem('wordbank_game_state');
    if (!saved) {
      console.log("🧩 No saved game found");
      return false;
    }
  
    try {
      const parsed = JSON.parse(saved);
  
      if (
        parsed &&
        parsed.currentPhrase &&
        Array.isArray(parsed.purchasedLetters) &&
        typeof parsed.bankroll === 'number'
      ) {
        gameStore.set(parsed);
        console.log('✅ Game state restored from localStorage:', parsed);
        return true;
      } else {
        console.warn("⚠️ Saved game incomplete:", parsed);
        return false;
      }
  
    } catch (e) {
      console.warn('⚠️ Failed to parse saved game:', e);
      return false;
    }
  }
export function clearSavedGame() {
  localStorage.removeItem('wordbank_game_state');
  console.log('🧹 Saved game cleared');
}
