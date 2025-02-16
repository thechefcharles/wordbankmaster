import { writable } from 'svelte/store';

/**
 * letterCosts: Cost table for each letter.
 */
export const letterCosts = {
  Q: 30, W: 50, E: 140, R: 120, T: 120, Y: 60, U: 80, I: 110, O: 90, P: 80,
  A: 130, S: 120, D: 80, F: 60, G: 70, H: 70, J: 30, K: 50, L: 80,
  Z: 40, X: 40, C: 80, V: 50, B: 60, N: 100, M: 70
};

/**
 * gameStore: Holds the entire state of the game.
 */
export const gameStore = writable({
    bankroll: 1000,
    guessesRemaining: 2,
    currentPhrase: "MICHAEL JORDAN",
    category: "Person", // New property for category
    gameState: "default", // "default", "purchase_pending", "guess_mode", "won", "lost"
    purchasedLetters: [],
    incorrectLetters: [],
    hintRevealedLetters: [],
    selectedPurchase: null,
    guessInput: []
  });
  
/**
 * checkLossCondition(state):
 * Checks if guessesRemaining <= 0 and bankroll < minLetterCost => "lost".
 */
function checkLossCondition(state) {
  const minLetterCost = Math.min(...Object.values(letterCosts));
  if (state.guessesRemaining <= 0 && state.bankroll < minLetterCost) {
    console.log("Loss condition triggered: no guesses remaining + insufficient bankroll.");
    return {
      ...state,
      gameState: "lost",
      guessInput: state.currentPhrase.split(''),
      guessesRemaining: 0
    };
  }
  return state;
}

// ---------------- Purchase Mode Functions ----------------

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

// ---------------- Guess Mode Functions ----------------

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

function getEditableIndices(state) {
  const indices = [];
  for (let i = 0; i < state.currentPhrase.length; i++) {
    const char = state.currentPhrase[i];
    if (char === ' ') continue;
    if (state.purchasedLetters.includes(char)) continue;
    indices.push(i);
  }
  return indices;
}

export function inputGuessLetter(letter) {
  gameStore.update(state => {
    if (state.gameState !== "guess_mode") return state;
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
    console.log(`Input letter ${letter} at index ${activeIndex}.`, newGuessInput);
    return { ...state, guessInput: newGuessInput };
  });
}

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
    console.log(`Deleted letter at index ${activeIndex}.`, newGuessInput);
    return { ...state, guessInput: newGuessInput };
  });
}

export function submitGuess() {
  gameStore.update(state => {
    if (state.gameState !== "guess_mode") return state;
    const newGuessInput = [...state.guessInput];
    let allCorrect = true;

    for (let i = 0; i < state.currentPhrase.length; i++) {
      const char = state.currentPhrase[i];
      if (char === ' ') continue;
      if (state.purchasedLetters.includes(char)) continue;
      if (newGuessInput[i] !== char) {
        newGuessInput[i] = '';
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

export function resetGame() {
    gameStore.set({
      bankroll: 1000,
      guessesRemaining: 2,
      currentPhrase: "MICHAEL JORDAN",
      category: "Person", // Reset the category here
      gameState: "default",
      purchasedLetters: [],
      incorrectLetters: [],
      hintRevealedLetters: [],
      selectedPurchase: null,
      guessInput: []
    });
    console.log("Game reset.");
  }
  