<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { searchUsers, addFriend, respondFriendRequest, removeFriend, listFriends, listFriendRequests } from '$lib/stores/statsStore.js';
  import { track } from '$lib/analytics.js';
  import { fx } from '$lib/sound.js';

  /** @type {{username:string,name:string}[]} */
  let friends = $state([]);
  /** @type {{username:string,name:string}[]} */
  let incoming = $state([]);
  /** @type {{username:string,name:string}[]} */
  let outgoing = $state([]);
  let loading = $state(true);
  let busy = $state('');
  let msg = $state('');

  let query = $state('');
  /** @type {{username:string,status:string,is_friend:boolean}[]} */
  let results = $state([]);
  let searching = $state(false);

  async function load() {
    const [f, r] = await Promise.all([listFriends(), listFriendRequests()]);
    friends = f;
    incoming = r.incoming ?? [];
    outgoing = r.outgoing ?? [];
  }

  onMount(async () => {
    track('friends_view');
    try { await load(); } finally { loading = false; }
  });

  // debounced typeahead
  let timer;
  $effect(() => {
    const q = query.trim();
    clearTimeout(timer);
    if (q.length < 2) { results = []; searching = false; return; }
    searching = true;
    timer = setTimeout(async () => {
      results = await searchUsers(q);
      searching = false;
    }, 280);
  });

  /** @param {string} username */
  async function add(username) {
    if (busy) return;
    busy = username; msg = '';
    const res = await addFriend(username);
    busy = '';
    if (res?.ok) {
      fx('select'); track('friend_request_send', { to: username });
      msg = res.status === 'friends' ? `You're now friends with ${res.friend_name ?? username}!` : `Request sent to ${res.friend_name ?? username}.`;
      results = results.map((u) => u.username === username ? { ...u, status: res.status === 'friends' ? 'friends' : 'pending_out', is_friend: res.status === 'friends' } : u);
      await load();
    } else {
      msg = res?.reason === 'already_friends' ? 'Already friends.' : res?.reason === 'not_found' ? 'No player with that name.' : 'Could not send request.';
    }
  }

  /** @param {any} u @param {boolean} accept */
  async function respond(u, accept) {
    if (busy) return;
    busy = u.id;
    const res = await respondFriendRequest(u.id, accept);
    busy = '';
    if (res?.ok) { fx(accept ? 'win' : 'tap'); track('friend_respond', { accept }); await load(); }
  }

  /** @param {any} u */
  async function unfriend(u) {
    if (busy) return;
    busy = u.id;
    await removeFriend(u.id);
    busy = '';
    fx('tap'); await load();
  }

  /** Display label: @username if they have one, else their name. @param {any} u */
  const label = (u) => (u.username ? '@' + u.username : (u.name || 'Player'));
</script>

<svelte:head><title>WordBank — Friends</title></svelte:head>

