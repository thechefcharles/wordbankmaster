<script>
  // 🎒 My Bag — everything you currently own that you bought/earned, grouped by type:
  // Power-ups (incl. Bounty Boosts), Sabotage, and Extras (titles + name colors).
  // Power-ups are spent in-game; cosmetics are equipped from the Store/Profile.
  import { onMount } from 'svelte';
  import { getPowerups, getShop } from '$lib/stores/statsStore.js';

  /** @type {any[]} */ let pups = [];
  /** @type {any[]} */ let cosmetics = [];
  let loading = true;

  /** @type {Record<string,{icon:string,desc:string}>} */
  const META = {
    bounty_boost:  { icon: '💥', desc: 'Adds ×0.5 to your Daily bounty' },
    jackpot_boost: { icon: '💎', desc: 'Adds ×1.0 to your Daily bounty' },
    free_reveal:   { icon: '🔍', desc: 'Reveal the most useful letter' },
    free_vowel:    { icon: '🅰️', desc: 'Reveal one vowel free' },
    half_off:      { icon: '🏷️', desc: 'Letters cost 50% less this puzzle' },
    vowel_vision:  { icon: '👁️', desc: 'Reveal every vowel' },
    reveal_word:   { icon: '📖', desc: 'Reveal a whole word' },
    extra_hint:    { icon: '💡', desc: 'First letter of each word' },
    last_letters:  { icon: '🔚', desc: 'Last letter of each word' },
    sabotage_tax:  { icon: '💸', desc: "An opponent's letters cost +50%" },
    sabotage_fog:  { icon: '🌫️', desc: "Hide an opponent's clue" },
    sabotage_toll: { icon: '🚧', desc: "An opponent's next letter costs 3×" },
    sabotage_vowel_block: { icon: '🚫', desc: "An opponent's vowels cost 3×" },
    sabotage_lock: { icon: '🔒', desc: 'Wipe a letter an opponent revealed' }
  };
  const GROUPS = [
    { key: 'powerups', title: '⚡ Power-ups', note: 'Use in the Daily, Cash Game, or a challenge.' },
    { key: 'sabotage', title: '😈 Sabotage', note: 'Hit an opponent in a challenge.' },
    { key: 'extras',   title: '✨ Extras',   note: 'Titles & name colors for your profile.' }
  ];

  onMount(async () => {
    try { pups = (await getPowerups()).items ?? []; } catch { /* non-fatal */ }
    try { cosmetics = (await getShop()).items ?? []; } catch { /* non-fatal */ }
    loading = false;
  });

  $: ownedPups = pups.filter((/** @type {any} */ i) => (i.owned ?? 0) > 0);
  $: ownedCos = cosmetics.filter((/** @type {any} */ i) => i.owned && (i.kind === 'title' || i.kind === 'color'));
  $: totalCount = ownedPups.reduce((/** @type {number} */ s, /** @type {any} */ i) => s + (i.owned ?? 0), 0) + ownedCos.length;
  /** @param {string} key */
  function itemsFor(key) {
    if (key === 'powerups') return ownedPups.filter((/** @type {any} */ i) => i.kind === 'climb' || i.kind === 'daily');
    if (key === 'sabotage') return ownedPups.filter((/** @type {any} */ i) => i.kind === 'sabotage');
    return ownedCos;
  }
</script>

<div class="inv">
  {#if loading}
    <p class="inv-msg">Loading…</p>
  {:else if totalCount === 0}
    <p class="inv-msg">Nothing yet. Skip the Daily Twist to bank Bounty Boosts, or buy power-ups &amp; extras in the Store.</p>
  {:else}
    <p class="inv-total">{totalCount} item{totalCount === 1 ? '' : 's'} in your bag</p>
    {#each GROUPS as g}
      {@const list = itemsFor(g.key)}
      {#if list.length}
        <div class="inv-h">{g.title}</div>
        <p class="inv-note">{g.note}</p>
        <div class="inv-grid">
          {#each list as it}
            <div class="inv-card">
              {#if it.kind === 'title' || it.kind === 'color'}
                <span class="inv-ic">{it.kind === 'color' ? '🎨' : '👑'}</span>
                {#if it.equipped}<span class="inv-badge">✓</span>{/if}
                <span class="inv-name" style={it.kind === 'color' && it.value ? `color:${it.value}` : ''}>{it.label}</span>
                <span class="inv-desc">{it.equipped ? 'Equipped' : (it.kind === 'color' ? 'Name color' : 'Profile title')}</span>
              {:else}
                <span class="inv-ic">{META[it.id]?.icon ?? '✨'}</span>
                <span class="inv-badge">×{it.owned}</span>
                <span class="inv-name">{it.name}</span>
                <span class="inv-desc">{META[it.id]?.desc ?? ''}</span>
              {/if}
            </div>
          {/each}
        </div>
      {/if}
    {/each}
  {/if}
</div>

<style>
  .inv { width: 100%; }
  .inv-msg { color: var(--text-muted); font-size: 0.9rem; text-align: center; padding: 1.2rem 0.5rem; }
  .inv-total { font-size: 0.8rem; color: var(--text-faint); margin: 0 0 0.6rem; }
  .inv-h { font-family: var(--font-display); font-size: 0.92rem; font-weight: 700; margin: 1.1rem 0 0.1rem; text-align: left; }
  .inv-note { font-size: 0.74rem; color: var(--text-faint); margin: 0 0 0.6rem; }
  .inv-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
  .inv-card { position: relative; display: flex; flex-direction: column; align-items: center; text-align: center; gap: 3px;
    padding: 0.9rem 0.5rem; border-radius: 14px; background: var(--surface); border: 1px solid var(--border); }
  .inv-ic { font-size: 1.7rem; line-height: 1; }
  .inv-badge { position: absolute; top: 7px; right: 9px; font-family: 'Orbitron', var(--font-display); font-weight: 800;
    font-size: 0.78rem; color: #fde047; }
  .inv-name { font-family: var(--font-display); font-weight: 700; font-size: 0.86rem; color: var(--text); }
  .inv-desc { font-size: 0.72rem; line-height: 1.3; color: var(--text-muted); }
</style>
