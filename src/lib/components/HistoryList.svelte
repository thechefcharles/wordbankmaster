<script>
	import { onMount } from 'svelte';
	import { getHistory, getMatchDetail } from '$lib/stores/statsStore.js';
	import MatchDetailModal from '$lib/components/MatchDetailModal.svelte';
	import ModeIcon from '$lib/components/ModeIcon.svelte';
	import { track } from '$lib/analytics.js';

	/** @type {'all'|'daily'|'climb'|'challenge'} */
	let mode = $state('all');
	/** @type {'all'|'won'|'lost'|'tie'} */
	let result = $state('all');
	/** @type {'recent'|'net'|'multiple'} */
	let sort = $state('recent');

	/** @type {any[]} */
	let rows = $state([]);
	let loading = $state(true);
	let error = $state('');
	let offset = $state(0);
	let done = $state(false);
	const PAGE = 30;

	let openRow = $state('');
	/** @type {any} */
	let detail = $state(null);

	const MODES = [
		{ k: 'all', label: 'All' },
		{ k: 'daily', label: 'Daily' },
		{ k: 'climb', label: 'Cash Game' },
		{ k: 'challenge', label: 'Versus' }
	];
	const money = (/** @type {any} */ n) =>
		(Number(n) < 0 ? '−$' : '+$') + Math.abs(Math.round(Number(n ?? 0))).toLocaleString();
	const mult = (/** @type {any} */ x) => (x ? (Number(x) / 100).toFixed(1) + '×' : '');
	const when = (/** @type {string} */ t) =>
		new Date(t).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });

	/** @param {any} r */
	const title = (r) =>
		r.game_mode === 'challenge'
			? r.opponent_name
				? '@' + r.opponent_name
				: r.group_name || 'Challenge'
			: r.category || 'Puzzle';

	async function load(reset = false) {
		if (reset) {
			offset = 0;
			done = false;
			rows = [];
		}
		loading = true;
		error = '';
		try {
			const page = await getHistory({
				mode: mode === 'all' ? null : mode,
				result: result === 'all' ? null : result,
				sort,
				limit: PAGE,
				offset
			});
			rows = reset ? page : [...rows, ...page];
			offset += page.length;
			if (page.length < PAGE) done = true;
		} catch (e) {
			error = (e instanceof Error ? e.message : String(e)) || 'Failed to load';
		} finally {
			loading = false;
		}
	}

	/** @param {any} r */
	async function openDetail(r) {
		if (r.game_mode === 'challenge' && r.match_id) {
			detail = { loading: true };
			const d = await getMatchDetail(r.match_id);
			detail = d || null;
			if (!d) error = 'Could not load that challenge.';
		} else {
			openRow = openRow === r.id ? '' : r.id;
		}
	}

	onMount(() => {
		track('history_view');
		load(true);
	});
	function setMode(/** @type {any} */ k) {
		mode = k;
		load(true);
	}
	function setResult(/** @type {any} */ k) {
		result = k;
		load(true);
	}
</script>

