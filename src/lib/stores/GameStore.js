import { writable } from 'svelte/store';
import { supabase } from '$lib/supabase.js';

export const letterCosts = {
  Q: 30, W: 50, E: 140, R: 120, T: 120, Y: 60, U: 80, I: 110, O: 90, P: 80,
  A: 130, S: 120, D: 80, F: 60, G: 70, H: 70, J: 30, K: 50, L: 80,
  Z: 40, X: 40, C: 80, V: 50, B: 60, N: 100, M: 70
};

export const gameStore = writable({
  bankroll: 1000,
  guessesRemaining: 2,
  category: "Person",
  currentPhrase: "MICHAEL JORDAN",
  gameState: "default", // "default", "purchase_pending", "guess_mode", "won", "lost"
  purchasedLetters: [],
  guessedLetters: {},
  lockedLetters: {},
  incorrectLetters: [],
  hintRevealedLetters: [],
  selectedPurchase: null,
  lastCorrectLetter: null,  // ✅ Track last purchased correct letter
});

// Helper: Check for loss conditions.
function checkLossCondition(state) {
  const minLetterCost = Math.min(...Object.values(letterCosts));
  if (state.guessesRemaining <= 0 && state.bankroll < minLetterCost) {
    console.log("Loss condition triggered: no guesses remaining and insufficient bankroll.");
    return {
      ...state,
      gameState: "lost",
      // Reveal entire phrase in guessedLetters.
      guessedLetters: Object.fromEntries(
        state.currentPhrase.split('').map((ch, i) => [i, ch])
      ),
      guessesRemaining: 0
    };
  }
  return state;
}


// ---------------- Purchase Mode Functions ----------------

