<script>
	// Today's Daily leaderboard. Sort by any column (name / cash / score / streaks);
	// scope dropdown: Everyone · Friends · a specific group.
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { getDailyBoard, getMyGroups } from '$lib/stores/statsStore.js';

	/** scope: 'global' (Everyone) | 'friends' | a group id */
	let scope = $state('global');
	/** @type {any[]} */
	let rows = $state([]);
	/** @type {any[]} */
	let groups = $state([]);
	let loading = $state(true);
	let error = $state('');

	// Sortable columns (client-side). Default: by place, best → worst. Tap # again to
	// flip and bring LAST place to the top.
	/** @typedef {'place'|'name'|'net_worth'|'credit'|'score'|'efficiency'|'play_streak'|'win_streak'} SortKey */
	let sortKey = $state(/** @type {SortKey} */ ('place'));
	let sortDir = $state(/** @type {'asc'|'desc'} */ ('asc'));
	/** @param {SortKey} k */
	function setSort(k) {
		if (sortKey === k) sortDir = sortDir === 'asc' ? 'desc' : 'asc';
		else {
			sortKey = k;
			sortDir = k === 'name' || k === 'place' ? 'asc' : 'desc';
		}
	}
	/** @param {SortKey} k */
	const arrow = (k) => (sortKey === k ? (sortDir === 'asc' ? ' ▲' : ' ▼') : '');
	// Canonical place = rank by today's score (played first, high → low). Stays fixed
	// no matter how the list is sorted, so the # column always shows the real place.
	let ranked = $derived.by(() =>
		[...rows]
			.sort(
				(a, b) =>
					(b.score ?? -Infinity) - (a.score ?? -Infinity) ||
					String(a.name || '').localeCompare(String(b.name || ''), undefined, {
						sensitivity: 'base'
					})
			)
			.map((r, i) => ({ ...r, _place: i + 1 }))
	);
	let sortedRows = $derived.by(() => {
		const dir = sortDir === 'asc' ? 1 : -1;
		return [...ranked].sort((a, b) => {
			if (sortKey === 'place') return dir * (a._place - b._place);
			if (sortKey === 'name')
				return (
					dir *
					String(a.name || '').localeCompare(String(b.name || ''), undefined, {
						sensitivity: 'base'
					})
				);
			const nullLast = sortKey === 'score' || sortKey === 'efficiency';
			const av = nullLast ? (a[sortKey] ?? -Infinity) : Number(a[sortKey] ?? 0);
			const bv = nullLast ? (b[sortKey] ?? -Infinity) : Number(b[sortKey] ?? 0);
			return dir * (av - bv) || a._place - b._place;
		});
	});

	const fmt = (/** @type {any} */ n) => '$' + Math.round(Number(n ?? 0)).toLocaleString();

	async function load() {
		loading = true;
		error = '';
		try {
			const isGroup = scope !== 'global' && scope !== 'friends';
			rows = await getDailyBoard(isGroup ? 'group' : scope, isGroup ? scope : null);
		} catch (e) {
			error = (e instanceof Error ? e.message : String(e)) || 'Failed to load';
		} finally {
			loading = false;
		}
	}

	onMount(async () => {
		groups = await getMyGroups();
		await load();
	});
	$effect(() => {
		void scope;
		load();
	});

	/** @param {number} rank */
	const medal = (rank) =>
		rank === 1 ? '🥇' : rank === 2 ? '🥈' : rank === 3 ? '🥉' : String(rank);
</script>

