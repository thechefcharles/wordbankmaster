// src/lib/stores/GameStore.js

import { writable, get } from 'svelte/store';
import { supabase } from '$lib/supabaseClient.js';
import confetti from 'canvas-confetti';
import { saveUserProfile } from '$lib/stores/userStore.js';
import { user } from '$lib/stores/userStore.js';
import { saveGameToLocalStorage } from '$lib/stores/localGameUtils.js';



/* ================================
   Constants & Store Initialization
=================================== */

// Letter purchase costs
export const LETTER_COSTS = {
  Q: 30, W: 50, E: 140, R: 120, T: 120, Y: 60, U: 80, I: 110, O: 90, P: 80,
  A: 130, S: 120, D: 80, F: 60, G: 70, H: 70, J: 30, K: 50, L: 80,
  Z: 40, X: 40, C: 80, V: 50, B: 60, N: 100, M: 70
};

export const gameStore = writable({
  bankroll: 1000,
  wagerAmount: 1,
  category: '',
  currentPhrase: '',
  gameState: 'default', // States: "default", "purchase_pending", "guess_mode", "won", "lost"
  purchasedLetters: [],
  guessedLetters: {},
  lockedLetters: {},
  incorrectLetters: [],
  selectedPurchase: null,
  shakenLetters: [],
  message: ''
});

/* ================================
   Utility Functions
=================================== */

/**
 * launchConfetti
 * Triggers a celebratory confetti animation.
 */
function launchConfetti() {
  confetti({
    particleCount: 120,
    spread: 100,
    startVelocity: 40,
    scalar: 1.2,
    origin: { y: 0.6 }
  });
}

/**
 * animateBankrollReduction
 * Gradually reduces the bankroll to zero (used in game over).
 *
 * @param {number} startingAmount - The bankroll amount to start from.
 */
function animateBankrollReduction(startingAmount) {
  let currentAmount = startingAmount;
  const decrementStep = Math.max(1, Math.floor(startingAmount / 50)); // Use small decrement steps
  const interval = setInterval(() => {
    gameStore.update(state => {
      if (currentAmount <= 0) {
        clearInterval(interval);
        return { ...state, bankroll: 0 };
      }
      currentAmount -= decrementStep;
      return { ...state, bankroll: Math.max(0, currentAmount) };
    });
  }, 200);
}


/**
 * checkLossCondition
 * Ends the game if bankroll hits zero, reveals the phrase,
 * resets bankroll to 1000, and syncs state locally and remotely.
 *
 * @param {object} state - The current game state
 * @returns {object} Updated state if loss occurred, otherwise original state
 */
function checkLossCondition(state) {
  if (state.bankroll >= 1) return state;

  console.log("💀 Game Over: Bankroll is zero.");
  animateBankrollReduction(state.bankroll);

  // Reveal the full phrase
  const fullReveal = Object.fromEntries(
    state.currentPhrase.split('').map((ch, i) => [i, ch])
  );

  const resetBankroll = 1000;

  const newState = {
    ...state,
    gameState: "lost",
    guessedLetters: fullReveal,
    bankroll: resetBankroll
  };

  // 💾 Save to Supabase
  const currentUser = get(user);
  if (currentUser?.id) {
    saveUserProfile({ id: currentUser.id, current_bankroll: resetBankroll });
  }

  // 💾 Save to localStorage
  saveGameToLocalStorage();
  console.log("💾 Saved game state after loss:", newState);

  return newState;
}
/* ================================
   Purchase Mode Functions
=================================== */

/**
 * selectLetter
 * Selects or deselects a letter for purchase.
 *
 * @param {string} letter - The letter to select.
 */
export function selectLetter(letter) {
  gameStore.update(state => {
    const cost = LETTER_COSTS[letter] || 0;
    if (state.bankroll < cost) {
      console.log(`Insufficient funds to purchase letter ${letter}`);
      return state;
    }
    // Deselect if already selected
    if (
      state.selectedPurchase &&
      state.selectedPurchase.type === 'letter' &&
      state.selectedPurchase.value === letter
    ) {
      console.log(`Deselecting letter: ${letter}`);
      return { ...state, selectedPurchase: null, gameState: "default" };
    }
    // Prevent selection if letter is locked or marked incorrect
    if ((state.lockedLetters && state.lockedLetters[letter]) ||
        state.incorrectLetters.includes(letter)) {
      console.log(`Letter ${letter} is fully locked or marked incorrect.`);
      return state;
    }
    console.log(`Selecting letter: ${letter}`);
    return {
      ...state,
      gameState: "purchase_pending",
      selectedPurchase: { type: 'letter', value: letter }
    };
  });
}

