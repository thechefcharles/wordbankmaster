// GameStore.js
import { writable } from 'svelte/store';
import { supabase } from '$lib/supabase.js';
import confetti from 'canvas-confetti';

// -------------------- Cost Definitions --------------------
export const letterCosts = {
  Q: 30,  W: 50,  E: 140, R: 120, T: 120, Y: 60,  U: 80,  I: 110, O: 90,  P: 80,
  A: 130, S: 120, D: 80,  F: 60,  G: 70,  H: 70,  J: 30,  K: 50,  L: 80,
  Z: 40,  X: 40,  C: 80,  V: 50,  B: 60,  N: 100, M: 70
};

// -------------------- Store Initialization --------------------
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
  selectedPurchase: null,
  shakenLetters: []
});

// -------------------- Confetti + Utility --------------------
function launchConfetti() {
  confetti({
    particleCount: 120,
    spread: 100,
    startVelocity: 40,
    scalar: 1.2,
    origin: { y: 0.6 }
  });
}

// Check if the player lost: no guesses + insufficient bankroll.
function checkLossCondition(state) {
  const minLetterCost = Math.min(...Object.values(letterCosts));
  if (state.guessesRemaining <= 0 && state.bankroll < minLetterCost) {
    console.log("Loss condition triggered: no guesses remaining and insufficient bankroll.");
    return {
      ...state,
      gameState: "lost",
      // Reveal entire phrase
      guessedLetters: Object.fromEntries(
        state.currentPhrase.split('').map((ch, i) => [i, ch])
      ),
      guessesRemaining: 0
    };
  }
  return state;
}

