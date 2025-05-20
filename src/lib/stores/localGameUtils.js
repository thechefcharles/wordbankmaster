import { get } from 'svelte/store';
import { gameStore } from '$lib/stores/GameStore.js';

/**
 * 💾 Save the current game state to localStorage
 */
export function saveGameToLocalStorage() {
  const state = get(gameStore);
  localStorage.setItem('wordbank_game_state', JSON.stringify(state));
  console.log('💾 Game saved:', state);
}

/**
 * 📥 Load game state from localStorage if valid
 * @returns {boolean} whether a valid game was restored
 */
export function loadGameFromLocalStorage() {
  const saved = localStorage.getItem('wordbank_game_state');

  if (!saved) {
    console.log("🧩 No saved game found");
    return false;
  }

  try {
    const parsed = JSON.parse(saved);

    // ✅ Validate required fields
    const isValid =
      parsed &&
      typeof parsed.currentPhrase === 'string' &&
      parsed.currentPhrase.trim().length > 0 &&
      typeof parsed.category === 'string' &&
      Array.isArray(parsed.purchasedLetters) &&
      typeof parsed.bankroll === 'number';

    if (!isValid) {
      console.warn("⚠️ Saved game incomplete or invalid:", parsed);
      localStorage.removeItem('wordbank_game_state');
      return false;
    }

    gameStore.set(parsed);
    console.log('✅ Game state restored from localStorage:', parsed);
    return true;

  } catch (err) {
    console.warn('⚠️ Failed to parse saved game:', err);
    localStorage.removeItem('wordbank_game_state');
    return false;
  }
}

/**
 * 🧹 Remove saved game from localStorage
 */
export function clearSavedGame() {
  localStorage.removeItem('wordbank_game_state');
  console.log('🧹 Saved game cleared');
}