<div class="hl">
	<div class="chips">
		{#each MODES as m}
			<button class="chip" class:active={mode === m.k} onclick={() => setMode(m.k)}
				>{#if m.k !== 'all'}<ModeIcon mode={m.k} size={15} />{/if}{m.label}</button
			>
		{/each}
	</div>

	<div class="row2">
		<div class="seg">
			{#each [['all', 'All'], ['won', 'Won'], ['lost', 'Lost'], ['tie', 'Tie']] as [k, l]}
				<button class="seg-btn" class:active={result === k} onclick={() => setResult(k)}>{l}</button
				>
			{/each}
		</div>
		<select class="sort" bind:value={sort} onchange={() => load(true)}>
			<option value="recent">Newest</option>
			<option value="net">Biggest net</option>
			<option value="multiple">Highest ×</option>
		</select>
	</div>

	{#if error}<p class="msg err">{error}</p>{/if}

	{#if loading && rows.length === 0}
		<p class="msg">Loading…</p>
	{:else if rows.length === 0}
		<p class="msg">No games yet. Play a round and it’ll show up here.</p>
	{:else}
		<ul class="list">
			{#each rows as r (r.id)}
				<li class="item" class:open={openRow === r.id}>
					<button class="item-main" onclick={() => openDetail(r)}>
						<span class="ic"><ModeIcon mode={r.game_mode} size={20} /></span>
						<span class="mid">
							<span class="ttl">{title(r)}</span>
							<span class="sub">
								{#if r.game_mode === 'challenge'}
									{r.outcome === 'won' ? 'Won' : r.outcome === 'tie' ? 'Tied' : 'Lost'}
									{#if r.rank && r.field_size}· #{r.rank}/{r.field_size}{/if}
									{#if r.solved_count != null}· solved {r.solved_count}/{r.puzzle_count}{/if}
								{:else}
									{r.outcome === 'won'
										? 'Solved'
										: r.outcome === 'lost'
											? 'Missed'
											: r.outcome || ''}
									{#if r.spent != null}· spent ${r.spent}{/if}
								{/if}
							</span>
						</span>
						<span class="right">
							{#if r.game_mode === 'challenge' && r.net == null}
								<span class="oc {r.outcome}"
									>{r.outcome === 'won' ? 'WON' : r.outcome === 'tie' ? 'TIE' : 'LOST'}</span
								>
								{#if Number(r.pot) > 0}<span class="mult"
										>${Number(r.pot).toLocaleString()} pot</span
									>{/if}
							{:else}
								{#if r.net != null}<span class="net" class:neg={Number(r.net) < 0}
										>{money(r.net)}</span
									>{/if}
								{#if mult(r.multiple_x100)}<span class="mult">{mult(r.multiple_x100)}</span>{/if}
							{/if}
							<span class="date">{when(r.played_at)}</span>
						</span>
					</button>
					{#if openRow === r.id && r.game_mode !== 'challenge'}
						<div class="detail-inline">
							{#if r.puzzle_phrase}<div class="answer">“{r.puzzle_phrase}”</div>{/if}
							<div class="kv">
								{#if r.earned != null}<span>Bounty <b>${r.earned}</b></span>{/if}
								{#if r.spent != null}<span>Spent <b>${r.spent}</b></span>{/if}
								{#if r.net != null}<span
										>Net <b class:neg={Number(r.net) < 0}>{money(r.net)}</b></span
									>{/if}
								{#if mult(r.multiple_x100)}<span>Multiple <b>{mult(r.multiple_x100)}</b></span>{/if}
							</div>
						</div>
					{/if}
				</li>
			{/each}
		</ul>

		{#if !done}
			<button class="more" onclick={() => load(false)} disabled={loading}>
				{loading ? 'Loading…' : 'Load more'}
			</button>
		{/if}
	{/if}
</div>

<MatchDetailModal {detail} on:close={() => (detail = null)} />

<style>
	.chips {
		display: flex;
		gap: 8px;
		overflow-x: auto;
		padding-bottom: 6px;
		margin-bottom: 10px;
	}
	.chip {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		flex: 0 0 auto;
		padding: 7px 13px;
		border-radius: var(--r-pill);
		border: 1px solid var(--border);
		background: var(--surface);
		color: var(--text-muted);
		font-weight: 600;
		font-size: 0.84rem;
		cursor: pointer;
	}
	.chip.active {
		background: linear-gradient(135deg, #fde047, #f59e0b);
		color: #3a2a00;
		border-color: transparent;
	}

	.row2 {
		display: flex;
		gap: 10px;
		align-items: center;
		margin-bottom: 14px;
	}
	.seg {
		display: flex;
		flex: 1;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--r-md);
		overflow: hidden;
	}
	.seg-btn {
		flex: 1;
		padding: 8px 0;
		background: none;
		border: none;
		color: var(--text-muted);
		font-size: 0.82rem;
		font-weight: 600;
		cursor: pointer;
	}
	.seg-btn.active {
		background: var(--surface-2);
		color: var(--gold);
	}
	.sort {
		background: var(--surface);
		border: 1px solid var(--border);
		color: var(--text);
		border-radius: var(--r-md);
		padding: 8px 10px;
		font-size: 0.82rem;
	}

	.list {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.item {
		border: 1px solid var(--border);
		border-radius: var(--r-md);
		background: var(--surface);
		overflow: hidden;
	}
	.item.open {
		border-color: rgba(251, 191, 36, 0.4);
	}
	.item-main {
		width: 100%;
		display: flex;
		align-items: center;
		gap: 11px;
		padding: 12px 13px;
		background: none;
		border: none;
		cursor: pointer;
		text-align: left;
	}
	.ic {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		flex: 0 0 auto;
	}
	.mid {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
		flex: 1;
	}
	.ttl {
		color: var(--text);
		font-weight: 700;
		font-size: 0.95rem;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.sub {
		color: var(--text-faint);
		font-size: 0.76rem;
	}
	.right {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 1px;
		flex: 0 0 auto;
	}
	.net {
		color: #7ee0a8;
		font-weight: 800;
		font-size: 0.95rem;
		font-variant-numeric: tabular-nums;
	}
	.net.neg,
	b.neg {
		color: #fb7185;
	}
	.mult {
		color: var(--gold);
		font-size: 0.74rem;
		font-weight: 700;
	}
	.date {
		color: var(--text-faint);
		font-size: 0.7rem;
	}
	.oc {
		font-size: 0.68rem;
		font-weight: 800;
		letter-spacing: 0.04em;
		padding: 2px 7px;
		border-radius: 6px;
	}
	.oc.won {
		background: rgba(126, 224, 168, 0.18);
		color: #7ee0a8;
	}
	.oc.lost {
		background: rgba(251, 113, 133, 0.18);
		color: #fb7185;
	}
	.oc.tie {
		background: var(--surface-2);
		color: var(--text-muted);
	}

	.detail-inline {
		padding: 0 13px 13px 49px;
	}
	.answer {
		color: var(--gold);
		font-weight: 700;
		margin: 0 0 8px;
	}
	.kv {
		display: flex;
		flex-wrap: wrap;
		gap: 6px 16px;
		color: var(--text-muted);
		font-size: 0.8rem;
	}
	.kv b {
		color: var(--text);
	}

	.more {
		display: block;
		margin: 14px auto 0;
		padding: 9px 22px;
		border-radius: var(--r-pill);
		background: var(--surface);
		border: 1px solid var(--border);
		color: var(--text);
		font-weight: 600;
		cursor: pointer;
	}

	.msg {
		color: var(--text-muted);
		text-align: center;
		padding: 24px 0;
	}
	.msg.err {
		color: #fb7185;
	}
</style>
