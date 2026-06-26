<script>
  import { renderAvatarSvg } from '$lib/avatar.js';
  /** @type {any} */
  export let config = null;
  export let size = 64;
  $: svg = renderAvatarSvg(config);
</script>

<div class="wb-avatar" style="--sz:{size}px" aria-hidden="true">
  {@html svg}
</div>

<style>
  .wb-avatar {
    width: var(--sz); height: var(--sz); border-radius: 50%; overflow: hidden; flex: none;
    background: linear-gradient(135deg, #2a3344, #1b2230);
    border: 2px solid var(--border, rgba(255,255,255,0.15));
  }
  .wb-avatar :global(svg) { width: 100%; height: 100%; display: block; }
</style>
