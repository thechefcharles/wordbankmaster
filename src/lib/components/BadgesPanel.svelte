<script>
	import { onMount } from 'svelte';
	import { getCategoryStats, getUserBadges } from '$lib/stores/statsStore.js';
	import { CATEGORIES } from '$lib/categories.js';
	import { categoryProgress, SOLVE_MILESTONES, COLLECTOR } from '$lib/categoryBadges.js';
	import { BADGES, badgeInfo } from '$lib/badges.js';

	/** @type {{category: string, solves: number}[]} */
	let categoryStats = $state([]);
	/** @type {string[]} */
	let earnedBadges = $state([]);
	let loaded = $state(false);
	/** @type {'categories'|'achievements'} */
	let tab = $state('categories');

	onMount(async () => {
		const [stats, earned] = await Promise.all([getCategoryStats(), getUserBadges()]);
		categoryStats = stats;
		earnedBadges = earned;
		loaded = true;
	});

	let solvesByCat = $derived(Object.fromEntries(categoryStats.map((r) => [r.category, r.solves])));
	let total = $derived(categoryStats.reduce((n, r) => n + (r.solves || 0), 0));
	let rows = $derived(
		CATEGORIES.map((c) => ({ ...c, ...categoryProgress(solvesByCat[c.value] ?? 0) }))
	);
	let goldCount = $derived(rows.filter((r) => (r.solves ?? 0) >= 25).length);
	let achievements = $derived([
		...Object.keys(BADGES).map((id) => ({ ...badgeInfo(id), earned: earnedBadges.includes(id) })),
		...SOLVE_MILESTONES.map((m) => ({
			emoji: m.emoji,
			name: m.name,
			desc: m.desc,
			earned: total >= m.at
		})),
		{ emoji: COLLECTOR.emoji, name: COLLECTOR.name, desc: COLLECTOR.desc, earned: goldCount >= 12 }
	]);
	// Earned first, so unlocked badges lead instead of being buried under locked ones.
	let achSorted = $derived(
		[...achievements].sort((a, b) => (b.earned ? 1 : 0) - (a.earned ? 1 : 0))
	);
	let earnedCount = $derived(achievements.filter((a) => a.earned).length);
	let rankedCats = $derived(rows.filter((r) => r.current).length);

	// SVG progress ring geometry (r = 19 → circumference ≈ 119.38)
	const CIRC = 2 * Math.PI * 19;
</script>

