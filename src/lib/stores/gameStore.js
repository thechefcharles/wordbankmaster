/**
 * GameStore.js
 *
 * This module contains the core game state and all functions for BankWord.
 * It includes:
 *  - The Svelte writable store that holds the game state.
 *  - A letter cost table.
 *  - A helper function (checkLossCondition) to evaluate loss conditions.
 *  - Functions to handle purchase mode actions (selecting letters/hints/extra guesses, confirming purchases).
 *  - Functions to handle guess mode actions (entering guess mode, inputting and deleting guess letters, submitting a guess).
 *  - A function to reset the game.
 */

import { writable } from 'svelte/store';

// --- Letter Cost Table ---
export const letterCosts = {
  Q: 30, W: 50, E: 140, R: 120, T: 120, Y: 60, U: 80, I: 110, O: 90, P: 80,
  A: 130, S: 120, D: 80, F: 60, G: 70, H: 70, J: 30, K: 50, L: 80,
  Z: 40, X: 40, C: 80, V: 50, B: 60, N: 100, M: 70
};

// --- Game Store Initialization ---
export const gameStore = writable({
  bankroll: 1000,
  guessesRemaining: 2,
  currentPhrase: "MICHAEL JORDAN",
  gameState: "default", // "default", "purchase_pending", "guess_mode", "won", "lost"
  purchasedLetters: [],
  incorrectLetters: [],
  hintRevealedLetters: [],
  selectedPurchase: null, // Object: { type: 'letter'|'hint'|'extra_guess', value?: letter }
  guessInput: []         // Array representing the user's guess for each letter; initialized in guess mode
});

// --- Helper Function --- 
/**
 * checkLossCondition(state)
 * Checks whether the loss (stalemate) condition is met:
 * - No guesses remaining AND bankroll is less than the cheapest letter cost.
 * If true, updates gameState to "lost", fills guessInput with the correct phrase, and sets guessesRemaining to 0.
 *
 * @param {Object} state - The current game state.
 * @returns {Object} The updated state.
 */
function checkLossCondition(state) {
  const minLetterCost = Math.min(...Object.values(letterCosts));
  if (state.guessesRemaining <= 0 && state.bankroll < minLetterCost) {
    console.log("Loss condition triggered: no guesses remaining and insufficient bankroll.");
    return {
      ...state,
      gameState: "lost",
      guessInput: state.currentPhrase.split(''),
      guessesRemaining: 0
    };
  }
  return state;
}

/*-------------------------------------------
  PURCHASE MODE FUNCTIONS
-------------------------------------------*/

/**
 * selectLetter(letter)
 * If the letter is already pending selection, deselect it.
 * Otherwise, if it hasn't been purchased or marked incorrect, set it as pending.
 */
