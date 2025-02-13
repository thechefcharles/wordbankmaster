import { writable } from 'svelte/store';

// ✅ Define Letter Costs
export const letterCosts = {
  q: 30, w: 50, e: 140, r: 120, t: 120, y: 60, u: 80, i: 110, o: 90, p: 80,
  a: 130, s: 120, d: 80, f: 60, g: 70, h: 70, j: 30, k: 50, l: 80,
  z: 40, x: 40, c: 80, v: 50, b: 60, n: 100, m: 70
};

// ✅ Define Initial Game State
const initialState = {
  currentPhrase: "hello world",
  category: "Greeting",
  guessedLetters: [],
  purchasedLetters: [],
  correctPositions: [],
  bankroll: 1000,
  guesses: 2,
  isGuessMode: false,
  activeBoxIndex: null,
  winState: false,
  lossState: false,
  pendingPurchase: null,
  currentInput: ""
};

// ✅ Auto-fill spaces as correct
initialState.correctPositions = initialState.currentPhrase.split('').map(char => (char === ' ' ? char : null));

// ✅ Create Writable Store with Initial State
export const gameStore = writable({ ...initialState });

export const actions = {
  
  // ✅ Toggles Guess Mode
  toggleGuessMode() {
    gameStore.update(state => {
      if (state.guesses === 0) {
        alert('You need at least one guess remaining to enter Guess Mode!');
        return state;
      }
  
      const phraseArray = state.currentPhrase.split('');
  
      // ✅ Find the first empty space (not a space character)
      let firstEmptyIndex = phraseArray.findIndex((char, i) => !state.correctPositions[i] && char !== ' ');
  
      return {
        ...state,
        isGuessMode: !state.isGuessMode,
        activeBoxIndex: state.isGuessMode ? null : firstEmptyIndex,
        currentInput: state.isGuessMode ? state.correctPositions.join('') : state.currentInput,
        pendingPurchase: null // ✅ Clears any pending purchase when toggling
      };
    });
  },
      
toggleGuessModeAndClearPurchase() {
  gameStore.update(state => {
    if (state.pendingPurchase) {
      console.log("🟡 Pending purchase detected. Clearing and entering Guess Mode...");
      return {
        ...state,
        isGuessMode: true,
        activeBoxIndex: 0,
        currentInput: '',  // ✅ Clear any typed letters
        pendingPurchase: null, // ✅ Remove pending purchase selection
      };
    } else {
      console.log("🔹 No pending purchase. Just toggling Guess Mode...");
      return {
        ...state,
        isGuessMode: !state.isGuessMode,
        activeBoxIndex: state.isGuessMode ? null : 0,
        currentInput: state.isGuessMode ? '' : state.currentInput, // ✅ Reset input if leaving Guess Mode
        pendingPurchase: null, // ✅ Double-check that nothing is selected
      };
    }
  });

  // ✅ Ensure UI is fully reset (fix lingering blue selection)
  setTimeout(() => {
    document.activeElement?.blur();  
  }, 50);
},


  // ✅ Handles Letter Purchase Selection
  selectLetterForPurchase(letter) {
    console.log("🟣 selectLetterForPurchase called with:", letter);
  
    gameStore.update(state => {
      console.log("🔵 Before Update:", state.pendingPurchase);
      if (state.purchasedLetters.includes(letter) || state.correctPositions.includes(letter)) return state;
  
      const newState = {
        ...state,
        pendingPurchase: state.pendingPurchase?.letter === letter ? null : { letter, cost: letterCosts[letter] }
      };
  
      console.log("🔵 After Update:", newState.pendingPurchase);
      return newState;
    });
  },
  
  // ✅ Handles Guess Mode Input
  fillActiveBox(letter) {
    gameStore.update(state => {
      if (!state.isGuessMode || state.activeBoxIndex === null) return state;
  
      const phraseArray = state.currentPhrase.split('');
      let inputArray = state.currentInput.split('') || Array(phraseArray.length).fill('_');
  
      let currentIndex = state.activeBoxIndex;
  
      // ✅ SKIP spaces when entering letters
// ✅ Ensure currentIndex is NOT a space before inserting a letter
if (phraseArray[currentIndex] !== ' ') {
  inputArray[currentIndex] = letter;
}

// ✅ Find next valid box (SKIP spaces & pre-filled letters)
let nextIndex = currentIndex + 1;
while (nextIndex < phraseArray.length && (phraseArray[nextIndex] === ' ' || state.correctPositions[nextIndex])) {
  nextIndex++;  // ✅ Correct! Just update `nextIndex`
}

return {
  ...state,
  currentInput: inputArray.join(''),
  activeBoxIndex: nextIndex < phraseArray.length ? nextIndex : null
};
  
      // ✅ PLACE the letter in the correct position
      if (currentIndex < phraseArray.length) {
        inputArray[currentIndex] = letter;
      }
    
      return {
        ...state,
        currentInput: inputArray.join(''),
        activeBoxIndex: nextIndex < phraseArray.length ? nextIndex : null
      };
    });
  },
            
  // ✅ Handles Guess Submission
  submitGuess() {
    gameStore.update(state => {
      if (!state.isGuessMode || state.currentInput.includes('_')) {
        alert('Fill in every space before submitting!');
        return state;
      }

      const phraseArray = state.currentPhrase.split('');
      const newCorrectPositions = phraseArray.map((char, i) =>
        char.toLowerCase() === state.currentInput[i]?.toLowerCase() ? char : state.correctPositions[i] || null
      );

      const isWin = newCorrectPositions.join('') === phraseArray.join('');

      return {
        ...state,
        correctPositions: newCorrectPositions,
        currentInput: newCorrectPositions.join(''),
        isGuessMode: false,
        activeBoxIndex: null,
        winState: isWin,
        guesses: isWin ? state.guesses : state.guesses - 1
      };
    });
  },

  selectPurchase(type) {
    gameStore.update(state => {
      return {
        ...state,
        isGuessMode: false,  // ✅ Exit Guess Mode
        activeBoxIndex: null, // ✅ No active input
        currentInput: '',  // ✅ Clear any letters entered in Guess Mode
        pendingPurchase: state.pendingPurchase?.type === type ? null : { type, cost: type === 'hint' ? 150 : 100 }
      };
    });
  },
  

  // ✅ Handles All Purchases (Letters, Hints, Extra Guesses)
  confirmPurchase() {
    console.log("✅ confirmPurchase() FUNCTION CALLED!");
    
    gameStore.update(state => {
        if (!state.pendingPurchase) {
            console.log("⛔ No pending purchase detected.");
            return state;
        }

        let updatedState = { ...state };
        console.log("Before Purchase:", updatedState);

        const phraseArray = state.currentPhrase.split('');

        // ✅ Handling Letter Purchase
        if (state.pendingPurchase.letter) {
            const letter = state.pendingPurchase.letter.toLowerCase();
            if (updatedState.purchasedLetters.includes(letter)) return state; // ✅ Prevent duplicate purchases
            if (updatedState.bankroll < letterCosts[letter]) {
                alert("Not enough bankroll!");
                return state;
            }

            const isCorrect = phraseArray.includes(letter);
            if (isCorrect) {
                updatedState.correctPositions = updatedState.correctPositions.map((char, i) =>
                    phraseArray[i] === letter ? phraseArray[i] : char
                );
            } else {
                updatedState.guessedLetters = [...updatedState.guessedLetters, letter];
            }

            updatedState.purchasedLetters.push(letter);
            updatedState.bankroll -= letterCosts[letter];

            // ✅ Check for win condition
            updatedState.winState = updatedState.correctPositions.every((char, i) => char === phraseArray[i]);
        }

        // ✅ Handling Hint Purchase
        if (state.pendingPurchase.type === "hint") {
            console.log("🟡 Purchasing Hint...");
            console.log("Current Bankroll BEFORE:", updatedState.bankroll);

            if (updatedState.bankroll < 150) {
                alert("Not enough bankroll to buy a hint!");
                return state;
            }

            // ✅ Find all unrevealed letters
            const unrevealedIndexes = phraseArray
                .map((char, i) => (!updatedState.correctPositions[i] && char !== ' ' ? i : null))
                .filter(i => i !== null);

            if (unrevealedIndexes.length === 0) {
                console.log("⛔ No more letters left to reveal!");
                return state;
            }

            // ✅ Pick a random letter to reveal
            const randomIndex = unrevealedIndexes[Math.floor(Math.random() * unrevealedIndexes.length)];
            updatedState.correctPositions[randomIndex] = phraseArray[randomIndex];

            // ✅ Deduct cost from bankroll
            updatedState.bankroll -= 150;
            console.log("✅ After Hint Purchase - New Bankroll:", updatedState.bankroll);
            console.log("✅ Revealed Letter:", phraseArray[randomIndex]);
        }

        // ✅ Handling Extra Guess Purchase
        if (state.pendingPurchase.type === "guess") {
            console.log("🟡 Purchasing Extra Guess...");
            console.log("Current Bankroll BEFORE:", updatedState.bankroll);
            
            if (updatedState.bankroll < 100) {
                alert("Not enough bankroll to buy an extra guess!");
                return state;
            }

            updatedState.guesses += 1; // ✅ Increase guess count
            updatedState.bankroll -= 100; // ✅ Deduct cost of extra guess

            console.log("✅ After Guess Purchase - New Guesses:", updatedState.guesses);
            console.log("✅ After Guess Purchase - New Bankroll:", updatedState.bankroll);
        }

        // ✅ Reset pending purchase AFTER all types of purchases are checked
        updatedState.pendingPurchase = null;
        console.log("After Purchase:", updatedState);

        // ✅ Force Svelte to recognize the state update
        gameStore.set({ ...updatedState });

        return updatedState;
    });

    // ✅ Ensure UI Resets After State Update
    setTimeout(() => {
        gameStore.update(state => ({
            ...state,
            pendingPurchase: null, // ✅ Double-check nothing remains selected
        }));
    }, 50);
},

resetSelection() {
  gameStore.update(state => ({
    ...state,
    pendingPurchase: null // ✅ Ensures nothing remains selected after purchase
  }));
},


  deleteActiveBox() {
    gameStore.update(state => {
        if (!state.isGuessMode || state.activeBoxIndex === null) return state;

        let inputArray = state.currentInput.split('');

        // ✅ Remove letter at active index
        inputArray[state.activeBoxIndex] = '_';

        // ✅ Move back to the previous empty space
        let prevIndex = state.activeBoxIndex - 1;
        while (prevIndex >= 0 && state.correctPositions[prevIndex]) {
            prevIndex--;
        }

        return {
            ...state,
            currentInput: inputArray.join(''),
            activeBoxIndex: prevIndex >= 0 ? prevIndex : null
        };
    });
},


  // ✅ Checks for Loss Condition
  checkLossCondition(state) {
    if (state.bankroll < 30 && state.guesses === 0) {
      return { ...state, lossState: true, correctPositions: state.currentPhrase.split('') };
    }
    return state;
  },

  // ✅ Resets Game to Default State
  resetGame() {
    gameStore.set({ ...initialState, correctPositions: initialState.currentPhrase.split('').map(char => (char === ' ' ? char : null)) });
  }
};
