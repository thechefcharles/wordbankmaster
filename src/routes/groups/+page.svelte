<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import GroupsPanel from '$lib/components/GroupsPanel.svelte';
  import { track } from '$lib/analytics.js';
  onMount(() => track('groups_view'));
</script>

<svelte:head><title>WordBank — Groups</title></svelte:head>

<main class="groups-page">
  <GroupsPanel title="👥 Groups" onExit={() => goto('/')} />
</main>

<style>
  .groups-page { max-width: 560px; margin: 0 auto; padding: 1.5rem 1rem 3rem; }
</style>
