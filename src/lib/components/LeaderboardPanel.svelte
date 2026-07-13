<script>
	// Game-type leaderboard: Daily (sortable) · Cash Game · Challenges · Wealth.
	// scope dropdown: Everyone · Friends · a specific group.
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import Icon from '$lib/components/Icon.svelte';
	import { fmtSecs } from '$lib/time.js';
	import {
		getDailyBoard,
		getClimbLeaderboard,
		getChallengeLeaderboard,
		getWealthLeaderboard,
		getMyGroups
	} from '$lib/stores/statsStore.js';

	// Which game-type board is showing. Daily is the rich sortable table; the rest are
	// simple rank/metric boards fed by their own server RPCs (same scope convention).
	const BOARDS = [
		{ key: 'daily', label: 'Daily' },
		{ key: 'climb', label: 'Cash Game' },
		{ key: 'challenge', label: 'Challenges' },
		{ key: 'wealth', label: 'Wealth' }
	];
	let board = $state('daily');

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
	/** @typedef {'place'|'name'|'score'|'efficiency'|'play_streak'|'win_streak'|'time'} SortKey */
	let sortKey = $state(/** @type {SortKey} */ ('place'));
	let sortDir = $state(/** @type {'asc'|'desc'} */ ('asc'));
	/** @param {SortKey} k */
	function setSort(k) {
		if (sortKey === k) sortDir = sortDir === 'asc' ? 'desc' : 'asc';
		else {
			sortKey = k;
			sortDir = k === 'name' || k === 'place' || k === 'time' ? 'asc' : 'desc';
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
			if (sortKey === 'time') {
				// Fastest-solve: ascending = fastest first; unsolved (null) always last.
				const av = a.solve_seconds ?? Infinity;
				const bv = b.solve_seconds ?? Infinity;
				return dir * (av - bv) || a._place - b._place;
			}
			const nullLast = sortKey === 'score' || sortKey === 'efficiency';
			const av = nullLast ? (a[sortKey] ?? -Infinity) : Number(a[sortKey] ?? 0);
			const bv = nullLast ? (b[sortKey] ?? -Infinity) : Number(b[sortKey] ?? 0);
			return dir * (av - bv) || a._place - b._place;
		});
	});

	const fmt = (/** @type {any} */ n) => '$' + Math.round(Number(n ?? 0)).toLocaleString();

	// Metric columns for the simple (non-Daily) boards. Rows arrive pre-ranked from the server.
	let modeCols = $derived(
		board === 'climb'
			? [
					{ label: 'Best Run', cell: (/** @type {any} */ r) => fmt(r.best_run ?? 0) },
					{ label: 'Streak', cell: (/** @type {any} */ r) => r.best_streak ?? 0 },
					{
						label: 'Heat',
						cell: (/** @type {any} */ r) =>
							r.best_heat ? (r.best_heat / 100).toFixed(1) + '×' : '—'
					}
				]
			: board === 'challenge'
				? [
						{ label: 'Wins', cell: (/** @type {any} */ r) => r.metric ?? 0 },
						{
							label: 'Win %',
							cell: (/** @type {any} */ r) =>
								r.played ? Math.round(((r.metric ?? 0) / r.played) * 100) + '%' : '—'
						}
					]
				: board === 'wealth'
					? [
							{
								label: 'Net Worth',
								cell: (/** @type {any} */ r) => fmt(r.net_worth ?? r.cash)
							},
							{ label: 'Cash', cell: (/** @type {any} */ r) => fmt(r.cash ?? r.net_worth) },
							{ label: 'Credit', cell: (/** @type {any} */ r) => r.credit ?? 650 }
						]
					: []
	);
	// Per-board column legend for the "ⓘ What do these mean?" key.
	let legend = $derived(
		board === 'daily'
			? [
					{
						term: 'Daily Earnings',
						desc: "What you banked from today's Daily — the budget you didn't spend, grown by your Interest."
					},
					{
						term: 'Efficiency',
						desc: "Share of the puzzle's base budget you kept. Same for everyone — pure spend-less skill."
					},
					{ term: 'Play', desc: "Play streak — days in a row you've shown up for the Daily." },
					{ term: 'Win', desc: "Win streak — Dailies you've solved in a row." },
					{
						term: 'Time',
						desc: "How fast you solved today's Daily — same puzzle for everyone, so fastest wins. Blank until you solve it."
					}
				]
			: board === 'climb'
				? [
						{
							term: 'Best Run',
							desc: "The most Cash you've ever banked in a single run — the board is ranked by this."
						},
						{
							term: 'Streak',
							desc: 'Most puzzles solved in one run before you cashed out or busted.'
						},
						{ term: 'Heat', desc: "The highest heat multiplier you've reached in a run." }
					]
				: board === 'challenge'
					? [
							{ term: 'Wins', desc: "Challenge matches you've won (all-time)." },
							{ term: 'Win %', desc: 'Share of the challenges you played that you won.' }
						]
					: [
							{
								term: 'Net Worth',
								desc: 'Your true wealth — Available Balance minus any loan you owe. This is what the board ranks by.'
							},
							{
								term: 'Cash',
								desc: 'Your Available Balance — spendable money, before subtracting debt.'
							},
							{
								term: 'Credit',
								desc: 'Your credit score (300-850) — reputation from responsible money management.'
							}
						]
	);
	let showKey = $state(false);

	async function load() {
		loading = true;
		error = '';
		try {
			const isGroup = scope !== 'global' && scope !== 'friends';
			const sc = isGroup ? 'group' : scope;
			const grp = isGroup ? scope : null;
			if (board === 'climb') rows = await getClimbLeaderboard(sc, grp);
			else if (board === 'challenge') rows = await getChallengeLeaderboard(sc, grp, 'all');
			else if (board === 'wealth') rows = await getWealthLeaderboard(sc, 'all', grp);
			else rows = await getDailyBoard(sc, grp);
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
		void board;
		load();
	});
