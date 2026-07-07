<script>
	import { goto } from '$app/navigation';
	import PageNav from '$lib/components/PageNav.svelte';
	import HistoryList from '$lib/components/HistoryList.svelte';
</script>

<svelte:head><title>WordBank — History</title></svelte:head>

<main class="h-page">
	<PageNav />
	<h1>📜 History</h1>
	<HistoryList />
</main>

<style>
	.h-page {
		max-width: 560px;
		margin: 0 auto;
		padding: 16px 14px 60px;
	}
	.back-btn {
		background: none;
		border: none;
		color: var(--text-muted);
		font-size: 0.92rem;
		cursor: pointer;
		padding: 6px 0;
	}
	h1 {
		font-family: var(--font-display);
		font-size: 1.5rem;
		margin: 4px 0 14px;
	}
</style>
