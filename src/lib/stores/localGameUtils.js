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
   * 📋 Peek at saved game without restoring (for menu labels: Resume daily/arcade)
   * @param {string} userId
   * @returns {{ gameMode: string, gameState: string } | null}
   */
  export function getSavedGameInfo(userId) {
    if (!userId) return null;
    const key = `wordbank_game_state_${userId}`;
    const saved = localStorage.getItem(key);
    if (!saved) return null;
    try {
      const parsed = JSON.parse(saved);
      if (!parsed || typeof parsed.currentPhrase !== 'string' || !parsed.currentPhrase.trim()) return null;
      const gameMode = parsed.gameMode === 'practice' ? 'arcade' : (parsed.gameMode || 'arcade');
      const gameState = parsed.gameState || 'default';
      return { gameMode, gameState };
    } catch {
      return null;
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