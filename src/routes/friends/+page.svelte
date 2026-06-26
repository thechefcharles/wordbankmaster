<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import PageNav from "$lib/components/PageNav.svelte";
  import FriendsPanel from '$lib/components/FriendsPanel.svelte';
  import { track } from '$lib/analytics.js';
  onMount(() => track('friends_view'));
</script>

<svelte:head><title>WordBank — Friends</title></svelte:head>

<main class="friends-page">
  <PageNav />
  <h1>👥 Friends</h1>
  <FriendsPanel onChallenge={(/** @type {string} */ u) => goto('/?challenge=' + encodeURIComponent(u))} />
</main>

<style>
  .friends-page { max-width: 480px; margin: 0 auto; padding: 1.5rem 1rem 3rem; }
  .back-btn { display: inline-block; margin-bottom: 1.2rem; padding: 0.55rem 1.1rem; background: var(--surface); color: var(--text); border: 1px solid var(--border); border-radius: 12px; cursor: pointer; font-weight: 600; font-size: 0.9rem; }
  h1 { font-family: var(--font-display); font-size: 1.7rem; margin: 0 0 1rem; }
</style>
