<script>
	import { onMount } from 'svelte';
	import PageNav from '$lib/components/PageNav.svelte';
	import Icon from '$lib/components/Icon.svelte';
	import ActivityPanel from '$lib/components/ActivityPanel.svelte';
	import { track } from '$lib/analytics.js';
	onMount(() => track('activity_view'));
</script>

<svelte:head><title>WordBank — Activity</title></svelte:head>

<main class="a-page">
	<PageNav back="/" />
	<h1><Icon name="bell" size={22} /> Activity</h1>
	<p class="sub">You, your friends, and your groups.</p>
	<ActivityPanel />
</main>

<style>
	.a-page {
		max-width: 560px;
		margin: 0 auto;
		padding: 16px 14px 60px;
	}

	h1 {
		font-family: var(--font-display);
		font-size: 1.5rem;
		margin: 4px 0 2px;
	}
	.sub {
		color: var(--text-faint);
		font-size: 0.84rem;
		margin: 0 0 16px;
	}
</style>
