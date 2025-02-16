import { writable } from 'svelte/store';

// Letter Costs (Based on original prompt)
const letterCosts = {
    Q: 30, W: 50, E: 140, R: 120, T: 120, Y: 60, U: 80, I: 110, O: 90, P: 80,
    A: 130, S: 120, D: 80, F: 60, G: 70, H: 70, J: 30, K: 50, L: 80,
    Z: 40, X: 40, C: 80, V: 50, B: 60, N: 100, M: 70
};

// Initial game state
export const gameState = writable({
    mode: 'default',
    bankroll: 1000,
    guessesRemaining: 2,
    phrase: 'MICHAEL JORDAN'.split(''),
    revealedLetters: new Set(),
    incorrectLetters: new Set(),
    selectedItem: null,
    selectedLetter: null,
    purchasePending: false,
    guessInput: [],
    guessTrackerIndex: null,
    gameOver: false
});

// Function to start a new game
export function startNewGame() {
    gameState.set({
        mode: 'default',
        bankroll: 1000,
        guessesRemaining: 2,
        phrase: 'MICHAEL JORDAN'.split(''),
        revealedLetters: new Set(),
        incorrectLetters: new Set(),
        selectedItem: null,
        selectedLetter: null,
        purchasePending: false,
        guessInput: [],
        guessTrackerIndex: null,
        gameOver: false
    });
}

// Function to select a letter, hint, or extra guess
export function selectItem(type, value = null) {
    gameState.update(state => {
        if (state.mode !== 'default') return state;

        if (state.selectedItem === type && state.selectedLetter === value) {
            return { ...state, selectedItem: null, selectedLetter: null, purchasePending: false };
        }

        return { ...state, selectedItem: type, selectedLetter: type === 'letter' ? value : null, purchasePending: true };
    });
}

// Function to cancel selection
export function cancelSelection() {
    gameState.update(state => ({
        ...state,
        selectedItem: null,
        selectedLetter: null,
        purchasePending: false
    }));
}

// Function to confirm a purchase
export function confirmPurchase() {
    gameState.update(state => {
        if (!state.purchasePending) return state;

        if (state.selectedItem === 'letter') {
            const letter = state.selectedLetter;
            if (!letter || !letterCosts[letter]) return state;

            if (state.bankroll >= letterCosts[letter]) {
                state.bankroll -= letterCosts[letter];
                state.phrase.includes(letter) ? state.revealedLetters.add(letter) : state.incorrectLetters.add(letter);
            }
        } else if (state.selectedItem === 'hint' && state.bankroll >= 150) {
            state.bankroll -= 150;
            let hiddenLetters = state.phrase.filter(l => !state.revealedLetters.has(l) && l !== ' ');
            if (hiddenLetters.length > 0) state.revealedLetters.add(hiddenLetters[Math.floor(Math.random() * hiddenLetters.length)]);
        } else if (state.selectedItem === 'extra_guess' && state.bankroll >= 150) {
            state.bankroll -= 150;
            state.guessesRemaining++;
        }

        return { ...state, selectedItem: null, selectedLetter: null, purchasePending: false };
    });
}

// ✅ Toggle Guess Mode On/Off
export function enterGuessMode() {
    gameState.update(state => {
        if (state.mode === 'guess_mode') {
            // ✅ If already in guess mode, return to default mode
            return {
                ...state,
                mode: 'default',
                guessTrackerIndex: null, // Reset tracker
            };
        } else if (state.mode === 'default') {
            // ✅ If in default mode, enter guess mode
            return {
                ...state,
                mode: 'guess_mode',
                purchasePending: false, // Cancel any pending purchases
                selectedItem: null,
                selectedLetter: null,
                guessInput: state.phrase.map(letter => (state.revealedLetters.has(letter) ? letter : '_')),
                guessTrackerIndex: state.phrase.findIndex(l => !state.revealedLetters.has(l) && l !== ' '),
            };
        }
        return state;
    });
}

// Function to update guess input
export function updateGuess(letter) {
    gameState.update(state => {
        if (state.mode !== 'guess_mode') return state;

        console.log("Guess Mode Active");

        let { guessTrackerIndex, revealedLetters } = state;

        if (guessTrackerIndex === -1) {
            console.log("No empty spaces to fill.");
            return state;
        }

        if (!revealedLetters.has(letter)) {
            console.log(`Inserting letter ${letter} at index ${guessTrackerIndex}`);
            
            // ✅ Use a Map to track guesses for better reactivity
            state.guessInput = [...state.guessInput]; // ✅ Ensure it's an array, not a Map
            updatedGuessInput.set(guessTrackerIndex, letter.toUpperCase());

            // Move tracker to next available space
            let nextIndex = [...state.phrase.keys()].find(i => i > guessTrackerIndex && !state.revealedLetters.has(state.phrase[i]));

            return {
                ...state,
                guessInput: updatedGuessInput,  // ✅ Assign a new Map
                guessTrackerIndex: nextIndex !== undefined ? nextIndex : guessTrackerIndex
            };
        }

        return state;
    });
}

// Function to delete the last letter in guess mode
export function deleteLastGuessLetter() {
    gameState.update(state => {
        if (state.mode !== 'guess_mode' || state.guessTrackerIndex === null) return state;

        if (state.guessTrackerIndex > 0) {
            state.guessInput[state.guessTrackerIndex] = '_';
            let prevIndex = state.guessInput.lastIndexOf('_', state.guessTrackerIndex - 1);
            state.guessTrackerIndex = prevIndex !== -1 ? prevIndex : state.guessTrackerIndex;
        }

        return { ...state, guessInput: [...state.guessInput] };
    });
}

// Function to submit a guess
export function submitGuess() {
    gameState.update(state => {
        if (state.mode !== 'guess_mode') return state;

        const correctPhrase = state.phrase.join('');
        const userGuess = state.guessInput.join('');

        if (userGuess === correctPhrase) {
            alert('Congratulations! You won!');
            return { ...state, gameOver: true };
        } else {
            state.guessInput = state.guessInput.map((letter, i) => (letter === correctPhrase[i] ? letter : '_'));
            state.guessesRemaining--;
            if (state.guessesRemaining === 0 && state.bankroll < 30) {
                alert('Game Over! You lost!');
                return { ...state, gameOver: true };
            }
        }

        return { ...state, mode: 'default', guessTrackerIndex: 0 };
    });
}
