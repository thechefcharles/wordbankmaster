<script>
  import { createEventDispatcher, onMount } from 'svelte';
  import { tweened } from 'svelte/motion';
  import { cubicOut } from 'svelte/easing';
  import PinPad from '$lib/components/PinPad.svelte';
  import { setPin, verifyPin, tooManyFails, rememberedName } from '$lib/pin.js';
  import { getBank } from '$lib/stores/statsStore.js';
  import { fx } from '$lib/sound.js';

  /** @type {'set'|'unlock'} */
  export let mode = 'unlock';
  export let uid = '';
  /** @type {string|null} */
  export let name = null;
  /** @type {number|null} */
  export let balance = null;

  const dispatch = createEventDispatcher();

  // set-PIN flow
  let step = 'create'; // 'create' | 'confirm'
  let firstPin = '';
  let msg = '';
  let error = false;
  /** @type {any} */
  let pad;

  // vault reveal
  let revealing = false;
  let doorOpen = false;
  const shownBalance = tweened(0, { duration: 1100, easing: cubicOut });

  let displayName = name || rememberedName();

  function flashError(text) {
    msg = text; error = true;
    setTimeout(() => { error = false; pad?.reset(); }, 480);
  }

  /** @param {CustomEvent<string>} e */
  async function onSubmit(e) {
    const pin = e.detail;
    msg = '';
    if (mode === 'set') {
      if (step === 'create') {
        firstPin = pin;
        step = 'confirm';
        pad?.reset();
      } else {
        if (pin === firstPin) {
          await setPin(uid, name, pin);
          fx('win');
          dispatch('pinset');
        } else {
          step = 'create'; firstPin = '';
          flashError('PINs didn’t match — try again.');
        }
      }
      return;
    }
    // unlock
    const ok = await verifyPin(uid, pin);
    if (ok) {
      await openVault();
    } else if (tooManyFails()) {
      msg = 'Too many tries — sign in with your password.';
      setTimeout(() => dispatch('logout'), 900);
    } else {
      flashError('Wrong PIN — try again.');
    }
  }

  async function openVault() {
    revealing = true;
    fx('win');
    // fetch a fresh balance for the reveal if we weren't handed one
    let bal = balance;
    if (bal == null) { try { const b = await getBank(); bal = b?.bank ?? b?.cash ?? 0; } catch { bal = 0; } }
    // door swings, then number spins up
    setTimeout(() => { doorOpen = true; }, 250);
    setTimeout(() => { shownBalance.set(bal ?? 0); }, 900);
  }

  function enter() { dispatch('unlocked'); }
  onMount(() => { /* mode-driven render */ });

  $: title = mode === 'set'
    ? (step === 'create' ? 'Create your PIN' : 'Confirm your PIN')
    : 'Enter your PIN';
  $: sub = mode === 'set'
    ? (step === 'create' ? 'A 4-digit PIN to unlock WordBank fast on this device.' : 'Type it once more to confirm.')
    : (displayName ? `Welcome back, @${displayName}` : 'Welcome back');
</script>

