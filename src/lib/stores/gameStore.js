import { writable } from 'svelte/store';

export const letterCosts = {
  Q: 30, W: 50, E: 140, R: 120, T: 120, Y: 60, U: 80, I: 110, O: 90, P: 80,
  A: 130, S: 120, D: 80, F: 60, G: 70, H: 70, J: 30, K: 50, L: 80,
  Z: 40, X: 40, C: 80, V: 50, B: 60, N: 100, M: 70
};

export const gameStore = writable({
  bankroll: 1000,
  guessesRemaining: 2,
  currentPhrase: "MICHAEL JORDAN",
  gameState: "default", // "default", "purchase_pending", "guess_mode", "won", "lost"
  // purchasedLetters: an array (indexed per character) holding locked letters.
  purchasedLetters: [],
  // guessedLetters: an object mapping index -> letter for current guess in guess mode.
  guessedLetters: {},
  // lockedLetters: an object mapping a letter to true only if every occurrence is correct.
  lockedLetters: {},
  incorrectLetters: [],
  hintRevealedLetters: [],
  selectedPurchase: null // { type: 'letter'|'hint'|'extra_guess', value?: letter }
  // (Deprecated: guessInput removed)
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
    if (
      state.selectedPurchase &&
      state.selectedPurchase.type === 'letter' &&
      state.selectedPurchase.value === letter
    ) {
      console.log(`Deselecting letter: ${letter}`);
      return { ...state, selectedPurchase: null, gameState: "default" };
    }
    // Instead of a global check with purchasedLetters, we check lockedLetters.
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
export function confirmPurchase() {
  gameStore.update(state => {
    if (!state.selectedPurchase) return state;
    const purchase = state.selectedPurchase;
    console.log("Selected purchase:", purchase);

    if (purchase.type === 'letter') {
      const letter = purchase.value;
      const cost = letterCosts[letter] || 0;
      if (state.bankroll < cost) {
        console.log(`Not enough bankroll to purchase letter ${letter}`);
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      const phrase = state.currentPhrase;

      if (state.gameState !== 'guess_mode') {
        // DEFAULT MODE: Purchase globally—update every occurrence.
        let newPurchased = [...state.purchasedLetters];
        for (let i = 0; i < phrase.length; i++) {
          if (phrase[i] === letter) {
            newPurchased[i] = letter;
          }
        }
        // If the letter doesn't appear in the phrase, mark it as incorrect.
        let newIncorrect = [...state.incorrectLetters];
        if (!phrase.includes(letter)) {
          newIncorrect.push(letter);
        }
        // Update lockedLetters for this letter:
        let newLockedLetters = { ...state.lockedLetters };
        const indices = [];
        for (let i = 0; i < phrase.length; i++) {
          if (phrase[i] === letter) indices.push(i);
        }
        newLockedLetters[letter] = indices.length > 0 && indices.every(idx => newPurchased[idx] === letter);
        
        // Check win condition: if every non-space index in the phrase is locked.
        let win = true;
        for (let i = 0; i < phrase.length; i++) {
          if (phrase[i] === ' ') continue;
          if (newPurchased[i] !== phrase[i]) {
            win = false;
            break;
          }
        }
        
        let newState = {
          ...state,
          bankroll: state.bankroll - cost,
          purchasedLetters: newPurchased,
          incorrectLetters: newIncorrect,
          lockedLetters: newLockedLetters,
          selectedPurchase: null,
          gameState: win ? "won" : "default"
        };
        return checkLossCondition(newState);
      } else {
        // GUESS MODE: Update only the active index.
        const editableIndices = [];
        for (let i = 0; i < phrase.length; i++) {
          if (phrase[i] === ' ') continue;
          if (state.purchasedLetters[i] === phrase[i]) continue;
          editableIndices.push(i);
        }
        if (editableIndices.length === 0) {
          return { ...state, selectedPurchase: null, gameState: "default" };
        }
        let activeIndex = -1;
        for (let j = 0; j < editableIndices.length; j++) {
          const idx = editableIndices[j];
          if (!state.guessedLetters.hasOwnProperty(idx)) {
            activeIndex = idx;
            break;
          }
        }
        if (activeIndex === -1) {
          activeIndex = editableIndices[editableIndices.length - 1];
        }
        if (phrase[activeIndex] === letter) {
          let newPurchased = [...state.purchasedLetters];
          newPurchased[activeIndex] = letter;
          let newGuessed = { ...state.guessedLetters, [activeIndex]: letter };
          let newState = {
            ...state,
            bankroll: state.bankroll - cost,
            purchasedLetters: newPurchased,
            guessedLetters: newGuessed,
            selectedPurchase: null,
            gameState: "default"
          };
          return checkLossCondition(newState);
        } else {
          console.log(`Letter ${letter} does not match target at active index; purchase canceled.`);
          return { ...state, selectedPurchase: null, gameState: "default" };
        }
      }
    } else if (purchase.type === 'hint') {
      const cost = 150;
      if (state.bankroll < cost) {
        console.log("Not enough bankroll for hint");
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      const phrase = state.currentPhrase;
      const unrevealed = phrase.split('').filter(
        ch => ch !== ' ' && !state.purchasedLetters.includes(ch)
      );
      if (unrevealed.length === 0) {
        console.log("No unrevealed letters available for hint");
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      const randomIndex = Math.floor(Math.random() * unrevealed.length);
      const chosenLetter = unrevealed[randomIndex].toUpperCase();
      console.log(`Hint: revealing letter ${chosenLetter}`);
      let newPurchased = [...state.purchasedLetters];
      for (let i = 0; i < phrase.length; i++) {
        if (phrase[i] === chosenLetter) {
          newPurchased[i] = chosenLetter;
        }
      }
      // Update lockedLetters for the chosen letter.
      let newLockedLetters = { ...state.lockedLetters };
      const indices = [];
      for (let i = 0; i < phrase.length; i++) {
        if (phrase[i] === chosenLetter) indices.push(i);
      }
      newLockedLetters[chosenLetter] = indices.length > 0 && indices.every(idx => newPurchased[idx] === chosenLetter);
      let newState = {
        ...state,
        bankroll: state.bankroll - cost,
        purchasedLetters: newPurchased,
        lockedLetters: newLockedLetters,
        selectedPurchase: null,
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
