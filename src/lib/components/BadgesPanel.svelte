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

	// Theme groups for the Achievements tab — inferred from the badge id.
	const GROUP_ORDER = ['Milestones', 'Daily', 'Cash Game', 'Blitz', 'Challenges', 'Bank'];
	/** @param {string} id */
	function groupFor(id) {
		if (id.startsWith('cg_')) return 'Cash Game';
		if (id.startsWith('bz_')) return 'Blitz';
		if (['flawless', 'streak_7', 'streak_30', 'week_complete', 'month_complete'].includes(id))
			return 'Daily';
		if (['first_blood', 'gold_duelist', 'hustler'].includes(id)) return 'Challenges';
		if (id === 'paid_in_full') return 'Bank';
		return 'Milestones';
	}

	let achievements = $derived([
		...Object.keys(BADGES).map((id) => ({
			id,
			...badgeInfo(id),
			earned: earnedBadges.includes(id),
			group: groupFor(id),
			/** @type {number|undefined} */ progress: undefined,
			/** @type {string|undefined} */ progText: undefined
		})),
		...SOLVE_MILESTONES.map((m) => ({
			id: m.id,
			emoji: m.emoji,
			name: m.name,
			desc: m.desc,
			earned: total >= m.at,
			group: 'Milestones',
			progress: Math.min(1, total / m.at),
			progText: `${Math.min(total, m.at)}/${m.at}`
		})),
		{
			id: 'collector',
			emoji: COLLECTOR.emoji,
			name: COLLECTOR.name,
			desc: COLLECTOR.desc,
			earned: goldCount >= 12,
			group: 'Milestones',
			progress: Math.min(1, goldCount / 12),
			progText: `${Math.min(goldCount, 12)}/12`
		}
	]);
	let earnedCount = $derived(achievements.filter((a) => a.earned).length);
	// Grouped by theme, earned-first within each group.
	let grouped = $derived(
		GROUP_ORDER.map((name) => {
			const items = achievements
				.filter((a) => a.group === name)
				.sort((a, b) => (b.earned ? 1 : 0) - (a.earned ? 1 : 0));
			return { name, items, earned: items.filter((a) => a.earned).length };
		}).filter((g) => g.items.length)
	);
	let rankedCats = $derived(rows.filter((r) => r.current).length);

	// 🎯 Closest unearned badge — smallest remaining across milestones, the collector,
	// and category tier-ups. Drives the "N more … → Badge" nudge on the hero.
	let closest = $derived.by(() => {
		/** @type {{remaining:number, label:string, target:string}[]} */
		const cands = [];
		for (const m of SOLVE_MILESTONES) {
			if (total < m.at) {
				const n = m.at - total;
				cands.push({
					remaining: n,
					label: `${n} more ${n === 1 ? 'solve' : 'solves'}`,
					target: `${m.emoji} ${m.name}`
				});
			}
		}
		if (goldCount < 12) {
			const n = 12 - goldCount;
			cands.push({
				remaining: n,
				label: `${n} more Gold categor${n === 1 ? 'y' : 'ies'}`,
				target: `${COLLECTOR.emoji} ${COLLECTOR.name}`
			});
		}
		for (const r of rows) {
			if (r.next) {
				const n = r.toNext;
				cands.push({
					remaining: n,
					label: `${n} more ${r.label} solve${n === 1 ? '' : 's'}`,
					target: `${r.next.medal} ${r.next.name}`
				});
			}
		}
		cands.sort((a, b) => a.remaining - b.remaining);
		return cands[0] ?? null;
	});

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
		{#if closest}
			<div class="bp-nudge">🎯 {closest.label} → <b>{closest.target}</b></div>
		{/if}
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
		{#each grouped as g}
			<div class="ach-group-h">
				{g.name}<span class="ach-group-count">{g.earned}/{g.items.length}</span>
			</div>
			<div class="ach-grid">
				{#each g.items as a}
					<div
						class="ach {a.earned ? 'earned' : 'locked'}"
						class:has-prog={a.progText && !a.earned && (a.progress ?? 0) > 0}
						title={a.desc}
					>
						<span class="ach-emoji">{a.emoji}</span>
						<span class="ach-name">{a.name}</span>
						<span class="ach-desc">{a.desc}</span>
						{#if a.progText && !a.earned}
							<div class="ach-prog">
								<div
									class="ach-prog-fill"
									style="width:{Math.round((a.progress ?? 0) * 100)}%"
								></div>
							</div>
							<span class="ach-prog-t">{a.progText}</span>
						{/if}
					</div>
				{/each}
			</div>
		{/each}
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
	.bp-nudge {
		display: inline-block;
		margin-top: 11px;
		padding: 6px 13px;
		border-radius: 999px;
		background: rgba(251, 191, 36, 0.14);
		border: 1px solid rgba(251, 191, 36, 0.32);
		font-size: 0.75rem;
		color: var(--text);
	}
	.bp-nudge b {
		font-family: var(--font-display);
		font-weight: 800;
		color: #fde047;
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

	/* Achievement groups */
	.ach-group-h {
		display: flex;
		align-items: center;
		gap: 8px;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 0.72rem;
		letter-spacing: 0.12em;
		text-transform: uppercase;
		color: var(--brand-2, #fde047);
		margin: 18px 0 9px;
	}
	.ach-group-h:first-child {
		margin-top: 0;
	}
	.ach-group-count {
		font-size: 0.66rem;
		font-weight: 700;
		color: var(--text-muted);
		letter-spacing: 0.02em;
	}
	.ach-grid {
		display: grid;
		grid-template-columns: repeat(2, 1fr);
		gap: 8px;
	}
	.ach-prog {
		width: 70%;
		height: 4px;
		border-radius: 999px;
		background: rgba(255, 255, 255, 0.14);
		overflow: hidden;
		margin: 5px 0 1px;
	}
	.ach-prog-fill {
		height: 100%;
		border-radius: 999px;
		background: linear-gradient(90deg, #fbbf24, #fde047);
	}
	.ach-prog-t {
		font-family: var(--font-display);
		font-size: 0.62rem;
		font-weight: 700;
		color: var(--text-muted);
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
	/* In-progress locked badges stay more visible so the progress bar reads. */
	.ach.locked.has-prog {
		opacity: 0.8;
		filter: grayscale(0.25);
		border-color: rgba(251, 191, 36, 0.22);
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
