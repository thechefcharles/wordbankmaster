<script>
  export let phrase = [];
  export let revealedLetters = new Set();
  export let guessInput = []; // ✅ Ensure it's treated as a normal array
  export let guessTrackerIndex = null;
  export let mode = "default"; // Track game mode
</script>

<div class="phrase-container">
  {#each phrase as letter, index}
    {#if letter === ' '}
      <span class="space"> </span>
    {:else if revealedLetters.has(letter)}
      <span class="letter revealed">{letter}</span>
    {:else}
      <!-- ✅ Make sure `guessInput` is displayed properly -->
      <span class="letter hidden {index === guessTrackerIndex ? 'guess-active' : ''}">
        {mode === 'guess_mode' ? guessInput[index] || '_' : '_'}
      </span>
    {/if}
  {/each}
</div>

<style>
  .phrase-container {
      display: flex;
      justify-content: center;
      font-size: 2em;
      margin: 20px 0;
  }
  .letter {
      display: inline-block;
      width: 30px;
      height: 40px;
      line-height: 40px;
      text-align: center;
      border-bottom: 2px solid black;
      margin: 0 5px;
  }
  .hidden {
      color: transparent;
  }
  .revealed {
      font-weight: bold;
  }
  .space {
      width: 20px;
  }
  .guess-active {
      border-bottom: 2px solid orange;
      background: #fff8e1;
  }
</style>
