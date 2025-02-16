<!-- PhraseDisplay.svelte -->
<script>
    /**
     * PhraseDisplay.svelte
     *
     * This component displays the current phrase.
     * - In "guess_mode": It shows the user’s guessInput for each letter,
     *   highlighting the active (orange outlined) box for the next letter entry.
     * - In other modes: It shows letters that have been purchased.
     *
     * The active guess index is computed by determining which editable position (i.e.
     * a non-space that isn't already locked by a purchased letter) is empty.
     */
    import { gameStore } from '$lib/stores/GameStore.js';
  
    $: activeGuessIndex = (() => {
      if ($gameStore.gameState !== 'guess_mode') return -1;
      const editableIndices = [];
      // Build list of editable positions (skip spaces and locked letters)
      for (let i = 0; i < $gameStore.currentPhrase.length; i++) {
        if ($gameStore.currentPhrase[i] === ' ') continue;
        if ($gameStore.purchasedLetters.includes($gameStore.currentPhrase[i])) continue;
        editableIndices.push(i);
      }
      if (editableIndices.length === 0) return -1;
      // Return the first editable index that is empty; if all filled, return the last one.
      for (let j = 0; j < editableIndices.length; j++) {
        const idx = editableIndices[j];
        if ($gameStore.guessInput[idx] === '') return idx;
      }
      return editableIndices[editableIndices.length - 1];
    })();
  </script>
  
  {#if $gameStore.gameState === 'guess_mode'}
    <!-- Display the phrase for guess mode, using guessInput array -->
    <div class="phrase-display">
      {#each $gameStore.currentPhrase.split('') as letter, i}
        {#if letter === ' '}
          <span class="space"></span>
        {:else}
          <span class="letter-box {i === activeGuessIndex ? 'active' : ''}">
            {$gameStore.guessInput[i]}
          </span>
        {/if}
      {/each}
    </div>
  {:else}
    <!-- In default mode, display only the letters that have been purchased -->
    <div class="phrase-display">
      {#each $gameStore.currentPhrase.split('') as letter}
        {#if letter === ' '}
          <span class="space"></span>
        {:else}
          <span class="letter-box">
            {$gameStore.purchasedLetters.includes(letter) ? letter : ""}
          </span>
        {/if}
      {/each}
    </div>
  {/if}
  
  <style>
    .phrase-display {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      justify-content: center;
      margin: 20px 0;
    }
    .letter-box {
      width: 40px;
      height: 40px;
      display: flex;
      align-items: center;
      justify-content: center;
      border: 2px solid black;
      font-size: 24px;
      font-weight: bold;
    }
    /* Highlight the active (next editable) slot with an orange border */
    .letter-box.active {
      border-color: orange;
    }
    .space {
      width: 20px;
    }
  </style>
  