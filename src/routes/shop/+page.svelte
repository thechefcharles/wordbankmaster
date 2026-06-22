<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { getShop, buyCosmetic, equipCosmetic, unequipCosmetic } from '$lib/stores/statsStore.js';
  import { track } from '$lib/analytics.js';
  import { fx } from '$lib/sound.js';

  let bank = $state(0);
  /** @type {any[]} */
  let items = $state([]);
  let loading = $state(true);
  let busy = $state('');
  let msg = $state('');

  async function load() {
    const shop = await getShop();
    bank = shop.bank;
    items = shop.items;
  }
  onMount(async () => {
    track('shop_view');
    try { await load(); } finally { loading = false; }
  });

  let titles = $derived(items.filter((i) => i.kind === 'title'));
  let colors = $derived(items.filter((i) => i.kind === 'color'));

  /** @param {any} item */
  async function buy(item) {
    if (busy) return;
    busy = item.id; msg = '';
    const res = await buyCosmetic(item.id);
    busy = '';
    if (res.ok) { fx('win'); track('cosmetic_buy', { id: item.id }); await load(); }
    else { msg = res.reason === 'insufficient' ? "Not enough Cash." : 'Could not buy that.'; }
  }
  /** @param {any} item */
  async function equip(item) {
    if (busy) return;
    busy = item.id;
    const res = item.equipped ? await unequipCosmetic(item.kind) : await equipCosmetic(item.id);
    busy = '';
    if (res.ok) { await load(); }
  }
</script>

<svelte:head><title>WordBank — Shop</title></svelte:head>

<main class="shop-page">
  <button class="back-btn" onclick={() => goto('/')}>← Menu</button>

  <div class="head">
    <h1>🛍️ Shop</h1>
    <span class="bank-chip">💰 ${bank.toLocaleString()}</span>
  </div>
  <p class="sub">Spend your Cash on titles &amp; name colors — pure flair, shows on the leaderboards. No pay-to-win.</p>

  {#if loading}
    <p class="loading">Loading…</p>
  {:else}
    {#if msg}<p class="msg">{msg}</p>{/if}

    <h2 class="section">Titles</h2>
    <div class="grid">
      {#each titles as item}
        <div class="card" class:owned={item.owned}>
          <span class="c-label">{item.label}</span>
          {#if item.owned}
            <button class="c-btn equip" class:on={item.equipped} disabled={busy === item.id} onclick={() => equip(item)}>
              {item.equipped ? '✓ Equipped' : 'Equip'}
            </button>
          {:else}
            <button class="c-btn buy" disabled={busy === item.id || bank < item.price} onclick={() => buy(item)}>
              💰 ${item.price.toLocaleString()}
            </button>
          {/if}
        </div>
      {/each}
    </div>

    <h2 class="section">Name Colors</h2>
    <div class="grid">
      {#each colors as item}
        <div class="card" class:owned={item.owned}>
          <span class="c-label" style="color:{item.value}">{item.label}</span>
          {#if item.owned}
            <button class="c-btn equip" class:on={item.equipped} disabled={busy === item.id} onclick={() => equip(item)}>
              {item.equipped ? '✓ Equipped' : 'Equip'}
            </button>
          {:else}
            <button class="c-btn buy" disabled={busy === item.id || bank < item.price} onclick={() => buy(item)}>
              💰 ${item.price.toLocaleString()}
            </button>
          {/if}
        </div>
      {/each}
    </div>
  {/if}
</main>

<style>
  .shop-page { max-width: 480px; margin: 0 auto; padding: 1.5rem 1rem 3rem; }
  .back-btn {
    display: inline-block; margin-bottom: 1.2rem; padding: 0.55rem 1.1rem;
    background: var(--surface); color: var(--text); border: 1px solid var(--border);
    border-radius: 12px; cursor: pointer; font-weight: 600; font-size: 0.9rem;
  }
  .head { display: flex; align-items: baseline; justify-content: space-between; }
  h1 { font-family: var(--font-display); font-size: 1.7rem; margin: 0; }
  .bank-chip { font-family: var(--font-display); font-weight: 800; color: #fbbf24; font-size: 1.05rem; }
  .sub { color: var(--text-muted); font-size: 0.9rem; margin: 0.2rem 0 1.4rem; }
  .loading { color: var(--text-muted); padding: 2rem; text-align: center; }
  .msg { text-align: center; color: #f87171; font-size: 0.88rem; margin: 0 0 1rem; }
  .section { font-family: var(--font-display); font-size: 1.05rem; margin: 1.4rem 0 0.7rem; }
  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 0.6rem; }
  .card {
    display: flex; flex-direction: column; gap: 0.6rem; align-items: flex-start;
    padding: 0.9rem; border-radius: 14px; border: 1px solid var(--border); background: var(--surface);
  }
  .card.owned { border-color: rgba(163,230,53,0.35); }
  .c-label { font-family: var(--font-display); font-weight: 700; font-size: 1rem; }
  .c-btn {
    width: 100%; padding: 0.5rem 0.7rem; border-radius: 10px; cursor: pointer; font-weight: 700; font-size: 0.85rem;
    border: 1px solid var(--border); background: var(--surface-2, rgba(255,255,255,0.04)); color: var(--text);
  }
  .c-btn.buy { color: #06210f; border: none; background: var(--brand-grad, linear-gradient(135deg,#34d399,#a3e635)); }
  .c-btn.buy:disabled { opacity: 0.45; cursor: default; }
  .c-btn.equip.on { color: var(--brand-2); border-color: rgba(163,230,53,0.5); background: rgba(163,230,53,0.1); }
  .c-btn:disabled { opacity: 0.6; }
</style>
