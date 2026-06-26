<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import PageNav from "$lib/components/PageNav.svelte";
  import ActivityPanel from '$lib/components/ActivityPanel.svelte';
  import { track } from '$lib/analytics.js';
  onMount(() => track('activity_view'));
</script>

<svelte:head><title>WordBank — Activity</title></svelte:head>

<main class="a-page">
  <PageNav />
  <h1>📣 Activity</h1>
  <p class="sub">You, your friends, and your groups.</p>
  <ActivityPanel />
</main>

<style>
  .a-page { max-width: 560px; margin: 0 auto; padding: 16px 14px 60px; }
  .back-btn { background: none; border: none; color: var(--text-muted); font-size: 0.92rem; cursor: pointer; padding: 6px 0; }
  h1 { font-family: var(--font-display); font-size: 1.5rem; margin: 4px 0 2px; }
  .sub { color: var(--text-faint); font-size: 0.84rem; margin: 0 0 16px; }
</style>
