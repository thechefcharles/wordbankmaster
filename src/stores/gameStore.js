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
  currentInput: "hello world".split('').map(c => c === ' ' ? ' ' : '_').join('')  // ✅ Ensure spaces are pre-filled
};

// ✅ Auto-fill spaces as correct
initialState.correctPositions = initialState.currentPhrase.split('').map(char => 
  char === ' ' ? ' ' : null
);

// ✅ Create Writable Store with Initial State
export const gameStore = writable({ ...initialState });

export const actions = {
  
  // ✅ Toggles Guess Mode
  toggleGuessMode() {
    gameStore.update(state => {
        if (!state.isGuessMode) {
            // ✅ Entering Guess Mode: Find the first empty box (not a space, not already correct)
            let firstEmptyIndex = state.currentPhrase.split('').findIndex((char, i) => 
                state.correctPositions[i] === null && char !== ' '
            );

            console.log("🔹 Entering Guess Mode. First Empty Index:", firstEmptyIndex);

            return {
                ...state,
                isGuessMode: true,
                activeBoxIndex: firstEmptyIndex, // ✅ Orange box starts at first empty spot
                currentInput: state.correctPositions.map((char, i) => 
                    char ? char : '_'
                ).join('') // ✅ Reset input to correct letters only
            };
        } else {
            // ✅ Exiting Guess Mode: Reset input to correct letters only
            console.log("🔹 Exiting Guess Mode. Resetting input.");

            return {
                ...state,
                isGuessMode: false,
                activeBoxIndex: null,
                currentInput: state.correctPositions.join('') // ✅ Remove any incorrect guesses
            };
        }
    });
},
toggleGuessModeAndClearPurchase() {
  gameStore.update(state => {
      // ✅ Prevent entering Guess Mode if the user has zero guesses
      if (state.guesses === 0) {
          console.log("⛔ Cannot enter Guess Mode - No guesses remaining!");
          alert("You need at least one guess to enter Guess Mode!");
          return state;
      }

      // ✅ If something is selected for purchase, clear it before entering Guess Mode
      if (state.pendingPurchase) {
          console.log("🟡 Clearing purchase and entering Guess Mode...");
          return {
              ...state,
              isGuessMode: true,
              activeBoxIndex: state.correctPositions.indexOf(null), // ✅ Find first empty box
              currentInput: '',
              pendingPurchase: null
          };
      }

      // ✅ Just toggle Guess Mode if nothing was selected
      console.log("🔹 Toggling Guess Mode...");
      return {
          ...state,
          isGuessMode: !state.isGuessMode,
          activeBoxIndex: state.isGuessMode ? null : state.correctPositions.indexOf(null),
          currentInput: state.isGuessMode ? '' : state.currentInput,
          pendingPurchase: null
      };
  });

  // ✅ Ensure UI is reset
  setTimeout(() => {
      document.activeElement?.blur();
  }, 50);
},


  // ✅ Handles Letter Purchase Selection
  selectLetterForPurchase(letter) {
    gameStore.update(state => {
        console.log("🟣 selectLetterForPurchase called with:", letter);

        // ✅ If Guess Mode is active, disable it when selecting a letter
        if (state.isGuessMode) {
            console.log("🔹 Exiting Guess Mode for Purchase");
            return {
                ...state,
                isGuessMode: false,
                activeBoxIndex: null,
                pendingPurchase: { letter, cost: letterCosts[letter] }
            };
        }

        // ✅ If the letter is already selected, deselect it
        if (state.pendingPurchase?.letter === letter) {
            console.log("🔹 Deselecting Letter:", letter);
            return {
                ...state,
                pendingPurchase: null
            };
        }

        // ✅ Otherwise, select the letter for purchase
        console.log("🔹 Selecting Letter:", letter);
        return {
            ...state,
            pendingPurchase: { letter, cost: letterCosts[letter] }
        };
    });
},
  
  // ✅ Handles Guess Mode Input
  fillActiveBox(letter) {
    gameStore.update(state => {
        if (!state.isGuessMode || state.activeBoxIndex === null) return state;

        const phraseArray = state.currentPhrase.split('');
        let inputArray = state.currentInput.split('');
        let currentIndex = state.activeBoxIndex;

        console.log(`🔹 Before Typing: ${inputArray.join('')}`);
        console.log("🔹 Current Phrase:", phraseArray.join(''));
        console.log("🔹 Active Box Index Before:", currentIndex);

        // ✅ Ensure the active box is a valid input position (not a space or already correct)
        while (phraseArray[currentIndex] === ' ' || state.correctPositions[currentIndex]) {
            console.warn("🚨 Skipping space or already correct letter at index:", currentIndex);
            currentIndex++;
        }

        // ✅ Insert letter in the active box
        if (currentIndex < phraseArray.length) {
            inputArray[currentIndex] = letter;
            console.log(`✅ Inserted Letter "${letter}" at index ${currentIndex}`);
        }

        // ✅ Find the next empty box, but don't move past the last valid box
        let nextIndex = currentIndex + 1;
        while (nextIndex < phraseArray.length && (phraseArray[nextIndex] === ' ' || state.correctPositions[nextIndex])) {
            nextIndex++;
        }

        // ✅ If at the last valid box, stop advancing
        if (nextIndex >= phraseArray.length) {
            nextIndex = currentIndex; // Stay in the last box
        }

        console.log("🔹 Next Active Box Index:", nextIndex);

        return {
            ...state,
            currentInput: inputArray.join(''), // ✅ Keeps input in sync
            activeBoxIndex: nextIndex // ✅ Prevents out-of-sync issues
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
        let newCorrectPositions = [...state.correctPositions];
        let newCurrentInput = [...state.currentInput]; 
        let newGuessedLetters = [...state.guessedLetters]; // ✅ Track incorrect guesses

        console.log("🔹 Before Submission:");
        console.log(`Phrase:  ${phraseArray.join('')}`);
        console.log(`Input:   ${state.currentInput}`);
        console.log(`Correct: ${newCorrectPositions.join('')}`);
        console.log("🔍 Before Guess - Correct Positions:", newCorrectPositions.join(''));
        console.log("🔍 User Input:", state.currentInput);

        // ✅ Compare input to the actual phrase and update correctPositions
        for (let i = 0; i < phraseArray.length; i++) {
            if (
                phraseArray[i].toLowerCase() === state.currentInput[i]?.toLowerCase() &&
                !state.correctPositions[i] // ✅ Only update if it's still empty!
            ) {
                newCorrectPositions[i] = phraseArray[i]; // ✅ Store correct letter
                newCurrentInput[i] = phraseArray[i]; // ✅ Keep correct letters in input
            } else if (!state.correctPositions[i]) {
                if (!newGuessedLetters.includes(state.currentInput[i])) {
                    newGuessedLetters.push(state.currentInput[i]); // ✅ Store incorrect guesses
                }
                newCurrentInput[i] = '_'; // ✅ Reset incorrect letters in phrase
            }
        }

        console.log("✅ After Submission:");
        console.log(`Correct: ${newCorrectPositions.join('')}`);
        console.log("✅ After Guess - Correct Positions:", newCorrectPositions.join(''));
        console.log("✅ Incorrect Guessed Letters:", newGuessedLetters.join(', '));

        // ✅ Win condition: Check if all letters are correct
        const isWin = newCorrectPositions.join('') === phraseArray.join('');
        const remainingGuesses = Math.max(state.guesses - 1, 0);  // ✅ Prevent negative guesses

        // ✅ Game Over Condition: 0 guesses & bankroll < $30 & not won
        const isLoss = remainingGuesses === 0 && state.bankroll < 30 && !isWin;

        console.log("✅ Guesses Remaining:", remainingGuesses);

        return {
            ...state,
            correctPositions: newCorrectPositions,
            guessedLetters: newGuessedLetters, // ✅ Update guessed letters for keyboard coloring
            currentInput: newCurrentInput.join(''), // ✅ Ensures incorrect letters disappear
            isGuessMode: false,
            activeBoxIndex: null,
            winState: isWin,
            lossState: isLoss,  // ✅ Now correctly triggers when necessary
            guesses: isWin ? state.guesses : remainingGuesses  // ✅ Prevent negative guesses
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

        // ✅ Game Over Condition: If bankroll is below $30 AND guesses are 0, trigger game over
        if (updatedState.guesses === 0 && updatedState.bankroll < 30) {
            updatedState.lossState = true;
            console.log("🚨 Game Over! No guesses and not enough bankroll.");
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
      let currentIndex = state.activeBoxIndex;

      console.log("🔹 Deleting Letter at:", currentIndex);

      // ✅ Remove letter at current position
      inputArray[currentIndex] = '_';

      // ✅ FIND PREVIOUS EMPTY BOX (if available)
      let prevIndex = currentIndex - 1;
      while (prevIndex >= 0 && (state.correctPositions[prevIndex] || state.currentPhrase[prevIndex] === ' ')) {
          prevIndex--;
      }

      // ✅ Stay in place if at the first box
      let newActiveIndex = prevIndex >= 0 ? prevIndex : currentIndex;

      console.log("🔹 New Active Box Index:", newActiveIndex);

      return {
          ...state,
          currentInput: inputArray.join(''),
          activeBoxIndex: newActiveIndex
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
    gameStore.set({
        ...initialState, 
        purchasedLetters: [],  // ✅ Reset purchased letters
        correctPositions: initialState.currentPhrase.split('').map(char => (char === ' ' ? char : null))
    });
}
};