</script>

<!-- Game-type tabs -->
<div class="lb-tabs" role="tablist">
	{#each BOARDS as b}
		<button
			class="lb-tab"
			class:on={board === b.key}
			role="tab"
			aria-selected={board === b.key}
			onclick={() => (board = b.key)}>{b.label}</button
		>
	{/each}
</div>

<!-- Scope: Everyone · Friends · a specific group -->
<div class="filters">
	<select class="filter-select" bind:value={scope}>
		<option value="global">Everyone</option>
		<option value="friends">Friends</option>
		{#each groups as g}<option value={g.id}>{g.name}</option>{/each}
	</select>
</div>

<!-- ⓘ Column key: explains what each column on the current board means. -->
<div class="lb-key-row">
	<button class="lb-key-toggle" onclick={() => (showKey = !showKey)}>
		{#if showKey}<Icon name="close" size={13} /> Close key{:else}<Icon name="info" size={13} /> What
			do these mean?{/if}
	</button>
</div>
{#if showKey}
	<div class="lb-key">
		{#each legend as item}
			<div class="lb-key-item">
				<span class="lbk-term">{item.term}</span><span class="lbk-desc">{item.desc}</span>
			</div>
		{/each}
	</div>
{/if}

{#if loading}
	<p class="muted">Loading…</p>
{:else if error}
	<p class="error">{error}</p>
{:else if rows.length === 0}
	<p class="muted">Nobody here yet. Add friends or play!</p>
{:else if board !== 'daily'}
	<!-- Simple mode board: rank · player · metric(s), pre-ranked by the server. -->
	<div class="table-wrap">
		<table>
			<thead>
				<tr>
					<th>#</th>
					<th>Player</th>
					{#each modeCols as c}<th class="num">{c.label}</th>{/each}
				</tr>
			</thead>
			<tbody>
				{#each rows as r}
					<tr class={r.is_me ? 'me' : r.rank <= 3 ? 'top' : ''}>
						<td class="rank"
							>{#if r.rank >= 1 && r.rank <= 3}<span class="rk-{r.rank}"
									><Icon name="medal" size={15} /></span
								>{:else}{r.rank}{/if}</td
						>
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
						{#each modeCols as c}<td class="metric gold">{c.cell(r)}</td>{/each}
					</tr>
				{/each}
			</tbody>
		</table>
	</div>
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
							class:on={sortKey === 'score'}
							onclick={() => setSort('score')}
							title="Earnings — what you banked from today's Daily"
							><svg class="hcol-ic" viewBox="0 0 24 24" aria-hidden="true"
								><circle cx="12" cy="12" r="8.5" /><circle cx="12" cy="12" r="4.5" /><circle
									cx="12"
									cy="12"
									r="1.2"
								/></svg
							>
							Earned{arrow('score')}</button
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
							onclick={() => setSort('play_streak')}>Play{arrow('play_streak')}</button
						></th
					>
					<th class="num"
						><button
							class="sort"
							class:on={sortKey === 'win_streak'}
							onclick={() => setSort('win_streak')}>Win{arrow('win_streak')}</button
						></th
					>
					<th class="num"
						><button
							class="sort"
							class:on={sortKey === 'time'}
							onclick={() => setSort('time')}
							title="Solve time — how fast you cracked today's Daily (same puzzle for everyone)"
							>Time{arrow('time')}</button
						></th
					>
				</tr>
			</thead>
			<tbody>
				{#each sortedRows as r}
					<tr class={r.is_me ? 'me' : r._place <= 3 ? 'top' : ''}>
						<td class="rank"
							>{#if r._place >= 1 && r._place <= 3}<span class="rk-{r._place}"
									><Icon name="medal" size={15} /></span
								>{:else}{r._place}{/if}</td
						>
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
						<td class="metric gold">{r.played ? Number(r.score).toLocaleString() : '—'}</td>
						<td class="metric eff">{r.efficiency != null ? r.efficiency + '%' : '—'}</td>
						<td class="metric small">{r.play_streak > 0 ? r.play_streak : '—'}</td>
						<td class="metric small">{r.win_streak > 0 ? r.win_streak : '—'}</td>
						<td class="metric small">{fmtSecs(r.solve_seconds)}</td>
					</tr>
				{/each}
			</tbody>
		</table>
	</div>
{/if}

<style>
	.lb-tabs {
		display: flex;
		gap: 0.4rem;
		justify-content: center;
		flex-wrap: wrap;
		margin-bottom: 0.7rem;
	}
	.lb-tab {
		padding: 0.4rem 0.85rem;
		border-radius: 999px;
		border: 1px solid var(--border);
		background: var(--surface);
		color: var(--text-muted);
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.82rem;
		cursor: pointer;
		transition:
			background 0.15s,
			color 0.15s,
			border-color 0.15s;
	}
	.lb-tab:hover {
		color: var(--text);
	}
	.lb-tab.on {
		background: var(--brand-2);
		border-color: var(--brand-2);
		color: #0a0a0a;
	}
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
	.lb-key-row {
		display: flex;
		justify-content: center;
		margin: 0 0 0.8rem;
	}
	.lb-key-toggle {
		background: none;
		border: none;
		cursor: pointer;
		color: var(--brand-2);
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.8rem;
		padding: 0.2rem 0.4rem;
	}
	.lb-key-toggle:hover {
		text-decoration: underline;
	}
	.lb-key {
		text-align: left;
		max-width: 520px;
		margin: 0 auto 1rem;
		border: 1px solid var(--border);
		border-radius: 12px;
		padding: 0.75rem 0.9rem;
		background: var(--surface);
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
	}
	.lb-key-item {
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.lbk-term {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.82rem;
		color: var(--brand-2);
	}
	.lbk-desc {
		font-size: 0.8rem;
		color: var(--text-muted);
		line-height: 1.4;
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
		padding: 0.55rem 0.28rem;
		text-align: left;
		border-bottom: 1px solid var(--border);
	}
	td {
		padding: 0.55rem 0.28rem;
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
	td.rank .rk-1 {
		color: #fbbf24;
	}
	td.rank .rk-2 {
		color: #cbd5e1;
	}
	td.rank .rk-3 {
		color: #d19a66;
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
		display: inline-block;
		max-width: 108px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		vertical-align: bottom;
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
</style>
