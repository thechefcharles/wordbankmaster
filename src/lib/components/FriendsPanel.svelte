<script>
	// Friends management — search/add, requests, your list. Reused by the /friends
	// route and the Community ▸ People ▸ Friends tab.
	import { onMount, onDestroy } from 'svelte';
	import { goto } from '$app/navigation';
	import Icon from '$lib/components/Icon.svelte';
	import {
		searchUsers,
		addFriend,
		respondFriendRequest,
		removeFriend,
		listFriends,
		listFriendRequests
	} from '$lib/stores/statsStore.js';
	import { requireConfirm } from '$lib/confirm.js';
	import { fx } from '$lib/sound.js';
	import { supabase } from '$lib/supabaseClient';

	/** Optional: called to start a challenge with a friend (username). */
	let { onChallenge = null } = $props();

	/** @type {{id?:string,username:string,name:string,added_at?:string}[]} */
	let friends = $state([]);
	/** @type {{id?:string,username:string,name:string}[]} */
	let incoming = $state([]);
	/** @type {{id?:string,username:string,name:string}[]} */
	let outgoing = $state([]);
	let loading = $state(true);
	let busy = $state('');
	let msg = $state('');

	let query = $state('');
	/** @type {Array<{username:string,name?:string,status?:string,id?:string,is_friend:boolean}>} */
	let results = $state([]);
	let searching = $state(false);

	async function load() {
		const [f, r] = await Promise.all([listFriends(), listFriendRequests()]);
		friends = f;
		incoming = r.incoming ?? [];
		outgoing = r.outgoing ?? [];
	}

	/** @type {any} */
	let channel;
	/** @type {ReturnType<typeof setTimeout>|undefined} */
	let reloadTimer;
	// Coalesce bursts of friend_requests changes into one re-fetch.
	function scheduleReload() {
		clearTimeout(reloadTimer);
		reloadTimer = setTimeout(() => load(), 150);
	}

	onMount(async () => {
		try {
			await load();
		} finally {
			loading = false;
		}
		// Realtime: when a friend_requests row involving me changes, re-derive the
		// incoming/outgoing/friends lists live. RLS ("friend_requests_self") scopes
		// delivery to rows where I'm requester or addressee, so an unfiltered
		// subscription only fires for me. On accept the server deletes the request
		// row (+ inserts the friendship), so my outgoing "Pending" flips to a friend
		// and the recipient's incoming request disappears — all without a poll.
		try {
			const { data } = await supabase.auth.getSession();
			const uid = data?.session?.user?.id;
			if (uid) {
				channel = supabase
					.channel(`friends:${uid}`)
					.on(
						'postgres_changes',
						{ event: '*', schema: 'public', table: 'friend_requests' },
						() => scheduleReload()
					)
					.subscribe();
			}
		} catch {
			/* realtime is best-effort; the panel still works via manual load() */
		}
	});

	onDestroy(() => {
		clearTimeout(reloadTimer);
		if (channel) {
			supabase.removeChannel(channel);
			channel = undefined;
		}
	});

	/** @type {ReturnType<typeof setTimeout>|undefined} */
	let timer;
	$effect(() => {
		const q = query.trim();
		clearTimeout(timer);
		if (q.length < 2) {
			results = [];
			searching = false;
			return;
		}
		searching = true;
		timer = setTimeout(async () => {
			results = await searchUsers(q);
			searching = false;
		}, 280);
	});

	/** @param {string} username */
	async function add(username) {
		if (busy) return;
		busy = username;
		msg = '';
		const res = await addFriend(username);
		busy = '';
		if (res?.ok) {
			fx('select');
			msg =
				res.status === 'friends'
					? `You're now friends with ${res.friend_name ?? username}!`
					: `Request sent to ${res.friend_name ?? username}.`;
			query = ''; // clear the search box so the results list collapses
			results = [];
			await load();
		} else {
			msg =
				res?.reason === 'already_friends'
					? 'Already friends.'
					: res?.reason === 'not_found'
						? 'No player with that name.'
						: 'Could not send request.';
		}
	}

	/** @param {any} u @param {boolean} accept */
	async function respond(u, accept) {
		if (busy) return;
		busy = u.id;
		const res = await respondFriendRequest(u.id, accept);
		busy = '';
		if (res?.ok) {
			fx(accept ? 'win' : 'tap');
			await load();
		}
	}

	/** @param {any} u */
	async function unfriend(u) {
		if (busy) return;
		if (
			!(await requireConfirm({
				title: 'Remove friend?',
				message: `Remove @${u.username || u.name} from your friends?`,
				confirmText: 'Remove',
				danger: true
			}))
		)
			return;
		busy = u.id;
		await removeFriend(u.id);
		busy = '';
		fx('tap');
		await load();
	}

	const label = (/** @type {any} */ u) => (u.username ? '@' + u.username : u.name || 'Player');

	// Long-list handling: sort your friends (A–Z or recently added) + filter live.
	// The top search box adds NEW people; this narrows the ones you already have.
	let listFilter = $state('');
	/** @type {'az'|'recent'} */
	let sortMode = $state('az');
	const sortedFriends = $derived.by(() => {
		const arr = [...friends];
		if (sortMode === 'recent') {
			// added_at is an ISO string → lexical compare desc = newest first
			return arr.sort((a, b) => (b.added_at || '').localeCompare(a.added_at || ''));
		}
		return arr.sort((a, b) =>
			(a.username || a.name || '').localeCompare(b.username || b.name || '', undefined, {
				sensitivity: 'base'
			})
		);
	});
	const shownFriends = $derived.by(() => {
		const q = listFilter.trim().toLowerCase();
		if (!q) return sortedFriends;
		return sortedFriends.filter((u) =>
			((u.username || '') + ' ' + (u.name || '')).toLowerCase().includes(q)
		);
	});
