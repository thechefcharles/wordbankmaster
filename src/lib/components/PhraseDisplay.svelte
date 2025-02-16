<script>
    import { gameStore } from '$lib/stores/GameStore.js';
    
    // Compute the active guess index if in guess mode.
    $: activeGuessIndex = (() => {
      if ($gameStore.gameState !== 'guess_mode') return -1;
      const editableIndices = [];
      for (let i = 0; i < $gameStore.currentPhrase.length; i++) {
        if ($gameStore.currentPhrase[i] === ' ') continue;
        if ($gameStore.purchasedLetters.includes($gameStore.currentPhrase[i])) continue;
        editableIndices.push(i);
      }
      if (editableIndices.length === 0) return -1;
      for (let j = 0; j < editableIndices.length; j++) {
        const idx = editableIndices[j];
        if ($gameStore.guessInput[idx] === '') return idx;
      }
      return editableIndices[editableIndices.length - 1];
    })();
  </script>
  
  {#if $gameStore.gameState === 'guess_mode'}
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
    .letter-box.active {
      border-color: orange;
    }
    .space {
      width: 20px;
    }
  </style>
  