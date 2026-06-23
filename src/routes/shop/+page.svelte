<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { getShop, buyCosmetic, equipCosmetic, unequipCosmetic, getPowerups, buyPowerup } from '$lib/stores/statsStore.js';
  import { requirePin } from '$lib/pinConfirm.js';
  import { track } from '$lib/analytics.js';
  import { fx } from '$lib/sound.js';

  let bank = $state(0);
  /** @type {any[]} */
  let items = $state([]);
  /** @type {any[]} */
  let pups = $state([]);
  let loading = $state(true);
  let busy = $state('');
  let msg = $state('');

  const PUP_META = /** @type {Record<string,{icon:string,desc:string}>} */ ({
    free_reveal:  { icon: '🔍', desc: 'Reveal the most useful letter' },
    free_vowel:   { icon: '🅰️', desc: 'Reveal one vowel free' },
    half_off:     { icon: '🏷️', desc: 'Letters cost 50% less this puzzle' },
    vowel_vision: { icon: '👁️', desc: 'Reveal every vowel' },
    reveal_word:  { icon: '📖', desc: 'Reveal a whole word' },
    extra_hint:   { icon: '💡', desc: 'Reveal the first letter of each word' },
    last_letters: { icon: '🔚', desc: 'Reveal the last letter of each word' },
    sabotage_tax: { icon: '💸', desc: "An opponent's letters cost +50%" },
    sabotage_fog: { icon: '🌫️', desc: "Hide an opponent's clue" },
    sabotage_toll:        { icon: '🚧', desc: "An opponent's next letter costs 3×" },
    sabotage_vowel_block: { icon: '🚫', desc: "An opponent's vowels cost 3×" },
    sabotage_lock:        { icon: '🔒', desc: 'Wipe a letter an opponent revealed' }
  });

  /** @type {any[]} */
  let sabs = $state([]);

  async function load() {
    const [shop, pu] = await Promise.all([getShop(), getPowerups()]);
    bank = shop.bank;
    items = shop.items;
    pups = (pu.items || []).filter((/** @type {any} */ i) => i.kind === 'climb');
    sabs = (pu.items || []).filter((/** @type {any} */ i) => i.kind === 'sabotage');
  }

  /** @param {any} item */
  async function buyPup(item) {
    if (busy) return;
    try { await requirePin(`Buy ${item.name} · $${item.price.toLocaleString()}`); } catch { return; }
    busy = item.id; msg = '';
    const res = await buyPowerup(item.id);
    busy = '';
    if (res?.ok) { fx('win'); track('powerup_buy', { id: item.id }); await load(); }
    else { msg = res?.reason === 'insufficient' ? 'Not enough Cash.' : res?.reason === 'owned' ? 'You already own one — use it first.' : 'Could not buy that.'; }
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
    try { await requirePin(`Buy ${item.label} · $${item.price.toLocaleString()}`); } catch { return; }
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
  <p class="sub">Stock up on power-ups to bring into the Cash Game &amp; challenges, and spend on flair. Cosmetics are pure show — no pay-to-win.</p>

  {#if loading}
    <p class="loading">Loading…</p>
  {:else}
    {#if msg}<p class="msg">{msg}</p>{/if}

    <h2 class="section">⚡ Power-ups</h2>
    <p class="section-note">Carry one of each. Bring them to the Cash Game or a challenge and use them whenever you like — the Daily stays power-up-free.</p>
    <div class="grid">
      {#each pups as item}
        <div class="card pup" class:owned={item.owned > 0}>
          <span class="pup-ic">{PUP_META[item.id]?.icon ?? '✨'}</span>
          <span class="c-label">{item.name}</span>
          <span class="pup-desc">{PUP_META[item.id]?.desc ?? ''}</span>
          {#if item.owned > 0}
            <button class="c-btn equip on" disabled>✓ In your bag</button>
          {:else}
            <button class="c-btn buy" disabled={busy === item.id || bank < item.price} onclick={() => buyPup(item)}>
              💰 ${item.price.toLocaleString()}
            </button>
          {/if}
        </div>
      {/each}
    </div>

    {#if sabs.length}
      <h2 class="section">😈 Sabotage</h2>
      <p class="section-note">Bring these to a challenge with power-ups on, then hit an opponent — they get notified.</p>
      <div class="grid">
        {#each sabs as item}
          <div class="card pup" class:owned={item.owned > 0}>
            <span class="pup-ic">{PUP_META[item.id]?.icon ?? '😈'}</span>
            <span class="c-label">{item.name}</span>
            <span class="pup-desc">{PUP_META[item.id]?.desc ?? ''}</span>
            {#if item.owned > 0}
              <button class="c-btn equip on" disabled>✓ In your bag</button>
            {:else}
              <button class="c-btn buy" disabled={busy === item.id || bank < item.price} onclick={() => buyPup(item)}>
                💰 ${item.price.toLocaleString()}
              </button>
            {/if}
          </div>
        {/each}
      </div>
    {/if}

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
  .section { font-family: var(--font-display); font-size: 1.05rem; margin: 1.4rem 0 0.4rem; }
  .section-note { font-size: 0.76rem; color: var(--text-faint); margin: 0 0 0.8rem; }
  .card.pup { align-items: center; text-align: center; gap: 0.3rem; }
  .pup-ic { font-size: 1.7rem; line-height: 1; }
  .pup-desc { font-size: 0.72rem; color: var(--text-muted); line-height: 1.3; min-height: 2.1em; }
  .card.pup .c-btn { margin-top: 0.3rem; }
  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 0.6rem; }
  .card {
    display: flex; flex-direction: column; gap: 0.6rem; align-items: flex-start;
    padding: 0.9rem; border-radius: 14px; border: 1px solid var(--border); background: var(--surface);
  }
  .card.owned { border-color: rgba(253, 224, 71,0.35); }
  .c-label { font-family: var(--font-display); font-weight: 700; font-size: 1rem; }
  .c-btn {
    width: 100%; padding: 0.5rem 0.7rem; border-radius: 10px; cursor: pointer; font-weight: 700; font-size: 0.85rem;
    border: 1px solid var(--border); background: var(--surface-2, rgba(255,255,255,0.04)); color: var(--text);
  }
  .c-btn.buy { color: #3a2a00; border: none; background: var(--brand-grad, linear-gradient(135deg,#fbbf24,#fde047)); }
  .c-btn.buy:disabled { opacity: 0.45; cursor: default; }
  .c-btn.equip.on { color: var(--brand-2); border-color: rgba(253, 224, 71,0.5); background: rgba(253, 224, 71,0.1); }
  .c-btn:disabled { opacity: 0.6; }
</style>
