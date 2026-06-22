<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { getMyGroups, getGroup, createGroup, joinGroup, leaveGroup, getGroupMessages, sendGroupMessage } from '$lib/stores/statsStore.js';
  import { supabase } from '$lib/supabaseClient.js';
  import { track } from '$lib/analytics.js';

  /** @type {any[]} */
  let groups = $state([]);
  /** @type {any|null} */
  let open = $state(null); // the group currently being viewed
  let loading = $state(true);
  let busy = $state(false);
  let newName = $state('');
  let joinCode = $state('');
  let msg = $state('');
  let codeCopied = $state(false);

  // --- group chat ---
  /** @type {any[]} */
  let messages = $state([]);
  let chatInput = $state('');
  let chatBusy = $state(false);
  /** @type {HTMLElement|undefined} */
  let chatScroll = $state();

  // Live chat while a group is open: Supabase Realtime for instant messages, with a
  // slow poll as a safety net (catches anything missed if the socket drops).
  $effect(() => {
    const g = open;
    if (!g?.id) { messages = []; return; }
    let alive = true;
    const reload = async () => {
      const m = await getGroupMessages(g.id);
      if (alive && open?.id === g.id) messages = m;
    };
    reload();
    const channel = supabase
      .channel(`group:${g.id}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'group_messages', filter: `group_id=eq.${g.id}` }, reload)
      .subscribe();
    const iv = setInterval(reload, 30000);
    return () => { alive = false; clearInterval(iv); supabase.removeChannel(channel); };
  });
  // Keep the chat scrolled to the latest message.
  $effect(() => { messages; if (chatScroll) chatScroll.scrollTop = chatScroll.scrollHeight; });

  async function sendMessage() {
    const body = chatInput.trim();
    if (!body || chatBusy || !open) return;
    chatBusy = true;
    const res = await sendGroupMessage(open.id, body);
    chatBusy = false;
    if (res.ok) { chatInput = ''; messages = await getGroupMessages(open.id); }
  }

  async function refresh() { groups = await getMyGroups(); }
  onMount(async () => { track('groups_view'); try { await refresh(); } finally { loading = false; } });

  const fmt = (/** @type {number} */ n) => '$' + Math.round(n ?? 0).toLocaleString();

  async function create() {
    const name = newName.trim();
    if (!name || busy) return;
    busy = true; msg = '';
    const res = await createGroup(name);
    busy = false;
    if (res.ok) { newName = ''; track('group_create'); await refresh(); open = res.group; }
    else { msg = res.reason === 'name' ? 'Name must be 2–24 characters.' : 'Could not create group.'; }
  }
  async function join() {
    const code = joinCode.trim().toUpperCase();
    if (!code || busy) return;
    busy = true; msg = '';
    const res = await joinGroup(code);
    busy = false;
    if (res.ok) { joinCode = ''; track('group_join'); await refresh(); open = res.group; }
    else { msg = res.reason === 'not_found' ? 'No group with that code.' : 'Could not join.'; }
  }
  /** @param {string} id */
  async function view(id) { open = await getGroup(id); }
  async function leave() {
    if (!open || busy) return;
    busy = true;
    await leaveGroup(open.id);
    busy = false;
    open = null;
    await refresh();
  }
  function share() {
    if (!open) return;
    const origin = typeof window !== 'undefined' ? window.location.origin : '';
    const text = `Join my WordBank group "${open.name}" — code ${open.join_code}\n${origin}/groups`;
    if (typeof navigator !== 'undefined' && navigator.share) { navigator.share({ text }).catch(() => {}); return; }
    navigator.clipboard?.writeText(text).then(() => { codeCopied = true; setTimeout(() => codeCopied = false, 1800); }, () => {});
  }
</script>

<svelte:head><title>WordBank — Groups</title></svelte:head>

<main class="groups-page">
  {#if open}
    <button class="back-btn" onclick={() => (open = null)}>← Groups</button>
    <div class="g-head">
      <h1>{open.name}</h1>
      <button class="code-pill" onclick={share} title="Share invite code">{open.join_code} <span class="share-ico">{codeCopied ? '✓' : '↗'}</span></button>
    </div>
    <p class="sub">Net Worth · {open.members.length} member{open.members.length === 1 ? '' : 's'}</p>
    <div class="table-wrap">
      <table>
        <thead><tr><th>#</th><th>Player</th><th>Net Worth</th><th>Cash</th></tr></thead>
        <tbody>
          {#each open.members as m}
            <tr class={m.is_me ? 'me-row' : ((m.rank ?? 0) <= 3 ? 'top-three' : '')}>
              <td class="rank">{#if m.rank === 1}🥇{:else if m.rank === 2}🥈{:else if m.rank === 3}🥉{:else}{m.rank}{/if}</td>
              <td class="name"><span style={m.color ? `color:${m.color}` : ''}>{m.is_me ? 'You' : m.name}</span>{#if m.title}<span class="nw-title">{m.title}</span>{/if}</td>
              <td class="score-cell" class:neg={(m.net_worth ?? 0) < 0}>{fmt(m.net_worth)}</td>
              <td>{fmt(m.cash)}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
    <!-- 💬 Group chat -->
    <div class="chat">
      <h2 class="chat-title">💬 Chat</h2>
      <div class="chat-msgs" bind:this={chatScroll}>
        {#if messages.length}
          {#each messages as m}
            <div class="cmsg" class:mine={m.is_me}>
              {#if !m.is_me}<span class="cm-name">{m.name}</span>{/if}
              <span class="cm-body">{m.body}</span>
            </div>
          {/each}
        {:else}
          <p class="chat-empty">No messages yet — say hi 👋</p>
        {/if}
      </div>
      <div class="g-row chat-input-row">
        <input class="g-input" placeholder="Message…" bind:value={chatInput} maxlength="500"
          onkeydown={(e) => { if (e.key === 'Enter') sendMessage(); }} />
        <button class="g-btn" onclick={sendMessage} disabled={chatBusy || !chatInput.trim()}>Send</button>
      </div>
    </div>

    <button class="leave-btn" onclick={leave} disabled={busy}>Leave group</button>
  {:else}
    <button class="back-btn" onclick={() => goto('/')}>← Menu</button>
    <h1>👥 Groups</h1>
    <p class="sub">Your crews. Everyone's Net Worth, ranked.</p>

    {#if loading}
      <p class="loading">Loading…</p>
    {:else}
      {#if groups.length}
        <div class="g-list">
          {#each groups as g}
            <button class="g-card" onclick={() => view(g.id)}>
              <div class="gc-body"><span class="gc-name">{g.name}</span><span class="gc-meta">{g.members} member{g.members === 1 ? '' : 's'} · {g.join_code}</span></div>
              <span class="gc-arrow">→</span>
            </button>
          {/each}
        </div>
      {:else}
        <p class="empty">No groups yet — create one or join with a code.</p>
      {/if}

      <div class="g-forms">
        <div class="g-row">
          <input class="g-input" placeholder="New group name" bind:value={newName} maxlength="24" onkeydown={(e) => { if (e.key === 'Enter') create(); }} />
          <button class="g-btn" onclick={create} disabled={busy}>Create</button>
        </div>
        <div class="g-row">
          <input class="g-input" placeholder="Join code" bind:value={joinCode} maxlength="6" onkeydown={(e) => { if (e.key === 'Enter') join(); }} />
          <button class="g-btn ghost" onclick={join} disabled={busy}>Join</button>
        </div>
        {#if msg}<p class="msg">{msg}</p>{/if}
      </div>
    {/if}
  {/if}
</main>

<style>
  .groups-page { max-width: 560px; margin: 0 auto; padding: 1.5rem 1rem 3rem; }
  .back-btn { display: inline-block; margin-bottom: 1rem; padding: 0.55rem 1.1rem; background: var(--surface); color: var(--text); border: 1px solid var(--border); border-radius: 12px; cursor: pointer; font-weight: 600; font-size: 0.9rem; }
  h1 { font-family: var(--font-display); font-size: 1.7rem; margin: 0; }
  .sub { color: var(--text-muted); font-size: 0.9rem; margin: 0.2rem 0 1.2rem; }
  .loading, .empty { color: var(--text-muted); padding: 1.5rem 0; text-align: center; }
  .g-head { display: flex; align-items: center; justify-content: space-between; gap: 0.6rem; }
  .code-pill { font-family: var(--font-display); font-weight: 800; letter-spacing: 0.1em; padding: 0.45rem 0.9rem; border-radius: 999px; cursor: pointer; color: var(--brand-2); background: rgba(163,230,53,0.1); border: 1px solid rgba(163,230,53,0.4); display: inline-flex; align-items: center; gap: 0.4rem; }
  .share-ico { font-size: 0.8rem; opacity: 0.8; }
  .g-list { display: flex; flex-direction: column; gap: 0.5rem; margin-bottom: 1.2rem; }
  .g-card { display: flex; align-items: center; justify-content: space-between; gap: 0.6rem; padding: 0.9rem 1rem; background: var(--surface); border: 1px solid var(--border); border-radius: 14px; cursor: pointer; text-align: left; }
  .g-card:hover { border-color: rgba(163,230,53,0.4); }
  .gc-body { display: flex; flex-direction: column; gap: 2px; }
  .gc-name { font-family: var(--font-display); font-weight: 700; font-size: 1rem; color: var(--text); }
  .gc-meta { font-size: 0.78rem; color: var(--text-faint); }
  .gc-arrow { color: var(--text-faint); }
  .g-forms { display: flex; flex-direction: column; gap: 0.5rem; }
  .g-row { display: flex; gap: 0.5rem; }
  .g-input { flex: 1; min-width: 0; padding: 0.6rem 0.9rem; border-radius: 12px; border: 1px solid var(--border); background: var(--surface); color: var(--text); font-size: 0.95rem; }
  .g-btn { padding: 0.6rem 1.2rem; border: none; border-radius: 12px; cursor: pointer; font-weight: 700; color: #06210f; background: var(--brand-grad, linear-gradient(135deg,#34d399,#a3e635)); }
  .g-btn.ghost { background: transparent; color: var(--brand-2); border: 1px solid rgba(163,230,53,0.4); }
  .g-btn:disabled { opacity: 0.5; }
  .msg { text-align: center; color: #f87171; font-size: 0.85rem; margin: 0.3rem 0 0; }
  .table-wrap { overflow-x: auto; border: 1px solid var(--border); border-radius: 14px; }
  table { width: 100%; border-collapse: collapse; }
  th { font-size: 0.65rem; text-transform: uppercase; letter-spacing: 0.06em; color: var(--text-faint); padding: 0.7rem 0.6rem; text-align: left; border-bottom: 1px solid var(--border); }
  td { padding: 0.7rem 0.6rem; border-bottom: 1px solid var(--border); font-size: 0.9rem; }
  tr:last-child td { border-bottom: none; }
  td.rank { width: 36px; }
  td.name { font-weight: 600; }
  td.score-cell { font-family: var(--font-display); font-weight: 700; color: var(--brand-2); }
  td.score-cell.neg { color: #fb7185; }
  tr.me-row { background: rgba(56,189,248,0.1); }
  tr.me-row td.name { color: #7dd3fc; }
  .nw-title { font-size: 0.7rem; color: var(--text-faint); margin-left: 0.4rem; white-space: nowrap; }
  .leave-btn { margin-top: 1.2rem; padding: 0.6rem 1.2rem; border: 1px solid rgba(251,113,133,0.4); border-radius: 12px; background: transparent; color: #fb7185; cursor: pointer; font-weight: 600; font-size: 0.85rem; }
  .leave-btn:disabled { opacity: 0.5; }
  /* group chat */
  .chat { margin-top: 1.6rem; }
  .chat-title { font-family: var(--font-display); font-size: 1.05rem; margin: 0 0 0.6rem; }
  .chat-msgs {
    display: flex; flex-direction: column; gap: 6px; height: 260px; overflow-y: auto;
    padding: 0.8rem; border-radius: 14px; border: 1px solid var(--border); background: var(--surface);
  }
  .chat-empty { color: var(--text-faint); font-size: 0.85rem; text-align: center; margin: auto; }
  .cmsg {
    max-width: 80%; align-self: flex-start; display: flex; flex-direction: column; gap: 1px;
    padding: 0.45rem 0.7rem; border-radius: 12px; background: var(--surface-2, rgba(255,255,255,0.05)); border: 1px solid var(--border);
  }
  .cmsg.mine { align-self: flex-end; background: rgba(163,230,53,0.12); border-color: rgba(163,230,53,0.3); }
  .cm-name { font-size: 0.66rem; font-weight: 700; color: var(--brand-2); }
  .cm-body { font-size: 0.88rem; color: var(--text); word-break: break-word; }
  .chat-input-row { margin-top: 0.6rem; }
</style>
