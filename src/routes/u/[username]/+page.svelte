<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { page } from '$app/stores';
  import { getPublicProfile, addFriend } from '$lib/stores/statsStore.js';
  import Avatar from '$lib/components/Avatar.svelte';
  import { track } from '$lib/analytics.js';

  /** @type {any} */
  let p = $state(null);
  let loading = $state(true);
  let notFound = $state(false);
  let addBusy = $state(false);
  let addMsg = $state('');

  const username = $derived($page.params.username);

  const money = (/** @type {any} */ n) => '$' + Math.round(Number(n ?? 0)).toLocaleString();
  const mult = (/** @type {any} */ x) => x ? (Number(x) / 100).toFixed(1) + '×' : '—';
  const winPct = (/** @type {any} */ a) =>
    a?.games_played ? Math.round((a.games_won / a.games_played) * 100) + '%' : '—';

  async function load() {
    loading = true; notFound = false;
    const d = await getPublicProfile($page.params.username);
    p = d; notFound = !d; loading = false;
  }

  async function add() {
    if (addBusy || !p) return;
    addBusy = true;
    const res = await addFriend(p.username);
    if (res?.ok) { addMsg = 'Request sent ✓'; p = { ...p, request_outgoing: true }; }
    else addMsg = res?.reason || 'Could not send request';
    addBusy = false;
  }

  onMount(() => { track('public_profile_view'); load(); });
  $effect(() => { $page.params.username; load(); });
</script>

<svelte:head><title>WordBank — @{username}</title></svelte:head>

