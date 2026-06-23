<script>
  import { onMount } from 'svelte';
  import { getCategoryStats, getUserBadges } from '$lib/stores/statsStore.js';
  import { CATEGORIES } from '$lib/categories.js';
  import { categoryProgress, SOLVE_MILESTONES, COLLECTOR } from '$lib/categoryBadges.js';
  import { BADGES, badgeInfo } from '$lib/badges.js';

  /** @type {{category: string, solves: number}[]} */
  let categoryStats = $state([]);
  /** @type {string[]} */
  let earnedBadges = $state([]);
  let loaded = $state(false);

  onMount(async () => {
    const [stats, earned] = await Promise.all([getCategoryStats(), getUserBadges()]);
    categoryStats = stats;
    earnedBadges = earned;
    loaded = true;
  });

  let solvesByCat = $derived(Object.fromEntries(categoryStats.map((r) => [r.category, r.solves])));
  let total = $derived(categoryStats.reduce((n, r) => n + (r.solves || 0), 0));
  let rows = $derived(CATEGORIES.map((c) => ({ ...c, ...categoryProgress(solvesByCat[c.value] ?? 0) })));
  let goldCount = $derived(rows.filter((r) => (r.solves ?? 0) >= 25).length);
  let achievements = $derived([
    ...Object.keys(BADGES).map((id) => ({ ...badgeInfo(id), earned: earnedBadges.includes(id) })),
    ...SOLVE_MILESTONES.map((m) => ({ emoji: m.emoji, name: m.name, desc: m.desc, earned: total >= m.at })),
    { emoji: COLLECTOR.emoji, name: COLLECTOR.name, desc: COLLECTOR.desc, earned: goldCount >= 12 }
  ]);
</script>

<div class="bp">
  <p class="badges-total">{total} {total === 1 ? 'puzzle' : 'puzzles'} solved all-time</p>

  <p class="bm-section-title">Category Levels</p>
  <div class="bm-cats">
    {#each rows as r (r.value)}
      <div class="bm-cat">
        <span class="bm-cat-emoji">{r.emoji}</span>
        <div class="bm-cat-body">
          <div class="bm-cat-top">
            <span class="bm-cat-name">{r.label}</span>
            <span class="bm-cat-tier">{r.current ? r.current.medal + ' ' + r.current.name : '—'}</span>
          </div>
          <div class="bm-bar"><div class="bm-bar-fill" style="width:{Math.round(r.progress * 100)}%"></div></div>
          <span class="bm-cat-sub">
            {#if r.next}{r.toNext} more → {r.next.medal} {r.next.name}{:else}Maxed out 💎 · {r.solves} solved{/if}
          </span>
        </div>
      </div>
    {/each}
  </div>

  <p class="bm-section-title">Achievements</p>
  <div class="bm-ach-grid">
    {#each achievements as a}
      <div class="bm-ach {a.earned ? 'earned' : 'locked'}" title={a.desc}>
        <span class="bm-ach-emoji">{a.emoji}</span>
        <span class="bm-ach-name">{a.name}</span>
        <span class="bm-ach-desc">{a.desc}</span>
      </div>
    {/each}
  </div>

  {#if !loaded}<p class="bm-loading">Loading…</p>{/if}
</div>

<style>
  .badges-total { font-size: 0.9rem; color: var(--text-muted); margin: 0 0 14px; text-align: center; }
  .bm-section-title {
    font-family: var(--font-display); font-weight: 700; font-size: 0.7rem; letter-spacing: 0.14em;
    text-transform: uppercase; color: var(--brand-2, #fde047); text-align: left; margin: 22px 0 10px;
  }
  .bm-cats { display: flex; flex-direction: column; gap: 10px; }
  .bm-cat { display: flex; align-items: center; gap: 12px; text-align: left; padding: 10px 12px;
    border-radius: var(--r-md, 12px); background: var(--surface, rgba(255, 255, 255, 0.05)); border: 1px solid var(--border, rgba(255, 255, 255, 0.1)); }
  .bm-cat-emoji { font-size: 1.5rem; line-height: 1; }
  .bm-cat-body { flex: 1; min-width: 0; }
  .bm-cat-top { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; }
  .bm-cat-name { font-family: var(--font-display); font-weight: 600; font-size: 0.9rem; }
  .bm-cat-tier { font-family: var(--font-display); font-weight: 700; font-size: 0.78rem; color: #fcd34d; white-space: nowrap; }
  .bm-bar { height: 6px; border-radius: 999px; background: var(--border, rgba(255, 255, 255, 0.12)); margin: 6px 0 4px; overflow: hidden; }
  .bm-bar-fill { height: 100%; border-radius: 999px; background: var(--brand-grad, linear-gradient(90deg, #fbbf24, #fde047)); transition: width 0.4s var(--ease-spring, ease); }
  .bm-cat-sub { font-family: var(--font-ui); font-size: 0.72rem; color: var(--text-muted); }

  .bm-ach-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 8px; }
  .bm-ach { display: flex; flex-direction: column; align-items: center; gap: 3px; text-align: center; padding: 12px 8px;
    border-radius: var(--r-md, 12px); background: var(--surface, rgba(255, 255, 255, 0.05)); border: 1px solid var(--border, rgba(255, 255, 255, 0.1)); }
  .bm-ach.earned { border-color: rgba(253, 224, 71, 0.45); box-shadow: 0 0 14px rgba(251, 191, 36, 0.14); }
  .bm-ach.locked { opacity: 0.45; filter: grayscale(0.7); }
  .bm-ach-emoji { font-size: 1.5rem; line-height: 1; }
  .bm-ach-name { font-family: var(--font-display); font-weight: 700; font-size: 0.78rem; }
  .bm-ach-desc { font-family: var(--font-ui); font-size: 0.66rem; color: var(--text-muted); line-height: 1.2; }
  .bm-loading { color: var(--text-muted); font-size: 0.85rem; }
</style>
