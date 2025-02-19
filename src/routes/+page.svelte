<!-- page.svelte -->
<svelte:head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
</svelte:head>

<script>
  import { onMount } from 'svelte';
  import PhraseDisplay from '$lib/components/PhraseDisplay.svelte';
  import Keyboard from '$lib/components/Keyboard.svelte';
  import GameButtons from '$lib/components/GameButtons.svelte';
  import { gameStore, fetchRandomGame } from '$lib/stores/GameStore.js';
  import { selectHint, selectExtraGuess } from '$lib/stores/GameStore.js';
  import confetti from 'canvas-confetti';

   // Reactive: Watch for game win state
   $: if ($gameStore.gameState === "won") {
    launchConfetti();
  }
  function launchConfetti() {
    confetti({
      particleCount: 300,
      spread: 300,
      startVelocity: 200,
      scalar: 1.4, // Bigger confetti
      decay: 0.2,  // Slows down confetti disappearance (0.9 means 90% speed reduction per frame)
      origin: { y: 0.6 }
    });
  }

  // Create a local reactive variable for the game state
  $: currentGame = $gameStore;

  onMount(() => {
    fetchRandomGame();
  });
</script>

<main>
 <!-- 2. Use the imported image as the src -->
 <div class="logo-container">
  <img src="/WordBank.png" alt="WordBank Logo" class="wordbank-logo" />
</div>
 <!-- Use the local variable instead of $gameStore directly -->
  <p class="category">{currentGame.category} 🌍</p>

  <!-- Phrase Display -->
  <section class="phrase-section">
    <PhraseDisplay />
  </section>

<!-- Resource Stats -->
<section class="stats-section">
  <div class="bankroll-container">
    <p class="bankroll-box">$ {Math.floor(currentGame.bankroll)}</p>
  </div>
</section>


  <!-- Keyboard Section -->
  <section class="keyboard-section">
    <Keyboard />
  </section>

  <!-- Win/Loss Banner -->
  {#if currentGame.gameState === "won"}
    <div class="banner win">Congratulations! You won!</div>
  {:else if currentGame.gameState === "lost"}
    <div class="banner lose">Game Over</div>
  {/if}

  <!-- Game Buttons Section -->
  <section class="buttons-section">
    <GameButtons />
  </section>

  <button class="reset-button hidden" on:click={fetchRandomGame}>
    Reset Game
  </button>
</main>

<style>
/* Center everything better */
main {
  max-width: 600px;
  margin: 0 auto;
  text-align: center;
  font-family: sans-serif;
  padding: 10px;  /* Reduce padding */
  display: flex;
  flex-direction: column;
  align-items: center;
}

/* Fix WordBank spacing */
h1 {
  margin-top: 40px; /* Move down slightly */
  margin-bottom: 5px;
  font-size: 2rem;
}

/* Category display */
.category {
  font-size: 1.4rem;
  margin-top: -140px;  /* Moves up */
  margin-bottom: 0px;  /* Removes extra space below */
  font-weight: bold;
}

/* Move Buy Guess & Hint buttons to avoid overlap */
.top-buttons {
  display: flex;
  justify-content: space-between;
  width: 100%;
  padding: 5px 10px;
}

.top-buttons button {
  flex: 1;
  margin: -10 5px;
  font-size: 14px;
}

/* Adjust stats-section to move everything up */
.stats-section {
  margin-top: 10px; /* Move up */
  margin-bottom: 5px; /* Reduce extra space */
  font-size: 1.2rem;
  font-weight: bold;
}

/* Move guesses remaining up */
.guesses-remaining {
  margin-top: 20px; /* Adjust to move up */
}

/* PHRASE BOXES: Bigger & Tighter Spacing */
.phrase-container {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  width: 100%;
  max-width: 100%;
  gap: 2px; /* Minimized space between boxes */
}

/* Adjust letter box size */
.letter-box {
  width: min(60px, 7vw); /* Increased by 10px */
  height: min(60px, 7vw); /* Increased by 10px */
  font-size: min(26px, 4vw); /* Scale text */
}

/* KEYBOARD: Bigger Keys & No Space Between */
.keyboard-section {
  width: 100%;
  padding: 5px;
}

.keyboard-row {
  display: flex;
  justify-content: center;
  gap: 0px; /* No space between keys */
  flex-wrap: nowrap; /* Keep QWERTY layout */
}

/* Make keys larger while removing spacing */
.key {
  width: min(55px, 8vw); /* Slightly larger */
  height: min(55px, 8vw);
  font-size: min(18px, 3.5vw);
  margin: 0; /* Remove any extra margins */
  padding: 2px; /* Minimal padding */
}

/* Hide Reset Game Button */
.reset-button.hidden {
  display: none;
}
/* Center the bankroll box */
.bankroll-container {
  display: flex;
  justify-content: center;  /* Centers horizontally */
  align-items: center;      /* Aligns content in the middle */
  width: 100%;              /* Full width of the container */
  margin: 0 auto;           /* Centers it */
  padding-top: -5px;         /* Adjust spacing above */
}

/* Make sure bankroll box stays centered */
.bankroll-box {
  padding: 5px 15px;
  font-size: 1.5rem;
  font-weight: bold;
  color: white;
  background-color: green;
  border-radius: 1px;
  text-align: center;
  display: inline-block;
  width: fit-content;  /* Prevents it from stretching */
  margin: 0 auto;      /* Ensures centering */
}



/* Buy Guess & Hint Buttons Positioned Closer to Guesses Remaining */
.guess-hint-buttons {
  display: flex;
  justify-content: space-between; /* Places Buy Guess on the left, Hint on the right */
  width: 100%;
  max-width: 300px; /* Adjusts button width */
  margin-top: -5px; /* Moves buttons up */
}

/* 💰 Buy Guess Button (Left) */
.buy-guess-button {
  background-color: #007bff;
  color: white;
  padding: 6px 10px;
  border-radius: 5px;
  border: none;
  cursor: pointer;
  font-size: 14px;
  width: 140px; /* 🔹 Fix width */
  text-align: center;
}

/* 💡 Hint Button (Right) */
.hint-button {
  background-color: #007bff;
  color: white;
  padding: 6px 10px;
  border-radius: 5px;
  border: none;
  cursor: pointer;
  font-size: 14px;a
  width: 140px; /* 🔹 Fix width */
  text-align: center;
}

 /* 3. Style the logo as needed */
 .wordbank-logo {
  width: 380px; /* Make it even bigger */
  height: auto;
  display: block;
  margin-bottom: -50px; /* Move elements up more */
  margin-top: -30px;  /* Reduce space above */
  padding-bottom: 0px; /* No space below the logo */
}

/* ✅ Adjust spacing for the logo container */
.logo-container {
  display: flex;
  justify-content: center;
  align-items: center;
  /* Increase negative margin-top to push the logo up */
  margin-top: -50px;
  margin-bottom: 0px;
}

.phrase-section {
  margin-top: 0px;  /* Move phrase display up */
}


</style>
