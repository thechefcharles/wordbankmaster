<script>
  import { goto } from '$app/navigation';
  import { toasts, dismissToast } from '$lib/stores/notificationStore.js';
  import { fx } from '$lib/sound.js';

  /** @param {any} t */
  function open(t) {
    fx('select');
    dismissToast(t.id);
    // Challenge toasts (incoming + result) all live in the home Challenges inbox.
    goto('/?challenges=1');
  }
</script>

<div class="toaster" aria-live="polite">
  {#each $toasts as t (t.id)}
    <button class="toast" on:click={() => open(t)}>
      <span class="t-title">{t.title}</span>
      <span class="t-body">{t.body}</span>
      <span class="t-x" role="presentation" on:click|stopPropagation={() => dismissToast(t.id)}>✕</span>
    </button>
  {/each}
</div>

<style>
  .toaster {
    position: fixed;
    top: max(10px, env(safe-area-inset-top));
    left: 50%;
    transform: translateX(-50%);
    z-index: 5000;
    display: flex;
    flex-direction: column;
    gap: 8px;
    width: calc(100% - 24px);
    max-width: 420px;
    pointer-events: none;
  }
  .toast {
    pointer-events: auto;
    position: relative;
    display: flex;
    flex-direction: column;
    gap: 2px;
    text-align: left;
    padding: 12px 34px 12px 14px;
    border-radius: 14px;
    border: 1px solid rgba(253, 224, 71, 0.4);
    background: linear-gradient(135deg, rgba(20, 26, 38, 0.96), rgba(16, 22, 32, 0.96));
    box-shadow: 0 14px 36px rgba(0, 0, 0, 0.45), 0 0 18px rgba(251, 191, 36, 0.18);
    color: var(--text, #fff);
    cursor: pointer;
    backdrop-filter: blur(8px);
    animation: toastIn 0.32s cubic-bezier(0.34, 1.56, 0.64, 1);
  }
  @keyframes toastIn {
    from { transform: translateY(-14px); opacity: 0; }
    to { transform: translateY(0); opacity: 1; }
  }
  .t-title { font-family: var(--font-display, sans-serif); font-weight: 800; font-size: 0.95rem; }
  .t-body { font-size: 0.82rem; color: var(--text-muted, #c2cbd8); }
  .t-x {
    position: absolute;
    top: 8px;
    right: 10px;
    font-size: 0.8rem;
    color: var(--text-faint, #6b7686);
    line-height: 1;
  }
</style>