<!-- Scope: Everyone · Friends · a specific group -->
<div class="filters">
	<select class="filter-select" bind:value={scope}>
		<option value="global">🌍 Everyone</option>
		<option value="friends">👋 Friends</option>
		{#each groups as g}<option value={g.id}>👥 {g.name}</option>{/each}
	</select>
</div>

<p class="caption">Today's Daily — same puzzle for everyone. Tap a column to sort.</p>

{#if loading}
	<p class="muted">Loading…</p>
{:else if error}
	<p class="error">{error}</p>
{:else if rows.length === 0}
	<p class="muted">Nobody here yet — add friends or play today's Daily!</p>
{:else}
	<div class="table-wrap">
		<table>
			<thead>
				<tr>
					<th
						><button class="sort" class:on={sortKey === 'place'} onclick={() => setSort('place')}
							>#{arrow('place')}</button
						></th
					>
					<th
						><button class="sort" class:on={sortKey === 'name'} onclick={() => setSort('name')}
							>Player{arrow('name')}</button
						></th
					>
					<th class="num"
						><button
							class="sort"
							class:on={sortKey === 'net_worth'}
							onclick={() => setSort('net_worth')}
							><svg class="hcol-ic" viewBox="0 0 24 24" aria-hidden="true"
								><circle cx="12" cy="12" r="8.6" /><path d="M12 7v10" /><path
									d="M14.6 9.2c-.6-.8-1.6-1.2-2.7-1.2-1.7 0-2.9 1-2.9 2.3s1.3 1.9 2.9 2.2 2.9 1 2.9 2.3-1.3 2.3-2.9 2.3c-1.1 0-2.2-.5-2.8-1.3"
								/></svg
							>
							Cash{arrow('net_worth')}</button
						></th
					>
					<th class="num"
						><button
							class="sort"
							class:on={sortKey === 'credit'}
							onclick={() => setSort('credit')}
							title="Credit score — reputation from responsible money management (300–850)"
							><svg class="hcol-ic" viewBox="0 0 24 24" aria-hidden="true"
								><rect x="2.5" y="5" width="19" height="14" rx="2.5" /><path d="M2.5 9.5h19" /></svg
							>
							Credit{arrow('credit')}</button
						></th
					>
					<th class="num"
						><button class="sort" class:on={sortKey === 'score'} onclick={() => setSort('score')}
							><svg class="hcol-ic" viewBox="0 0 24 24" aria-hidden="true"
								><circle cx="12" cy="12" r="8.5" /><circle cx="12" cy="12" r="4.5" /><circle
									cx="12"
									cy="12"
									r="1.2"
								/></svg
							>
							Bounty Earned{arrow('score')}</button
						></th
					>
					<th class="num"
						><button
							class="sort"
							class:on={sortKey === 'efficiency'}
							onclick={() => setSort('efficiency')}
							title="Efficiency — value kept of the puzzle's base bounty (same for everyone; pure spend-less skill)"
							><svg class="hcol-ic" viewBox="0 0 24 24" aria-hidden="true"
								><path d="M4.5 16a7.5 7.5 0 0 1 15 0" /><path d="M12 16l3.6-3" /><circle
									cx="12"
									cy="16"
									r="1"
								/></svg
							>
							Eff{arrow('efficiency')}</button
						></th
					>
					<th class="num"
						><button
							class="sort"
							class:on={sortKey === 'play_streak'}
							onclick={() => setSort('play_streak')}
							><svg class="hcol-ic" viewBox="0 0 24 24" aria-hidden="true"
								><path
									d="M12 3s5 3.8 5 9a5 5 0 0 1-10 0c0-2 .9-3.5 2.4-4.6C10.2 8.7 12 7 12 3Z"
								/></svg
							>{arrow('play_streak')}</button
						></th
					>
					<th class="num"
						><button
							class="sort"
							class:on={sortKey === 'win_streak'}
							onclick={() => setSort('win_streak')}
							><svg class="hcol-ic" viewBox="0 0 24 24" aria-hidden="true"
								><path d="M7 4.2h10v4.8a5 5 0 0 1-10 0z" /><path
									d="M7 6.2H4.2v.8a3 3 0 0 0 2.8 3M17 6.2h2.8v.8a3 3 0 0 1-2.8 3"
								/><path
									d="M12 13.8v2.8M9 20.4h6M10.3 20.4c0-1.9.5-3.8 1.7-3.8s1.7 1.9 1.7 3.8"
								/></svg
							>{arrow('win_streak')}</button
						></th
					>
				</tr>
			</thead>
			<tbody>
				{#each sortedRows as r}
					<tr class={r.is_me ? 'me' : r._place <= 3 ? 'top' : ''}>
						<td class="rank">{medal(r._place)}</td>
						<td class="name">
							{#if r.is_me}
								<button
									class="name-link"
									onclick={() => goto('/profile')}
									style={r.color ? `color:${r.color}` : ''}>You</button
								>
							{:else}
								<button
									class="name-link"
									onclick={() => goto('/u/' + encodeURIComponent(r.name || ''))}
									style={r.color ? `color:${r.color}` : ''}>{r.name || 'Player'}</button
								>
							{/if}
							{#if r.title}<span class="title">{r.title}</span>{/if}
						</td>
						<td class="metric">{fmt(r.net_worth)}</td>
						<td class="metric">{r.credit ?? 650}</td>
						<td class="metric gold">{r.played ? Number(r.score).toLocaleString() : '—'}</td>
						<td class="metric eff">{r.efficiency != null ? r.efficiency + '%' : '—'}</td>
						<td class="metric small">{r.play_streak > 0 ? '🔥' + r.play_streak : '—'}</td>
						<td class="metric small">{r.win_streak > 0 ? '🏆' + r.win_streak : '—'}</td>
					</tr>
				{/each}
			</tbody>
		</table>
	</div>
{/if}

<p class="hint">Same puzzle for everyone today. Spend less, score more.</p>

<style>
	.filters {
		display: flex;
		gap: 0.5rem;
		justify-content: center;
		align-items: center;
		flex-wrap: wrap;
		margin-bottom: 0.5rem;
	}
	.filter-select {
		padding: 0.55rem 1rem;
		border-radius: 10px;
		border: 1px solid var(--border);
		background: var(--surface);
		color: var(--text);
		font-size: 0.95rem;
		font-weight: 600;
	}
	.caption {
		color: var(--text-faint);
		font-size: 0.8rem;
		margin: 0.2rem 0 1rem;
		text-align: center;
	}
	.muted {
		color: var(--text-muted);
		padding: 2rem 0;
		text-align: center;
	}
	.error {
		color: #fb7185;
		text-align: center;
	}
	.table-wrap {
		overflow-x: auto;
		border: 1px solid var(--border);
		border-radius: 14px;
	}
	table {
		width: 100%;
		border-collapse: collapse;
	}
	th {
		font-size: 0.62rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--text-faint);
		padding: 0.6rem 0.45rem;
		text-align: left;
		border-bottom: 1px solid var(--border);
	}
	td {
		padding: 0.6rem 0.45rem;
		border-bottom: 1px solid var(--border);
		font-size: 0.9rem;
		text-align: left;
	}
	tr:last-child td {
		border-bottom: none;
	}
	td.rank {
		width: 30px;
		padding-left: 0.5rem;
	}
	td.name {
		font-weight: 600;
	}
	.name-link {
		background: none;
		border: none;
		padding: 0;
		font: inherit;
		color: inherit;
		cursor: pointer;
		text-decoration: underline;
		text-decoration-color: rgba(255, 255, 255, 0.2);
		text-underline-offset: 2px;
	}
	.name-link:hover {
		text-decoration-color: var(--gold);
	}
	td.metric {
		font-family: var(--font-display);
		font-weight: 700;
		color: var(--text);
		text-align: right;
		white-space: nowrap;
	}
	td.metric.gold {
		color: var(--brand-2);
	}
	td.metric.eff {
		color: #6ee7b7;
		font-size: 0.85rem;
	}
	td.metric.small {
		font-weight: 700;
		font-size: 0.82rem;
		color: var(--text-muted);
	}
	th.num {
		text-align: right;
	}
	th button.sort {
		background: none;
		border: none;
		padding: 0;
		margin: 0;
		cursor: pointer;
		font: inherit;
		color: inherit;
		text-transform: inherit;
		letter-spacing: inherit;
		white-space: nowrap;
	}
	th button.sort:hover {
		color: var(--text-muted);
	}
	th button.sort.on {
		color: var(--brand-2);
	}
	/* Column-header line icons — inherit the header/sort color via currentColor. */
	.hcol-ic {
		width: 1.05em;
		height: 1.05em;
		fill: none;
		stroke: currentColor;
		stroke-width: 1.7;
		stroke-linecap: round;
		stroke-linejoin: round;
		vertical-align: -0.16em;
	}
	tr.me {
		background: rgba(56, 189, 248, 0.1);
	}
	tr.me td.name {
		color: #7dd3fc;
	}
	.title {
		font-size: 0.68rem;
		color: var(--text-faint);
		margin-left: 0.35rem;
		white-space: nowrap;
	}
	.hint {
		margin-top: 1.2rem;
		font-size: 0.76rem;
		color: var(--text-faint);
		line-height: 1.5;
		text-align: center;
	}
</style>
