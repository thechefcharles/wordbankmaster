<script>
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import PageNav from '$lib/components/PageNav.svelte';
	import { page } from '$app/stores';
	import { getPublicProfile, addFriend, requestJoinGroup } from '$lib/stores/statsStore.js';
	import Avatar from '$lib/components/Avatar.svelte';
	import AccountCard from '$lib/components/AccountCard.svelte';
	import ModeIcon from '$lib/components/ModeIcon.svelte';
	import { track } from '$lib/analytics.js';
	/** @type {Record<string,string>} */ let busyFriend = $state({});
	/** @type {Record<string,string>} */ let groupState = $state({});

	/** @type {any} */
	let p = $state(null);
	let loading = $state(true);
	let notFound = $state(false);
	let addBusy = $state(false);
	let addMsg = $state('');

	const username = $derived($page.params.username);

	const mult = (/** @type {any} */ x) => (x ? (Number(x) / 100).toFixed(1) + '×' : '—');
	const winPct = (/** @type {any} */ a) =>
		a?.games_played ? Math.round((a.games_won / a.games_played) * 100) + '%' : '—';

	async function load() {
		loading = true;
		notFound = false;
		const d = await getPublicProfile($page.params.username);
		p = d;
		notFound = !d;
		loading = false;
	}

	async function add() {
		if (addBusy || !p) return;
		addBusy = true;
		const res = await addFriend(p.username);
		if (res?.ok) {
			addMsg = 'Request sent ✓';
			p = { ...p, request_outgoing: true };
		} else addMsg = res?.reason || 'Could not send request';
		addBusy = false;
	}

	/** @param {string} uname */
	async function addOne(uname) {
		if (busyFriend[uname]) return;
		busyFriend = { ...busyFriend, [uname]: 'busy' };
		const res = await addFriend(uname);
		busyFriend = { ...busyFriend, [uname]: res?.ok ? 'sent' : 'err' };
	}
	/** @param {any} g */
	async function join(g) {
		if (groupState[g.id]) return;
		groupState = { ...groupState, [g.id]: 'busy' };
		const res = await requestJoinGroup(g.id);
		groupState = { ...groupState, [g.id]: res?.ok ? 'requested' : 'err' };
	}

	onMount(() => {
		track('public_profile_view');
		load();
	});
	$effect(() => {
		void $page.params.username;
		load();
	});
</script>

<svelte:head><title>WordBank — @{username}</title></svelte:head>