</script>

<div class="search-wrap">
	<input
		class="search"
		type="text"
		placeholder="Search players by username…"
		bind:value={query}
		maxlength="20"
		autocomplete="off"
	/>
	{#if query.trim().length >= 2}
		<div class="results">
			{#if searching}
				<p class="muted small pad">Searching…</p>
			{:else if results.length === 0}
				<p class="muted small pad">No players found.</p>
			{:else}
				{#each results as u}
					<div class="row">
						<span class="who">
							{#if u.name && u.name !== u.username}<span class="rname">{u.name}</span>{/if}
							<span class="uname">@{u.username}</span>
						</span>
						{#if u.status === 'friends'}<span class="tag friend"
								><Icon name="check" size={12} /> Friend</span
							>
						{:else if u.status === 'pending_out'}<span class="tag pending">Requested</span>
						{:else if u.status === 'pending_in'}<button
								class="act accept"
								disabled={busy === u.id}
								onclick={() => respond(u, true)}>Accept</button
							>
						{:else}<button
								class="act add"
								disabled={busy === u.username}
								onclick={() => add(u.username)}>+ Add</button
							>{/if}
					</div>
				{/each}
			{/if}
		</div>
	{/if}
</div>

{#if msg}<p class="msg">{msg}</p>{/if}

{#if loading}
	<p class="muted pad">Loading…</p>
{:else}
	{#if incoming.length > 0}
		<h2 class="sec">Requests <span class="count">{incoming.length}</span></h2>
		<div class="list">
			{#each incoming as u}
				<div class="row card">
					<span class="uname">{label(u)}</span>
					<div class="row-acts">
						<button class="act accept" disabled={busy === u.id} onclick={() => respond(u, true)}
							>Accept</button
						>
						<button class="act decline" disabled={busy === u.id} onclick={() => respond(u, false)}
							>Decline</button
						>
					</div>
				</div>
			{/each}
		</div>
	{/if}

	<div class="sec-row">
		<h2 class="sec">Your Friends <span class="count">{friends.length}</span></h2>
		{#if friends.length > 1}
			<div class="sort-toggle" role="group" aria-label="Sort friends">
				<button class:on={sortMode === 'az'} onclick={() => (sortMode = 'az')}>A–Z</button>
				<button class:on={sortMode === 'recent'} onclick={() => (sortMode = 'recent')}
					>Recent</button
				>
			</div>
		{/if}
	</div>
	{#if friends.length === 0}
		<p class="muted small pad">No friends yet — search above to add some.</p>
	{:else}
		{#if friends.length > 8}
			<input
				class="list-filter"
				type="text"
				placeholder="Filter your friends…"
				bind:value={listFilter}
				aria-label="Filter your friends"
			/>
			{#if listFilter.trim()}
				<div class="filter-count">Showing {shownFriends.length} of {friends.length}</div>
			{/if}
		{/if}
		<div class="list">
			{#each shownFriends as u}
				<div class="row card">
					<button
						class="uname namelink"
						onclick={() => goto('/u/' + encodeURIComponent(u.username || ''))}>{label(u)}</button
					>
					<div class="row-acts">
						{#if onChallenge}<button
								class="act challenge"
								onclick={() => onChallenge(u.username)}
								title="Challenge"><Icon name="swords" size={16} /></button
							>{/if}
						<button
							class="act remove"
							disabled={busy === u.id}
							onclick={() => unfriend(u)}
							title="Remove friend"><Icon name="close" size={14} /></button
						>
					</div>
				</div>
			{/each}
			{#if shownFriends.length === 0}
				<p class="muted small pad">No friends match “{listFilter.trim()}”.</p>
			{/if}
		</div>
	{/if}

	{#if outgoing.length > 0}
		<h2 class="sec muted-sec">Sent</h2>
		<div class="list">
			{#each outgoing as u}
				<div class="row card dim">
					<span class="uname">{label(u)}</span><span class="tag pending">Pending</span>
				</div>
			{/each}
		</div>
	{/if}
{/if}

<style>
	.search-wrap {
		position: relative;
	}
	.search {
		width: 100%;
		padding: 0.85rem 1rem;
		border-radius: 14px;
		font-size: 0.95rem;
		background: var(--surface);
		border: 1px solid var(--border);
		color: var(--text);
	}
	.search:focus {
		outline: none;
		border-color: rgba(251, 191, 36, 0.5);
	}
	.list-filter {
		width: 100%;
		margin-bottom: 0.6rem;
		padding: 0.6rem 0.9rem;
		border-radius: 12px;
		font-size: 0.9rem;
		background: var(--surface);
		border: 1px solid var(--border);
		color: var(--text);
	}
	.list-filter:focus {
		outline: none;
		border-color: rgba(251, 191, 36, 0.5);
	}
	.filter-count {
		font-size: 0.72rem;
		color: var(--text-muted);
		margin: -0.2rem 0 0.5rem 0.2rem;
	}
	.sec-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 10px;
	}
	.sort-toggle {
		display: inline-flex;
		border: 1px solid var(--border);
		border-radius: 10px;
		overflow: hidden;
		flex: none;
	}
	.sort-toggle button {
		padding: 4px 10px;
		font-size: 0.74rem;
		font-weight: 700;
		background: var(--surface);
		color: var(--text-muted);
		border: none;
		cursor: pointer;
	}
	.sort-toggle button + button {
		border-left: 1px solid var(--border);
	}
	.sort-toggle button.on {
		background: rgba(251, 191, 36, 0.18);
		color: #fcd34d;
	}
	.results {
		margin-top: 0.5rem;
		border: 1px solid var(--border);
		border-radius: 14px;
		background: var(--surface);
		overflow: hidden;
	}
	.results .row {
		padding: 0.7rem 0.9rem;
		border-bottom: 1px solid var(--border);
	}
	.results .row:last-child {
		border-bottom: none;
	}
	.row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.6rem;
	}
	.card {
		padding: 0.8rem 0.9rem;
		border: 1px solid var(--border);
		border-radius: 14px;
		background: var(--surface);
	}
	.card.dim {
		opacity: 0.7;
	}
	.list {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
	}
	.who {
		display: flex;
		flex-direction: column;
		gap: 1px;
		min-width: 0;
		text-align: left;
	}
	.rname {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.95rem;
		line-height: 1.1;
	}
	.who .uname {
		font-weight: 600;
		font-size: 0.78rem;
		color: var(--text-muted);
	}
	.uname {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1rem;
	}
	.namelink {
		background: none;
		border: none;
		padding: 0;
		color: var(--text);
		cursor: pointer;
		text-align: left;
	}
	.namelink:hover {
		color: var(--brand-2);
	}
	.row-acts {
		display: flex;
		gap: 0.4rem;
	}
	.act {
		padding: 0.45rem 0.9rem;
		border-radius: 10px;
		cursor: pointer;
		font-weight: 800;
		font-size: 0.85rem;
		border: 1px solid var(--border);
		background: var(--surface-2, rgba(255, 255, 255, 0.06));
		color: var(--text);
	}
	.act:disabled {
		opacity: 0.5;
		cursor: default;
	}
	.act.add,
	.act.accept {
		color: #3a2a00;
		border: none;
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
	}
	.act.decline {
		color: #f87171;
		border-color: rgba(248, 113, 113, 0.4);
	}
	.act.challenge {
		padding: 0.4rem 0.6rem;
	}
	.act.remove {
		color: var(--text-faint);
		padding: 0.35rem 0.6rem;
	}
	.tag {
		font-size: 0.78rem;
		font-weight: 800;
		padding: 0.3rem 0.7rem;
		border-radius: 999px;
	}
	.tag.friend {
		color: var(--brand-2);
		background: rgba(253, 224, 71, 0.12);
		border: 1px solid rgba(253, 224, 71, 0.35);
	}
	.tag.pending {
		color: #fbbf24;
		background: rgba(251, 191, 36, 0.12);
		border: 1px solid rgba(251, 191, 36, 0.3);
	}
	.sec {
		font-family: var(--font-display);
		font-size: 1.05rem;
		margin: 1.6rem 0 0.6rem;
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}
	.muted-sec {
		color: var(--text-muted);
		font-size: 0.95rem;
	}
	.count {
		font-size: 0.8rem;
		font-weight: 800;
		color: #fbbf24;
		background: rgba(251, 191, 36, 0.12);
		border-radius: 999px;
		padding: 1px 9px;
	}
	.msg {
		text-align: center;
		font-size: 0.88rem;
		color: var(--brand-2);
		margin: 0.8rem 0 0;
	}
	.muted {
		color: var(--text-muted);
	}
	.small {
		font-size: 0.85rem;
	}
	.pad {
		padding: 1rem 0.2rem;
		text-align: center;
	}
</style>
