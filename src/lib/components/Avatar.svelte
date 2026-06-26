<script>
  import { renderAvatarSvg } from '$lib/avatar.js';
  /** @type {any} */
  export let config = null;
  export let size = 64;
  /** 'bust' = head + shoulders · 'head' = cropped head circle · 'full' = standing figure */
  export let mode = 'bust';

  $: pants = '#3a3f4b';
  $: shoes = '#22252c';
  $: headSvg = mode === 'head' ? renderAvatarSvg(config, { scale: 170, translateY: 18 }) : '';
  $: bustSvg = mode !== 'head' ? renderAvatarSvg(config) : '';
</script>

{#if mode === 'head'}
  <div class="wb-avatar" style="--sz:{size}px" aria-hidden="true">{@html headSvg}</div>
{:else if mode === 'full'}
  <div class="wb-avatar-full" style="--w:{size}px" aria-hidden="true">
    <div class="avf-bust">{@html bustSvg}</div>
    <svg class="avf-legs" viewBox="0 0 280 116" xmlns="http://www.w3.org/2000/svg">
      <rect x="94" y="0" width="42" height="80" rx="20" fill={pants} />
      <rect x="144" y="0" width="42" height="80" rx="20" fill={pants} />
      <rect x="82" y="72" width="58" height="34" rx="16" fill={shoes} />
      <rect x="140" y="72" width="58" height="34" rx="16" fill={shoes} />
    </svg>
  </div>
{:else}
  <div class="wb-avatar" style="--sz:{size}px" aria-hidden="true">{@html bustSvg}</div>
{/if}

<style>
  .wb-avatar {
    width: var(--sz); height: var(--sz); border-radius: 50%; overflow: hidden; flex: none;
    background: linear-gradient(135deg, #2a3344, #1b2230);
    border: 2px solid var(--border, rgba(255,255,255,0.15));
  }
  .wb-avatar :global(svg) { width: 100%; height: 100%; display: block; }

  /* full standing figure: avataaars bust over drawn legs + shoes */
  .wb-avatar-full { width: var(--w); flex: none; display: flex; flex-direction: column; align-items: center; }
  .avf-bust { width: 100%; position: relative; z-index: 1; }
  .avf-bust :global(svg) { width: 100%; display: block; }
  .avf-legs { width: 84%; margin-top: -13%; display: block; z-index: 0; }
</style>
