<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import LeaderboardPanel from '$lib/components/LeaderboardPanel.svelte';
  import { track } from '$lib/analytics.js';
  onMount(() => track('leaderboard_view'));
</script>

<svelte:head><title>WordBank — Leaderboard</title></svelte:head>

<main class="lb-page">
  <button class="back-btn" onclick={() => goto('/')}>← Menu</button>
  <h1>🏆 Leaderboard</h1>
  <LeaderboardPanel />
</main>

<style>
  .lb-page { max-width: 640px; margin: 0 auto; padding: 2rem 1rem 3rem; text-align: center; }
  .back-btn { display: inline-block; margin-bottom: 1rem; padding: 0.55rem 1.1rem; background: var(--surface); color: var(--text); border: 1px solid var(--border); border-radius: 12px; cursor: pointer; font-weight: 600; font-size: 0.9rem; }
  h1 { font-family: var(--font-display); font-size: 1.9rem; margin: 0 0 1rem; }
</style>
