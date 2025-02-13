<script>
    import { gameStore } from '../stores/gameStore';
</script>

<!-- ✅ Display Category -->
<h2 class="category">Category: {$gameStore.category}</h2>

<!-- ✅ Display Phrase -->
<div class="phrase-display">
    {#each $gameStore.currentPhrase.split('') as char, index}
    {#if char !== ' '}
      <div
        class="phrase-box"
        class:active={$gameStore.isGuessMode && $gameStore.activeBoxIndex === index}
        class:win={$gameStore.winState}
        class:loss={$gameStore.lossState}
      >
        {#if $gameStore.lossState}
          {$gameStore.currentPhrase[index]} <!-- ✅ Reveal entire phrase on loss -->
        {:else if $gameStore.correctPositions[index]}
          {$gameStore.correctPositions[index]} <!-- ✅ Persist correct letters -->
        {:else if $gameStore.isGuessMode && index === $gameStore.activeBoxIndex}
    -->
    {:else if $gameStore.isGuessMode}
    {#if $gameStore.activeBoxIndex === index}
      <span class="guess-cursor"></span> <!-- ✅ Empty span to avoid rendering unintended characters -->
    {:else if $gameStore.currentInput[index]}
      {$gameStore.currentInput[index]} <!-- ✅ Shows correct letter -->
    {:else}
      _ <!-- ✅ Placeholder when not in Guess Mode -->
    {/if}
            {:else}
          _ <!-- ✅ Placeholder when not in Guess Mode -->
        {/if}
      </div>
    {:else}
      <div class="phrase-space">&nbsp;</div>
    {/if}
  {/each}
  </div>

<!-- ✅ Styles -->
<style>
    .phrase-display-wrapper {
        display: flex;
        flex-direction: column;
        align-items: center;
        margin-bottom: 20px;
    }
  
    .category {
        font-size: 18px;
        font-weight: bold;
        margin-bottom: 10px;
    }
  
    .phrase-display {
        display: flex;
        gap: 5px;
        flex-wrap: wrap;
        justify-content: center;
    }
  
    .phrase-box {
        width: 40px;
        height: 40px;
        display: flex;
        align-items: center;
        justify-content: center;
        border: 2px solid #ccc;
        font-size: 24px;
        font-weight: bold;
        background-color: #f9f9f9;
        color: #333;
        transition: all 0.2s ease;
    }
  
    /* ✅ Active Guess Mode Box (Orange) */
    .phrase-box.active {
        border-color: orange;
        box-shadow: 0 0 10px orange;
    }
  
    /* ✅ Fix floating arrow issue by using an empty span */
    .guess-cursor {
        display: inline-block;
        width: 1ch;
        height: 1.2em;
        border-bottom: 2px solid orange;
    }
  
    /* ✅ Reveals Full Phrase on Loss */
    .phrase-box.loss {
        background-color: red;
        color: white;
        border-color: darkred;
    }
  
    /* ✅ Highlights Phrase on Win */
    .phrase-box.win {
        background-color: green;
        color: white;
        border-color: darkgreen;
    }
  
    .phrase-space {
        width: 20px;
    }
  </style>
  