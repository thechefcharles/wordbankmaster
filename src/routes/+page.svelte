<script>
    import { 
        gameState, 
        startNewGame, 
        confirmPurchase, 
        enterGuessMode, 
        updateGuess, 
        submitGuess, 
        deleteLastGuessLetter, 
        cancelSelection, 
        selectItem 
    } from '$lib/stores/gameStore';

    import Keyboard from '$lib/components/Keyboard.svelte';
    import PhraseDisplay from '$lib/components/PhraseDisplay.svelte';
    import { goto } from '$app/navigation';

    let currentState;
    gameState.subscribe(value => currentState = value);

    let username = 'Guest';

    if (typeof window !== 'undefined') {
        username = localStorage.getItem('username') || 'Guest';
        console.log('User Logged In:', username !== 'Guest' ? `Yes (Username: ${username})` : 'No');
    }

    function handleLetterClick(event) {
        const { letter } = event.detail;

        if (currentState.mode === 'default') {
            selectItem('letter', letter);
        } 
        else if (currentState.mode === 'guess_mode') {
            console.log(`Guess Mode Letter Clicked: ${letter}`); 
            updateGuess(letter); // ✅ Update guess input
        }
    }

    function handleEnter() {
        if (currentState.purchasePending) {
            confirmPurchase();
        } else if (currentState.mode === 'guess_mode') {
            submitGuess();
        }
    }

    function logout() {
        localStorage.removeItem('username'); 
        goto('/login'); 
    }

    // Letter Costs (Needed for Keyboard Component)
    const letterCosts = {
        Q: 30, W: 50, E: 140, R: 120, T: 120, Y: 60, U: 80, I: 110, O: 90, P: 80,
        A: 130, S: 120, D: 80, F: 60, G: 70, H: 70, J: 30, K: 50, L: 80,
        Z: 40, X: 40, C: 80, V: 50, B: 60, N: 100, M: 70
    };
</script>

<main class="game-container">
    <h1>WordBank</h1>
    <h2>Welcome, {username}!</h2>
    <button on:click={logout} class="logout-button">Logout</button>

    <div class="game-info">
        <p>Category: <strong>Person</strong></p>
        <p>Bankroll: <strong>${currentState.bankroll}</strong></p>
        <p>Guesses Remaining: <strong>${currentState.guessesRemaining}</strong></p>
    </div>

    <PhraseDisplay 
        phrase={currentState.phrase} 
        revealedLetters={currentState.revealedLetters} 
        guessInput={currentState.guessInput}  
        guessTrackerIndex={currentState.guessTrackerIndex} 
        mode={currentState.mode} 
    />

    <div class="button-container">
        <button on:click={handleEnter} class="enter-button {currentState.purchasePending ? 'confirm' : ''}">
            {currentState.purchasePending ? 'Confirm' : 'Enter'}
        </button>
        
        <button 
            on:click={enterGuessMode} 
            class="guess-button {currentState.mode === 'guess_mode' ? 'active' : ''}">
            Guess
        </button>
    
        <button 
            on:click={() => selectItem('hint')} 
            class="hint-button {currentState.selectedItem === 'hint' ? 'selected' : ''}">
            Hint (-$150)
        </button>

        <button 
            on:click={() => selectItem('extra_guess')} 
            class="extra-guess-button {currentState.selectedItem === 'extra_guess' ? 'selected' : ''}">
            Extra Guess (-$150)
        </button>

        <button on:click={deleteLastGuessLetter} class="delete-button">Delete</button>

        {#if currentState.purchasePending}
            <button on:click={cancelSelection} class="cancel-button">Cancel</button>
        {/if}
    </div>

    <Keyboard 
        on:letterClick={handleLetterClick} 
        letterCosts={letterCosts} 
        selectedLetter={currentState.selectedLetter} 
        revealedLetters={currentState.revealedLetters} 
        incorrectLetters={currentState.incorrectLetters} 
    />

    {#if currentState.mode === 'guess_mode'}
        <div class="guess-container">
            {#each currentState.guessInput as letter, index}
                <input 
                    type="text" 
                    class="{index === currentState.guessTrackerIndex ? 'guess-active' : ''}"
                    value={letter} 
                    readonly 
                    on:click={() => updateGuess('')} 
                />
            {/each}
        </div>
    {/if}
</main>

<style>
    .game-container {
        text-align: center;
        font-family: Arial, sans-serif;
        max-width: 600px;
        margin: auto;
    }
    .logout-button {
        position: absolute;
        top: 10px;
        right: 10px;
        padding: 10px;
        background: red;
        color: white;
        border: none;
        cursor: pointer;
    }
    .game-info p {
        font-size: 1.2em;
        margin: 5px 0;
    }
    .button-container {
        margin: 15px 0;
    }
    .button-container button {
        margin: 5px;
        padding: 10px;
        font-size: 1em;
    }
    .selected {
        background-color: blue !important;
        color: white !important;
    }
    .confirm {
        background-color: green !important;
        color: white !important;
    }
    .delete-button {
        background: orange;
        color: white;
    }
    .cancel-button {
        background: gray;
        color: white;
    }
    .guess-container {
        display: flex;
        justify-content: center;
        gap: 5px;
        margin-top: 10px;
    }
    .guess-container input {
        width: 40px;
        height: 40px;
        text-align: center;
        font-size: 1.5em;
        text-transform: uppercase;
        border: 2px solid gray;
        background: white;
    }
    .guess-active {
        border: 2px solid orange;
        background: #fff8e1;
    }
</style>
