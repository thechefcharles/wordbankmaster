// GameStore.js
import { writable } from 'svelte/store';
import { supabase } from '$lib/supabase.js';
import confetti from 'canvas-confetti';

/* ================================
   Constants & Store Initialization
=================================== */

// Cost definitions for each letter
export const LETTER_COSTS = {
  Q: 30,  W: 50,  E: 140, R: 120, T: 120, Y: 60,  U: 80,  I: 110, O: 90,  P: 80,
  A: 130, S: 120, D: 80,  F: 60,  G: 70,  H: 70,  J: 30,  K: 50,  L: 80,
  Z: 40,  X: 40,  C: 80,  V: 50,  B: 60,  N: 100, M: 70
};

// Initial state for the game store
export const gameStore = writable({
  bankroll: 1000,
  guessesRemaining: 2,
  category: "Person",
  currentPhrase: "MICHAEL JORDAN",
  gameState: "default", // States: "default", "purchase_pending", "guess_mode", "won", "lost"
  purchasedLetters: [],
  guessedLetters: {},
  lockedLetters: {},
  incorrectLetters: [],
  selectedPurchase: null,
  shakenLetters: [],
  extraGuessPending: false, // Flag for extra guess purchase pending
  message: "" // Feedback messages (e.g., incorrect guess)
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
 * Checks if the player has lost (no guesses remaining and insufficient bankroll).
 * Also reveals the entire phrase upon loss.
 *
 * @param {object} state - The current game state.
 * @returns {object} Updated state if loss condition met.
 */
function checkLossCondition(state) {
  const minLetterCost = Math.min(...Object.values(LETTER_COSTS));
  const isLost = state.guessesRemaining <= 0 && state.bankroll < minLetterCost;
  if (isLost) {
    console.log("💀 Game Over: No guesses remaining and insufficient bankroll.");
    animateBankrollReduction(state.bankroll);
    return {
      ...state,
      gameState: "lost",
      guessesRemaining: 0,
      guessedLetters: Object.fromEntries(
        state.currentPhrase.split('').map((ch, i) => [i, ch])
      )
    };
  }
  return state;
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

/**
 * selectExtraGuess
 * Toggles extra guess selection for purchase.
 */
export function selectExtraGuess() {
  gameStore.update(state => {
    if (state.selectedPurchase && state.selectedPurchase.type === 'extra_guess') {
      console.log("Deselecting extra guess");
      return { ...state, selectedPurchase: null, gameState: "default" };
    }
    console.log("Selecting extra guess");
    return {
      ...state,
      gameState: "purchase_pending",
      selectedPurchase: { type: 'extra_guess' }
    };
  });
}

/**
 * confirmPurchase
 * Processes the selected purchase (letter, hint, or extra guess) and updates the state.
 */
export function confirmPurchase() {
  gameStore.update(state => {
    if (!state.selectedPurchase) return state;
    const purchase = state.selectedPurchase;
    let newShakenLetters = new Set(state.shakenLetters || []);

    // --- Process Letter Purchase ---
    if (purchase.type === 'letter') {
      const letter = purchase.value;
      const cost = LETTER_COSTS[letter] || 0;
      if (state.bankroll < cost) return { ...state, selectedPurchase: null };

      const phrase = state.currentPhrase;
      let newPurchased = [...state.purchasedLetters];
      let newIncorrect = [...state.incorrectLetters];
      let correctIndexes = [];

      // Mark positions where the purchased letter occurs
      for (let i = 0; i < phrase.length; i++) {
        if (phrase[i] === letter) {
          newPurchased[i] = letter;
          if (!newShakenLetters.has(i)) correctIndexes.push(i);
        }
      }
      // Add indexes for shake animation if letter is found
      if (correctIndexes.length > 0) {
        correctIndexes.forEach(idx => newShakenLetters.add(idx));
      } else {
        newIncorrect.push(letter);
      }

      // Lock letter if all its occurrences are now purchased
      let newLockedLetters = { ...state.lockedLetters };
      const indices = phrase.split('').reduce((acc, ch, i) => {
        if (ch === letter) acc.push(i);
        return acc;
      }, []);
      newLockedLetters[letter] = indices.length > 0 &&
        indices.every(idx => newPurchased[idx] === letter);

      // Determine if the player has won
      const win = phrase.split('').every((ch, i) => ch === ' ' || newPurchased[i] === ch);
      const newState = {
        ...state,
        bankroll: state.bankroll - cost,
        purchasedLetters: newPurchased,
        incorrectLetters: newIncorrect,
        lockedLetters: newLockedLetters,
        shakenLetters: Array.from(newShakenLetters),
        selectedPurchase: null,
        gameState: win ? "won" : "default"
      };

      if (win) {
        setTimeout(() => launchConfetti(), 300);
      }
      return checkLossCondition(newState);
    }
    // --- Process Hint Purchase ---
    else if (purchase.type === 'hint') {
      const cost = 150;
      if (state.bankroll < cost) {
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      const phrase = state.currentPhrase;
      const unrevealedIndices = phrase.split('').reduce((acc, ch, i) => {
        if (ch !== ' ' && !state.purchasedLetters[i]) acc.push(i);
        return acc;
      }, []);
      if (unrevealedIndices.length === 0) return { ...state, selectedPurchase: null, gameState: "default" };

      const randomIndex = unrevealedIndices[Math.floor(Math.random() * unrevealedIndices.length)];
      let newPurchased = [...state.purchasedLetters];
      newPurchased[randomIndex] = phrase[randomIndex];

      let newLockedLetters = { ...state.lockedLetters };
      const letter = phrase[randomIndex];
      const indices = phrase.split('').reduce((acc, ch, i) => {
        if (ch === letter) acc.push(i);
        return acc;
      }, []);
      newLockedLetters[letter] = indices.every(idx => newPurchased[idx] === letter);

      const newState = {
        ...state,
        bankroll: state.bankroll - cost,
        purchasedLetters: newPurchased,
        lockedLetters: newLockedLetters,
        selectedPurchase: null,
        gameState: "default"
      };
      return checkLossCondition(newState);
    }
    // --- Process Extra Guess Purchase ---
    else if (purchase.type === 'extra_guess') {
      const cost = 150;
      if (state.bankroll < cost) {
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      const newState = {
        ...state,
        bankroll: state.bankroll - cost,
        guessesRemaining: state.guessesRemaining + 1,
        selectedPurchase: null,
        gameState: "default"
      };
      return checkLossCondition(newState);
    }
    return state;
  });
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
    if (state.guessesRemaining <= 0) {
      console.log("Cannot enter guess mode: no guesses remaining.");
      return state;
    }
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
 * Validates the guess, updates game state, and provides feedback.
 */
export function submitGuess() {
  gameStore.update(state => {
    if (state.gameState !== "guess_mode") return state;
    
    const phrase = state.currentPhrase;
    // Ensure all non-space positions are filled
    for (let i = 0; i < phrase.length; i++) {
      if (phrase[i] === ' ') continue;
      if (state.purchasedLetters[i] === phrase[i]) continue;
      if (!state.guessedLetters[i]) {
        console.log("Guess submission aborted: not all guess slots are filled.");
        return state;
      }
    }
    if (state.guessesRemaining <= 0) {
      console.log("No guesses remaining.");
      return state;
    }

    let newGuessed = { ...state.guessedLetters };
    let newPurchased = [...state.purchasedLetters];
    let newLockedLetters = { ...state.lockedLetters };
    let newShakenLetters = new Set(state.shakenLetters || []);
    let correctIndexes = [];
    let allCorrect = true;

    // Validate each guess
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

    // Update locked letters: lock a letter if all instances are correctly guessed/purchased.
    const distinctLetters = [...new Set(phrase.replace(/\s/g, ''))];
    distinctLetters.forEach(letter => {
      const indices = [];
      for (let i = 0; i < phrase.length; i++) {
        if (phrase[i] === letter) indices.push(i);
      }
      newLockedLetters[letter] = indices.every(idx => newPurchased[idx] === letter);
    });

    correctIndexes.forEach(idx => newShakenLetters.add(idx));
    const newGuessesRemaining = Math.max(state.guessesRemaining - 1, 0);
    const win = phrase.split('').every((ch, i) => ch === ' ' || newPurchased[i] === ch);

    if (allCorrect || win) {
      console.log("✅ Guess submitted correctly. You win!");
      return {
        ...state,
        gameState: "won",
        guessedLetters: newGuessed,
        purchasedLetters: newPurchased,
        lockedLetters: newLockedLetters,
        shakenLetters: Array.from(newShakenLetters),
        guessesRemaining: newGuessesRemaining,
      };
    } else {
      console.log("❌ Incorrect guess. Returning to default mode.");
      return checkLossCondition({
        ...state,
        gameState: "default",
        guessedLetters: newGuessed,
        purchasedLetters: newPurchased,
        lockedLetters: newLockedLetters,
        shakenLetters: Array.from(newShakenLetters),
        guessesRemaining: newGuessesRemaining,
        message: `❌ Incorrect! You have ${newGuessesRemaining} guesses remaining.`
      });
    }
  });

  // Clear feedback message after 2 seconds
  setTimeout(() => {
    gameStore.update(state => ({ ...state, message: "" }));
  }, 2000);

  // Toggle extra guess pending flag post submission
  gameStore.update(state => ({ ...state, extraGuessPending: !state.extraGuessPending }));
}

/* ================================
   Puzzle Fetch & Reset Functions
=================================== */

/**
 * fetchRandomGame
 * Retrieves a random puzzle using Supabase and initializes the game state.
 */
export async function fetchRandomGame() {
  try {
    const { data, error } = await supabase.rpc('get_random_puzzle').single();
    if (error) throw error;

    gameStore.set({
      bankroll: 1000,
      guessesRemaining: 2,
      currentPhrase: data.phrase.toUpperCase(),
      category: data.category,
      gameState: "default",
      purchasedLetters: [],
      guessedLetters: {},
      lockedLetters: {},
      incorrectLetters: [],
      selectedPurchase: null,
      shakenLetters: [],
      extraGuessPending: false,
      message: ""
    });
    console.log(`Game loaded: ${data.phrase} - ${data.category}`);
  } catch (err) {
    console.error("Error fetching game data:", err);
  }
}

/**
 * resetGame
 * Resets the game state to the initial values.
 */
export function resetGame() {
  gameStore.set({
    bankroll: 1000,
    guessesRemaining: 2,
    currentPhrase: "MICHAEL JORDAN",
    gameState: "default",
    purchasedLetters: [],
    lockedLetters: {},
    incorrectLetters: [],
    selectedPurchase: null,
    guessedLetters: {},
    shakenLetters: [],
    extraGuessPending: false,
    message: ""
  });
  console.log("Game reset.");
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
