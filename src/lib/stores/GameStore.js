// GameStore.js
import { writable } from 'svelte/store';
import { supabase } from '$lib/supabase.js';
import confetti from 'canvas-confetti';

/* ================================
   Cost Definitions & Store Initialization
=================================== */

// Define the cost for each letter.
export const letterCosts = {
  Q: 30,  W: 50,  E: 140, R: 120, T: 120, Y: 60,  U: 80,  I: 110, O: 90,  P: 80,
  A: 130, S: 120, D: 80,  F: 60,  G: 70,  H: 70,  J: 30,  K: 50,  L: 80,
  Z: 40,  X: 40,  C: 80,  V: 50,  B: 60,  N: 100, M: 70
};

// Initialize the game store with default properties.
export const gameStore = writable({
  bankroll: 1000,
  guessesRemaining: 2,
  category: "Person",
  currentPhrase: "MICHAEL JORDAN",
  gameState: "default", // Possible values: "default", "purchase_pending", "guess_mode", "won", "lost"
  purchasedLetters: [],
  guessedLetters: {},
  lockedLetters: {},
  incorrectLetters: [],
  selectedPurchase: null,
  shakenLetters: [],
  extraGuessPending: false, // Flag for extra guess pending purchase
  message: "" // Temporary feedback messages (e.g. incorrect guess)
});

/* ================================
   Utility Functions
=================================== */

/**
 * launchConfetti()
 * Triggers a confetti effect for celebration.
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
 * checkLossCondition(state)
 * Checks if the loss condition is met (no guesses remaining and insufficient bankroll)
 * and triggers the bankroll reduction animation if so.
 */
function checkLossCondition(state) {
  const minLetterCost = Math.min(...Object.values(letterCosts));
  const isLost = state.guessesRemaining <= 0 && state.bankroll < minLetterCost;

  if (isLost) {
    console.log("💀 Game Over: No guesses remaining and insufficient bankroll.");
    animateBankrollReduction(state.bankroll);
    return {
      ...state,
      gameState: "lost",
      guessesRemaining: 0,
      // Reveal the entire phrase upon loss.
      guessedLetters: Object.fromEntries(
        state.currentPhrase.split('').map((ch, i) => [i, ch])
      )
    };
  }
  return state;
}

/**
 * animateBankrollReduction(startingAmount)
 * Gradually reduces the bankroll from the starting amount to 0.
 */
function animateBankrollReduction(startingAmount) {
  let currentAmount = startingAmount;
  const step = Math.max(1, Math.floor(startingAmount / 50)); // Small decrement steps
  const interval = setInterval(() => {
    gameStore.update(state => {
      if (currentAmount <= 0) {
        clearInterval(interval);
        return { ...state, bankroll: 0 };
      }
      currentAmount -= step;
      return { ...state, bankroll: Math.max(0, currentAmount) };
    });
  }, 200);
}

/* ================================
   Purchase Mode Functions
=================================== */

/**
 * selectLetter(letter)
 * Selects a letter for purchase if funds are sufficient.
 * If the same letter is reselected, it deselects it.
 */
