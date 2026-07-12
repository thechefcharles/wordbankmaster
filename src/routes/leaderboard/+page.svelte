<script>
	import { onMount } from 'svelte';
	import PageNav from '$lib/components/PageNav.svelte';
	import Icon from '$lib/components/Icon.svelte';
	import LeaderboardPanel from '$lib/components/LeaderboardPanel.svelte';
	import { track } from '$lib/analytics.js';
	onMount(() => track('leaderboard_view'));
</script>

<svelte:head><title>WordBank — Leaderboard</title></svelte:head>

<main class="lb-page">
	<PageNav />
	<h1><Icon name="trophy" size={22} /> Leaderboard</h1>
	<LeaderboardPanel />
</main>

<style>
	.lb-page {
		max-width: 640px;
		margin: 0 auto;
		padding: 2rem 1rem 3rem;
		text-align: center;
	}

	h1 {
		font-family: var(--font-display);
		font-size: 1.9rem;
		margin: 0 0 1rem;
	}
</style>
