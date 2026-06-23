<script>
  import { createEventDispatcher } from 'svelte';

  /** @type {any} */
  export let detail = null; // get_match_detail() result, or { loading:true }

  const dispatch = createEventDispatcher();
  const close = () => dispatch('close');

  $: parts = detail?.participants ?? [];
  $: m = detail?.match;
  $: opp = parts.find((/** @type {any} */ p) => !p.is_me);
  $: me = parts.find((/** @type {any} */ p) => p.is_me);
  $: noSolve = parts.length > 0 && parts.every((/** @type {any} */ p) => (p.solved ?? 0) === 0);
  $: title = detail?.group_name || (opp ? '@' + (opp.name || 'player') : 'Challenge');
  $: wagered = Number(m?.wager) > 0;
  const rankIcon = (/** @type {number} */ r) => r === 1 ? '🥇' : r === 2 ? '🥈' : r === 3 ? '🥉' : '#' + r;
  const money = (/** @type {any} */ n) => (Number(n) < 0 ? '−$' : '+$') + Math.abs(Math.round(Number(n ?? 0))).toLocaleString();
  const mult = (/** @type {any} */ x) => x ? (Number(x) / 100).toFixed(1) + '×' : '';
</script>

{#if detail}
  <div class="md-overlay" role="button" tabindex="0"
       on:click={close} on:keydown={(e) => { if (e.key === 'Escape') close(); }}>
    <div class="md" role="dialog" tabindex="0" on:click|stopPropagation on:keydown={() => {}}>
      <button class="md-x" on:click={close}>✕</button>
      {#if detail.loading}
        <p class="md-msg">Loading…</p>
      {:else}
        <h2 class="md-title">{noSolve ? '🤝' : '⚔️'} {title}</h2>
        <p class="md-sub">
          {m?.pack_size} puzzle{m?.pack_size === 1 ? '' : 's'}
          · {m?.payout === 'podium' ? 'podium 3·2·1' : 'winner-take-all'}
          {#if wagered}· ${Number(m.wager).toLocaleString()} buy-in{:else}· friendly{/if}
          {#if m?.status !== 'settled'}· <em>in progress</em>{/if}
          {#if noSolve && wagered}· buy-in refunded{/if}
        </p>

        {#if wagered && m?.status === 'settled' && me && me.net != null && !noSolve}
          <div class="md-outcome {Number(me.net) >= 0 ? 'win' : 'loss'}">
            <span class="md-out-net">{money(me.net)}</span>
            <span class="md-out-lbl">
              {#if Number(me.net) >= 0}you took the pot{#if mult(me.multiple_x100)} · {mult(me.multiple_x100)}{/if}{:else}you spent ${me.spent}{/if}
            </span>
          </div>
        {/if}

        <div class="md-standings">
          {#each parts as p}
            <div class="md-row" class:me={p.is_me}>
              <span class="md-rank">{noSolve ? '🤝' : rankIcon(p.rank)}</span>
              <span class="md-name">{p.is_me ? 'You' : '@' + (p.name || 'player')}</span>
              <span class="md-meta">
                {#if p.state === 'done'}solved {p.solved ?? 0}/{m?.pack_size}{#if p.spent != null} · ${Number(p.spent).toLocaleString()} spent{/if}{#if wagered && p.net != null} · <span class:pos={Number(p.net) >= 0} class:neg={Number(p.net) < 0}>{money(p.net)}</span>{/if}
                {:else}{p.state}{/if}
              </span>
            </div>
          {/each}
        </div>

        {#if detail.pack?.length}
          <div class="md-pack">
            <div class="md-pack-h">Puzzles</div>
            {#each detail.pack as pk}
              <div class="md-pk">
                <span class="md-pos">{pk.position}</span>
                <span class="md-cat">{pk.category}</span>
                <span class="md-ans">{pk.phrase ? '“' + pk.phrase + '”' : '🔒 hidden until settled'}</span>
              </div>
            {/each}
          </div>
        {/if}
      {/if}
    </div>
  </div>
{/if}

<style>
  .md-overlay { position: fixed; inset: 0; z-index: 10000; display: grid; place-items: center; padding: 18px;
    background: rgba(5,5,5,0.8); backdrop-filter: blur(4px); }
  .md { width: 100%; max-width: 440px; max-height: 86vh; overflow-y: auto; position: relative;
    background: var(--surface-strong); border: 1px solid var(--border-strong); border-radius: var(--r-lg); padding: 20px; }
  .md-x { position: absolute; top: 12px; right: 14px; background: none; border: none; color: var(--text-muted); font-size: 1rem; cursor: pointer; }
  .md-title { font-family: var(--font-display); font-size: 1.25rem; margin: 0 0 4px; }
  .md-sub { color: var(--text-faint); font-size: 0.8rem; margin: 0 0 16px; }
  .md-msg { color: var(--text-muted); text-align: center; padding: 24px 0; }

  .md-outcome { display: flex; align-items: baseline; gap: 10px; justify-content: center; padding: 12px; margin: 0 0 16px;
    border-radius: var(--r-md); border: 1px solid var(--border); }
  .md-outcome.win { background: rgba(126,224,168,0.1); border-color: rgba(126,224,168,0.3); }
  .md-outcome.loss { background: rgba(251,113,133,0.08); border-color: rgba(251,113,133,0.25); }
  .md-out-net { font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 1.6rem; }
  .md-outcome.win .md-out-net { color: #7ee0a8; } .md-outcome.loss .md-out-net { color: #fb7185; }
  .md-out-lbl { color: var(--text-muted); font-size: 0.82rem; }
  .md-meta .pos { color: #7ee0a8; } .md-meta .neg { color: #fb7185; }

  .md-standings { display: flex; flex-direction: column; gap: 6px; margin-bottom: 16px; }
  .md-row { display: flex; align-items: center; gap: 10px; padding: 9px 11px; border-radius: var(--r-sm); background: var(--surface); }
  .md-row.me { background: rgba(251,191,36,0.12); border: 1px solid rgba(251,191,36,0.3); }
  .md-rank { flex: 0 0 28px; font-weight: 700; }
  .md-name { flex: 1; font-weight: 700; color: var(--text); }
  .md-meta { color: var(--text-faint); font-size: 0.76rem; text-align: right; }

  .md-pack { border-top: 1px solid var(--border); padding-top: 12px; }
  .md-pack-h { color: var(--text-faint); font-size: 0.72rem; text-transform: uppercase; letter-spacing: 0.08em; margin-bottom: 8px; }
  .md-pk { display: flex; align-items: center; gap: 10px; padding: 5px 0; font-size: 0.84rem; }
  .md-pos { flex: 0 0 20px; color: var(--text-faint); }
  .md-cat { flex: 0 0 auto; color: var(--text-muted); font-size: 0.74rem; }
  .md-ans { color: var(--gold); font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
</style>