/**
 * selectHint
 * Toggles hint selection for purchase.
 */
export function selectHint() {
  gameStore.update(state => {
    if (state.selectedPurchase && state.selectedPurchase.type === 'hint') {
      console.log("Deselecting hint");
      return { ...state, selectedPurchase: null, gameState: "default" };
    }
    console.log("Selecting hint");
    return {
      ...state,
      gameState: "purchase_pending",
      selectedPurchase: { type: 'hint' }
    };
  });
}


export function setWager(amount) {
  gameStore.update(state => ({
    ...state,
    wagerAmount: Math.max(1, Math.min(amount, state.bankroll))
  }));
}

// src/lib/stores/GameStore.js


// src/lib/stores/GameStore.js


/**
 * confirmPurchase
 * Handles purchase of a letter or hint and updates game state.
 */
export function confirmPurchase() {
  let finalState;

  gameStore.update(state => {
    const purchase = state.selectedPurchase;
    if (!purchase) return state;

    const phrase = state.currentPhrase;
    let newBankroll = state.bankroll;
    let newShakenLetters = new Set(state.shakenLetters || []);

    // === Handle Letter Purchase ===
    if (purchase.type === 'letter') {
      const letter = purchase.value;
      const cost = LETTER_COSTS[letter] || 0;
      if (newBankroll < cost) return { ...state, selectedPurchase: null };

      const newPurchased = [...state.purchasedLetters];
      const newIncorrect = [...state.incorrectLetters];
      const correctIndexes = [];

      // Reveal letter
      for (let i = 0; i < phrase.length; i++) {
        if (phrase[i] === letter) {
          newPurchased[i] = letter;
          if (!newShakenLetters.has(i)) correctIndexes.push(i);
        }
      }

      if (correctIndexes.length > 0) {
        correctIndexes.forEach(idx => newShakenLetters.add(idx));
      } else {
        newIncorrect.push(letter);
      }

      const newLockedLetters = { ...state.lockedLetters };
      const indices = phrase.split('').reduce((acc, ch, i) => {
        if (ch === letter) acc.push(i);
        return acc;
      }, []);
      newLockedLetters[letter] = indices.every(idx => newPurchased[idx] === letter);

      const win = phrase.split('').every((ch, i) => ch === ' ' || newPurchased[i] === ch);
      newBankroll -= cost;

      const newState = {
        ...state,
        bankroll: newBankroll,
        purchasedLetters: newPurchased,
        incorrectLetters: newIncorrect,
        lockedLetters: newLockedLetters,
        shakenLetters: Array.from(newShakenLetters),
        selectedPurchase: null, // ✅ make sure this is cleared
        gameState: win ? "won" : "default"
      };

      const currentUser = get(user);
      if (currentUser?.id) {
        saveUserProfile({ id: currentUser.id, current_bankroll: newBankroll });
      }

      finalState = checkLossCondition(newState);

      if (win) {
        setTimeout(() => launchConfetti(), 300);
      }

      return finalState;
    }

    // === Handle Hint Purchase ===
    if (purchase.type === 'hint') {
      const cost = 150;
      if (newBankroll < cost) return { ...state, selectedPurchase: null, gameState: "default" };

      const unrevealedIndices = phrase.split('').reduce((acc, ch, i) => {
        if (ch !== ' ' && !state.purchasedLetters[i]) acc.push(i);
        return acc;
      }, []);
      if (unrevealedIndices.length === 0) return { ...state, selectedPurchase: null, gameState: "default" };

      const randomIndex = unrevealedIndices[Math.floor(Math.random() * unrevealedIndices.length)];
      const letter = phrase[randomIndex];
      const newPurchased = [...state.purchasedLetters];
      newPurchased[randomIndex] = letter;

      const indices = phrase.split('').reduce((acc, ch, i) => {
        if (ch === letter) acc.push(i);
        return acc;
      }, []);
      const newLockedLetters = { ...state.lockedLetters };
      newLockedLetters[letter] = indices.every(idx => newPurchased[idx] === letter);

      newBankroll -= cost;

      const newState = {
        ...state,
        bankroll: newBankroll,
        purchasedLetters: newPurchased,
        lockedLetters: newLockedLetters,
        selectedPurchase: null,
        gameState: "default"
      };

      const currentUser = get(user);
      if (currentUser?.id) {
        saveUserProfile({ id: currentUser.id, current_bankroll: newBankroll });
      }

      finalState = checkLossCondition(newState);
      return finalState;
    }

    // ❌ Unknown purchase type
    return state;
  });

  // ✅ Save after update completes
  saveGameToLocalStorage();
}
/* ================================
   Guess Mode Functions
=============================================== */