export function selectLetter(letter) {
  gameStore.update(state => {
    if (
      state.selectedPurchase &&
      state.selectedPurchase.type === 'letter' &&
      state.selectedPurchase.value === letter
    ) {
      console.log(`Deselecting letter: ${letter}`);
      return { ...state, selectedPurchase: null, gameState: "default" };
    }
    if (state.purchasedLetters.includes(letter) || state.incorrectLetters.includes(letter)) {
      console.log(`Letter ${letter} already purchased or incorrect.`);
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
 * Processes the pending purchase (letter, hint, or extra guess):
 * - Deducts the cost from bankroll.
 * - Updates purchasedLetters or incorrectLetters as appropriate.
 * - If in guess mode, updates guessInput so that revealed letters appear.
 * - Finally, checks for loss condition.
 */
export function confirmPurchase() {
  gameStore.update(state => {
    if (!state.selectedPurchase) return state;
    const purchase = state.selectedPurchase;

    if (purchase.type === 'letter') {
      const letter = purchase.value;
      const cost = letterCosts[letter] || 0;
      if (state.bankroll < cost) {
        console.log(`Not enough bankroll to purchase letter ${letter}`);
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      const isCorrect = state.currentPhrase.includes(letter);
      let newGuessInput = state.guessInput;
      if (state.gameState === 'guess_mode') {
        newGuessInput = state.currentPhrase.split('').map((ch, i) =>
          ch === letter ? letter : state.guessInput[i]
        );
      }
      let newState = {
        ...state,
        bankroll: state.bankroll - cost,
        purchasedLetters: isCorrect
          ? [...state.purchasedLetters, letter]
          : state.purchasedLetters,
        incorrectLetters: !isCorrect
          ? [...state.incorrectLetters, letter]
          : state.incorrectLetters,
        selectedPurchase: null,
        guessInput: newGuessInput,
        gameState: "default"
      };
      return checkLossCondition(newState);
    } else if (purchase.type === 'hint') {
      const cost = 150;
      if (state.bankroll < cost) {
        console.log("Not enough bankroll for hint");
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      const unrevealed = state.currentPhrase.split('').filter(
        ch => ch !== ' ' && !state.purchasedLetters.includes(ch)
      );
      if (unrevealed.length === 0) {
        console.log("No unrevealed letters available for hint");
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      const randomIndex = Math.floor(Math.random() * unrevealed.length);
      const chosenLetter = unrevealed[randomIndex].toUpperCase();
      console.log(`Hint: revealing letter ${chosenLetter}`);
      const newGuessInput = state.currentPhrase.split('').map((ch, i) =>
        ch === chosenLetter ? chosenLetter : state.guessInput[i]
      );
      let newState = {
        ...state,
        bankroll: state.bankroll - cost,
        purchasedLetters: [...state.purchasedLetters, chosenLetter],
        selectedPurchase: null,
        guessInput: newGuessInput,
        gameState: "default"
      };
      return checkLossCondition(newState);
    } else if (purchase.type === 'extra_guess') {
      const cost = 150;
      if (state.bankroll < cost) {
        console.log("Not enough bankroll for extra guess");
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      let newState = {
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

/*-------------------------------------------
  GUESS MODE FUNCTIONS
-------------------------------------------*/

/**
 * enterGuessMode()
 * Toggles guess mode:
 * - If already in guess mode, exits it.
 * - Prevents entering guess mode if no guesses remain.
 * - Initializes guessInput with spaces and any pre-purchased letters.
 */
export function enterGuessMode() {
  gameStore.update(state => {
    if (state.guessesRemaining <= 0) {
      const minLetterCost = Math.min(...Object.values(letterCosts));
      if (state.bankroll < minLetterCost) {
        console.log("Cannot enter guess mode: no guesses and insufficient bankroll.");
        return {
          ...state,
          gameState: "lost",
          guessInput: state.currentPhrase.split(''),
          guessesRemaining: 0
        };
      }
      console.log("Cannot enter guess mode: no guesses remaining.");
      return state;
    }
    if (state.gameState === 'guess_mode') {
      console.log("Exiting guess mode.");
      return { ...state, gameState: "default", guessInput: [] };
    }
    const guessInput = state.currentPhrase.split('').map(char =>
      char === ' ' ? ' ' : (state.purchasedLetters.includes(char) ? char : '')
    );
    console.log("Entering guess mode. Initial guessInput:", guessInput);
    return { ...state, gameState: "guess_mode", selectedPurchase: null, guessInput };
  });
}

/**
 * getEditableIndices(state)
 * Returns an array of indices from currentPhrase that are editable (i.e. not a space and not locked by purchased letters).
 */
function getEditableIndices(state) {
  const indices = [];
  for (let i = 0; i < state.currentPhrase.length; i++) {
    if (state.currentPhrase[i] === ' ') continue;
    if (state.purchasedLetters.includes(state.currentPhrase[i])) continue;
    indices.push(i);
  }
  return indices;
}

/**
 * inputGuessLetter(letter)
 * In guess mode, fills the first available (empty) editable slot with the provided letter.
 * If all editable slots are filled, defaults to the last editable slot (allowing override).
 */
export function inputGuessLetter(letter) {
  gameStore.update(state => {
    if (state.gameState !== "guess_mode") return state;
    // Prevent input of letters that are already purchased.
    if (state.purchasedLetters.includes(letter)) {
      console.log("Letter already purchased; ignoring input in guess mode.");
      return state;
    }
    const editableIndices = getEditableIndices(state);
    if (editableIndices.length === 0) return state;

    let activeIndex = null;
    for (let j = 0; j < editableIndices.length; j++) {
      const idx = editableIndices[j];
      if (state.guessInput[idx] === '') {
        activeIndex = idx;
        break;
      }
    }
    if (activeIndex === null) {
      activeIndex = editableIndices[editableIndices.length - 1];
    }
    const newGuessInput = [...state.guessInput];
    newGuessInput[activeIndex] = letter;
    console.log(`Input letter ${letter} at index ${activeIndex}. New guessInput:`, newGuessInput);
    return { ...state, guessInput: newGuessInput };
  });
}

/**
 * deleteGuessLetter()
 * In guess mode, deletes the letter at the active guess slot.
 * If the active slot is empty, recedes to the last non-empty editable slot.
 */
export function deleteGuessLetter() {
  gameStore.update(state => {
    if (state.gameState !== "guess_mode") return state;
    const editableIndices = getEditableIndices(state);
    if (editableIndices.length === 0) return state;

    let activeIndex = null;
    for (let j = 0; j < editableIndices.length; j++) {
      const idx = editableIndices[j];
      if (state.guessInput[idx] === '') {
        activeIndex = idx;
        break;
      }
    }
    if (activeIndex === null) {
      activeIndex = editableIndices[editableIndices.length - 1];
    }
    if (state.guessInput[activeIndex] === '') {
      for (let k = activeIndex - 1; k >= 0; k--) {
        if (editableIndices.includes(k) && state.guessInput[k] !== '') {
          activeIndex = k;
          break;
        }
      }
    }
    const newGuessInput = [...state.guessInput];
    newGuessInput[activeIndex] = '';
    console.log(`Deleted letter at index ${activeIndex}. New guessInput:`, newGuessInput);
    return { ...state, guessInput: newGuessInput };
  });
}

/**
 * submitGuess()
 * Processes the user's guess in guess mode:
 * - Checks each editable slot; if a letter is incorrect, clears that slot.
 * - Deducts one guess.
 * - If all editable slots are correct, sets gameState to "won".
 * - Otherwise, applies the loss condition check.
 */
export function submitGuess() {
  gameStore.update(state => {
    if (state.gameState !== "guess_mode") return state;
    const newGuessInput = [...state.guessInput];
    let allCorrect = true;
    
    for (let i = 0; i < state.currentPhrase.length; i++) {
      if (state.currentPhrase[i] === ' ') continue;
      if (state.purchasedLetters.includes(state.currentPhrase[i])) continue;
      if (newGuessInput[i] !== state.currentPhrase[i]) {
        newGuessInput[i] = ''; // Clear incorrect input.
        allCorrect = false;
      }
    }
    
    const newGuessesRemaining = state.guessesRemaining - 1;
    
    if (allCorrect) {
      console.log("✅ Guess submitted correctly. You win!");
      return {
        ...state,
        gameState: "won",
        guessInput: newGuessInput,
        guessesRemaining: newGuessesRemaining
      };
    } else {
      let newState = {
        ...state,
        gameState: "default",
        guessInput: newGuessInput,
        guessesRemaining: newGuessesRemaining
      };
      newState = checkLossCondition(newState);
      if (newState.gameState === "lost") {
        return newState;
      } else {
        console.log("❌ Guess submitted incorrectly. Try again.");
        return newState;
      }
    }
  });
}

/**
 * resetGame()
 * Resets the game store to its initial state.
 */
export function resetGame() {
  gameStore.set({
    bankroll: 1000,
    guessesRemaining: 2,
    currentPhrase: "MICHAEL JORDAN", // Static phrase for now.
    gameState: "default",
    purchasedLetters: [],
    incorrectLetters: [],
    hintRevealedLetters: [],
    selectedPurchase: null,
    guessInput: [] // Will be initialized when entering guess mode.
  });
  console.log("Game reset.");
}
