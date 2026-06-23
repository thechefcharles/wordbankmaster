<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { getHistory, getMatchDetail } from '$lib/stores/statsStore.js';
  import { track } from '$lib/analytics.js';

  /** @type {'all'|'daily'|'climb'|'arcade'|'challenge'} */
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

  /** which solo row is expanded (id) */
  let openRow = $state('');
  /** challenge detail modal */
  let detail = $state(/** @type {any} */ (null));
  let detailLoading = $state(false);

  const MODES = [
    { k: 'all', label: 'All' }, { k: 'daily', label: '📅 Daily' },
    { k: 'climb', label: '🎰 Climb' }, { k: 'arcade', label: '🎲 Arcade' },
    { k: 'challenge', label: '⚔️ Versus' }
  ];
  const icon = (/** @type {string} */ m) =>
    m === 'daily' ? '📅' : m === 'climb' ? '🎰' : m === 'arcade' ? '🎲' : m === 'challenge' ? '⚔️' : '🎮';
  const money = (/** @type {any} */ n) => (Number(n) < 0 ? '−$' : '+$') + Math.abs(Math.round(Number(n ?? 0))).toLocaleString();
  const mult = (/** @type {any} */ x) => x ? (Number(x) / 100).toFixed(1) + '×' : '';
  const when = (/** @type {string} */ t) => new Date(t).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });

  /** @param {any} r */
  const title = (r) =>
    r.game_mode === 'challenge'
      ? (r.opponent_name ? '@' + r.opponent_name : r.group_name || 'Challenge')
      : (r.category || 'Puzzle');

  async function load(reset = false) {
    if (reset) { offset = 0; done = false; rows = []; }
    loading = true; error = '';
    try {
      const page = await getHistory({
        mode: mode === 'all' ? null : mode,
        result: result === 'all' ? null : result,
        sort, limit: PAGE, offset
      });
      rows = reset ? page : [...rows, ...page];
      offset += page.length;
      if (page.length < PAGE) done = true;
    } catch (e) {
      error = (e instanceof Error ? e.message : String(e)) || 'Failed to load';
    } finally { loading = false; }
  }

  /** @param {any} r */
  async function openDetail(r) {
    if (r.game_mode === 'challenge' && r.match_id) {
      detailLoading = true; detail = { loading: true, row: r };
      const d = await getMatchDetail(r.match_id);
      detail = d ? { ...d, row: r } : null;
      detailLoading = false;
      if (!d) error = 'Could not load that challenge.';
    } else {
      openRow = openRow === r.id ? '' : r.id;
    }
  }

  onMount(() => track('history_view'));
  // initial load + reload whenever a filter changes
  $effect(() => { mode; result; sort; load(true); });
</script>

<svelte:head><title>WordBank — History</title></svelte:head>