/**
 * enterGuessMode
 * Toggles between default mode and guess mode.
 */
export function enterGuessMode() {
  gameStore.update(state => {
    if (state.gameState === 'guess_mode') {
      console.log("Exiting guess mode.");
      return { ...state, gameState: "default", guessedLetters: {} };
    }
    console.log("Entering guess mode.");
    return { ...state, gameState: "guess_mode", selectedPurchase: null, guessedLetters: {} };
  });
}

/**
 * getEditableIndices
 * Returns indices in the phrase that are editable (non-space and not already purchased).
 *
 * @param {object} state - The current game state.
 * @returns {number[]} Array of editable indices.
 */
function getEditableIndices(state) {
  const indices = [];
  for (let i = 0; i < state.currentPhrase.length; i++) {
    if (state.currentPhrase[i] === ' ') continue;
    if (state.purchasedLetters[i] === state.currentPhrase[i]) continue;
    indices.push(i);
  }
  return indices;
}

/**
 * inputGuessLetter
 * Inserts a guessed letter into the next available slot.
 *
 * @param {string} letter - The guessed letter.
 */
export function inputGuessLetter(letter) {
  gameStore.update(state => {
    if (state.gameState !== "guess_mode") return state;
    if (state.lockedLetters && state.lockedLetters[letter]) {
      console.log("Letter already fully locked; ignoring input in guess mode.");
      return state;
    }
    const editableIndices = getEditableIndices(state);
    if (editableIndices.length === 0) return state;

    // Find the first empty slot; if all filled, overwrite the last slot.
    let activeIndex = editableIndices.find(idx => !state.guessedLetters.hasOwnProperty(idx));
    if (activeIndex === undefined) {
      activeIndex = editableIndices[editableIndices.length - 1];
    }
    const newGuessed = { ...state.guessedLetters, [activeIndex]: letter };
    console.log(`Input letter ${letter} at index ${activeIndex}.`, newGuessed);
    return { ...state, guessedLetters: newGuessed };
  });
}

/**
 * deleteGuessLetter
 * Removes the last entered guessed letter.
 */
export function deleteGuessLetter() {
  gameStore.update(state => {
    if (state.gameState !== "guess_mode") return state;
    const editableIndices = getEditableIndices(state);
    if (editableIndices.length === 0) return state;

    // Remove the last filled slot
    let activeIndex = null;
    for (let i = editableIndices.length - 1; i >= 0; i--) {
      if (state.guessedLetters[editableIndices[i]]) {
        activeIndex = editableIndices[i];
        break;
      }
    }
    if (activeIndex === null) return state;
    const newGuessed = { ...state.guessedLetters };
    delete newGuessed[activeIndex];
    console.log(`Deleted letter at index ${activeIndex}.`, newGuessed);
    return { ...state, guessedLetters: newGuessed };
  });
}

/**
 * submitGuess
 * Validates user's full guess, updates state, adjusts bankroll,
 * syncs to Supabase, and hides wager slider.
 */
