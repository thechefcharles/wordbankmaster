<script>
	// Activity feed — you, your friends, your groups. Reused by the /activity route
	// and the Community ▸ Activity tab.
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { getActivityFeed } from '$lib/stores/statsStore.js';

	/** @type {any[]} */
	let rows = $state([]);
	let loading = $state(true);
	let done = $state(false);
	let offset = $state(0);
	const PAGE = 30;

	/** @type {Record<string,string>} */
	const ICON = {
		daily_win: '📅',
		challenge: '⚔️',
		big_solve: '🎰',
		badge: '🏅',
		group_join: '👥'
	};
	const pretty = (/** @type {string} */ s) =>
		(s || '').replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
	const mult = (/** @type {any} */ x) => (x ? (Number(x) / 100).toFixed(1) + '×' : '');
	const money = (/** @type {any} */ n) =>
		(Number(n) < 0 ? '−$' : '+$') + Math.abs(Math.round(Number(n ?? 0))).toLocaleString();

	/** relative time */
	function ago(/** @type {string} */ t) {
		const s = Math.max(1, Math.floor((Date.now() - new Date(t).getTime()) / 1000));
		if (s < 60) return s + 's';
		if (s < 3600) return Math.floor(s / 60) + 'm';
		if (s < 86400) return Math.floor(s / 3600) + 'h';
		if (s < 604800) return Math.floor(s / 86400) + 'd';
		return new Date(t).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
	}

	/** @param {any} r */
	function line(r) {
		const m = r.meta || {};
		switch (r.type) {
			case 'daily_win': {
				const extra = m.multiple_x100 ? ` (${mult(m.multiple_x100)})` : '';
				return { verb: `won the Daily${extra}`, tag: m.net != null ? money(m.net) : '' };
			}
			case 'challenge':
				return m.opponent_name
					? { verb: `beat @${m.opponent_name} in a challenge`, tag: '' }
					: { verb: `won a group challenge${m.rank ? ` · #${m.rank}` : ''}`, tag: '' };
			case 'big_solve':
				return {
					verb: `pulled a ${mult(m.multiple_x100)} solve in the Cash Game`,
					tag: m.net != null ? money(m.net) : ''
				};
			case 'badge':
				return { verb: `earned the “${pretty(m.badge)}” badge`, tag: '' };
			case 'group_join':
				return { verb: `joined ${r.group_name || 'a group'}`, tag: '' };
			default:
				return { verb: 'did something', tag: '' };
		}
	}

	async function load(reset = false) {
		if (reset) {
			offset = 0;
			done = false;
			rows = [];
		}
		loading = true;
		const page = await getActivityFeed(PAGE, offset);
		rows = reset ? page : [...rows, ...page];
		offset += page.length;
		if (page.length < PAGE) done = true;
		loading = false;
	}

	onMount(() => load(true));
</script>

{#if loading && rows.length === 0}
	<p class="msg">Loading…</p>
{:else if rows.length === 0}
	<p class="msg">Nothing yet. Add friends and play — wins, badges and challenges show up here.</p>
{:else}
	<ul class="feed">
		{#each rows as r, i (r.type + r.actor_id + r.ts + i)}
			{@const l = line(r)}
			<li class="ev">
				<span class="ev-ic">{ICON[r.type] || '•'}</span>
				<span class="ev-body">
					<button
						class="ev-actor"
						onclick={() => goto('/u/' + encodeURIComponent(r.actor_name || ''))}
						>@{r.actor_name || 'player'}</button
					>
					<span class="ev-verb">{l.verb}</span>
				</span>
				{#if l.tag}<span class="ev-tag" class:neg={l.tag.startsWith('−')}>{l.tag}</span>{/if}
				<span class="ev-time">{ago(r.ts)}</span>
			</li>
		{/each}
	</ul>
	{#if !done}
		<button class="more" onclick={() => load(false)} disabled={loading}
			>{loading ? 'Loading…' : 'Load more'}</button
		>
	{/if}
{/if}

<style>
	.msg {
		color: var(--text-muted);
		text-align: center;
		padding: 28px 10px;
	}
	.feed {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: 7px;
	}
	.ev {
		display: flex;
		align-items: center;
		gap: 11px;
		padding: 11px 13px;
		border: 1px solid var(--border);
		border-radius: var(--r-md);
		background: var(--surface);
	}
	.ev-ic {
		font-size: 1.2rem;
		flex: 0 0 auto;
	}
	.ev-body {
		flex: 1;
		min-width: 0;
		font-size: 0.9rem;
		line-height: 1.35;
		text-align: left;
	}
	.ev-actor {
		background: none;
		border: none;
		padding: 0;
		font: inherit;
		font-weight: 800;
		color: var(--gold);
		cursor: pointer;
	}
	.ev-verb {
		color: var(--text);
	}
	.ev-tag {
		flex: 0 0 auto;
		font-weight: 800;
		color: #7ee0a8;
		font-size: 0.85rem;
		font-variant-numeric: tabular-nums;
	}
	.ev-tag.neg {
		color: #fb7185;
	}
	.ev-time {
		flex: 0 0 auto;
		color: var(--text-faint);
		font-size: 0.72rem;
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
</style>
