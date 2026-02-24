import { get } from 'svelte/store';
import { gameStore } from '$lib/stores/GameStore.js';
import { user } from '$lib/stores/userStore.js';

/**
 * 💾 Save the current game state to localStorage (scoped by user ID)
 */
export function saveGameToLocalStorage() {
    const state = get(gameStore);
    const currentUser = get(user);
    const userId = currentUser?.id;
  
    if (!userId) {
      console.warn("⚠️ Cannot save game — no user ID");
      return;
    }
  
    const isValid =
      typeof state.currentPhrase === 'string' &&
      state.currentPhrase.trim().length > 0 &&
      typeof state.category === 'string' &&
      state.category.trim().length > 0 &&
      Array.isArray(state.purchasedLetters) &&
      typeof state.bankroll === 'number';
  
    if (!isValid) {
      console.warn("⚠️ Skipping save — invalid state:", state);
      return;
    }
  
    const key = `wordbank_game_state_${userId}`;
    localStorage.setItem(key, JSON.stringify(state));
    console.log(`💾 Game saved for user ${userId}:`, state);
  }
  
  /**
   * 📥 Load game state from localStorage (scoped by user ID)
   * @returns {boolean} whether a valid game was restored
   */
  export function loadGameFromLocalStorage() {
    const currentUser = get(user);
    const userId = currentUser?.id;
  
    if (!userId) {
      console.warn("⚠️ Cannot load saved game — no user ID");
      return false;
    }
  
    const key = `wordbank_game_state_${userId}`;
    const saved = localStorage.getItem(key);
    if (!saved) {
      console.log(`🧩 No saved game found for user ${userId}`);
      return false;
    }
  
    try {
      const parsed = JSON.parse(saved);
  
      const isValid =
        parsed &&
        typeof parsed.currentPhrase === 'string' &&
        parsed.currentPhrase.trim().length > 0 &&
        typeof parsed.category === 'string' &&
        parsed.category.trim().length > 0 &&
        Array.isArray(parsed.purchasedLetters) &&
        typeof parsed.bankroll === 'number';
  
      if (!isValid) {
        console.warn(`⚠️ Invalid saved game for user ${userId}:`, parsed);
        localStorage.removeItem(key);
        return false;
      }
  
      parsed.gameMode = parsed.gameMode === 'practice' ? 'arcade' : (parsed.gameMode || 'arcade');
      gameStore.set(parsed);
      console.log(`✅ Game state restored for user ${userId}:`, parsed);
      return true;
  
    } catch (err) {
      console.warn(`⚠️ Failed to parse saved game for user ${userId}:`, err);
      localStorage.removeItem(key);
      return false;
    }
  }
  
  /**
   * 🧹 Clear saved game from localStorage (scoped by user ID)
   */
  export function clearSavedGame() {
    const currentUser = get(user);
    const userId = currentUser?.id;
  
    if (!userId) {
      console.warn("⚠️ Cannot clear saved game — no user ID");
      return;
    }
  
    const key = `wordbank_game_state_${userId}`;
    localStorage.removeItem(key);
    console.log(`🧹 Saved game cleared for user ${userId}`);
  }