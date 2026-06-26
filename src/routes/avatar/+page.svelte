<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import Avatar from '$lib/components/Avatar.svelte';
  import { CATEGORIES, DEFAULT_AVATAR } from '$lib/avatar.js';
  import { getMyAvatar, setAvatar, buyCosmetic, getBank } from '$lib/stores/statsStore.js';
  import { fx } from '$lib/sound.js';
  import { track } from '$lib/analytics.js';

  /** @type {any} */ let config = { ...DEFAULT_AVATAR };
  /** @type {string[]} */ let owned = [];
  let bank = 0;
  let loading = true;
  let saving = false;
  let activeCat = CATEGORIES[0].key;
  let dirty = false;
  let toast = '';
  /** @type {any} */ let buying = null; // option pending purchase-confirm

  onMount(async () => {
    track('avatar_open');
    const [a, b] = await Promise.all([getMyAvatar(), getBank()]);
    if (a.config) config = { ...DEFAULT_AVATAR, ...a.config };
    owned = a.owned ?? [];
    bank = b?.bank ?? 0;
    loading = false;
  });

  $: cat = CATEGORIES.find((c) => c.key === activeCat) ?? CATEGORIES[0];
  const fmt = (/** @type {number} */ n) => '$' + Math.round(n ?? 0).toLocaleString();
  /** @param {any} o */
  const locked = (o) => !!o.price && !owned.includes(o.cosmeticId);
  /** preview config with one category overridden @param {string} key @param {string} value */
  const preview = (key, value) => ({ ...config, [key]: value });

  function flash(/** @type {string} */ m) { toast = m; setTimeout(() => { if (toast === m) toast = ''; }, 1800); }

  /** @param {string} key @param {any} o */
  function choose(key, o) {
    if (locked(o)) { buying = { key, o }; return; }
    fx('tap');
    config = { ...config, [key]: o.value };
    dirty = true;
  }

  async function confirmBuy() {
    if (!buying) return;
    const { key, o } = buying;
    if (bank < o.price) { flash("Not enough Cash"); buying = null; return; }
    saving = true;
    const res = await buyCosmetic(o.cosmeticId);
    saving = false;
    if (!res.ok) { flash(res.reason === 'insufficient' ? 'Not enough Cash' : 'Could not buy'); buying = null; return; }
    fx('win');
    owned = [...owned, o.cosmeticId];
    bank -= o.price;
    config = { ...config, [key]: o.value };
    dirty = true;
    buying = null;
    flash('Unlocked!');
  }

  async function save() {
    saving = true;
    const res = await setAvatar(config);
    saving = false;
    if (res.ok) { fx('select'); dirty = false; flash('Saved'); }
    else flash('Could not save');
  }
</script>

<svelte:head><title>WordBank — Avatar</title></svelte:head>