{#if revealing}
  <!-- 🔐 Vault reveal -->
  <div class="vault" class:open={doorOpen} on:click={enter} role="button" tabindex="0"
       on:keydown={(e) => { if (e.key === 'Enter') enter(); }}>
    <div class="vault-stage">
      <div class="reveal">
        <span class="reveal-label">Your balance</span>
        <span class="reveal-amount">${Math.round($shownBalance).toLocaleString()}</span>
        {#if doorOpen}<span class="reveal-go">Tap to enter →</span>{/if}
      </div>
      <div class="door">
        <div class="door-ring"></div>
        <div class="door-dial"><span class="spoke"></span><span class="spoke"></span><span class="spoke"></span></div>
        <img class="door-coin" src="/logo-coin.png" alt="" />
      </div>
    </div>
  </div>
{:else}
  <!-- PIN entry (set or unlock) -->
  <div class="pin-screen">
    <img class="pin-coin" src="/logo-coin.png" alt="" />
    <h2 class="pin-title">{title}</h2>
    <p class="pin-sub">{sub}</p>
    <PinPad bind:this={pad} {error} on:submit={onSubmit} on:change={() => (msg = '')} />
    {#if msg}<p class="pin-msg" class:err={error}>{msg}</p>{/if}
    {#if mode === 'unlock'}
      <button class="pin-forgot" on:click={() => dispatch('logout')}>Forgot PIN? Sign in with password</button>
    {/if}
  </div>
{/if}

<style>
  .pin-screen {
    position: fixed; inset: 0; z-index: 2500; display: flex; flex-direction: column; align-items: center;
    justify-content: flex-start; padding: 8vh 1.2rem 2rem; text-align: center;
    background: radial-gradient(70% 50% at 50% 12%, rgba(251,191,36,0.14), rgba(0,0,0,0) 60%), #070707;
  }
  .pin-coin { width: 84px; height: auto; filter: drop-shadow(0 6px 22px rgba(251,191,36,0.45)); }
  .pin-title { font-family: var(--font-display); font-size: 1.5rem; margin: 0.6rem 0 0.2rem; }
  .pin-sub { color: var(--text-muted); font-size: 0.9rem; margin: 0 0 1.8rem; max-width: 300px; }
  .pin-msg { margin-top: 1rem; font-size: 0.88rem; color: var(--text-muted); }
  .pin-msg.err { color: #f87171; }
  .pin-forgot { margin-top: 1.6rem; background: none; border: none; color: var(--text-faint); font-size: 0.82rem; text-decoration: underline; cursor: pointer; }

  /* ---- vault reveal ---- */
  .vault {
    position: fixed; inset: 0; z-index: 2600; display: grid; place-items: center; cursor: pointer;
    background: radial-gradient(60% 50% at 50% 50%, #14110a, #050505 70%);
    overflow: hidden;
  }
  .vault-stage { position: relative; width: 300px; height: 300px; display: grid; place-items: center; }
  .reveal {
    position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center;
    gap: 6px; opacity: 0; transform: scale(0.9); transition: opacity 0.6s 0.4s, transform 0.6s 0.4s;
  }
  .vault.open .reveal { opacity: 1; transform: scale(1); }
  .reveal-label { font-size: 0.85rem; letter-spacing: 0.18em; text-transform: uppercase; color: #b9962f; }
  .reveal-amount {
    font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 2.6rem; color: #fde047;
    text-shadow: 0 0 18px rgba(251,191,36,0.7), 0 0 40px rgba(251,191,36,0.4);
  }
  .reveal-go { margin-top: 1rem; font-size: 0.82rem; color: var(--text-faint); animation: pulse 1.4s ease-in-out infinite; }
  @keyframes pulse { 0%,100% { opacity: 0.5; } 50% { opacity: 1; } }

  /* the safe door sitting over the reveal, swings/scales away on open */
  .door {
    position: absolute; inset: 0; display: grid; place-items: center; border-radius: 50%;
    background: radial-gradient(circle at 38% 32%, #3a2f12, #1a1407 70%);
    box-shadow: inset 0 0 0 10px rgba(251,191,36,0.15), inset 0 0 60px rgba(0,0,0,0.7), 0 18px 50px rgba(0,0,0,0.7);
    transform-origin: 50% 50%;
    transition: transform 1s cubic-bezier(0.6,0,0.2,1), opacity 0.9s 0.5s;
  }
  .door-ring {
    position: absolute; inset: 20px; border-radius: 50%;
    border: 6px solid rgba(251,191,36,0.45); box-shadow: inset 0 0 24px rgba(251,191,36,0.2);
  }
  .door-dial {
    position: absolute; width: 96px; height: 96px; border-radius: 50%;
    background: radial-gradient(circle at 40% 35%, #fbcf4b, #9a6f12);
    box-shadow: 0 0 0 8px rgba(0,0,0,0.35), 0 6px 14px rgba(0,0,0,0.6);
    transition: transform 1s cubic-bezier(0.5,0,0.2,1);
  }
  .spoke { position: absolute; top: 50%; left: 50%; width: 54px; height: 6px; border-radius: 3px;
    background: linear-gradient(90deg, #7a5a0e, #fde047, #7a5a0e); transform-origin: 0 50%; }
  .spoke:nth-child(1) { transform: translate(-50%,-50%) rotate(0deg); }
  .spoke:nth-child(2) { transform: translate(-50%,-50%) rotate(60deg); }
  .spoke:nth-child(3) { transform: translate(-50%,-50%) rotate(120deg); }
  .door-coin { position: absolute; width: 70px; height: auto; opacity: 0.9; }

  .vault.open .door { transform: rotate(115deg) scale(2.1); opacity: 0; }
  .vault.open .door-dial { transform: rotate(540deg); }
</style>