<main class="u-page">
  <button class="back-btn" onclick={() => history.length > 1 ? history.back() : goto('/leaderboard')}>← Back</button>

  {#if loading}
    <p class="msg">Loading…</p>
  {:else if notFound}
    <p class="msg">No player named <b>@{username}</b>.</p>
  {:else}
    <header class="u-head">
      {#if p.avatar}
        <Avatar config={p.avatar} size={110} />
      {:else}
        <div class="u-coin" style={p.color ? `--c:${p.color}` : ''}>{(p.name || p.username || '?').slice(0, 1).toUpperCase()}</div>
      {/if}
      <h1>@{p.username}</h1>
      {#if p.title}<span class="u-title">{p.title}</span>{/if}
      <div class="u-net" class:neg={Number(p.net_worth) < 0}>{money(p.net_worth)}</div>
      <span class="u-net-lbl">Net Worth</span>
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
              <span class="pip {g.outcome}">{g.outcome === 'won' ? 'W' : g.outcome === 'lost' ? 'L' : 'T'}</span>
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
        <button class="pill gold" onclick={() => goto('/?challenge=' + p.username)}>⚔️ Challenge</button>
      </div>
      {#if addMsg}<p class="add-msg">{addMsg}</p>{/if}
    {:else}
      <div class="u-actions"><button class="pill" onclick={() => goto('/profile')}>This is you → your stats</button></div>
    {/if}

    <section class="grid">
      <div class="stat"><span class="s-n">🔥 {p.current_streak}</span><span class="s-l">Streak</span></div>
      <div class="stat"><span class="s-n">{p.longest_streak}</span><span class="s-l">Best streak</span></div>
      <div class="stat"><span class="s-n">{winPct(p)}</span><span class="s-l">Daily win %</span></div>
      <div class="stat"><span class="s-n">{p.puzzles_solved}</span><span class="s-l">Puzzles solved</span></div>
      <div class="stat"><span class="s-n">{p.challenge_wins}</span><span class="s-l">Challenge wins</span></div>
      <div class="stat"><span class="s-n">#{p.climb_position}</span><span class="s-l">Furthest</span></div>
      <div class="stat"><span class="s-n">{mult(p.avg_multiple_x100)}</span><span class="s-l">Avg multiple</span></div>
      <div class="stat"><span class="s-n">{mult(p.best_multiple_x100)}</span><span class="s-l">Best multiple</span></div>
    </section>

    {#if (p.badges ?? []).length}
      <section class="badges">
        <div class="b-h">Badges · {p.badges.length}</div>
        <div class="b-wrap">{#each p.badges as b}<span class="badge">🏅 {(b || '').replace(/_/g, ' ').replace(/\b\w/g, (/** @type {string} */ c) => c.toUpperCase())}</span>{/each}</div>
      </section>
    {/if}
  {/if}
</main>

<style>
  .u-page { max-width: 520px; margin: 0 auto; padding: 16px 14px 60px; }
  .back-btn { background: none; border: none; color: var(--text-muted); font-size: 0.92rem; cursor: pointer; padding: 6px 0; }
  .msg { color: var(--text-muted); text-align: center; padding: 40px 0; }

  .u-head { text-align: center; margin: 10px 0 20px; }
  .u-coin { width: 72px; height: 72px; margin: 0 auto 10px; border-radius: 50%; display: grid; place-items: center;
    font-family: var(--font-display); font-weight: 800; font-size: 1.8rem; color: #3a2a00;
    background: linear-gradient(135deg, var(--c, #fde047), #f59e0b); box-shadow: 0 0 26px rgba(251,191,36,0.4); }
  h1 { font-family: var(--font-display); font-size: 1.4rem; margin: 0; }
  .u-title { display: inline-block; margin-top: 4px; font-size: 0.78rem; color: var(--gold); }
  .u-net { font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 2rem; color: #fde047;
    margin-top: 12px; text-shadow: 0 0 18px rgba(251,191,36,0.5); }
  .u-net.neg { color: #fb7185; text-shadow: none; }
  .u-net-lbl { font-size: 0.72rem; color: var(--text-faint); text-transform: uppercase; letter-spacing: 0.1em; }

  .h2h { background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-md); padding: 14px; margin-bottom: 14px; }
  .h2h-h { color: var(--text-muted); font-size: 0.82rem; font-weight: 600; margin-bottom: 12px; text-align: center; }
  .h2h-tally { display: flex; justify-content: center; gap: 22px; }
  .t { display: flex; flex-direction: column; align-items: center; }
  .t b { font-family: var(--font-display); font-size: 1.6rem; }
  .t span { font-size: 0.7rem; color: var(--text-faint); }
  .t.win b { color: #7ee0a8; } .t.loss b { color: #fb7185; } .t.tie b { color: var(--text-muted); }
  .h2h-last { display: flex; justify-content: center; gap: 6px; margin-top: 12px; }
  .pip { width: 22px; height: 22px; border-radius: 6px; display: grid; place-items: center; font-size: 0.72rem; font-weight: 800; }
  .pip.won { background: rgba(126,224,168,0.2); color: #7ee0a8; }
  .pip.lost { background: rgba(251,113,133,0.2); color: #fb7185; }
  .pip.tie { background: var(--surface-2); color: var(--text-muted); }
  .h2h-empty { text-align: center; color: var(--text-faint); font-size: 0.8rem; margin-top: 10px; }

  .u-actions { display: flex; gap: 10px; justify-content: center; margin-bottom: 6px; flex-wrap: wrap; }
  .pill { padding: 9px 18px; border-radius: var(--r-pill); border: 1px solid var(--border-strong); background: var(--surface);
    color: var(--text); font-weight: 700; font-size: 0.86rem; cursor: pointer; }
  .pill.gold { background: linear-gradient(135deg, #fde047, #f59e0b); color: #3a2a00; border-color: transparent; }
  .pill.friend { color: #7ee0a8; }
  .pill.muted { color: var(--text-faint); cursor: default; }
  .add-msg { text-align: center; color: var(--text-muted); font-size: 0.82rem; margin: 8px 0 0; }

  .grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; margin: 18px 0; }
  .stat { background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-sm); padding: 12px 6px; text-align: center; }
  .s-n { display: block; font-family: var(--font-display); font-weight: 800; font-size: 1.05rem; color: var(--text); }
  .s-l { display: block; font-size: 0.64rem; color: var(--text-faint); margin-top: 3px; }

  .badges { margin-top: 6px; }
  .b-h { color: var(--text-faint); font-size: 0.72rem; text-transform: uppercase; letter-spacing: 0.08em; margin-bottom: 8px; }
  .b-wrap { display: flex; flex-wrap: wrap; gap: 7px; }
  .badge { font-size: 0.78rem; padding: 5px 10px; border-radius: var(--r-pill); background: var(--surface); border: 1px solid var(--border); color: var(--text-muted); }

  @media (max-width: 380px) { .grid { grid-template-columns: repeat(3, 1fr); } }
</style>