<main class="friends-page">
  <button class="back-btn" onclick={() => goto('/')}>← Menu</button>
  <h1>👥 Friends</h1>

  <div class="search-wrap">
    <input class="search" type="text" placeholder="Search players by username…" bind:value={query} maxlength="20" autocomplete="off" />
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
              {#if u.status === 'friends'}
                <span class="tag friend">✓ Friend</span>
              {:else if u.status === 'pending_out'}
                <span class="tag pending">Requested</span>
              {:else if u.status === 'pending_in'}
                <button class="act accept" disabled={busy === u.id} onclick={() => respond(u, true)}>Accept</button>
              {:else}
                <button class="act add" disabled={busy === u.username} onclick={() => add(u.username)}>+ Add</button>
              {/if}
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
              <button class="act accept" disabled={busy === u.id} onclick={() => respond(u, true)}>Accept</button>
              <button class="act decline" disabled={busy === u.id} onclick={() => respond(u, false)}>Decline</button>
            </div>
          </div>
        {/each}
      </div>
    {/if}

    <h2 class="sec">Your Friends <span class="count">{friends.length}</span></h2>
    {#if friends.length === 0}
      <p class="muted small pad">No friends yet — search above to add some.</p>
    {:else}
      <div class="list">
        {#each friends as u}
          <div class="row card">
            <span class="uname">{label(u)}</span>
            <button class="act remove" disabled={busy === u.id} onclick={() => unfriend(u)} title="Remove friend">✕</button>
          </div>
        {/each}
      </div>
    {/if}

    {#if outgoing.length > 0}
      <h2 class="sec muted-sec">Sent</h2>
      <div class="list">
        {#each outgoing as u}
          <div class="row card dim">
            <span class="uname">{label(u)}</span>
            <span class="tag pending">Pending</span>
          </div>
        {/each}
      </div>
    {/if}
  {/if}
</main>

<style>
  .friends-page { max-width: 480px; margin: 0 auto; padding: 1.5rem 1rem 3rem; }
  .back-btn {
    display: inline-block; margin-bottom: 1.2rem; padding: 0.55rem 1.1rem;
    background: var(--surface); color: var(--text); border: 1px solid var(--border);
    border-radius: 12px; cursor: pointer; font-weight: 600; font-size: 0.9rem;
  }
  h1 { font-family: var(--font-display); font-size: 1.7rem; margin: 0 0 1rem; }
  .search-wrap { position: relative; }
  .search {
    width: 100%; padding: 0.85rem 1rem; border-radius: 14px; font-size: 0.95rem;
    background: var(--surface); border: 1px solid var(--border); color: var(--text);
  }
  .search:focus { outline: none; border-color: rgba(251,191,36,0.5); }
  .results {
    margin-top: 0.5rem; border: 1px solid var(--border); border-radius: 14px;
    background: var(--surface); overflow: hidden;
  }
  .results .row { padding: 0.7rem 0.9rem; border-bottom: 1px solid var(--border); }
  .results .row:last-child { border-bottom: none; }
  .row { display: flex; align-items: center; justify-content: space-between; gap: 0.6rem; }
  .card { padding: 0.8rem 0.9rem; border: 1px solid var(--border); border-radius: 14px; background: var(--surface); }
  .card.dim { opacity: 0.7; }
  .list { display: flex; flex-direction: column; gap: 0.5rem; }
  .who { display: flex; flex-direction: column; gap: 1px; min-width: 0; }
  .rname { font-family: var(--font-display); font-weight: 700; font-size: 0.95rem; line-height: 1.1; }
  .who .uname { font-weight: 600; font-size: 0.78rem; color: var(--text-muted); }
  .uname { font-family: var(--font-display); font-weight: 700; font-size: 1rem; }
  .row-acts { display: flex; gap: 0.4rem; }
  .act {
    padding: 0.45rem 0.9rem; border-radius: 10px; cursor: pointer; font-weight: 800; font-size: 0.85rem; border: 1px solid var(--border);
    background: var(--surface-2, rgba(255,255,255,0.06)); color: var(--text);
  }
  .act:disabled { opacity: 0.5; cursor: default; }
  .act.add, .act.accept { color: #06210f; border: none; background: var(--brand-grad, linear-gradient(135deg,#34d399,#a3e635)); }
  .act.decline { color: #f87171; border-color: rgba(248,113,113,0.4); }
  .act.remove { color: var(--text-faint); padding: 0.35rem 0.6rem; }
  .tag { font-size: 0.78rem; font-weight: 800; padding: 0.3rem 0.7rem; border-radius: 999px; }
  .tag.friend { color: var(--brand-2); background: rgba(163,230,53,0.12); border: 1px solid rgba(163,230,53,0.35); }
  .tag.pending { color: #fbbf24; background: rgba(251,191,36,0.12); border: 1px solid rgba(251,191,36,0.3); }
  .sec { font-family: var(--font-display); font-size: 1.05rem; margin: 1.6rem 0 0.6rem; display: flex; align-items: center; gap: 0.5rem; }
  .muted-sec { color: var(--text-muted); font-size: 0.95rem; }
  .count { font-size: 0.8rem; font-weight: 800; color: #fbbf24; background: rgba(251,191,36,0.12); border-radius: 999px; padding: 1px 9px; }
  .msg { text-align: center; font-size: 0.88rem; color: var(--brand-2); margin: 0.8rem 0 0; }
  .muted { color: var(--text-muted); }
  .small { font-size: 0.85rem; }
  .pad { padding: 1rem 0.2rem; text-align: center; }
</style>
