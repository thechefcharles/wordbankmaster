<script>
  import { goto } from '$app/navigation';
  import { browser } from '$app/environment';
  /** Where "home" goes (and the back fallback when there's no history). */
  export let home = '/';
  function back() {
    if (browser && window.history.length > 1) window.history.back();
    else goto(home);
  }
</script>

<nav class="page-nav">
  <button class="pn-btn" on:click={back} aria-label="Back">← Back</button>
  <button class="pn-home" on:click={() => goto(home)} aria-label="Main menu" title="Main menu">🏠</button>
</nav>

<style>
  .page-nav { display: flex; align-items: center; justify-content: space-between; gap: 10px; margin-bottom: 14px; }
  .pn-btn, .pn-home { background: var(--surface); color: var(--text); border: 1px solid var(--border); border-radius: 12px; cursor: pointer; font-weight: 600; }
  .pn-btn { padding: 0.5rem 1rem; font-size: 0.9rem; }
  .pn-home { width: 42px; height: 38px; display: grid; place-items: center; font-size: 1.1rem; }
  .pn-btn:hover, .pn-home:hover { border-color: var(--brand-2); }
  .pn-btn:active, .pn-home:active { transform: scale(0.97); }
</style>