// Default mode: select a letter for purchase.
export function selectLetter(letter) {
  gameStore.update(state => {
    // If user can’t afford this letter, do nothing.
    if (state.bankroll < (letterCosts[letter] || 0)) {
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
 * confirmPurchase:
 * - In default (purchase) mode, if a letter is purchased, update purchasedLetters per index.
 *   For each occurrence of the purchased letter in currentPhrase, set that index in purchasedLetters.
 *   Then check if every non‑space index is now locked; if so, set gameState to "won".
 * - In guess mode, update only the active index.
 */
import confetti from 'canvas-confetti';

export function confirmPurchase() {
  gameStore.update(state => {
    if (!state.selectedPurchase) return state;
    const purchase = state.selectedPurchase;

    // Preserve the set of letter indexes that have already been shaken
    let newShakenLetters = new Set(state.shakenLetters || []);

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

      // Loop through the phrase. For each occurrence of the letter:
      // - Set it as purchased.
      // - If its index hasn’t been shaken before, record it.
      for (let i = 0; i < phrase.length; i++) {
        if (phrase[i] === letter) {
          newPurchased[i] = letter;
          if (!newShakenLetters.has(i)) {
            correctIndexes.push(i);
          }
        }
      }

      // If any correct letter indexes are found, mark them as shaken.
      if (correctIndexes.length > 0) {
        correctIndexes.forEach(idx => newShakenLetters.add(idx));
      } else {
        // If the letter isn’t found, record it as an incorrect purchase.
        newIncorrect.push(letter);
      }

// Update locked letters for this letter only if it appears in the phrase.
let newLockedLetters = { ...state.lockedLetters };
const indices = phrase.split('').map((ch, i) => (ch === letter ? i : -1)).filter(i => i !== -1);
newLockedLetters[letter] = indices.length > 0 && indices.every(idx => newPurchased[idx] === letter);

      // Check win condition: Every non-space letter must be correctly purchased.
      let win = phrase.split('').every((ch, i) => ch === ' ' || newPurchased[i] === ch);

      let newState = {
        ...state,
        bankroll: state.bankroll - cost,
        purchasedLetters: newPurchased,
        incorrectLetters: newIncorrect,
        lockedLetters: newLockedLetters,
        // Save the shaken indexes so these letters won’t shake again
        shakenLetters: Array.from(newShakenLetters),
        selectedPurchase: null,
        gameState: win ? "won" : "default"
      };

      // Trigger confetti if the player wins.
      if (win) {
        setTimeout(() => launchConfetti(), 300);
      }

      return checkLossCondition(newState);
    }
    // HINT PURCHASE
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
      // Pick a random unrevealed letter.
      const randomIndex = unrevealed[Math.floor(Math.random() * unrevealed.length)];
      let newPurchased = [...state.purchasedLetters];
      newPurchased[randomIndex] = phrase[randomIndex];
      // Update locked letters for that letter.
      let newLockedLetters = { ...state.lockedLetters };
      const letter = phrase[randomIndex];
      const indices = phrase.split('').map((ch, i) => (ch === letter ? i : -1)).filter(i => i !== -1);
      newLockedLetters[letter] = indices.every(idx => newPurchased[idx] === letter);
      let newState = {
        ...state,
        bankroll: state.bankroll - cost,
        purchasedLetters: newPurchased,
        lockedLetters: newLockedLetters,
        selectedPurchase: null,
        gameState: "default"
      };
      return checkLossCondition(newState);
    }
    // EXTRA GUESS PURCHASE
    else if (purchase.type === 'extra_guess') {
      const cost = 150;
      if (state.bankroll < cost) {
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

// 🎉 Confetti Effect Function
function launchConfetti() {
  confetti({
    particleCount: 120,
    spread: 100,
    startVelocity: 40,
    scalar: 1.2, // Adjust for larger confetti
    origin: { y: 0.6 }
  });
}

// ---------------- Guess Mode Functions ----------------

// Enter guess mode: clear pending purchase and initialize guessedLetters.
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
    return { ...state, gameState: "guess_mode", selectedPurchase: null, guessedLetters: {} };
  });
}

// Helper: Compute editable indices – indices that are non‑space and not locked (i.e. not correctly purchased).
function getEditableIndices(state) {
  const indices = [];
  for (let i = 0; i < state.currentPhrase.length; i++) {
    if (state.currentPhrase[i] === ' ') continue;
    if (state.purchasedLetters[i] === state.currentPhrase[i]) continue;
    indices.push(i);
  }
  return indices;
}
  
// Input a guess letter into the next editable index (update guessedLetters).
export function inputGuessLetter(letter) {
  gameStore.update(state => {
    if (state.gameState !== "guess_mode") return state;
    if (state.lockedLetters && state.lockedLetters[letter]) {
      console.log("Letter already fully locked; ignoring input in guess mode.");
      return state;
    }
    const editableIndices = getEditableIndices(state);
    if (editableIndices.length === 0) return state;
    let activeIndex = null;
    for (let j = 0; j < editableIndices.length; j++) {
      const idx = editableIndices[j];
      if (!state.guessedLetters.hasOwnProperty(idx)) {
        activeIndex = idx;
        break;
      }
    }
    if (activeIndex === null) {
      activeIndex = editableIndices[editableIndices.length - 1];
    }
    const newGuessed = { ...state.guessedLetters, [activeIndex]: letter };
    console.log(`Input letter ${letter} at index ${activeIndex}. New guessedLetters:`, newGuessed);
    return { ...state, guessedLetters: newGuessed };
  });
}
      
// Delete a guess from the current active guess slot (or recede to a previous slot).
export function deleteGuessLetter() {
  gameStore.update(state => {
    if (state.gameState !== "guess_mode") return state;
    const editableIndices = getEditableIndices(state);
    if (editableIndices.length === 0) return state;
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
    console.log(`Deleted letter at index ${activeIndex}. New guessedLetters:`, newGuessed);
    return { ...state, guessedLetters: newGuessed };
  });
}
  
// Submit the guess:
// For each non-space index, if guessedLetters at that index equals the corresponding letter in currentPhrase,
// lock it in by updating purchasedLetters. Otherwise, clear the guess at that index.
// Then, update lockedLetters for each distinct letter in the phrase.
// Deduct one guess and return to default mode.
export function submitGuess() {
  gameStore.update(state => {
    if (state.gameState !== "guess_mode") return state;

    // Check that every editable slot is filled.
    const phrase = state.currentPhrase;
    for (let i = 0; i < phrase.length; i++) {
      if (phrase[i] === ' ') continue;
      if (state.purchasedLetters[i] === phrase[i]) continue;
      if (!state.guessedLetters[i]) {
        console.log("Guess submission aborted: not all guess slots are filled.");
        return state;
      }
    }

    // Prevent deducting a guess if none remain.
    if (state.guessesRemaining <= 0) {
      console.log("No guesses remaining.");
      return state;
    }

    const newGuessed = { ...state.guessedLetters };
    const newPurchased = [...state.purchasedLetters];
    let allCorrect = true;
    
    // Process each non-space character.
    for (let i = 0; i < phrase.length; i++) {
      if (phrase[i] === ' ') continue;
      if (newPurchased[i] === phrase[i]) continue;
      if (newGuessed[i] === phrase[i]) {
        newPurchased[i] = phrase[i];
      } else {
        delete newGuessed[i];
        allCorrect = false;
      }
    }
    
    // Update lockedLetters for each distinct letter.
    let newLockedLetters = { ...state.lockedLetters };
    const distinctLetters = Array.from(new Set(phrase.split('').filter(ch => ch !== ' ')));
    distinctLetters.forEach(letter => {
      const indices = [];
      for (let i = 0; i < phrase.length; i++) {
        if (phrase[i] === letter) indices.push(i);
      }
      newLockedLetters[letter] = indices.length > 0 && indices.every(idx => newPurchased[idx] === letter);
    });
    
    // Deduct one guess, ensuring it never goes below zero.
    const newGuessesRemaining = Math.max(state.guessesRemaining - 1, 0);
    
    // Determine win condition.
    let win = true;
    for (let i = 0; i < phrase.length; i++) {
      if (phrase[i] === ' ') continue;
      if (newPurchased[i] !== phrase[i]) {
        win = false;
        break;
      }
    }
    
    if (allCorrect || win) {
      console.log("✅ Guess submitted correctly. You win!");
      return {
        ...state,
        gameState: "won",
        guessedLetters: newGuessed,
        purchasedLetters: newPurchased,
        lockedLetters: newLockedLetters,
        guessesRemaining: newGuessesRemaining
      };
    } else {
      console.log("❌ Guess submitted incorrectly. Correct letters remain; returning to default mode.");
      const newState = {
        ...state,
        gameState: "default",
        guessedLetters: newGuessed,
        purchasedLetters: newPurchased,
        lockedLetters: newLockedLetters,
        guessesRemaining: newGuessesRemaining
      };
      return checkLossCondition(newState);
    }
  });
}

// In your GameStore.js
export async function fetchRandomGame() {
  try {
    // Call the RPC function get_random_puzzle()
    const { data, error } = await supabase
      .rpc('get_random_puzzle')
      .single();

    if (error) {
      throw error;
    }

    // Update the game store with the fetched puzzle.
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
      hintRevealedLetters: [],
      selectedPurchase: null
    });

    console.log(`Game loaded: ${data.phrase} - ${data.category}`);
  } catch (err) {
    console.error("Error fetching game data:", err);
  }
}

export function resetGame() {
  gameStore.set({
    bankroll: 1000,
    guessesRemaining: 2,
    currentPhrase: "MICHAEL JORDAN", // Static phrase for now.
    gameState: "default",
    purchasedLetters: [],
    lockedLetters: {},
    incorrectLetters: [],
    hintRevealedLetters: [],
    selectedPurchase: null,
    // Deprecated: guessInput
    guessedLetters: {}
  });
  console.log("Game reset.");
}
