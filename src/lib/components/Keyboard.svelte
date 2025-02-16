<script>
  export let letterCosts = {};
  export let selectedLetter = null;
  export let revealedLetters = new Set(); // Letters already purchased (correct)
  export let incorrectLetters = new Set(); // Incorrectly purchased letters

  import { createEventDispatcher } from 'svelte';

  const dispatch = createEventDispatcher();

  function handleLetterClick(letter) {
    if (revealedLetters.has(letter) || incorrectLetters.has(letter)) return;

    // Allow letter selection for default mode, allow input in guess mode
    dispatch('letterClick', { letter, cost: letterCosts[letter] });
}
</script>

<div class="keyboard">
  {#each Object.keys(letterCosts) as letter}
      <button 
          class="
              {selectedLetter === letter ? 'selected' : ''}
              {revealedLetters.has(letter) ? 'correct' : ''}
              {incorrectLetters.has(letter) ? 'incorrect' : ''}
          " 
          on:click={() => handleLetterClick(letter)}
          disabled={revealedLetters.has(letter) || incorrectLetters.has(letter)}
      >
          {letter} (${letterCosts[letter]})
      </button>
  {/each}
</div>

<style>
  .keyboard {
      display: flex;
      flex-wrap: wrap;
      justify-content: center;
      gap: 5px;
      margin-top: 20px;
  }
  button {
      width: 50px;
      height: 50px;
      font-size: 1.2em;
      border: 1px solid black;
      background: white;
      cursor: pointer;
  }
  .selected {
      background: blue;
      color: white;
  }
  .correct {
      background: green;
      color: white;
      cursor: not-allowed;
  }
  .incorrect {
      background: red;
      color: white;
      cursor: not-allowed;
  }
</style>