// -------------------- Purchase Mode Functions --------------------
export function selectLetter(letter) {
  gameStore.update(state => {
    const cost = letterCosts[letter] || 0;
    if (state.bankroll < cost) {
      console.log(`Insufficient funds to purchase letter ${letter}`);
      return state;
    }
    // If currently selected is the same, deselect
    if (
      state.selectedPurchase &&
      state.selectedPurchase.type === 'letter' &&
      state.selectedPurchase.value === letter
    ) {
      console.log(`Deselecting letter: ${letter}`);
      return { ...state, selectedPurchase: null, gameState: "default" };
    }
    // If letter is locked or incorrect, ignore
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
    // Toggle if already selected
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
    // Toggle if already selected
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

export function confirmPurchase() {
  gameStore.update(state => {
    if (!state.selectedPurchase) return state;
    const purchase = state.selectedPurchase;

    // We'll keep a local set of shaken letters
    let newShakenLetters = new Set(state.shakenLetters || []);

    // 1) LETTER PURCHASE
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

      // Mark purchased positions; track new shakes
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
        // If none found, add to incorrect
        newIncorrect.push(letter);
      }

      // Update locked letters
      let newLockedLetters = { ...state.lockedLetters };
      const indices = phrase
        .split('')
        .map((ch, i) => (ch === letter ? i : -1))
        .filter(i => i !== -1);

      // If all positions for this letter are purchased, lock it
      newLockedLetters[letter] = indices.length > 0 &&
        indices.every(idx => newPurchased[idx] === letter);

      // Check win
      let win = phrase.split('').every((ch, i) => ch === ' ' || newPurchased[i] === ch);

      let newState = {
        ...state,
        bankroll: state.bankroll - cost,
        purchasedLetters: newPurchased,
        incorrectLetters: newIncorrect,
        lockedLetters: newLockedLetters,
        shakenLetters: Array.from(newShakenLetters),
        selectedPurchase: null,
        gameState: win ? "won" : "default"
      };

      // Trigger confetti if win
      if (win) {
        setTimeout(() => launchConfetti(), 300);
      }
      return checkLossCondition(newState);
    }

    // 2) HINT PURCHASE
    else if (purchase.type === 'hint') {
      const cost = 150;
      if (state.bankroll < cost) {
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      const phrase = state.currentPhrase;
      // find unrevealed indexes
      const unrevealed = phrase
        .split('')
        .map((ch, i) => (ch !== ' ' && !state.purchasedLetters[i] ? i : -1))
        .filter(i => i !== -1);

      if (unrevealed.length === 0) {
        // no letters to reveal
        return { ...state, selectedPurchase: null, gameState: "default" };
      }

      // pick one random unrevealed index
      const randomIndex = unrevealed[Math.floor(Math.random() * unrevealed.length)];
      let newPurchased = [...state.purchasedLetters];
      newPurchased[randomIndex] = phrase[randomIndex];

      // update locked letters
      let newLockedLetters = { ...state.lockedLetters };
      const letter = phrase[randomIndex];
      const indices = phrase
        .split('')
        .map((ch, i) => (ch === letter ? i : -1))
        .filter(i => i !== -1);

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

    // 3) EXTRA GUESS PURCHASE
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

// -------------------- Guess Mode Functions --------------------
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

// Return array of indices we can guess for (not locked & not spaces).
function getEditableIndices(state) {
  const indices = [];
  for (let i = 0; i < state.currentPhrase.length; i++) {
    if (state.currentPhrase[i] === ' ') continue;
    if (state.purchasedLetters[i] === state.currentPhrase[i]) continue;
    indices.push(i);
  }
  return indices;
}

export function inputGuessLetter(letter) {
  gameStore.update(state => {
    if (state.gameState !== "guess_mode") return state;
    if (state.lockedLetters && state.lockedLetters[letter]) {
      console.log("Letter already fully locked; ignoring input in guess mode.");
      return state;
    }
    const editableIndices = getEditableIndices(state);
    if (editableIndices.length === 0) return state;

    // find the first empty slot in guessedLetters
    let activeIndex = null;
    for (let idx of editableIndices) {
      if (!state.guessedLetters.hasOwnProperty(idx)) {
        activeIndex = idx;
        break;
      }
    }
    // fallback: if all are filled, overwrite the last one
    if (activeIndex === null) {
      activeIndex = editableIndices[editableIndices.length - 1];
    }
    const newGuessed = { ...state.guessedLetters, [activeIndex]: letter };
    console.log(`Input letter ${letter} at index ${activeIndex}.`, newGuessed);
    return { ...state, guessedLetters: newGuessed };
  });
}

export function deleteGuessLetter() {
  gameStore.update(state => {
    if (state.gameState !== "guess_mode") return state;
    const editableIndices = getEditableIndices(state);
    if (editableIndices.length === 0) return state;

    // find the last filled slot and clear it
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

export function submitGuess() {
  gameStore.update(state => {
    if (state.gameState !== "guess_mode") return state;

    // ensure all slots are filled
    const phrase = state.currentPhrase;
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

    const newGuessed = { ...state.guessedLetters };
    const newPurchased = [...state.purchasedLetters];
    let allCorrect = true;

    // lock correct guesses
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

    // update locked letters
    let newLockedLetters = { ...state.lockedLetters };
    const distinctLetters = [...new Set(phrase.replace(/\s/g, ''))];
    distinctLetters.forEach(letter => {
      const letterIndices = [];
      for (let i = 0; i < phrase.length; i++) {
        if (phrase[i] === letter) letterIndices.push(i);
      }
      newLockedLetters[letter] = letterIndices.every(idx => newPurchased[idx] === letter);
    });

    const newGuessesRemaining = Math.max(state.guessesRemaining - 1, 0);

    // check overall win
    let win = phrase.split('').every((ch, i) => ch === ' ' || newPurchased[i] === ch);

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
      console.log("❌ Incorrect guess. Returning to default mode.");
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

// -------------------- Puzzle Fetch & Reset --------------------
export async function fetchRandomGame() {
  try {
    // Call the Supabase RPC
    const { data, error } = await supabase.rpc('get_random_puzzle').single();
    if (error) throw error;

    // Initialize game store
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
      shakenLetters: []
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
    currentPhrase: "MICHAEL JORDAN",
    gameState: "default",
    purchasedLetters: [],
    lockedLetters: {},
    incorrectLetters: [],
    selectedPurchase: null,
    guessedLetters: {},
    shakenLetters: []
  });
  console.log("Game reset.");
}
