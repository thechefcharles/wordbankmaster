<script>
  import { gameStore, actions, letterCosts } from '../stores/gameStore';
  import { onMount } from 'svelte';
  import { get } from 'svelte/store';

  let row1 = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
  let row2 = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
  let row3 = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];

  function blurElement(event) {
      event.target.blur(); // ✅ Prevents lingering focus
  }

  function handleKeyPress(key) {
    gameStore.update(state => {
        if (!state.isGuessMode || state.activeBoxIndex === null) return state;

        const phraseArray = state.currentPhrase.split('');
        let inputArray = state.currentInput.split('');
        let currentIndex = state.activeBoxIndex;

        let updatedState = { 
            ...state, 
            pendingPurchase: null  
        };

        while (currentIndex < phraseArray.length && phraseArray[currentIndex] === ' ') {
            currentIndex++;
        }

        if (currentIndex < phraseArray.length) {
            inputArray[currentIndex] = key;
        }

        let nextIndex = currentIndex + 1;
        while (nextIndex < phraseArray.length && (phraseArray[nextIndex] === ' ' || state.correctPositions[nextIndex])) {
            nextIndex++;
        }

        updatedState = {
            ...updatedState,
            currentInput: inputArray.join(''),
            activeBoxIndex: nextIndex < phraseArray.length ? nextIndex : currentIndex 
        };

        return updatedState;
    });

    setTimeout(() => {
        document.activeElement?.blur(); 
    }, 50);
}

  function handleKeyDown(event) {
    console.log("🔹 Key Pressed:", event.key);
    const key = event.key.toLowerCase();

    const storeValue = get(gameStore);

    if (key === ' ') {  
        event.preventDefault();
        console.log("🔹 Spacebar Pressed! Entering Guess Mode...");
        actions.toggleGuessModeAndClearPurchase();
        return;
    }

    if (key === 'enter') {
        console.log("🔹 Enter Key Pressed!");

        if (storeValue.pendingPurchase) {
            console.log("🟢 Confirming Purchase...");
            actions.confirmPurchase();
        } else if (storeValue.isGuessMode) {
            console.log("🟢 Submitting Guess...");
            actions.submitGuess();
        }

        return;
    }

    if (key === 'backspace' || key === 'delete') {
        console.log("🔹 Backspace/Delete Pressed!");
        actions.deleteActiveBox();
        return;
    }

    if (/^[a-z]$/.test(key)) {
        if (storeValue.isGuessMode) {
            console.log("🟢 Guess Mode Active - Filling Active Box");
            actions.fillActiveBox(key);
        } else {
            console.log("🟡 Selecting Letter for Purchase:", key);
            actions.selectLetterForPurchase(key);
        }
    }
}

  function toggleGuessMode() {
    actions.toggleGuessMode();
  }

  function confirmAction(event) {
    console.log("🔹 confirmAction() triggered!");
    const storeValue = get(gameStore);
    console.log("🟡 Current Pending Purchase:", storeValue.pendingPurchase);

    if (storeValue.pendingPurchase?.letter) {
      console.log("🟢 Confirming Letter Purchase...");
      actions.confirmPurchase();
    } else if (storeValue.pendingPurchase?.type === "guess") {
      console.log("🟢 Confirming Guess Purchase...");
      actions.confirmPurchase();
    } else if (storeValue.pendingPurchase?.type === "hint") {
      console.log("🟢 Confirming Hint Purchase...");
      actions.confirmPurchase();
    } else if (storeValue.isGuessMode) {
      console.log("🟢 Submitting Guess...");
      actions.submitGuess();
    }

    if (event && event.target) {
      blurElement(event);
    }

    setTimeout(() => {
      actions.resetSelection();
    }, 50);
  }

  function selectHint() {
    console.log("🟡 Hint Selected (Pending Purchase)");
    actions.selectPurchase("hint");
  }

  function selectGuess() {
    actions.selectPurchase('guess');
  }

  onMount(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  });
</script>

<!-- ✅ Display Keyboard with Letter Costs -->
<div class="keyboard">
  {#each [row1, row2, row3] as row}
    <div class="key-row">
      {#each row as key}
        <button 
          on:click={() => actions.selectLetterForPurchase(key)}
          on:focus={blurElement}
          class:selected={$gameStore.pendingPurchase?.letter === key}
          class:correct={$gameStore.purchasedLetters.includes(key) && $gameStore.correctPositions.includes(key)}
          class:incorrect={$gameStore.purchasedLetters.includes(key) && !$gameStore.correctPositions.includes(key)}
                  >
          <span class="letter">{key.toUpperCase()}</span>
          <span class="cost">${letterCosts[key]}</span>
        </button>
      {/each}
    </div>
  {/each}

  <button 
  on:click={toggleGuessMode} 
  class="toggle-guess"
  class:active={$gameStore.isGuessMode} 
>
  {$gameStore.isGuessMode ? 'Exit Guess Mode' : 'Enter Guess Mode'}
</button>

  <button 
  on:click={confirmAction} 
  on:focus={blurElement}  
  class:confirm={$gameStore.pendingPurchase || ($gameStore.isGuessMode && !$gameStore.currentInput.includes('_'))}
  class:active={$gameStore.pendingPurchase}  
>
  Enter
</button>

  <!-- ✅ Hint Button -->
  <button 
      on:click={selectHint} 
      on:focus={blurElement}  
      class:selected={$gameStore.pendingPurchase?.type === 'hint'}
  >
      Buy Hint (-$150)
  </button>

  <!-- ✅ Purchase Extra Guess Button -->
  <button 
      on:click={selectGuess} 
      on:focus={blurElement}  
      class:selected={$gameStore.pendingPurchase?.type === 'guess'}
  >
      Buy Extra Guess (-$100)
  </button>
</div>

<!-- ✅ Styling -->
<style>
  .keyboard {
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  .key-row {
    display: flex;
    justify-content: center;
    margin-bottom: 5px;
  }

  button {
    padding: 10px;
    margin: 5px;
    border: none;
    border-radius: 5px;
    background-color: #f0f0f0;
    cursor: pointer;
    transition: background-color 0.3s;
    display: flex;
    flex-direction: column;
    align-items: center;
    font-size: 1.2em;
  }

  .letter {
    font-weight: bold;
  }

  .cost {
    font-size: 0.7em;
    color: gray;
    margin-top: 2px;
  }

  button:hover {
    background-color: #ddd;
  }

  /* ✅ Selected Items Turn Blue */
  .selected {
    background-color: blue;
    color: white;
  }

  /* ✅ Green - Correctly Guessed Letter */
  .correct {
    background-color: lightgreen;
    color: darkgreen;
    border-color: green;
  }

  /* ✅ Red - Incorrectly Guessed Letter */
  .incorrect {
    background-color: lightcoral;
    color: darkred;
    border-color: red;
  }

  .confirm {
    background-color: gray;
    color: white;
    margin-top: 15px;
    padding: 10px 20px;
    opacity: 0.5;
  }

  /* ✅ Turn Green When a Purchase is Pending */
.confirm.active {
  background-color: green !important;
  opacity: 1;
}

  .confirm.selected {
    background-color: green;
    opacity: 1;
  }

/* ✅ Default Guess Mode Button (Gray) */
.toggle-guess {
  background-color: gray;
  color: white;
  padding: 10px 20px;
  margin-top: 10px;
  border: none;
  border-radius: 5px;
  transition: background-color 0.2s ease;
}

/* ✅ Turns Orange when Guess Mode is Active */
.toggle-guess.active {
  background-color: orange !important;
  color: black;
}
</style>
