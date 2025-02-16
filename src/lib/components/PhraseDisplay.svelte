<script>
    /**
     * PhraseDisplay.svelte
     *
     * Displays the current phrase. Each word is stacked on its own line.
     * - In guess mode: shows guessInput for each letter, with an orange outline
     *   around the active (next-editable) slot.
     * - Otherwise: shows letters that have been purchased.
     */
  
    import { gameStore } from '$lib/stores/GameStore.js';
  
    /**
     * activeGuessIndex:
     * The index of the next empty (or incorrect) editable slot in guess mode.
     */
    $: activeGuessIndex = (() => {
      if ($gameStore.gameState !== 'guess_mode') return -1;
  
      // Build a list of editable positions (skip spaces and purchased letters).
      const editableIndices = [];
      for (let i = 0; i < $gameStore.currentPhrase.length; i++) {
        const char = $gameStore.currentPhrase[i];
        if (char === ' ') continue;
        if ($gameStore.purchasedLetters.includes(char)) continue;
        editableIndices.push(i);
      }
  
      // If no editable indices, return -1
      if (editableIndices.length === 0) return -1;
  
      // Return the first empty slot; if all filled, use the last one
      for (const idx of editableIndices) {
        if ($gameStore.guessInput[idx] === '') {
          return idx;
        }
      }
      return editableIndices[editableIndices.length - 1];
    })();
  
    /**
     * computeIndex(words, wordIndex, letterIndex):
     * Computes the "global index" in guessInput for a letter at (wordIndex, letterIndex).
     * We'll sum up the lengths of all previous words + 1 space per word.
     */
    function computeIndex(words, wordIndex, letterIndex) {
      let index = 0;
      for (let w = 0; w < wordIndex; w++) {
        // Add the length of that word + 1 space
        index += words[w].length + 1;
      }
      return index + letterIndex;
    }
  </script>
  
  {#if $gameStore.gameState === 'guess_mode'}
    <!-- GUESS MODE: Use guessInput -->
    <div class="phrase-container">
      {#each $gameStore.currentPhrase.split(' ') as word, wIndex}
        <div class="word">
          {#each word.split('') as letter, cIndex}
            <!-- Inline the globalIndex expression to avoid {#let} blocks -->
            {#if $gameStore.purchasedLetters.includes(
              $gameStore.currentPhrase[
                computeIndex($gameStore.currentPhrase.split(' '), wIndex, cIndex)
              ]
            )}
              <!-- This letter is locked (purchased) -->
              <span class="letter-box locked">
                {
                  $gameStore.currentPhrase[
                    computeIndex($gameStore.currentPhrase.split(' '), wIndex, cIndex)
                  ]
                }
              </span>
            {:else}
              <span
                class="letter-box {
                  computeIndex($gameStore.currentPhrase.split(' '), wIndex, cIndex) === activeGuessIndex
                    ? 'active'
                    : ''
                }"
              >
                {
                  $gameStore.guessInput[
                    computeIndex($gameStore.currentPhrase.split(' '), wIndex, cIndex)
                  ]
                }
              </span>
            {/if}
          {/each}
        </div>
      {/each}
    </div>
  {:else}
    <!-- DEFAULT MODE: Show purchased letters only -->
    <div class="phrase-container">
      {#each $gameStore.currentPhrase.split(' ') as word}
        <div class="word">
          {#each word.split('') as letter}
            <span class="letter-box">
              {$gameStore.purchasedLetters.includes(letter) ? letter : ""}
            </span>
          {/each}
        </div>
      {/each}
    </div>
  {/if}
  
  <style>
    .phrase-container {
      display: flex;
      flex-direction: column; /* stack each word on its own line */
      gap: 8px;
      align-items: center;
      margin: 20px 0;
    }
  
    .word {
      display: flex;
      gap: 10px;
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
  
    /* The active guess slot in guess mode has an orange outline */
    .letter-box.active {
      border-color: orange;
    }
  
    /* If a letter is locked/purchased, we can give it a subtle background */
    .letter-box.locked {
      background-color: #eee;
    }
  </style>
  