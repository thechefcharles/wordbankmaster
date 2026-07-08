<script>
	import { onMount, tick } from 'svelte';
	import { getCategoryStats, getUserBadges } from '$lib/stores/statsStore.js';
	import { CATEGORIES } from '$lib/categories.js';
	import {
		categoryProgress,
		CATEGORY_TIERS,
		SOLVE_MILESTONES,
		COLLECTOR
	} from '$lib/categoryBadges.js';
	import { BADGES, badgeInfo } from '$lib/badges.js';
	import { fx } from '$lib/sound.js';

	/** @type {{category: string, solves: number}[]} */
	let categoryStats = $state([]);
	/** @type {string[]} */
	let earnedBadges = $state([]);
	let loaded = $state(false);
	/** @type {'categories'|'achievements'} */
	let tab = $state('categories');
	/** Category row shown in the detail modal (null = closed). @type {any} */
	let detail = $state(null);
	/** Achievement shown in the detail modal (null = closed). @type {any} */
	let achDetail = $state(null);
	/** Badge ids unlocked since last visit — celebrated + pulsed. @type {string[]} */
	let newlyEarned = $state([]);

	onMount(async () => {
		const [stats, earned] = await Promise.all([getCategoryStats(), getUserBadges()]);
		categoryStats = stats;
		earnedBadges = earned;
		loaded = true;
		await tick();
		celebrateNewUnlocks();
		// Deep link from Full Stats: /badges?cat=<value> opens that category's detail.
		const cat = new URLSearchParams(location.search).get('cat');
		if (cat) {
			const row = rows.find((r) => r.value === cat);
			if (row) {
				tab = 'categories';
				detail = row;
			}
		}
	});

	// 🎉 Celebrate badges earned since the last visit. First visit seeds silently so
	// we only ever party for FUTURE unlocks, never retroactively.
	function celebrateNewUnlocks() {
		try {
			const earnedIds = achievements.filter((a) => a.earned).map((a) => a.id);
			const KEY = 'wb_seen_badges';
			const raw = localStorage.getItem(KEY);
			localStorage.setItem(KEY, JSON.stringify(earnedIds));
			if (raw == null) return; // first visit → seed silently
			const seen = new Set(JSON.parse(raw));
			const fresh = earnedIds.filter((id) => !seen.has(id));
			if (!fresh.length) return;
			newlyEarned = fresh;
			if (fresh.some((id) => achievements.find((a) => a.id === id))) tab = 'achievements';
			fx('win');
			if (!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) burstConfetti();
			setTimeout(() => (newlyEarned = []), 6500);
		} catch {
			/* non-fatal */
		}
	}

	// Lightweight one-shot confetti (badges are rare, so this stays tasteful).
	/** @param {number} [count] */
	function burstConfetti(count = 40) {
		if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) return;
		const colors = ['#fbbf24', '#fde047', '#34d399', '#60a5fa', '#f472b6', '#ffffff'];
		const c = document.createElement('div');
		c.className = 'wb-confetti';
		for (let i = 0; i < count; i++) {
			const p = document.createElement('span');
			p.style.left = Math.round(Math.random() * 100) + 'vw';
			p.style.background = colors[i % colors.length];
			p.style.animationDelay = (Math.random() * 0.35).toFixed(2) + 's';
			p.style.animationDuration = (2.2 + Math.random() * 1.2).toFixed(2) + 's';
			c.appendChild(p);
		}
		document.body.appendChild(c);
		setTimeout(() => c.remove(), 4000);
	}

	// Open an achievement's detail — earned ones get a celebratory confetti pop.
	/** @param {any} a */
	function openAch(a) {
		achDetail = a;
		if (a.earned) burstConfetti(24);
	}

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
				<div
					class="cat-tile"
					class:ranked={r.current}
					role="button"
					tabindex="0"
					onclick={() => (detail = r)}
					onkeydown={(e) => {
						if (e.key === 'Enter' || e.key === ' ') {
							e.preventDefault();
							detail = r;
						}
					}}
				>
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
						class:just={newlyEarned.includes(a.id)}
						role="button"
						tabindex="0"
						title={a.desc}
						onclick={() => openAch(a)}
						onkeydown={(e) => {
							if (e.key === 'Enter' || e.key === ' ') {
								e.preventDefault();
								openAch(a);
							}
						}}
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