<main class="u-page">
	<PageNav />

	{#if loading}
		<p class="msg">Loading…</p>
	{:else if notFound}
		<p class="msg">No player named <b>@{username}</b>.</p>
	{:else}
		<header class="u-head">
			<Avatar config={p.avatar} fx size={110} />
			<h1>@{p.username}</h1>
			{#if p.title}<span class="u-title">{p.title}</span>{/if}
			<div class="u-card">
				<AccountCard
					holder={p.name || p.username}
					balance={p.net_worth}
					tier={p.credit_tier ?? 'Good'}
				/>
			</div>
		</header>

		{#if !p.is_self}
			<!-- Head-to-head -->
			{@const h = p.head_to_head || {}}
			<section class="h2h">
				<div class="h2h-h">Your record vs @{p.username}</div>
				<div class="h2h-tally">
					<div class="t win"><b>{h.wins ?? 0}</b><span>W</span></div>
					<div class="t loss"><b>{h.losses ?? 0}</b><span>L</span></div>
					<div class="t tie"><b>{h.ties ?? 0}</b><span>T</span></div>
				</div>
				{#if (h.last5 ?? []).length}
					<div class="h2h-last">
						{#each h.last5 as g}
							<span class="pip {g.outcome}"
								>{g.outcome === 'won' ? 'W' : g.outcome === 'lost' ? 'L' : 'T'}</span
							>
						{/each}
					</div>
				{:else}
					<div class="h2h-empty">No challenges yet — send one!</div>
				{/if}
			</section>

			<div class="u-actions">
				{#if p.is_friend}
					<span class="pill friend">✓ Friends</span>
				{:else if p.request_outgoing}
					<span class="pill muted">Request sent</span>
				{:else if p.request_incoming}
					<button class="pill" onclick={() => goto('/friends')}>Respond to request →</button>
				{:else}
					<button class="pill" disabled={addBusy} onclick={add}>+ Add friend</button>
				{/if}
				<button class="pill gold" onclick={() => goto('/?challenge=' + p.username)}
					><ModeIcon mode="challenge" size={16} /> Challenge</button
				>
			</div>
			{#if addMsg}<p class="add-msg">{addMsg}</p>{/if}
		{:else}
			<div class="u-actions">
				<button class="pill" onclick={() => goto('/profile')}>This is you → your stats</button>
			</div>
		{/if}

		<section class="grid">
			<div class="stat">
				<span class="s-n">{p.current_streak}</span><span class="s-l">Streak</span>
			</div>
			<div class="stat">
				<span class="s-n">{p.longest_streak}</span><span class="s-l">Best streak</span>
			</div>
			<div class="stat">
				<span class="s-n">{winPct(p)}</span><span class="s-l">Daily win %</span>
			</div>
			<div class="stat">
				<span class="s-n">{p.puzzles_solved}</span><span class="s-l">Puzzles solved</span>
			</div>
			<div class="stat">
				<span class="s-n">{p.challenge_wins}</span><span class="s-l">Challenge wins</span>
			</div>
			<div class="stat">
				<span class="s-n">#{p.climb_position}</span><span class="s-l">Furthest</span>
			</div>
			<div class="stat">
				<span class="s-n">{mult(p.avg_multiple_x100)}</span><span class="s-l">Avg multiple</span>
			</div>
			<div class="stat">
				<span class="s-n">{mult(p.best_multiple_x100)}</span><span class="s-l">Best multiple</span>
			</div>
		</section>

		{#if (p.badges ?? []).length}
			<section class="badges">
				<div class="b-h">Badges · {p.badges.length}</div>
				<div class="b-wrap">
					{#each p.badges as b}<span class="badge"
							>{(b || '')
								.replace(/_/g, ' ')
								.replace(/\b\w/g, (/** @type {string} */ c) => c.toUpperCase())}</span
						>{/each}
				</div>
			</section>
		{/if}

		{#if !p.is_self && (p.friends ?? []).length}
			<section class="social">
				<div class="b-h">Friends · {p.friends.length}</div>
				{#each p.friends as f}
					<div class="soc-row">
						<button class="soc-main" onclick={() => goto('/u/' + encodeURIComponent(f.username))}
							>@{f.username}<span class="soc-go">›</span></button
						>
						{#if f.is_self}
							<span class="soc-tag">You</span>
						{:else if f.status === 'friends'}
							<span class="soc-tag ok">✓ Friend</span>
						{:else if f.status === 'pending_out' || busyFriend[f.username] === 'sent'}
							<span class="soc-tag">Requested</span>
						{:else}
							<button
								class="soc-act"
								disabled={!!busyFriend[f.username]}
								onclick={() => addOne(f.username)}
							>
								{busyFriend[f.username] === 'err' ? 'Retry' : '+ Add'}
							</button>
						{/if}
					</div>
				{/each}
			</section>
		{/if}

		{#if !p.is_self && (p.groups ?? []).length}
			<section class="social">
				<div class="b-h">Groups · {p.groups.length}</div>
				{#each p.groups as g}
					<div class="soc-row">
						<span class="soc-main static">{g.name}</span>
						{#if g.my_status === 'member'}
							<span class="soc-tag">✓ Member</span>
						{:else if groupState[g.id] === 'requested' || g.my_status === 'requested'}
							<span class="soc-tag">Requested</span>
						{:else}
							<button class="soc-act" disabled={groupState[g.id] === 'busy'} onclick={() => join(g)}
								>{groupState[g.id] === 'err' ? 'Failed' : 'Ask to join'}</button
							>
						{/if}
					</div>
				{/each}
			</section>
		{/if}
	{/if}
</main>

<style>
	.u-page {
		max-width: 520px;
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
	.msg {
		color: var(--text-muted);
		text-align: center;
		padding: 40px 0;
	}

	.u-head {
		text-align: center;
		margin: 10px 0 20px;
	}
	h1 {
		font-family: var(--font-display);
		font-size: 1.4rem;
		margin: 0;
	}
	.u-title {
		display: inline-block;
		margin-top: 4px;
		font-size: 0.78rem;
		color: var(--gold);
	}
	.u-card {
		max-width: 340px;
		margin: 16px auto 0;
	}

	.h2h {
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--r-md);
		padding: 14px;
		margin-bottom: 14px;
	}
	.h2h-h {
		color: var(--text-muted);
		font-size: 0.82rem;
		font-weight: 600;
		margin-bottom: 12px;
		text-align: center;
	}
	.h2h-tally {
		display: flex;
		justify-content: center;
		gap: 22px;
	}
	.t {
		display: flex;
		flex-direction: column;
		align-items: center;
	}
	.t b {
		font-family: var(--font-display);
		font-size: 1.6rem;
	}
	.t span {
		font-size: 0.7rem;
		color: var(--text-faint);
	}
	.t.win b {
		color: #7ee0a8;
	}
	.t.loss b {
		color: #fb7185;
	}
	.t.tie b {
		color: var(--text-muted);
	}
	.h2h-last {
		display: flex;
		justify-content: center;
		gap: 6px;
		margin-top: 12px;
	}
	.pip {
		width: 22px;
		height: 22px;
		border-radius: 6px;
		display: grid;
		place-items: center;
		font-size: 0.72rem;
		font-weight: 800;
	}
	.pip.won {
		background: rgba(126, 224, 168, 0.2);
		color: #7ee0a8;
	}
	.pip.lost {
		background: rgba(251, 113, 133, 0.2);
		color: #fb7185;
	}
	.pip.tie {
		background: var(--surface-2);
		color: var(--text-muted);
	}
	.h2h-empty {
		text-align: center;
		color: var(--text-faint);
		font-size: 0.8rem;
		margin-top: 10px;
	}

	.u-actions {
		display: flex;
		gap: 10px;
		justify-content: center;
		margin-bottom: 6px;
		flex-wrap: wrap;
	}
	.pill {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 5px;
		padding: 9px 18px;
		border-radius: var(--r-pill);
		border: 1px solid var(--border-strong);
		background: var(--surface);
		color: var(--text);
		font-weight: 700;
		font-size: 0.86rem;
		cursor: pointer;
	}
	.pill.gold {
		background: linear-gradient(135deg, #fde047, #f59e0b);
		color: #3a2a00;
		border-color: transparent;
	}
	.pill.friend {
		color: #7ee0a8;
	}
	.pill.muted {
		color: var(--text-faint);
		cursor: default;
	}
	.add-msg {
		text-align: center;
		color: var(--text-muted);
		font-size: 0.82rem;
		margin: 8px 0 0;
	}

	.grid {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: 8px;
		margin: 18px 0;
	}
	.stat {
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--r-sm);
		padding: 12px 6px;
		text-align: center;
	}
	.s-n {
		display: block;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1.05rem;
		color: var(--text);
	}
	.s-l {
		display: block;
		font-size: 0.64rem;
		color: var(--text-faint);
		margin-top: 3px;
	}

	.badges {
		margin-top: 6px;
	}
	.b-h {
		color: var(--text-faint);
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		margin-bottom: 8px;
	}
	.b-wrap {
		display: flex;
		flex-wrap: wrap;
		gap: 7px;
	}
	.social {
		margin-top: 18px;
	}
	.soc-row {
		display: flex;
		align-items: center;
		gap: 8px;
		margin-bottom: 7px;
	}
	.soc-main {
		flex: 1;
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 10px 13px;
		border-radius: 12px;
		background: var(--surface);
		border: 1px solid var(--border);
		color: var(--text);
		font-weight: 600;
		font-size: 0.92rem;
		cursor: pointer;
		text-align: left;
	}
	.soc-main.static {
		cursor: default;
	}
	button.soc-main:hover {
		border-color: var(--brand-2);
	}
	.soc-go {
		color: var(--text-faint);
	}
	.soc-act {
		flex: none;
		padding: 9px 14px;
		border-radius: 12px;
		cursor: pointer;
		font-weight: 800;
		font-size: 0.82rem;
		color: #3a2a00;
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
		border: none;
	}
	.soc-act:disabled {
		opacity: 0.5;
		cursor: default;
	}
	.soc-tag {
		flex: none;
		padding: 8px 13px;
		border-radius: 12px;
		font-weight: 700;
		font-size: 0.8rem;
		color: var(--text-muted, #aeb8c6);
		background: var(--surface-2, rgba(255, 255, 255, 0.06));
		border: 1px solid var(--border, rgba(255, 255, 255, 0.12));
	}
	.soc-tag.ok {
		color: #6ee7b7;
		border-color: rgba(110, 231, 183, 0.4);
		background: rgba(110, 231, 183, 0.1);
	}
	.soc-act:disabled {
		opacity: 0.6;
		cursor: default;
	}
	.soc-tag {
		flex: none;
		padding: 9px 12px;
		font-size: 0.8rem;
		font-weight: 700;
		color: var(--text-faint);
	}
	.badge {
		font-size: 0.78rem;
		padding: 5px 10px;
		border-radius: var(--r-pill);
		background: var(--surface);
		border: 1px solid var(--border);
		color: var(--text-muted);
	}

	@media (max-width: 380px) {
		.grid {
			grid-template-columns: repeat(3, 1fr);
		}
	}
</style>