<main class="h-page">
  <button class="back-btn" onclick={() => goto('/')}>← Menu</button>
  <h1>📜 History</h1>

  <div class="chips">
    {#each MODES as m}
      <button class="chip" class:active={mode === m.k} onclick={() => mode = /** @type {any} */ (m.k)}>{m.label}</button>
    {/each}
  </div>

  <div class="row2">
    <div class="seg">
      {#each [['all','All'],['won','Won'],['lost','Lost'],['tie','Tie']] as [k, l]}
        <button class="seg-btn" class:active={result === k} onclick={() => result = /** @type {any} */ (k)}>{l}</button>
      {/each}
    </div>
    <select class="sort" bind:value={sort}>
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
            <span class="ic">{icon(r.game_mode)}</span>
            <span class="mid">
              <span class="ttl">{title(r)}</span>
              <span class="sub">
                {#if r.game_mode === 'challenge'}
                  {r.outcome === 'won' ? 'Won' : r.outcome === 'tie' ? 'Tied' : 'Lost'}
                  {#if r.rank && r.field_size}· #{r.rank}/{r.field_size}{/if}
                  {#if r.solved_count != null}· solved {r.solved_count}/{r.puzzle_count}{/if}
                {:else}
                  {r.outcome === 'won' ? 'Solved' : r.outcome === 'lost' ? 'Missed' : (r.outcome || '')}
                  {#if r.spent != null}· spent ${r.spent}{/if}
                {/if}
              </span>
            </span>
            <span class="right">
              {#if r.net != null}<span class="net" class:neg={Number(r.net) < 0}>{money(r.net)}</span>{/if}
              {#if mult(r.multiple_x100)}<span class="mult">{mult(r.multiple_x100)}</span>{/if}
              <span class="date">{when(r.played_at)}</span>
            </span>
          </button>
          {#if openRow === r.id && r.game_mode !== 'challenge'}
            <div class="detail-inline">
              {#if r.puzzle_phrase}<div class="answer">“{r.puzzle_phrase}”</div>{/if}
              <div class="kv">
                {#if r.earned != null}<span>Bounty <b>${r.earned}</b></span>{/if}
                {#if r.spent != null}<span>Spent <b>${r.spent}</b></span>{/if}
                {#if r.net != null}<span>Net <b class:neg={Number(r.net) < 0}>{money(r.net)}</b></span>{/if}
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
</main>

<!-- Challenge detail -->
{#if detail}
  <div class="modal-overlay" role="button" tabindex="0"
       onclick={() => detail = null} onkeydown={(e) => { if (e.key === 'Escape') detail = null; }}>
    <div class="modal" role="dialog" tabindex="0" onclick={(e) => e.stopPropagation()} onkeydown={() => {}}>
      <button class="x" onclick={() => detail = null}>✕</button>
      {#if detail.loading}
        <p class="msg">Loading…</p>
      {:else}
        <h2 class="m-title">⚔️ {detail.group_name || (detail.row?.opponent_name ? '@' + detail.row.opponent_name : 'Challenge')}</h2>
        <p class="m-sub">
          {detail.match?.pack_size} puzzle{detail.match?.pack_size === 1 ? '' : 's'}
          · {detail.match?.payout === 'podium' ? 'podium' : 'winner-take-all'}
          {#if Number(detail.match?.wager) > 0}· ${detail.match.wager} buy-in{:else}· friendly{/if}
          {#if detail.match?.status !== 'settled'}· <em>in progress</em>{/if}
        </p>

        <div class="standings">
          {#each (detail.participants || []) as p}
            <div class="st-row" class:me={p.is_me}>
              <span class="st-rank">{p.rank === 1 ? '🥇' : p.rank === 2 ? '🥈' : p.rank === 3 ? '🥉' : '#' + p.rank}</span>
              <span class="st-name">{p.is_me ? 'You' : '@' + (p.name || 'player')}</span>
              <span class="st-meta">solved {p.solved ?? 0}/{detail.match?.pack_size} · {p.score ?? 0} pts</span>
            </div>
          {/each}
        </div>

        {#if detail.pack?.length}
          <div class="pack">
            <div class="pack-h">Puzzles</div>
            {#each detail.pack as pk}
              <div class="pk-row">
                <span class="pk-pos">{pk.position + 1}</span>
                <span class="pk-cat">{pk.category}</span>
                <span class="pk-ans">{pk.phrase ? '“' + pk.phrase + '”' : '🔒'}</span>
              </div>
            {/each}
          </div>
        {/if}
      {/if}
    </div>
  </div>
{/if}

<style>
  .h-page { max-width: 560px; margin: 0 auto; padding: 16px 14px 60px; }
  .back-btn { background: none; border: none; color: var(--text-muted); font-size: 0.92rem; cursor: pointer; padding: 6px 0; }
  h1 { font-family: var(--font-display); font-size: 1.5rem; margin: 4px 0 14px; }

  .chips { display: flex; gap: 8px; overflow-x: auto; padding-bottom: 6px; margin-bottom: 10px; }
  .chip { flex: 0 0 auto; padding: 7px 13px; border-radius: var(--r-pill); border: 1px solid var(--border);
    background: var(--surface); color: var(--text-muted); font-weight: 600; font-size: 0.84rem; cursor: pointer; }
  .chip.active { background: linear-gradient(135deg, #fde047, #f59e0b); color: #3a2a00; border-color: transparent; }

  .row2 { display: flex; gap: 10px; align-items: center; margin-bottom: 14px; }
  .seg { display: flex; flex: 1; background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-md); overflow: hidden; }
  .seg-btn { flex: 1; padding: 8px 0; background: none; border: none; color: var(--text-muted); font-size: 0.82rem; font-weight: 600; cursor: pointer; }
  .seg-btn.active { background: var(--surface-2); color: var(--gold); }
  .sort { background: var(--surface); border: 1px solid var(--border); color: var(--text); border-radius: var(--r-md); padding: 8px 10px; font-size: 0.82rem; }

  .list { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 8px; }
  .item { border: 1px solid var(--border); border-radius: var(--r-md); background: var(--surface); overflow: hidden; }
  .item.open { border-color: rgba(251,191,36,0.4); }
  .item-main { width: 100%; display: flex; align-items: center; gap: 11px; padding: 12px 13px; background: none; border: none; cursor: pointer; text-align: left; }
  .ic { font-size: 1.3rem; flex: 0 0 auto; }
  .mid { display: flex; flex-direction: column; gap: 2px; min-width: 0; flex: 1; }
  .ttl { color: var(--text); font-weight: 700; font-size: 0.95rem; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .sub { color: var(--text-faint); font-size: 0.76rem; }
  .right { display: flex; flex-direction: column; align-items: flex-end; gap: 1px; flex: 0 0 auto; }
  .net { color: #7ee0a8; font-weight: 800; font-size: 0.95rem; font-variant-numeric: tabular-nums; }
  .net.neg, b.neg { color: #fb7185; }
  .mult { color: var(--gold); font-size: 0.74rem; font-weight: 700; }
  .date { color: var(--text-faint); font-size: 0.7rem; }

  .detail-inline { padding: 0 13px 13px 49px; }
  .answer { color: var(--gold); font-weight: 700; margin: 0 0 8px; }
  .kv { display: flex; flex-wrap: wrap; gap: 6px 16px; color: var(--text-muted); font-size: 0.8rem; }
  .kv b { color: var(--text); }

  .more { display: block; margin: 14px auto 0; padding: 9px 22px; border-radius: var(--r-pill);
    background: var(--surface); border: 1px solid var(--border); color: var(--text); font-weight: 600; cursor: pointer; }

  .msg { color: var(--text-muted); text-align: center; padding: 24px 0; }
  .msg.err { color: #fb7185; }

  .modal-overlay { position: fixed; inset: 0; z-index: 9999; display: grid; place-items: center; padding: 18px;
    background: rgba(5,5,5,0.78); backdrop-filter: blur(4px); }
  .modal { width: 100%; max-width: 440px; max-height: 86vh; overflow-y: auto; position: relative;
    background: var(--surface-strong); border: 1px solid var(--border-strong); border-radius: var(--r-lg); padding: 20px; }
  .x { position: absolute; top: 12px; right: 14px; background: none; border: none; color: var(--text-muted); font-size: 1rem; cursor: pointer; }
  .m-title { font-family: var(--font-display); font-size: 1.25rem; margin: 0 0 4px; }
  .m-sub { color: var(--text-faint); font-size: 0.8rem; margin: 0 0 16px; }

  .standings { display: flex; flex-direction: column; gap: 6px; margin-bottom: 16px; }
  .st-row { display: flex; align-items: center; gap: 10px; padding: 9px 11px; border-radius: var(--r-sm); background: var(--surface); }
  .st-row.me { background: rgba(251,191,36,0.12); border: 1px solid rgba(251,191,36,0.3); }
  .st-rank { flex: 0 0 28px; font-weight: 700; }
  .st-name { flex: 1; font-weight: 700; color: var(--text); }
  .st-meta { color: var(--text-faint); font-size: 0.76rem; }

  .pack { border-top: 1px solid var(--border); padding-top: 12px; }
  .pack-h { color: var(--text-faint); font-size: 0.72rem; text-transform: uppercase; letter-spacing: 0.08em; margin-bottom: 8px; }
  .pk-row { display: flex; align-items: center; gap: 10px; padding: 5px 0; font-size: 0.84rem; }
  .pk-pos { flex: 0 0 20px; color: var(--text-faint); }
  .pk-cat { flex: 0 0 auto; color: var(--text-muted); font-size: 0.74rem; }
  .pk-ans { color: var(--gold); font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
</style>
