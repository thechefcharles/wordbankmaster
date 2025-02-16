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
  gameState: "default", // "default", "purchase_pending", "guess_mode", "won", etc
  purchasedLetters: [],
  incorrectLetters: [],
  hintRevealedLetters: [],
  selectedPurchase: null, // { type: 'letter'|'hint'|'extra_guess', value?: letter }
  guessInput: [] // Array matching currentPhrase, populated in guess mode
});

// Helper function to check for loss conditions.
function checkLossCondition(state) {
    // Determine the cheapest purchase cost from letterCosts.
    const minLetterCost = Math.min(...Object.values(letterCosts));
    if (state.guessesRemaining <= 0 && state.bankroll < minLetterCost) {
      console.log("Loss condition triggered: no guesses remaining and insufficient bankroll.");
      return {
        ...state,
        gameState: "lost",
        // Automatically fill in the correct phrase.
        guessInput: state.currentPhrase.split(''),
        guessesRemaining: 0
      };
    }
    return state;
  }

// (Purchase mode functions remain here...)
// -- selectLetter, selectHint, selectExtraGuess, confirmPurchase, etc. --
export function selectLetter(letter) {
    gameStore.update(state => {
      // If the letter is already selected, deselect it.
      if (
        state.selectedPurchase &&
        state.selectedPurchase.type === 'letter' &&
        state.selectedPurchase.value === letter
      ) {
        console.log(`Deselecting letter: ${letter}`);
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      // Otherwise, select the letter (if not already purchased or marked incorrect)
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
          

// --- Guess Mode Functions ---

// Enter Guess Mode: clear any pending purchase and initialize guessInput.
export function enterGuessMode() {
  gameStore.update(state => {
    // If there are no guesses, check loss condition immediately.
    console.log("Entered guess mode here is the current state: ", state);

    // REMOVE THIS START
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
      // Otherwise, simply do not allow entering guess mode.
      console.log("Cannot enter guess mode: no guesses remaining.");
      return state;
    }
    // REMOVE THIS END

    // Toggle guess mode if already active.
    if (state.gameState === 'guess_mode') {
      console.log("Exiting guess mode.");
      return { ...state, gameState: "default", guessInput: [] };
    }
    // Initialize guessInput for guess mode.
    const guessInput = state.currentPhrase.split('').map(char =>
      char === ' ' ? ' ' : (state.purchasedLetters.includes(char) ? char : '')
    );
    console.log("Entering guess mode. Initial guessInput:", guessInput);
    return { ...state, gameState: "guess_mode", selectedPurchase: null, guessInput };
  });
}
    
// Helper: Compute editable indices (non-space and not purchased)

// Input a guess letter into the active (tracked) index.
// Helper: Compute editable indices (non-space and not purchased)
function getEditableIndices(state) {
    const indices = [];
    for (let i = 0; i < state.currentPhrase.length; i++) {
      if (state.currentPhrase[i] === ' ') continue;
      if (state.purchasedLetters.includes(state.currentPhrase[i])) continue;
      indices.push(i);
    }
    return indices;
  }
  
  // Input a guess letter into the active (tracked) index.
  // The active index is determined as the first editable index that is either empty
  // or filled with an incorrect letter. If all editable indices are filled correctly,
  // we default to the last one.
  export function inputGuessLetter(letter) {
    console.log("letter entered in guess mode: ", letter);
    gameStore.update(state => {
      console.log("state after letter guess but before function run: ", state)
      if (state.gameState !== "guess_mode") return state;
      // Do not allow letters that are already purchased.
      if (state.purchasedLetters.includes(letter)) {
        console.log("Letter already purchased; ignoring input in guess mode.");
        return state;
      }
      const editableIndices = getEditableIndices(state);
      console.log("editable indices: ", editableIndices);
      if (editableIndices.length === 0) return state;
  
      let activeIndex = null;
      // Look for the first empty editable slot.
      for (let j = 0; j < editableIndices.length; j++) {
        const idx = editableIndices[j];
        console.log("j inidces: ", editableIndices[j])
        if (state.guessInput[idx] === '') {
          activeIndex = idx;
          break;
        }
      }
      // If all editable slots are filled, default to the last one (to allow overriding).
      if (activeIndex === null) {
        activeIndex = editableIndices[editableIndices.length - 1];
      }
      const newGuessInput = [...state.guessInput];
      newGuessInput[activeIndex] = letter;
      console.log(`Input letter ${letter} at index ${activeIndex}. New guessInput:`, newGuessInput);
      return { ...state, guessInput: newGuessInput };
    });
  }
      
// Delete a letter from the current active guess slot, or recede to a previous slot.
export function deleteGuessLetter() {
    gameStore.update(state => {
      if (state.gameState !== "guess_mode") return state;
      const editableIndices = getEditableIndices(state);
      console.log("editable indices: ", editableIndices)
      if (editableIndices.length === 0) return state;
      
      // Determine the active index for deletion.
      // First, try to find the first editable index that is empty.
      let activeIndex = null;
      for (let j = 0; j < editableIndices.length; j++) {
        const idx = editableIndices[j];
        if (state.guessInput[idx] === '') {
          activeIndex = idx;
          break;
        }
      }
      // If all editable indices are filled, default to the last one.
      if (activeIndex === null) {
        activeIndex = editableIndices[editableIndices.length - 1];
      }
      // If the active slot is empty, recede: find the last non-empty editable slot before it.
      if (state.guessInput[activeIndex] === '') {
        for (let k = activeIndex - 1; k >= 0; k--) {
          if (editableIndices.includes(k) && state.guessInput[k] !== '') {
            activeIndex = k;
            break;
          }
        }
      }
      
      // Clear the letter at the active index.
      const newGuessInput = [...state.guessInput];
      newGuessInput[activeIndex] = '';
      console.log(`Deleted letter at index ${activeIndex}. New guessInput:`, newGuessInput);
      return { ...state, guessInput: newGuessInput };
    });
  }

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
      guessInput: []  // Will be initialized when entering guess mode.
    });
    console.log("Game reset.");
  }
  
// Submit the guess: for each editable index, if the input matches the phrase letter, keep it; if not, clear it.
// Then check for win condition (all editable slots correct) and update state.
export function submitGuess() {
    gameStore.update(state => {
      console.log("current state right after sumbitting: ", state);
      if (state.gameState !== "guess_mode") return state;
      const newGuessInput = [...state.guessInput];
      let allCorrect = true;
      console.log("after sumbitting: ", newGuessInput)
      for (let i = 0; i < state.currentPhrase.length; i++) {
        console.log("in the loop at index ", i, state.currentPhrase[i])
        console.log("does it inclue it: ", state.purchasedLetters.includes(state.currentPhrase[i]))
        if (state.currentPhrase[i] === ' ') continue;
        if (state.purchasedLetters.includes(state.currentPhrase[i])) continue;
        console.log("new input of i: ", newGuessInput[i]);
        console.log("current phrase of i: ", state.currentPhrase[i]);
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
        console.log("we should be here ");
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
    