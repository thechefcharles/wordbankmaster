<script>
  import { gameStore, actions, letterCosts } from '../stores/gameStore';
  import { onMount } from 'svelte';
  import { get } from 'svelte/store';
  


  let row1 = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
  let row2 = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
  let row3 = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];

  function blurOnFocus(event) {
    event.target.blur();  // ✅ Ensures buttons don't stay selected
}


function handleKeyPress(key) {
  console.log("🟡 handleKeyPress called with:", key);
  console.log("🟠 Calling selectLetterForPurchase with:", key);
actions.selectLetterForPurchase(key);

  gameStore.update(state => {
    if (!state.isGuessMode || state.activeBoxIndex === null) return state;

    const phraseArray = state.currentPhrase.split('');
    let inputArray = state.currentInput.split('') || Array(phraseArray.length).fill('_');

    let currentIndex = state.activeBoxIndex;

    // ✅ Ensure we skip spaces **before placing** a letter
    while (currentIndex < phraseArray.length && phraseArray[currentIndex] === ' ') {
      currentIndex++; // Move past spaces
    }

    // ✅ Only place the letter if we are in a valid spot
    if (currentIndex < phraseArray.length) {
      inputArray[currentIndex] = key;
    }

    // ✅ MOVE to next available letter box (skip spaces & filled letters)
    currentIndex++; 
    while (currentIndex < phraseArray.length && (phraseArray[currentIndex] === ' ' || state.correctPositions[currentIndex])) {
      currentIndex++;
    }

    return {
      ...state,
      currentInput: inputArray.join(''),
      activeBoxIndex: currentIndex < phraseArray.length ? currentIndex : null
    };
  });
}

function handleKeyDown(event) {
  console.log("🔹 Key Pressed:", event.key);

  const key = event.key.toLowerCase();
  

  if (key === ' ') {  
    event.preventDefault(); // ✅ Prevent scrolling
    console.log("🔹 Spacebar Pressed! Entering Guess Mode...");
    
    // ✅ Toggle Guess Mode FIRST before other actions
    actions.toggleGuessModeAndClearPurchase();

    // ✅ Remove focus from selected buttons (fix lingering blue outline)
    setTimeout(() => {
      document.activeElement?.blur();
    }, 50);
    return;
  }

  if (key === 'enter') {
    confirmAction(event);
    setTimeout(() => {
      actions.resetSelection(); 
    }, 50);
  } else if (key === 'backspace' || key === 'delete') {
    actions.deleteActiveBox();
  } else if (/^[a-z]$/.test(key)) {
    handleKeyPress(key);
  }
}

  function toggleGuessMode() {
    actions.toggleGuessMode();
  }

  function confirmAction(event) {
  console.log("🔹 confirmAction() triggered!");
  const storeValue = get(gameStore);
  console.log("🟡 Current Pending Purchase:", storeValue.pendingPurchase);

  if (get(gameStore).pendingPurchase?.letter) {
    console.log("🟢 Confirming Letter Purchase...");
    actions.confirmPurchase();
  } else if (get(gameStore).pendingPurchase?.type === "guess") {
    console.log("🟢 Confirming Guess Purchase...");
    actions.confirmPurchase();
  } else if (get(gameStore).pendingPurchase?.type === "hint") {
    console.log("🟢 Confirming Hint Purchase...");
    actions.confirmPurchase();
  } else if (get(gameStore).isGuessMode) {
    console.log("🟢 Submitting Guess...");
    actions.submitGuess();
  }

  if (event && event.target) {
    event.target.blur();
  }

  setTimeout(() => {
    actions.resetSelection();
  }, 50);
}

// ✅ Remove duplicate unnecessary blurOnFocus code

function selectHint() {
    console.log("🟡 Hint Selected (Pending Purchase)");
    actions.selectPurchase("hint"); // ✅ Marks the hint for purchase but does not buy it immediately
}

  function selectGuess() {
    actions.selectPurchase('guess');
}

  onMount(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  });
</script>

<!-- ✅ Display Bankroll -->
<div class="game-info">
  <h2>Bankroll: {$gameStore.bankroll}</h2>
</div>

<!-- ✅ Display Keyboard with Letter Costs -->
<div class="keyboard">
  {#each [row1, row2, row3] as row}
    <div class="key-row">
      {#each row as key}
      <button 
      on:click={() => actions.selectLetterForPurchase(key)}
      class:selected={$gameStore.pendingPurchase?.letter === key}
      class:purchased={$gameStore.purchasedLetters.includes(key)} 
      class:incorrect={$gameStore.guessedLetters.includes(key)} 
    >
      <span class="letter">{key.toUpperCase()}</span>
      <span class="cost">${letterCosts[key]}</span>
    </button>
          {/each}
    </div>
  {/each}

  <button on:click={toggleGuessMode} class="toggle-guess">
    {$gameStore.isGuessMode ? 'Exit Guess Mode' : 'Enter Guess Mode'}
  </button>

<!-- ✅ Fix: Auto-removes focus on click to prevent lingering blue border -->
<button 
  on:click={confirmAction} 
  on:focus={(event) => event.target.blur()}  
  class:confirm={$gameStore.pendingPurchase || ($gameStore.isGuessMode && !$gameStore.currentInput.includes('_'))}
>
  Enter
</button>

  <button 
    on:click={selectHint} 
    class:selected={$gameStore.pendingPurchase?.type === 'hint'}
  >
    Buy Hint (-$150)
  </button>

  <button 
    on:click={selectGuess} 
    class:selected={$gameStore.pendingPurchase?.type === 'guess'}
  >
    Buy Extra Guess (-$100)
  </button>
</div>

<!-- ✅ Styling -->
<style>
  .game-info {
    text-align: center;
    font-size: 1.2em;
    font-weight: bold;
    margin-bottom: 15px;
  }

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

  /* ✅ Purchased Letters Turn Green */
  .purchased {
    background-color: green;
    color: white;
  }

  /* ✅ Incorrect Guesses Turn Red */
  .incorrect {
    background-color: red;
    color: white;
  }

  .confirm {
  background-color: gray;
  color: white;
  margin-top: 15px;
  padding: 10px 20px;
  opacity: 0.5;
}

.confirm.selected {
  background-color: green;
  opacity: 1;
}

  /* ✅ Guess Mode Toggle */
  .toggle-guess {
    background-color: purple;
    color: white;
  }
</style>