export function submitGuess() {
  gameStore.update(state => {
    if (state.gameState !== "guess_mode") return state;

    const phrase = state.currentPhrase;
    const wager = state.wagerAmount || 1;

    // 🔍 Abort if any guess slot is empty
    for (let i = 0; i < phrase.length; i++) {
      if (phrase[i] === ' ') continue;
      if (state.purchasedLetters[i] === phrase[i]) continue;
      if (!state.guessedLetters[i]) {
        console.log("⛔ Guess aborted: not all slots are filled.");
        return state;
      }
    }

    const newGuessed = { ...state.guessedLetters };
    const newPurchased = [...state.purchasedLetters];
    const newLockedLetters = { ...state.lockedLetters };
    const newShakenLetters = new Set(state.shakenLetters || []);
    const correctIndexes = [];
    let allCorrect = true;

    // ✅ Validate guessed letters
    for (let i = 0; i < phrase.length; i++) {
      if (phrase[i] === ' ') continue;
      if (newPurchased[i] === phrase[i]) continue;

      if (newGuessed[i] === phrase[i]) {
        newPurchased[i] = phrase[i];
        correctIndexes.push(i);
      } else {
        delete newGuessed[i];
        allCorrect = false;
      }
    }

    // 🔐 Lock fully guessed letters
    const distinctLetters = [...new Set(phrase.replace(/\s/g, ''))];
    distinctLetters.forEach(letter => {
      const indices = [];
      for (let i = 0; i < phrase.length; i++) {
        if (phrase[i] === letter) indices.push(i);
      }
      newLockedLetters[letter] = indices.every(idx => newPurchased[idx] === letter);
    });

    // 💥 Shake animation
    correctIndexes.forEach(idx => newShakenLetters.add(idx));

    const win = phrase.split('').every((ch, i) => ch === ' ' || newPurchased[i] === ch);
    const bankrollChange = (allCorrect || win) ? wager : -wager;
    const newBankroll = state.bankroll + bankrollChange;

    const newState = {
      ...state,
      gameState: (allCorrect || win) ? "won" : "default",
      guessedLetters: {},
      purchasedLetters: newPurchased,
      lockedLetters: newLockedLetters,
      shakenLetters: Array.from(newShakenLetters),
      bankroll: newBankroll
    };

    // 💾 Sync to Supabase
    const currentUser = get(user);
    if (currentUser?.id) {
      saveUserProfile({ id: currentUser.id, current_bankroll: newBankroll });
    }

    // 💾 Save to localStorage
    saveGameToLocalStorage();

    if (allCorrect || win) {
      console.log("✅ Correct guess! Wager won.");
      setTimeout(() => launchConfetti(), 300);
    } else {
      console.log("❌ Incorrect guess. Wager lost.");
    }

    return checkLossCondition(newState);
  });

  // 🧹 Clear feedback message after 2 seconds
  setTimeout(() => {
    gameStore.update(state => ({ ...state, message: "" }));
  }, 2000);

  // 🎛️ Hide wager UI after guess
  setTimeout(() => {
    const event = new CustomEvent('setWagerUIVisible', { detail: false });
    window.dispatchEvent(event);
  }, 100);
}
/* ================================
   Puzzle Fetch & Reset Functions
=================================== */

/**
 * fetchRandomGame
 * Pulls a new puzzle from the Supabase `get_random_puzzle` RPC,
 * resets the game state, and saves it immediately.
 */
export async function fetchRandomGame() {
  try {
    const { data, error } = await supabase.rpc('get_random_puzzle').single();
    if (error) throw error;

    const currentBankroll = get(gameStore).bankroll;

    const newState = {
      bankroll: currentBankroll,
      wagerAmount: 1,
      category: data.category,
      currentPhrase: data.phrase.toUpperCase(),
      gameState: 'default',
      purchasedLetters: [],
      guessedLetters: {},
      lockedLetters: {},
      incorrectLetters: [],
      selectedPurchase: null,
      shakenLetters: [],
      message: ''
    };

    gameStore.set(newState);
    saveGameToLocalStorage(); // 💾 Save puzzle immediately

    console.log(`✅ New game loaded and saved: ${data.phrase} [${data.category}]`);
  } catch (err) {
    console.error('❌ Error fetching puzzle:', err.message);
  }
}

/**
 * resetGame
 * Fetches a brand new puzzle from the database.
 */
export function resetGame() {
  fetchRandomGame();
}

/**
 * reduceBankrollToZero
 * Gradually reduces the bankroll to zero (for a game-over visual effect).
 */
export function reduceBankrollToZero() {
  gameStore.update(state => {
    if (state.gameState !== "lost") return state;

    const decrementRate = Math.max(state.bankroll / 100, 1);
    const interval = setInterval(() => {
      gameStore.update(state => {
        const newBankroll = Math.max(0, state.bankroll - decrementRate);
        if (newBankroll <= 0) {
          clearInterval(interval);
          return { ...state, bankroll: 0 };
        }
        return { ...state, bankroll: newBankroll };
      });
    }, 50);

    return state;
  });
}