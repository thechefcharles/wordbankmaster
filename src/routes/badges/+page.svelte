<script>
	import PageNav from '$lib/components/PageNav.svelte';
	import Icon from '$lib/components/Icon.svelte';
	import BadgesPanel from '$lib/components/BadgesPanel.svelte';
</script>

<svelte:head><title>WordBank — Badges</title></svelte:head>

<main class="badges-page">
	<PageNav back="/" />
	<h1><Icon name="medal" size={22} /> Badges</h1>
	<BadgesPanel />
</main>

<style>
	.badges-page {
		max-width: 480px;
		margin: 0 auto;
		padding: 28px 16px 60px;
		font-family: var(--font-ui);
	}
	.badges-page h1 {
		font-family: var(--font-display);
		font-size: 1.8rem;
		margin: 6px 0 4px;
		text-align: center;
	}
</style>