export function selectLetter(letter) {
  gameStore.update(state => {
    const cost = letterCosts[letter] || 0;
    if (state.bankroll < cost) {
      console.log(`Insufficient funds to purchase letter ${letter}`);
      return state;
    }
    if (
      state.selectedPurchase &&
      state.selectedPurchase.type === 'letter' &&
      state.selectedPurchase.value === letter
    ) {
      console.log(`Deselecting letter: ${letter}`);
      return { ...state, selectedPurchase: null, gameState: "default" };
    }
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
 * selectHint()
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
 * selectExtraGuess()
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
 * confirmPurchase()
 * Processes the current selected purchase based on its type (letter, hint, or extra guess).
 */
export function confirmPurchase() {
  gameStore.update(state => {
    if (!state.selectedPurchase) return state;
    const purchase = state.selectedPurchase;
    let newShakenLetters = new Set(state.shakenLetters || []);

    // --- Letter Purchase ---
    if (purchase.type === 'letter') {
      const letter = purchase.value;
      const cost = letterCosts[letter] || 0;
      if (state.bankroll < cost) {
        return { ...state, selectedPurchase: null };
      }
      const phrase = state.currentPhrase;
      let newPurchased = [...state.purchasedLetters];
      let newIncorrect = [...state.incorrectLetters];
      let correctIndexes = [];

      // Mark purchased letters and record indices for shaking animation
      for (let i = 0; i < phrase.length; i++) {
        if (phrase[i] === letter) {
          newPurchased[i] = letter;
          if (!newShakenLetters.has(i)) {
            correctIndexes.push(i);
          }
        }
      }
      if (correctIndexes.length > 0) {
        correctIndexes.forEach(idx => newShakenLetters.add(idx));
      } else {
        newIncorrect.push(letter);
      }

      // Update locked letters for the letter if all instances are purchased
      let newLockedLetters = { ...state.lockedLetters };
      const indices = phrase
        .split('')
        .map((ch, i) => (ch === letter ? i : -1))
        .filter(i => i !== -1);
      newLockedLetters[letter] = indices.length > 0 &&
        indices.every(idx => newPurchased[idx] === letter);

      // Check win condition
      let win = phrase.split('').every((ch, i) => ch === ' ' || newPurchased[i] === ch);

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

    // --- Hint Purchase ---
    else if (purchase.type === 'hint') {
      const cost = 150;
      if (state.bankroll < cost) {
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      const phrase = state.currentPhrase;
      const unrevealed = phrase
        .split('')
        .map((ch, i) => (ch !== ' ' && !state.purchasedLetters[i] ? i : -1))
        .filter(i => i !== -1);
      if (unrevealed.length === 0) {
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      const randomIndex = unrevealed[Math.floor(Math.random() * unrevealed.length)];
      let newPurchased = [...state.purchasedLetters];
      newPurchased[randomIndex] = phrase[randomIndex];

      let newLockedLetters = { ...state.lockedLetters };
      const letter = phrase[randomIndex];
      const indices = phrase
        .split('')
        .map((ch, i) => (ch === letter ? i : -1))
        .filter(i => i !== -1);
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

    // --- Extra Guess Purchase ---
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
=================================== */

/**
 * enterGuessMode()
 * Toggles between guess mode and default mode.
 */
export function enterGuessMode() {
  gameStore.update(state => {
    if (state.guessesRemaining <= 0) {
      console.log("Cannot enter guess mode: no guesses remaining.");
      return state;
    }
    if (state.gameState === 'guess_mode') {
      console.log("Exiting guess mode.");
      return { 
        ...state, 
        gameState: "default", 
        guessedLetters: {} 
      };
    }
    console.log("Entering guess mode.");
    return { 
      ...state, 
      gameState: "guess_mode", 
      selectedPurchase: null, 
      guessedLetters: {} 
    };
  });
}

/**
 * getEditableIndices(state)
 * Returns an array of indices for letters that are not spaces and not yet purchased.
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
 * inputGuessLetter(letter)
 * Inserts a guessed letter into the next available slot.
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

    // Find the first empty slot in guessedLetters; if all are filled, overwrite the last one.
    let activeIndex = null;
    for (let idx of editableIndices) {
      if (!state.guessedLetters.hasOwnProperty(idx)) {
        activeIndex = idx;
        break;
      }
    }
    if (activeIndex === null) {
      activeIndex = editableIndices[editableIndices.length - 1];
    }
    const newGuessed = { ...state.guessedLetters, [activeIndex]: letter };
    console.log(`Input letter ${letter} at index ${activeIndex}.`, newGuessed);
    return { ...state, guessedLetters: newGuessed };
  });
}

/**
 * deleteGuessLetter()
 * Removes the last entered guessed letter.
 */
export function deleteGuessLetter() {
  gameStore.update(state => {
    if (state.gameState !== "guess_mode") return state;
    const editableIndices = getEditableIndices(state);
    if (editableIndices.length === 0) return state;

    // Find the last filled slot in guessedLetters.
    let activeIndex = null;
    for (let i = editableIndices.length - 1; i >= 0; i--) {
      const idx = editableIndices[i];
      if (state.guessedLetters[idx]) {
        activeIndex = idx;
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
 * submitGuess()
 * Validates the guess, updates state for correct or incorrect submission,
 * and displays a message.
 */
export function submitGuess() {
  gameStore.update(state => {
    if (state.gameState !== "guess_mode") return state;
    
    const phrase = state.currentPhrase;
    // Check that all non-space slots have a guess.
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

    // Validate each guessed letter
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

    // Update locked letters: lock a letter if all its positions are correct.
    const distinctLetters = [...new Set(phrase.replace(/\s/g, ''))];
    distinctLetters.forEach(letter => {
      const letterIndices = [];
      for (let i = 0; i < phrase.length; i++) {
        if (phrase[i] === letter) letterIndices.push(i);
      }
      newLockedLetters[letter] = letterIndices.every(idx => newPurchased[idx] === letter);
    });

    correctIndexes.forEach(idx => newShakenLetters.add(idx));
    const newGuessesRemaining = Math.max(state.guessesRemaining - 1, 0);
    let win = phrase.split('').every((ch, i) => ch === ' ' || newPurchased[i] === ch);

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

  // Auto-clear feedback message after 2 seconds.
  setTimeout(() => {
    gameStore.update(state => ({ ...state, message: "" }));
  }, 2000);

  // Toggle the extra guess pending flag after submission.
  gameStore.update(state => ({ 
    ...state, 
    extraGuessPending: !state.extraGuessPending 
  }));
}

/* ================================
   Puzzle Fetch & Reset Functions
=================================== */

/**
 * fetchRandomGame()
 * Retrieves a random puzzle via a Supabase RPC and initializes the game store.
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
 * resetGame()
 * Resets the game store to its initial state.
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
 * reduceBankrollToZero()
 * Gradually reduces the bankroll to 0 (for game over effect) when the game state is "lost".
 */
export function reduceBankrollToZero() {
  gameStore.update(state => {
    if (state.gameState !== "lost") return state;
    let decrementRate = Math.max(state.bankroll / 100, 1);
    let interval = setInterval(() => {
      gameStore.update(state => {
        let newBankroll = Math.max(0, state.bankroll - decrementRate);
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