<div class="bp">
	<!-- 🏅 Progress hero -->
	<div class="bp-hero">
		<div class="bp-hero-count">
			<span class="bp-hero-num">{earnedCount}</span><span class="bp-hero-den"
				>/ {achievements.length}</span
			>
		</div>
		<div class="bp-hero-lbl">badges unlocked</div>
		<div class="bp-hero-bar">
			<div
				class="bp-hero-fill"
				style="width:{Math.round((earnedCount / achievements.length) * 100)}%"
			></div>
		</div>
		<div class="bp-hero-sub">
			{total}
			{total === 1 ? 'puzzle' : 'puzzles'} solved · {rankedCats}/{rows.length} categories ranked
		</div>
	</div>

	<!-- Tabs -->
	<div class="bp-tabs" role="tablist">
		<button class:on={tab === 'categories'} onclick={() => (tab = 'categories')}>Categories</button>
		<button class:on={tab === 'achievements'} onclick={() => (tab = 'achievements')}
			>Achievements <span class="bp-tab-count">{earnedCount}</span></button
		>
	</div>

	{#if tab === 'categories'}
		<div class="cat-grid">
			{#each rows as r (r.value)}
				<div class="cat-tile" class:ranked={r.current}>
					<div class="ring-wrap">
						<svg class="ring" viewBox="0 0 44 44">
							<circle class="ring-bg" cx="22" cy="22" r="19" />
							<circle
								class="ring-fg"
								cx="22"
								cy="22"
								r="19"
								style="stroke-dasharray:{CIRC};stroke-dashoffset:{CIRC * (1 - r.progress)}"
							/>
						</svg>
						<span class="ring-emoji">{r.emoji}</span>
						{#if r.current}<span class="ring-medal">{r.current.medal}</span>{/if}
					</div>
					<div class="cat-name">{r.label}</div>
					<div class="cat-sub">
						{#if r.next}
							{r.toNext} → {r.next.medal}
						{:else}
							💎 Maxed · {r.solves}
						{/if}
					</div>
				</div>
			{/each}
		</div>
	{:else}
		<div class="ach-grid">
			{#each achSorted as a}
				<div class="ach {a.earned ? 'earned' : 'locked'}" title={a.desc}>
					<span class="ach-emoji">{a.emoji}</span>
					<span class="ach-name">{a.name}</span>
					<span class="ach-desc">{a.desc}</span>
				</div>
			{/each}
		</div>
	{/if}

	{#if !loaded}<p class="bp-loading">Loading…</p>{/if}
</div>

<style>
	/* 🏅 Progress hero */
	.bp-hero {
		text-align: center;
		padding: 16px 18px 18px;
		border-radius: 18px;
		margin-bottom: 16px;
		background: linear-gradient(180deg, rgba(251, 191, 36, 0.12), rgba(251, 191, 36, 0.02));
		border: 1px solid rgba(251, 191, 36, 0.28);
	}
	.bp-hero-count {
		display: flex;
		align-items: baseline;
		justify-content: center;
		gap: 4px;
	}
	.bp-hero-num {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 2.4rem;
		line-height: 1;
		color: #fde047;
	}
	.bp-hero-den {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1.1rem;
		color: var(--text-muted);
	}
	.bp-hero-lbl {
		font-size: 0.72rem;
		letter-spacing: 0.14em;
		text-transform: uppercase;
		color: var(--text-muted);
		margin-top: 2px;
	}
	.bp-hero-bar {
		height: 8px;
		border-radius: 999px;
		background: rgba(255, 255, 255, 0.12);
		overflow: hidden;
		margin: 12px auto 8px;
		max-width: 260px;
	}
	.bp-hero-fill {
		height: 100%;
		border-radius: 999px;
		background: linear-gradient(90deg, #fbbf24, #fde047);
		transition: width 0.5s var(--ease-spring, ease);
	}
	.bp-hero-sub {
		font-size: 0.74rem;
		color: var(--text-muted);
	}

	/* Tabs */
	.bp-tabs {
		display: flex;
		gap: 6px;
		padding: 4px;
		border-radius: 12px;
		background: var(--surface, rgba(255, 255, 255, 0.05));
		border: 1px solid var(--border, rgba(255, 255, 255, 0.1));
		margin-bottom: 16px;
	}
	.bp-tabs button {
		flex: 1;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 6px;
		padding: 8px 10px;
		border: none;
		border-radius: 9px;
		cursor: pointer;
		background: transparent;
		color: var(--text-muted);
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.85rem;
		transition:
			background 0.15s,
			color 0.15s;
	}
	.bp-tabs button.on {
		background: rgba(251, 191, 36, 0.16);
		color: #fde047;
	}
	.bp-tab-count {
		min-width: 18px;
		height: 18px;
		padding: 0 5px;
		border-radius: 999px;
		display: grid;
		place-items: center;
		font-size: 0.66rem;
		font-weight: 800;
		background: rgba(251, 191, 36, 0.25);
		color: #fde047;
	}

	/* Category grid — progress-ring tiles */
	.cat-grid {
		display: grid;
		grid-template-columns: repeat(2, 1fr);
		gap: 10px;
	}
	.cat-tile {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 3px;
		padding: 14px 10px 12px;
		border-radius: 16px;
		background: var(--surface, rgba(255, 255, 255, 0.05));
		border: 1px solid var(--border, rgba(255, 255, 255, 0.1));
		text-align: center;
	}
	.cat-tile.ranked {
		border-color: rgba(251, 191, 36, 0.35);
	}
	.ring-wrap {
		position: relative;
		width: 60px;
		height: 60px;
		margin-bottom: 4px;
	}
	.ring {
		width: 60px;
		height: 60px;
		transform: rotate(-90deg);
	}
	.ring-bg {
		fill: none;
		stroke: rgba(255, 255, 255, 0.12);
		stroke-width: 3.5;
	}
	.ring-fg {
		fill: none;
		stroke: #fbbf24;
		stroke-width: 3.5;
		stroke-linecap: round;
		transition: stroke-dashoffset 0.6s var(--ease-spring, ease);
	}
	.ring-emoji {
		position: absolute;
		inset: 0;
		display: grid;
		place-items: center;
		font-size: 1.5rem;
	}
	.ring-medal {
		position: absolute;
		right: -2px;
		bottom: -2px;
		font-size: 0.9rem;
		filter: drop-shadow(0 1px 2px rgba(0, 0, 0, 0.5));
	}
	.cat-name {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.82rem;
		line-height: 1.15;
	}
	.cat-sub {
		font-size: 0.7rem;
		color: var(--text-muted);
	}

	/* Achievement grid */
	.ach-grid {
		display: grid;
		grid-template-columns: repeat(2, 1fr);
		gap: 8px;
	}
	.ach {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 3px;
		text-align: center;
		padding: 14px 8px;
		border-radius: 14px;
		background: var(--surface, rgba(255, 255, 255, 0.05));
		border: 1px solid var(--border, rgba(255, 255, 255, 0.1));
	}
	.ach.earned {
		border-color: rgba(253, 224, 71, 0.5);
		box-shadow: 0 0 14px rgba(251, 191, 36, 0.16);
	}
	.ach.locked {
		opacity: 0.45;
		filter: grayscale(0.7);
	}
	.ach-emoji {
		font-size: 1.6rem;
		line-height: 1;
	}
	.ach-name {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.78rem;
	}
	.ach-desc {
		font-size: 0.66rem;
		color: var(--text-muted);
		line-height: 1.2;
	}
	.bp-loading {
		color: var(--text-muted);
		font-size: 0.85rem;
		text-align: center;
	}
</style>
