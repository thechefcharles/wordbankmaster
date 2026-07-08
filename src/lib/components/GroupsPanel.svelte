<script>
	// Groups — list, create, and the per-group detail (wealth/compete, members,
	// add-friends, chat). Reused by the /groups route and Community ▸ People ▸ Groups.
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import {
		getMyGroups,
		getGroup,
		createGroup,
		leaveGroup,
		addGroupMember,
		removeGroupMember,
		renameGroup,
		listFriends,
		getGroupMessages,
		sendGroupMessage,
		getGroupStandings
	} from '$lib/stores/statsStore.js';
	import { requireConfirm } from '$lib/confirm.js';
	import { supabase } from '$lib/supabaseClient.js';

	/** Optional: list-view back button (e.g. the route's "← Menu"). Hidden if absent.
	 *  Optional title: shown only on the list view (the route shows it; in Community
	 *  the tab already says "Groups"). */
	let { onExit = null, title = '' } = $props();

	/** @type {any[]} */
	let groups = $state([]);
	/** @type {any|null} */
	let open = $state(null);
	let loading = $state(true);

	// Long-list handling: alphabetize groups + live filter (shown once you have a few).
	let groupFilter = $state('');
	const sortedGroups = $derived(
		[...groups].sort((a, b) =>
			(a.name || '').localeCompare(b.name || '', undefined, { sensitivity: 'base' })
		)
	);
	const shownGroups = $derived.by(() => {
		const q = groupFilter.trim().toLowerCase();
		if (!q) return sortedGroups;
		return sortedGroups.filter((g) => (g.name || '').toLowerCase().includes(q));
	});
	let busy = $state(false);
	let newName = $state('');
	let msg = $state('');

	let renaming = $state(false);
	let renameInput = $state('');

	let gtab = $state('wealth');
	/** @type {any|null} */
	let standings = $state(null);
	let standingsLoading = $state(false);

	async function switchTab(/** @type {string} */ t) {
		gtab = t;
		if (t === 'compete' && !standings && open) {
			standingsLoading = true;
			standings = await getGroupStandings(open.id);
			standingsLoading = false;
		}
	}

	/** @type {{username:string,name:string}[]} */
	let friends = $state([]);
	let showAdd = $state(false);
	let addMsg = $state('');

	let availableFriends = $derived(
		open
			? friends.filter(
					(f) =>
						!open.members.some(
							(/** @type {any} */ m) =>
								(m.username ?? '').toLowerCase() === (f.username ?? '').toLowerCase()
						)
				)
			: []
	);

	/** @type {any[]} */
	let messages = $state([]);
	let chatInput = $state('');
	let chatBusy = $state(false);
	/** @type {HTMLElement|undefined} */
	let chatScroll = $state();

	$effect(() => {
		const g = open;
		if (!g?.id) {
			messages = [];
			return;
		}
		let alive = true;
		const reload = async () => {
			const m = await getGroupMessages(g.id);
			if (alive && open?.id === g.id) messages = m;
		};
		reload();
		const channel = supabase
			.channel(`group:${g.id}`)
			.on(
				'postgres_changes',
				{
					event: 'INSERT',
					schema: 'public',
					table: 'group_messages',
					filter: `group_id=eq.${g.id}`
				},
				reload
			)
			.subscribe();
		const iv = setInterval(reload, 30000);
		return () => {
			alive = false;
			clearInterval(iv);
			supabase.removeChannel(channel);
		};
	});
	$effect(() => {
		void messages;
		if (chatScroll) chatScroll.scrollTop = chatScroll.scrollHeight;
	});

	async function sendMessage() {
		const body = chatInput.trim();
		if (!body || chatBusy || !open) return;
		chatBusy = true;
		const res = await sendGroupMessage(open.id, body);
		chatBusy = false;
		if (res.ok) {
			chatInput = '';
			messages = await getGroupMessages(open.id);
		}
	}

	async function refresh() {
		groups = await getMyGroups();
	}
	onMount(async () => {
		try {
			await refresh();
		} finally {
			loading = false;
		}
	});

	const fmt = (/** @type {number} */ n) => '$' + Math.round(n ?? 0).toLocaleString();

	async function create() {
		const name = newName.trim();
		if (!name || busy) return;
		busy = true;
		msg = '';
		const res = await createGroup(name);
		busy = false;
		if (res.ok) {
			newName = '';
			await refresh();
			await openGroup(res.group);
		} else {
			msg = res.reason === 'name' ? 'Name must be 2–24 characters.' : 'Could not create group.';
		}
	}

	/** @param {any} g */
	async function openGroup(g) {
		open = g;
		renaming = false;
		showAdd = false;
		addMsg = '';
		gtab = 'wealth';
		standings = null;
		if (!friends.length) friends = await listFriends();
	}
	/** @param {string} id */
	async function view(id) {
		await openGroup(await getGroup(id));
	}
	function backToList() {
		open = null;
		renaming = false;
		showAdd = false;
		gtab = 'wealth';
		standings = null;
	}

	async function leave() {
		if (!open || busy) return;
		if (
			!(await requireConfirm({
				title: 'Leave group?',
				message: `Leave "${open.name}"? You can be re-added by a member.`,
				confirmText: 'Leave',
				danger: true
			}))
		)
			return;
		busy = true;
		await leaveGroup(open.id);
		busy = false;
		backToList();
		await refresh();
	}

	function startRename() {
		renameInput = open.name;
		renaming = true;
	}
	async function saveRename() {
		const name = renameInput.trim();
		if (!name || busy) return;
		busy = true;
		const res = await renameGroup(open.id, name);
		busy = false;
		if (res.ok) {
			open = res.group;
			renaming = false;
			await refresh();
		}
	}

	/** @param {string} username */
	async function addMember(username) {
		if (busy) return;
		busy = true;
		addMsg = '';
		const res = await addGroupMember(open.id, username);
		busy = false;
		if (res.ok) {
			open = res.group;
			await refresh();
		} else {
			addMsg =
				res.reason === 'not_friend'
					? 'You can only add friends.'
					: res.reason === 'already_member'
						? 'Already in the group.'
						: 'Could not add.';
		}
	}
	/** @param {string} username */
	async function removeMember(username) {
		if (busy) return;
		if (
			!(await requireConfirm({
				title: 'Remove member?',
				message: `Remove @${username} from "${open.name}"?`,
				confirmText: 'Remove',
				danger: true
			}))
		)
			return;
		busy = true;
		const res = await removeGroupMember(open.id, username);
		busy = false;
		if (res.ok) {
			open = res.group;
			await refresh();
		}
	}
