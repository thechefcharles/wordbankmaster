<script>
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import PageNav from '$lib/components/PageNav.svelte';
	import FriendsPanel from '$lib/components/FriendsPanel.svelte';
	import { track } from '$lib/analytics.js';
	onMount(() => track('friends_view'));
</script>

<svelte:head><title>WordBank — Friends</title></svelte:head>

<main class="friends-page">
	<PageNav />
	<h1>👥 Friends</h1>
	<FriendsPanel
		onChallenge={(/** @type {string} */ u) => goto('/?challenge=' + encodeURIComponent(u))}
	/>
</main>

<style>
	.friends-page {
		max-width: 480px;
		margin: 0 auto;
		padding: 1.5rem 1rem 3rem;
	}

	h1 {
		font-family: var(--font-display);
		font-size: 1.7rem;
		margin: 0 0 1rem;
	}
</style>
