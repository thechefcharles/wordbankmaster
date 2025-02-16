<script>
    import { gameStore } from '$lib/stores/GameStore.js';
    import PhraseDisplay from '$lib/components/PhraseDisplay.svelte';
    import Keyboard from '$lib/components/Keyboard.svelte';
    import GameButtons from '$lib/components/GameButtons.svelte';
</script>

<main>
    <h1>BankWord</h1>
    <p>✅ +page.svelte is rendering...</p>
    <PhraseDisplay />
    <Keyboard />
    <p>Bankroll: {$gameStore.bankroll}</p>
    <p>Guesses Remaining: {$gameStore.guessesRemaining}</p>
    <p>Game State: {$gameStore.gameState}</p>
    <GameButtons />
</main>