<!-- 🎉 New-unlock banner -->
{#if newlyEarned.length}
	<div class="bp-unlock" role="status">
		🎉 New badge{newlyEarned.length > 1 ? 's' : ''} unlocked!
	</div>
{/if}

<!-- 🗂️ Category detail modal -->
<svelte:window
	onkeydown={(e) => {
		if (e.key === 'Escape') {
			detail = null;
			achDetail = null;
		}
	}}
/>
{#if detail}
	<div class="cd-overlay">
		<button class="cd-backdrop" aria-label="Close" onclick={() => (detail = null)}></button>
		<div class="cd-card" role="dialog" aria-modal="true">
			<button class="cd-x" onclick={() => (detail = null)} aria-label="Close">✕</button>
			<div class="cd-emoji">{detail.emoji}</div>
			<h3 class="cd-name">{detail.label}</h3>
			<p class="cd-solves">
				{detail.solves}
				{detail.solves === 1 ? 'solve' : 'solves'}
			</p>
			<div class="cd-ladder">
				{#each CATEGORY_TIERS as t}
					{@const got = detail.solves >= t.at}
					<div class="cd-tier" class:got>
						<span class="cd-medal">{t.medal}</span>
						<span class="cd-tname">{t.name}</span>
						<span class="cd-treq"
							>{#if got}✓ Unlocked{:else}{t.at - detail.solves} more{/if}</span
						>
					</div>
				{/each}
			</div>
		</div>
	</div>
{/if}

<!-- 🏅 Achievement detail modal -->
{#if achDetail}
	<div class="cd-overlay">
		<button class="cd-backdrop" aria-label="Close" onclick={() => (achDetail = null)}></button>
		<div class="cd-card" role="dialog" aria-modal="true">
			<button class="cd-x" onclick={() => (achDetail = null)} aria-label="Close">✕</button>
			<div class="cd-emoji" class:ad-dim={!achDetail.earned}>{achDetail.emoji}</div>
			<h3 class="cd-name">{achDetail.name}</h3>
			<p class="cd-solves">{achDetail.desc}</p>
			{#if achDetail.earned}
				<div class="ad-status earned">✓ Unlocked</div>
			{:else}
				{#if achDetail.progText}
					<div class="ad-prog">
						<div
							class="ad-prog-fill"
							style="width:{Math.round((achDetail.progress ?? 0) * 100)}%"
						></div>
					</div>
					<div class="ad-prog-t">{achDetail.progText}</div>
				{/if}
				<div class="ad-status locked">🔒 Locked</div>
			{/if}
		</div>
	</div>
{/if}

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
		cursor: pointer;
		transition:
			transform 0.15s,
			border-color 0.2s;
	}
	.cat-tile:hover {
		transform: translateY(-2px);
		border-color: rgba(251, 191, 36, 0.5);
	}
	.cat-tile:active {
		transform: scale(0.97);
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
		cursor: pointer;
		transition:
			transform 0.15s,
			border-color 0.2s;
	}
	.ach:hover {
		transform: translateY(-2px);
	}
	.ach:active {
		transform: scale(0.97);
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

	/* 🎉 Newly-unlocked pulse + banner */
	.ach.just {
		opacity: 1;
		filter: none;
		border-color: rgba(253, 224, 71, 0.85);
		animation: bp-pop 0.7s var(--ease-spring, ease) 1;
		box-shadow: 0 0 20px rgba(251, 191, 36, 0.4);
	}
	@keyframes bp-pop {
		0% {
			transform: scale(0.85);
		}
		55% {
			transform: scale(1.08);
		}
		100% {
			transform: scale(1);
		}
	}
	.bp-unlock {
		position: fixed;
		left: 50%;
		bottom: 26px;
		transform: translateX(-50%);
		z-index: 10000;
		padding: 10px 18px;
		border-radius: 999px;
		background: linear-gradient(135deg, #fbbf24, #f59e0b);
		color: #2a1e00;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 0.9rem;
		box-shadow: 0 10px 28px rgba(245, 158, 11, 0.45);
		animation: bp-toast 0.4s var(--ease-spring, ease) 1;
	}
	@keyframes bp-toast {
		from {
			transform: translate(-50%, 16px);
			opacity: 0;
		}
		to {
			transform: translate(-50%, 0);
			opacity: 1;
		}
	}

	/* 🗂️ Category detail modal */
	.cd-overlay {
		position: fixed;
		inset: 0;
		z-index: 9990;
		display: grid;
		place-items: center;
		padding: 22px;
	}
	.cd-backdrop {
		position: absolute;
		inset: 0;
		border: none;
		cursor: default;
		background: rgba(4, 8, 14, 0.72);
		backdrop-filter: blur(6px);
	}
	.cd-card {
		position: relative;
		z-index: 1;
		width: 100%;
		max-width: 320px;
		padding: 24px 22px 20px;
		border-radius: 20px;
		text-align: center;
		background: var(--surface-strong, rgba(20, 26, 38, 0.96));
		border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.16));
		box-shadow: 0 24px 60px rgba(0, 0, 0, 0.5);
	}
	.cd-x {
		position: absolute;
		top: 10px;
		right: 10px;
		width: 30px;
		height: 30px;
		border-radius: 50%;
		border: none;
		cursor: pointer;
		font-weight: 900;
		color: #fff;
		background: rgba(255, 255, 255, 0.1);
	}
	.cd-emoji {
		font-size: 2.6rem;
		line-height: 1;
	}
	.cd-name {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1.2rem;
		margin: 8px 0 2px;
		color: var(--text);
	}
	.cd-solves {
		font-size: 0.8rem;
		color: var(--text-muted);
		margin: 0 0 14px;
	}
	.cd-ladder {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.cd-tier {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 9px 12px;
		border-radius: 12px;
		background: var(--surface, rgba(255, 255, 255, 0.05));
		border: 1px solid var(--border, rgba(255, 255, 255, 0.1));
		opacity: 0.55;
	}
	.cd-tier.got {
		opacity: 1;
		border-color: rgba(251, 191, 36, 0.4);
	}
	.cd-medal {
		font-size: 1.3rem;
	}
	.cd-tname {
		flex: 1;
		text-align: left;
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.9rem;
		color: var(--text);
	}
	.cd-treq {
		font-size: 0.76rem;
		font-weight: 700;
		color: var(--text-muted);
	}
	.cd-tier.got .cd-treq {
		color: #6ee7b7;
	}

	/* Achievement detail modal extras */
	.cd-emoji.ad-dim {
		filter: grayscale(0.6);
		opacity: 0.7;
	}
	.ad-status {
		margin-top: 14px;
		padding: 8px 16px;
		border-radius: 999px;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 0.82rem;
		display: inline-block;
	}
	.ad-status.earned {
		background: rgba(110, 231, 183, 0.16);
		border: 1px solid rgba(110, 231, 183, 0.45);
		color: #6ee7b7;
	}
	.ad-status.locked {
		background: rgba(255, 255, 255, 0.06);
		border: 1px solid var(--border, rgba(255, 255, 255, 0.12));
		color: var(--text-muted);
	}
	.ad-prog {
		width: 70%;
		height: 7px;
		border-radius: 999px;
		background: rgba(255, 255, 255, 0.14);
		overflow: hidden;
		margin: 14px auto 5px;
	}
	.ad-prog-fill {
		height: 100%;
		border-radius: 999px;
		background: linear-gradient(90deg, #fbbf24, #fde047);
	}
	.ad-prog-t {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.78rem;
		color: var(--text-muted);
	}

	/* 🎊 Confetti (appended to <body>, so styled globally) */
	:global(.wb-confetti) {
		position: fixed;
		inset: 0;
		z-index: 10001;
		pointer-events: none;
		overflow: hidden;
	}
	:global(.wb-confetti span) {
		position: absolute;
		top: -14px;
		width: 9px;
		height: 15px;
		border-radius: 2px;
		animation-name: -global-wb-fall;
		animation-timing-function: ease-in;
		animation-fill-mode: forwards;
	}
	@keyframes -global-wb-fall {
		0% {
			transform: translateY(-10px) rotate(0deg);
			opacity: 1;
		}
		100% {
			transform: translateY(105vh) rotate(720deg);
			opacity: 0.9;
		}
	}
</style>
