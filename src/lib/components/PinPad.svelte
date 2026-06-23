<script>
  import { createEventDispatcher } from 'svelte';
  import { fx } from '$lib/sound.js';

  export let length = 4;
  export let error = false; // parent sets true to flash/shake

  const dispatch = createEventDispatcher();
  let digits = '';

  export function reset() { digits = ''; }

  /** @param {string} d */
  function press(d) {
    if (digits.length >= length) return;
    digits += d;
    fx('tap');
    dispatch('change', digits);
    if (digits.length === length) dispatch('submit', digits);
  }
  function backspace() { if (digits.length) { digits = digits.slice(0, -1); fx('tap'); dispatch('change', digits); } }
  function clearAll() { digits = ''; fx('tap'); dispatch('change', digits); }
  function enter() { if (digits.length === length) dispatch('submit', digits); }
</script>

<div class="pinpad" class:error>
  <!-- entered-digit dots -->
  <div class="dots">
    {#each Array(length) as _, i}
      <span class="dot" class:filled={i < digits.length}></span>
    {/each}
  </div>

  <div class="keys">
    <button class="key num" on:click={() => press('1')}>1</button>
    <button class="key num" on:click={() => press('2')}>2</button>
    <button class="key num" on:click={() => press('3')}>3</button>
    <button class="key act cancel" on:click={clearAll} aria-label="Cancel">✕</button>

    <button class="key num" on:click={() => press('4')}>4</button>
    <button class="key num" on:click={() => press('5')}>5</button>
    <button class="key num" on:click={() => press('6')}>6</button>
    <button class="key act clear" on:click={backspace} aria-label="Delete">⌫</button>

    <button class="key num" on:click={() => press('7')}>7</button>
    <button class="key num" on:click={() => press('8')}>8</button>
    <button class="key num" on:click={() => press('9')}>9</button>
    <button class="key act enter" on:click={enter} aria-label="Enter">⏎</button>

    <button class="key num zero" on:click={() => press('0')}>0</button>
  </div>
</div>

<style>
  .pinpad { width: 100%; max-width: 320px; margin: 0 auto; }
  .dots { display: flex; justify-content: center; gap: 16px; margin-bottom: 22px; }
  .dot {
    width: 15px; height: 15px; border-radius: 50%;
    border: 2px solid rgba(251, 191, 36, 0.5); background: transparent;
    transition: transform 0.12s, background 0.15s, box-shadow 0.15s;
  }
  .dot.filled {
    background: #fde047; border-color: #fde047;
    box-shadow: 0 0 10px rgba(251, 191, 36, 0.8); transform: scale(1.08);
  }
  .pinpad.error .dots { animation: shake 0.4s; }
  .pinpad.error .dot { border-color: #f87171; }
  @keyframes shake {
    0%,100% { transform: translateX(0); }
    20%,60% { transform: translateX(-8px); }
    40%,80% { transform: translateX(8px); }
  }

  .keys { display: grid; grid-template-columns: repeat(4, 1fr); gap: 9px; }
  .key {
    height: 56px; border-radius: 12px; cursor: pointer; position: relative;
    font-family: 'Orbitron', var(--font-display); font-weight: 700; font-size: 22px;
    border: 1px solid rgba(251, 191, 36, 0.3);
    background: linear-gradient(160deg, #1c1f28, #0c0e13);
    color: #f4e7c6;
    box-shadow: inset 0 1px 0 rgba(255,255,255,0.06), 0 2px 0 rgba(0,0,0,0.6), 0 4px 8px rgba(0,0,0,0.5);
    transition: transform 0.1s, box-shadow 0.12s, border-color 0.15s;
  }
  .key:active {
    transform: translateY(1px) scale(0.97);
    border-color: #fde047;
    box-shadow: 0 0 0 2px rgba(253,224,71,1), 0 0 16px rgba(251,191,36,0.9), 0 0 34px rgba(251,191,36,0.6);
  }
  .key.zero { grid-column: 1 / 4; }
  /* ATM colored action keys */
  .key.act { font-size: 18px; }
  .key.cancel { background: linear-gradient(160deg, #f0584a, #b5311f); color: #fff; border-color: #b5311f; }
  .key.clear  { background: linear-gradient(160deg, #f6c945, #c98f12); color: #2a2000; border-color: #c98f12; }
  .key.enter  { background: linear-gradient(160deg, #46d07e, #1f9b4e); color: #3a2a00; border-color: #1f9b4e; }
</style>
