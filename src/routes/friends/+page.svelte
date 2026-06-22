<script>
  import { goto } from '$app/navigation';
</script>

<svelte:head><title>WordBank — Friends</title></svelte:head>

<main class="friends-page">
  <button class="back-btn" onclick={() => goto('/')}>← Menu</button>

  <div class="head">
    <h1>👥 Friends</h1>
  </div>

  <div class="soon">
    <span class="soon-ic">🚧</span>
    <p class="soon-t">Friends are almost here</p>
    <p class="soon-d">Soon you'll search players, send friend requests, and challenge friends to cash matches. Add friends to build groups too — no codes needed.</p>
  </div>
</main>

<style>
  .friends-page { max-width: 480px; margin: 0 auto; padding: 1.5rem 1rem 3rem; }
  .back-btn {
    display: inline-block; margin-bottom: 1.2rem; padding: 0.55rem 1.1rem;
    background: var(--surface); color: var(--text); border: 1px solid var(--border);
    border-radius: 12px; cursor: pointer; font-weight: 600; font-size: 0.9rem;
  }
  .head h1 { font-family: var(--font-display); font-size: 1.7rem; margin: 0 0 1.4rem; }
  .soon {
    text-align: center; padding: 2.4rem 1.4rem; border: 1px solid var(--border);
    border-radius: 18px; background: var(--surface);
  }
  .soon-ic { font-size: 2.4rem; }
  .soon-t { font-family: var(--font-display); font-weight: 800; font-size: 1.15rem; margin: 0.6rem 0 0.3rem; }
  .soon-d { color: var(--text-muted); font-size: 0.9rem; line-height: 1.5; margin: 0; }
</style>
