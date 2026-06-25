<script>
  // 🎒 Your owned power-ups, grouped by where you use them. Self-fetching so it can
  // drop into the Store, Profile, or anywhere. Power-ups are spent in-game (the
  // Daily hotbar / Cash Game / challenges) — this is the "what do I have" view.
  import { onMount } from 'svelte';
  import { getPowerups } from '$lib/stores/statsStore.js';

  /** @type {any[]} */
  let items = [];
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
    { kind: 'daily', title: '💥 Bounty Boosts', note: 'Tap in the Daily to grow your bounty multiplier.' },
    { kind: 'climb', title: '⚡ Power-ups', note: 'Use in the Cash Game or a challenge.' },
    { kind: 'sabotage', title: '😈 Sabotage', note: 'Hit an opponent in a challenge.' }
  ];

  onMount(async () => {
    try { items = (await getPowerups()).items ?? []; } finally { loading = false; }
  });

  $: owned = items.filter((/** @type {any} */ i) => (i.owned ?? 0) > 0);
  $: totalCount = owned.reduce((/** @type {number} */ s, /** @type {any} */ i) => s + (i.owned ?? 0), 0);
  /** @param {string} kind */
  const inGroup = (kind) => owned.filter((/** @type {any} */ i) => i.kind === kind);
</script>

<div class="inv">
  {#if loading}
    <p class="inv-msg">Loading…</p>
  {:else if owned.length === 0}
    <p class="inv-msg">No items yet. Skip the Daily Twist to bank Bounty Boosts, or buy power-ups in the Store.</p>
  {:else}
    <p class="inv-total">{totalCount} item{totalCount === 1 ? '' : 's'} in your bag</p>
    {#each GROUPS as g}
      {@const list = inGroup(g.kind)}
      {#if list.length}
        <div class="inv-h">{g.title}</div>
        <p class="inv-note">{g.note}</p>
        <div class="inv-grid">
          {#each list as it}
            <div class="inv-card">
              <span class="inv-ic">{META[it.id]?.icon ?? '✨'}</span>
              <span class="inv-count">×{it.owned}</span>
              <span class="inv-name">{it.name}</span>
              <span class="inv-desc">{META[it.id]?.desc ?? ''}</span>
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
  .inv-count { position: absolute; top: 7px; right: 9px; font-family: 'Orbitron', var(--font-display); font-weight: 800;
    font-size: 0.78rem; color: #fde047; }
  .inv-name { font-family: var(--font-display); font-weight: 700; font-size: 0.86rem; color: var(--text); }
  .inv-desc { font-size: 0.72rem; line-height: 1.3; color: var(--text-muted); }
</style>