</script>

<div class="groups-panel">
	{#if open}
		<button class="back-btn" onclick={backToList}>← Groups</button>
		<div class="g-head">
			{#if renaming}
				<input
					class="rename-input"
					bind:value={renameInput}
					maxlength="24"
					onkeydown={(e) => {
						if (e.key === 'Enter') saveRename();
					}}
				/>
				<button class="g-btn sm" onclick={saveRename} disabled={busy}>Save</button>
			{:else}
				<h1>{open.name}</h1>
				{#if open.is_owner}<button class="rename-btn" onclick={startRename} title="Rename group"
						>✏️</button
					>{/if}
			{/if}
		</div>
		<p class="sub">{open.members.length} member{open.members.length === 1 ? '' : 's'}</p>

		<div class="g-tabs">
			<button class="g-tab" class:active={gtab === 'wealth'} onclick={() => switchTab('wealth')}
				>💰 Wealth</button
			>
			<button class="g-tab" class:active={gtab === 'compete'} onclick={() => switchTab('compete')}
				>⚔️ Compete</button
			>
		</div>

		{#if gtab === 'wealth'}
			<div class="table-wrap">
				<table>
					<thead
						><tr
							><th>#</th><th>Player</th><th>Net Worth</th><th>Cash</th>{#if open.is_owner}<th
								></th>{/if}</tr
						></thead
					>
					<tbody>
						{#each open.members as m}
							<tr class={m.is_me ? 'me-row' : (m.rank ?? 0) <= 3 ? 'top-three' : ''}>
								<td class="rank"
									>{#if m.rank === 1}🥇{:else if m.rank === 2}🥈{:else if m.rank === 3}🥉{:else}{m.rank}{/if}</td
								>
								<td class="name"
									>{#if m.is_me}<span style={m.color ? `color:${m.color}` : ''}>You</span
										>{:else}<button
											class="m-link"
											style={m.color ? `color:${m.color}` : ''}
											onclick={() => m.username && goto('/u/' + encodeURIComponent(m.username))}
											>{m.name}</button
										>{/if}{#if m.is_owner}<span class="owner-tag">owner</span
										>{/if}{#if m.title}<span class="nw-title">{m.title}</span>{/if}</td
								>
								<td class="score-cell" class:neg={(m.net_worth ?? 0) < 0}>{fmt(m.net_worth)}</td>
								<td>{fmt(m.cash)}</td>
								{#if open.is_owner}<td class="rm-cell"
										>{#if !m.is_owner}<button
												class="rm-btn"
												onclick={() => removeMember(m.username)}
												disabled={busy}
												title="Remove">✕</button
											>{/if}</td
									>{/if}
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{:else if standingsLoading}
			<p class="msg">Loading…</p>
		{:else if !standings || standings.total_matches === 0}
			<p class="compete-empty">
				No group challenges yet. Start one from <button class="link" onclick={() => goto('/')}
					>the menu</button
				> — pick this group as the opponent.
			</p>
		{:else}
			<p class="compete-sub">
				{standings.total_matches} group challenge{standings.total_matches === 1 ? '' : 's'} played
			</p>
			<div class="table-wrap">
				<table>
					<thead><tr><th>#</th><th>Player</th><th>W</th><th>Played</th><th>Win %</th></tr></thead>
					<tbody>
						{#each standings.members as m, i}
							<tr class={m.is_me ? 'me-row' : i < 3 && m.wins > 0 ? 'top-three' : ''}>
								<td class="rank"
									>{#if i === 0 && m.wins > 0}🏆{:else}{i + 1}{/if}</td
								>
								<td class="name">{m.is_me ? 'You' : m.name}</td>
								<td class="score-cell">{m.wins}</td>
								<td>{m.played}</td>
								<td class="dim">{m.win_pct}%</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
			{#if (standings.recent ?? []).length}
				<div class="recent-h">Recent matches</div>
				<div class="recent">
					{#each standings.recent as r}
						<div class="recent-row">
							<span class="r-win">🏆 @{r.winner}</span>
							<span class="r-meta"
								>{r.players} players · {r.pack_size} puzzle{r.pack_size === 1
									? ''
									: 's'}{#if Number(r.wager) > 0}
									· ${Number(r.wager).toLocaleString()}{/if}</span
							>
						</div>
					{/each}
				</div>
			{/if}
		{/if}

		<button
			class="add-toggle"
			onclick={() => {
				showAdd = !showAdd;
				addMsg = '';
			}}>{showAdd ? '×' : '＋'} Add friends</button
		>
		{#if showAdd}
			<div class="add-panel">
				{#if availableFriends.length}
					{#each availableFriends as f}
						<div class="add-row">
							<span class="uname">@{f.username}</span><button
								class="g-btn sm"
								onclick={() => addMember(f.username)}
								disabled={busy}>Add</button
							>
						</div>
					{/each}
				{:else if friends.length === 0}
					<p class="add-empty">
						No friends yet — add some in <button class="link" onclick={() => goto('/friends')}
							>Friends</button
						>.
					</p>
				{:else}
					<p class="add-empty">All your friends are already in this group.</p>
				{/if}
				{#if addMsg}<p class="msg">{addMsg}</p>{/if}
			</div>
		{/if}

		<div class="chat">
			<h2 class="chat-title">💬 Chat</h2>
			<div class="chat-msgs" bind:this={chatScroll}>
				{#if messages.length}
					{#each messages as m}
						<div class="cmsg" class:mine={m.is_me}>
							{#if !m.is_me}<span class="cm-name">{m.name}</span>{/if}<span class="cm-body"
								>{m.body}</span
							>
						</div>
					{/each}
				{:else}
					<p class="chat-empty">No messages yet — say hi 👋</p>
				{/if}
			</div>
			<div class="g-row chat-input-row">
				<input
					class="g-input"
					placeholder="Message…"
					bind:value={chatInput}
					maxlength="500"
					onkeydown={(e) => {
						if (e.key === 'Enter') sendMessage();
					}}
				/>
				<button class="g-btn" onclick={sendMessage} disabled={chatBusy || !chatInput.trim()}
					>Send</button
				>
			</div>
		</div>

		<button class="leave-btn" onclick={leave} disabled={busy}>Leave group</button>
	{:else}
		{#if onExit}<button class="back-btn" onclick={onExit}>← Menu</button>{/if}
		{#if title}<h1>{title}</h1>{/if}

		{#if loading}
			<p class="loading">Loading…</p>
		{:else}
			{#if groups.length}
				{#if groups.length > 8}
					<input
						class="g-filter"
						type="text"
						placeholder="Filter your groups…"
						bind:value={groupFilter}
						aria-label="Filter your groups"
					/>
					{#if groupFilter.trim()}
						<div class="g-filter-count">Showing {shownGroups.length} of {groups.length}</div>
					{/if}
				{/if}
				<div class="g-list">
					{#each shownGroups as g}
						<button class="g-card" onclick={() => view(g.id)}>
							<div class="gc-body">
								<span class="gc-name">{g.name}</span><span class="gc-meta"
									>{g.members} member{g.members === 1 ? '' : 's'}</span
								>
							</div>
							<span class="gc-arrow">→</span>
						</button>
					{/each}
					{#if shownGroups.length === 0}
						<p class="empty">No groups match “{groupFilter.trim()}”.</p>
					{/if}
				</div>
			{:else}
				<p class="empty">No groups yet — create one and add your friends.</p>
			{/if}

			<div class="g-forms">
				<div class="g-row">
					<input
						class="g-input"
						placeholder="New group name"
						bind:value={newName}
						maxlength="24"
						onkeydown={(e) => {
							if (e.key === 'Enter') create();
						}}
					/>
					<button class="g-btn" onclick={create} disabled={busy}>Create</button>
				</div>
				{#if msg}<p class="msg">{msg}</p>{/if}
			</div>
		{/if}
	{/if}
</div>

<style>
	.groups-panel {
		width: 100%;
	}
	.back-btn {
		display: inline-block;
		margin-bottom: 1rem;
		padding: 0.55rem 1.1rem;
		background: var(--surface);
		color: var(--text);
		border: 1px solid var(--border);
		border-radius: 12px;
		cursor: pointer;
		font-weight: 600;
		font-size: 0.9rem;
	}
	h1 {
		font-family: var(--font-display);
		font-size: 1.7rem;
		margin: 0;
	}
	.sub {
		color: var(--text-muted);
		font-size: 0.9rem;
		margin: 0.2rem 0 1rem;
	}

	.g-tabs {
		display: flex;
		gap: 8px;
		margin: 0 0 14px;
	}
	.g-tab {
		flex: 1;
		padding: 9px 0;
		border-radius: 12px;
		border: 1px solid var(--border);
		background: var(--surface);
		color: var(--text-muted);
		font-weight: 700;
		font-size: 0.88rem;
		cursor: pointer;
	}
	.g-tab.active {
		background: linear-gradient(135deg, #fde047, #f59e0b);
		color: #3a2a00;
		border-color: transparent;
	}
	.compete-sub {
		color: var(--text-faint);
		font-size: 0.8rem;
		margin: 0 0 10px;
	}
	.compete-empty {
		color: var(--text-muted);
		text-align: center;
		padding: 24px 10px;
		font-size: 0.9rem;
	}
	.dim {
		color: var(--text-faint);
	}
	.recent-h {
		color: var(--text-faint);
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		margin: 18px 0 8px;
	}
	.recent {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.recent-row {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: 10px;
		padding: 9px 11px;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: 10px;
	}
	.r-win {
		font-weight: 700;
		color: var(--gold);
		font-size: 0.86rem;
	}
	.r-meta {
		color: var(--text-faint);
		font-size: 0.74rem;
		text-align: right;
	}
	.loading,
	.empty {
		color: var(--text-muted);
		padding: 1.5rem 0;
		text-align: center;
	}
	.g-head {
		display: flex;
		align-items: center;
		gap: 0.6rem;
	}
	.rename-btn {
		background: none;
		border: none;
		cursor: pointer;
		font-size: 1rem;
		opacity: 0.7;
	}
	.rename-btn:hover {
		opacity: 1;
	}
	.rename-input {
		flex: 1;
		min-width: 0;
		padding: 0.5rem 0.8rem;
		border-radius: 12px;
		border: 1px solid rgba(251, 191, 36, 0.5);
		background: var(--surface);
		color: var(--text);
		font-size: 1.1rem;
		font-family: var(--font-display);
		font-weight: 700;
	}
	.g-filter {
		width: 100%;
		margin-bottom: 0.6rem;
		padding: 0.6rem 0.9rem;
		border-radius: 12px;
		font-size: 0.9rem;
		background: var(--surface);
		border: 1px solid var(--border);
		color: var(--text);
	}
	.g-filter:focus {
		outline: none;
		border-color: rgba(251, 191, 36, 0.5);
	}
	.g-filter-count {
		font-size: 0.72rem;
		color: var(--text-muted);
		margin: -0.2rem 0 0.5rem 0.2rem;
	}
	.g-list {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		margin-bottom: 1.2rem;
	}
	.g-card {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.6rem;
		padding: 0.9rem 1rem;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: 14px;
		cursor: pointer;
		text-align: left;
	}
	.g-card:hover {
		border-color: rgba(253, 224, 71, 0.4);
	}
	.gc-body {
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.gc-name {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1rem;
		color: var(--text);
	}
	.gc-meta {
		font-size: 0.78rem;
		color: var(--text-faint);
	}
	.gc-arrow {
		color: var(--text-faint);
	}
	.g-forms {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
	}
	.g-row {
		display: flex;
		gap: 0.5rem;
	}
	.g-input {
		flex: 1;
		min-width: 0;
		padding: 0.6rem 0.9rem;
		border-radius: 12px;
		border: 1px solid var(--border);
		background: var(--surface);
		color: var(--text);
		font-size: 0.95rem;
	}
	.g-btn {
		padding: 0.6rem 1.2rem;
		border: none;
		border-radius: 12px;
		cursor: pointer;
		font-weight: 700;
		color: #3a2a00;
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
	}
	.g-btn.sm {
		padding: 0.45rem 0.9rem;
		font-size: 0.85rem;
	}
	.g-btn:disabled {
		opacity: 0.5;
	}
	.msg {
		text-align: center;
		color: #f87171;
		font-size: 0.85rem;
		margin: 0.3rem 0 0;
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
		font-size: 0.65rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--text-faint);
		padding: 0.7rem 0.6rem;
		text-align: left;
		border-bottom: 1px solid var(--border);
	}
	td {
		padding: 0.7rem 0.6rem;
		border-bottom: 1px solid var(--border);
		font-size: 0.9rem;
	}
	tr:last-child td {
		border-bottom: none;
	}
	td.rank {
		width: 36px;
	}
	td.name {
		font-weight: 600;
	}
	.m-link {
		background: none;
		border: none;
		padding: 0;
		font: inherit;
		font-weight: 600;
		color: var(--text);
		cursor: pointer;
		text-decoration: underline;
		text-decoration-color: rgba(255, 255, 255, 0.2);
		text-underline-offset: 2px;
	}
	.m-link:hover {
		text-decoration-color: var(--gold);
	}
	td.score-cell {
		font-family: var(--font-display);
		font-weight: 700;
		color: var(--brand-2);
	}
	td.score-cell.neg {
		color: #fb7185;
	}
	tr.me-row {
		background: rgba(56, 189, 248, 0.1);
	}
	tr.me-row td.name {
		color: #7dd3fc;
	}
	.owner-tag {
		font-size: 0.62rem;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: #fbbf24;
		background: rgba(251, 191, 36, 0.12);
		border-radius: 999px;
		padding: 1px 6px;
		margin-left: 0.4rem;
	}
	.nw-title {
		font-size: 0.7rem;
		color: var(--text-faint);
		margin-left: 0.4rem;
		white-space: nowrap;
	}
	.rm-cell {
		width: 30px;
		text-align: right;
	}
	.rm-btn {
		background: none;
		border: none;
		color: var(--text-faint);
		cursor: pointer;
		font-size: 0.85rem;
		padding: 2px 4px;
	}
	.rm-btn:hover {
		color: #fb7185;
	}
	.add-toggle {
		margin-top: 0.9rem;
		width: 100%;
		padding: 0.7rem;
		border: 1px dashed var(--border-strong, rgba(255, 255, 255, 0.18));
		border-radius: 12px;
		background: transparent;
		color: var(--brand-2);
		cursor: pointer;
		font-weight: 700;
		font-size: 0.9rem;
	}
	.add-panel {
		margin-top: 0.5rem;
		border: 1px solid var(--border);
		border-radius: 14px;
		background: var(--surface);
		overflow: hidden;
	}
	.add-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 0.6rem 0.9rem;
		border-bottom: 1px solid var(--border);
	}
	.add-row:last-child {
		border-bottom: none;
	}
	.add-empty {
		color: var(--text-muted);
		font-size: 0.85rem;
		padding: 0.9rem;
		text-align: center;
	}
	.link {
		background: none;
		border: none;
		color: var(--brand-2);
		cursor: pointer;
		text-decoration: underline;
		font-size: inherit;
	}
	.uname {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.95rem;
	}
	.leave-btn {
		margin-top: 1.2rem;
		padding: 0.6rem 1.2rem;
		border: 1px solid rgba(251, 113, 133, 0.4);
		border-radius: 12px;
		background: transparent;
		color: #fb7185;
		cursor: pointer;
		font-weight: 600;
		font-size: 0.85rem;
	}
	.leave-btn:disabled {
		opacity: 0.5;
	}
	.chat {
		margin-top: 1.6rem;
	}
	.chat-title {
		font-family: var(--font-display);
		font-size: 1.05rem;
		margin: 0 0 0.6rem;
	}
	.chat-msgs {
		display: flex;
		flex-direction: column;
		gap: 6px;
		height: 260px;
		overflow-y: auto;
		padding: 0.8rem;
		border-radius: 14px;
		border: 1px solid var(--border);
		background: var(--surface);
	}
	.chat-empty {
		color: var(--text-faint);
		font-size: 0.85rem;
		text-align: center;
		margin: auto;
	}
	.cmsg {
		max-width: 80%;
		align-self: flex-start;
		display: flex;
		flex-direction: column;
		gap: 1px;
		padding: 0.45rem 0.7rem;
		border-radius: 12px;
		background: var(--surface-2, rgba(255, 255, 255, 0.05));
		border: 1px solid var(--border);
	}
	.cmsg.mine {
		align-self: flex-end;
		background: rgba(253, 224, 71, 0.12);
		border-color: rgba(253, 224, 71, 0.3);
	}
	.cm-name {
		font-size: 0.66rem;
		font-weight: 700;
		color: var(--brand-2);
	}
	.cm-body {
		font-size: 0.88rem;
		color: var(--text);
		word-break: break-word;
	}
	.chat-input-row {
		margin-top: 0.6rem;
	}
</style>
