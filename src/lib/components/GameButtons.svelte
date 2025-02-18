<script>
  import { selectHint, selectExtraGuess } from '$lib/stores/GameStore.js';
  // No need to import guess/enter functions since they're handled in Keyboard.svelte now.
</script>

<!-- Fixed Top Buttons -->
<!-- Buy Guess button: Fixed at Top Left -->
<button class="buy-guess-button" on:click={() => selectExtraGuess()}>
  Buy Guess ($150)
</button>

<!-- Hint button: Fixed at Top Right -->
<button class="hint-button" on:click={() => selectHint()}>
  Hint ($150)
</button>

<!-- Utility Buttons Container -->
<div class="utility-buttons">
  <button on:click={() => { /* Open How to Play modal */ }}>
    How to Play
  </button>
  <button on:click={() => { /* Open Settings modal */ }}>
    Settings
  </button>
</div>

<style>
  button:focus {
    outline: none;
  }
  /* Fixed top buttons */
  .buy-guess-button {
    position: fixed;
    top: 10px;
    left: 10px;
    padding: 10px 15px;
    background-color: #28a745;
    color: white;
    border: none;
    border-radius: 5px;
    cursor: pointer;
    z-index: 1000;
  }
  .hint-button {
    position: fixed;
    top: 10px;
    right: 10px;
    padding: 10px 15px;
    background-color: #007bff;
    color: white;
    border: none;
    border-radius: 5px;
    cursor: pointer;
    z-index: 1000;
  }
  /* Utility buttons container */
  .utility-buttons {
    margin-top: 20px;
    display: flex;
    gap: 10px;
    justify-content: center;
  }
  .utility-buttons button {
    padding: 8px 12px;
    font-size: 14px;
    background-color: #f0f0f0;
    border: 1px solid #ccc;
    border-radius: 4px;
    cursor: pointer;
  }
  .utility-buttons button:hover {
    background-color: #ddd;
  }
</style>