<main class="av-page">
  <header class="av-head">
    <button class="back-btn" on:click={() => goto('/')}>← Menu</button>
    <span class="av-cash">💰 {fmt(bank)}</span>
  </header>

  {#if loading}
    <p class="loading">Loading…</p>
  {:else}
    <div class="av-hero"><Avatar {config} size={160} /></div>

    <div class="cat-row">
      {#each CATEGORIES as c}
        <button class="cat-chip" class:on={c.key === activeCat} on:click={() => { activeCat = c.key; fx('tap'); }}>{c.label}</button>
      {/each}
    </div>

    <div class="opt-grid" class:colors={cat.type === 'color'}>
      {#each cat.options as o (o.value)}
        <button class="opt" class:sel={config[cat.key] === o.value} class:locked={locked(o)} on:click={() => choose(cat.key, o)}
          title={o.label}>
          {#if cat.type === 'color'}
            <span class="sw" style="background:#{o.value}"></span>
          {:else}
            <Avatar config={preview(cat.key, o.value)} size={62} />
          {/if}
          <span class="opt-label">{o.label}</span>
          {#if locked(o)}<span class="opt-price">🔒 {fmt(o.price)}</span>{/if}
        </button>
      {/each}
    </div>
  {/if}

  {#if toast}<div class="av-toast">{toast}</div>{/if}

  <button class="av-save" class:dirty disabled={saving || !dirty} on:click={save}>{saving ? 'Saving…' : dirty ? 'Save' : 'Saved'}</button>
</main>

{#if buying}
  <div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Unlock item">
    <button type="button" class="modal-backdrop" aria-label="Cancel" on:click={() => buying = null}></button>
    <div class="buy-card">
      <Avatar config={preview(buying.key, buying.o.value)} size={120} />
      <h3>{buying.o.label}</h3>
      <p class="buy-price">{fmt(buying.o.price)}</p>
      <button class="buy-go" disabled={saving || bank < buying.o.price} on:click={confirmBuy}>
        {bank < buying.o.price ? 'Not enough Cash' : (saving ? 'Unlocking…' : `Unlock for ${fmt(buying.o.price)}`)}
      </button>
      <button class="buy-cancel" on:click={() => buying = null}>Cancel</button>
    </div>
  </div>
{/if}

<style>
  .av-page { max-width: 480px; margin: 0 auto; padding: 1rem 1rem 6rem; min-height: 100vh; }
  .av-head { display: flex; align-items: center; justify-content: space-between; margin-bottom: 0.5rem; }
  .back-btn { padding: 0.5rem 1rem; background: var(--surface); color: var(--text); border: 1px solid var(--border); border-radius: 12px; cursor: pointer; font-weight: 600; font-size: 0.9rem; }
  .av-cash { font-family: var(--font-display); font-weight: 800; color: var(--brand-2); }
  .loading { text-align: center; color: var(--text-muted); padding: 3rem; }
  .av-hero { display: grid; place-items: center; margin: 0.5rem 0 1rem; }
  .av-hero :global(.wb-avatar) { box-shadow: 0 8px 30px rgba(0,0,0,0.5); }

  .cat-row { display: flex; gap: 7px; overflow-x: auto; padding: 4px 0 10px; -webkit-overflow-scrolling: touch; scrollbar-width: none; }
  .cat-row::-webkit-scrollbar { display: none; }
  .cat-chip { flex: none; padding: 7px 13px; border-radius: 999px; cursor: pointer; font-weight: 700; font-size: 0.82rem; white-space: nowrap;
    color: var(--text-muted); background: var(--surface); border: 1px solid var(--border); }
  .cat-chip.on { color: #3a2a00; background: linear-gradient(135deg, #fde047, #f59e0b); border-color: transparent; }

  .opt-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 9px; }
  .opt-grid.colors { grid-template-columns: repeat(5, 1fr); }
  .opt { position: relative; display: flex; flex-direction: column; align-items: center; gap: 4px; padding: 8px 4px; border-radius: 14px; cursor: pointer;
    background: var(--surface); border: 1px solid var(--border); color: var(--text); }
  .opt.sel { border-color: var(--brand-2); box-shadow: 0 0 0 1px var(--brand-2); }
  .opt.locked { opacity: 0.96; }
  .opt.locked :global(.wb-avatar) { filter: grayscale(0.5) brightness(0.8); }
  .opt-label { font-size: 0.68rem; color: var(--text-muted); text-align: center; line-height: 1.1; }
  .opt-price { font-size: 0.68rem; font-weight: 800; color: var(--brand-2); }
  .sw { width: 42px; height: 42px; border-radius: 50%; border: 2px solid rgba(255,255,255,0.25); }
  .colors .opt-label { display: none; }

  .av-toast { position: fixed; left: 50%; bottom: 84px; transform: translateX(-50%); z-index: 1200; padding: 9px 18px; border-radius: 999px;
    background: rgba(20,28,40,0.95); color: var(--text); border: 1px solid var(--border-strong, var(--border)); font-weight: 700; font-size: 0.9rem; }
  .av-save { position: fixed; left: 50%; bottom: 18px; transform: translateX(-50%); z-index: 1100; width: calc(100% - 2rem); max-width: 448px;
    height: 52px; border-radius: 16px; cursor: pointer; font-family: var(--font-display); font-weight: 800; font-size: 1.05rem; border: none;
    background: var(--surface-2, rgba(255,255,255,0.08)); color: var(--text-faint); }
  .av-save.dirty { background: linear-gradient(135deg, #fde047, #f59e0b); color: #3a2a00; box-shadow: 0 8px 24px rgba(245,158,11,0.4); }
  .av-save:disabled { cursor: default; }

  .buy-card { position: relative; z-index: 1; width: calc(100% - 3rem); max-width: 320px; margin: auto; padding: 22px; border-radius: 20px; text-align: center;
    background: var(--surface-strong, rgba(20,26,38,0.95)); border: 1px solid var(--border-strong, var(--border)); display: flex; flex-direction: column; align-items: center; gap: 8px; }
  .buy-card h3 { margin: 6px 0 0; font-family: var(--font-display); }
  .buy-price { margin: 0; font-family: var(--font-display); font-weight: 800; font-size: 1.3rem; color: var(--brand-2); }
  .buy-go { width: 100%; height: 48px; border-radius: 14px; border: none; cursor: pointer; font-weight: 800; font-size: 1rem; color: #3a2a00;
    background: linear-gradient(135deg, #fde047, #f59e0b); }
  .buy-go:disabled { opacity: 0.5; cursor: not-allowed; }
  .buy-cancel { background: none; border: none; color: var(--text-muted); cursor: pointer; font-weight: 600; padding: 4px; }
</style>
