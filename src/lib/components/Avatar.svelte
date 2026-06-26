<script>
  import { renderAvatarSvg, renderHoloAvatar } from '$lib/avatar.js';
  /** @type {any} */
  export let config = null;
  export let size = 64;
  /** 'bust' = head + shoulders · 'head' = cropped head circle · 'full' = legacy figure */
  export let mode = 'bust';
  /** render premium FX (frame / aura / headpiece / holographic shirt) */
  export let fx = false;

  $: c = config || {};
  $: useHolo = fx && mode !== 'head' && c.fxShirt === 'holo';
  $: coreSvg = mode === 'head'
    ? renderAvatarSvg(config, { scale: 170, translateY: 18 })
    : (useHolo ? renderHoloAvatar(config) : renderAvatarSvg(config));
  $: frame = fx ? (c.frame || 'none') : 'none';
  $: aura = fx ? (c.aura || 'none') : 'none';
  $: overlay = fx ? (c.overlay || 'none') : 'none';
  $: wrapped = frame !== 'none' || aura !== 'none' || overlay !== 'none';
</script>

{#if wrapped}
  <div class="wb-fx" style="--sz:{size}px" aria-hidden="true">
    {#if aura !== 'none'}<div class="fx-aura aura-{aura}"></div>{/if}
    {#if frame !== 'none'}<div class="fx-ring frame-{frame}"></div>{/if}
    <div class="fx-core">{@html coreSvg}</div>
    {#if overlay !== 'none'}<img class="fx-overlay" src="/avatar/fx/{overlay}.svg" alt="" />{/if}
  </div>
{:else}
  <div class="wb-avatar" style="--sz:{size}px" aria-hidden="true">{@html coreSvg}</div>
{/if}

<style>
  .wb-avatar {
    width: var(--sz); height: var(--sz); border-radius: 50%; overflow: hidden; flex: none;
    background: linear-gradient(135deg, #2a3344, #1b2230);
    border: 2px solid var(--border, rgba(255,255,255,0.15));
  }
  .wb-avatar :global(svg), .fx-core :global(svg) { width: 100%; height: 100%; display: block; }

  .wb-fx { position: relative; width: var(--sz); height: var(--sz); flex: none; }
  .fx-core { position: absolute; inset: 0; z-index: 2; border-radius: 50%; overflow: hidden; background: #0b0f1a; }
  .fx-aura { position: absolute; inset: -22%; border-radius: 50%; z-index: 0; filter: blur(10px); animation: fxpulse 2.6s ease-in-out infinite; }
  .aura-neon { background: radial-gradient(circle, rgba(124,255,107,0.5), rgba(92,208,255,0.35) 45%, transparent 70%); }
  .aura-gold { background: radial-gradient(circle, rgba(255,210,74,0.6), rgba(255,140,0,0.35) 45%, transparent 70%); }
  .fx-ring { position: absolute; inset: -6%; border-radius: 50%; z-index: 1; animation: fxspin 4s linear infinite; }
  .frame-neon { background: conic-gradient(from 0deg, #ff5cf0, #5cd0ff, #7cff6b, #ffe45c, #ff5cf0); box-shadow: 0 0 18px rgba(124,255,107,0.5); }
  .frame-gold { background: conic-gradient(from 0deg, #fff0a8, #ffd24a, #d99100, #ffd24a, #fff0a8); box-shadow: 0 0 16px rgba(255,210,74,0.55); }
  .frame-gem { background: conic-gradient(from 0deg, #c4b5fd, #5cd0ff, #ff88e0, #7cff6b, #c4b5fd); box-shadow: 0 0 20px rgba(196,181,253,0.6); }
  .fx-overlay { position: absolute; z-index: 3; top: -10%; left: 50%; transform: translateX(-50%); width: 58%;
    filter: drop-shadow(0 2px 4px rgba(0,0,0,0.5)); animation: fxfloat 2.4s ease-in-out infinite; }

  @keyframes fxspin { to { transform: rotate(360deg); } }
  @keyframes fxpulse { 0%, 100% { opacity: 0.6; transform: scale(0.96); } 50% { opacity: 1; transform: scale(1.04); } }
  @keyframes fxfloat { 0%, 100% { transform: translateX(-50%) translateY(0); } 50% { transform: translateX(-50%) translateY(-3px); } }
</style>
