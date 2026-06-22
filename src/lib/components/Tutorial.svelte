<script>
  import { createEventDispatcher } from 'svelte';
  import { fx } from '$lib/sound.js';

  const dispatch = createEventDispatcher();

  const steps = [
    {
      icon: '💰',
      title: 'Guess the phrase',
      body: 'Guess the phrase by spending as little as possible. Whatever’s left of your $1,000 is your score.'
    },
    {
      icon: '🔤',
      title: 'Buy letters',
      body: 'Buy a letter by tapping it. If it’s in the phrase, every copy appears. If it’s not, you lose what you paid.'
    },
    {
      icon: '🔍',
      title: 'Reveal',
      body: 'Buy a clue with Reveal. It fills in the most useful letter for you, but it costs money, so save it for when you’re stuck.'
    },
    {
      icon: '🎯',
      title: 'Solve',
      body: 'Solve the phrase by tapping Solve, typing it in, and submitting. You get three tries, and a wrong guess only costs a try, not money.'
    },
    {
      icon: '🏆',
      title: 'Daily & Arcade',
      body: 'Play Daily for one ranked puzzle everyone shares. Play Arcade to keep solving, banking each win and building your multiplier until you bust.'
    },
    {
      icon: '🏦',
      title: 'Your Cash',
      isNew: true,
      body: 'You start with $2,000 Cash. Buy as few letters as you can to solve — spend less, keep more. Your Cash balance is your Net Worth: the score you brag about.'
    },
    {
      icon: '⚔️',
      title: 'Challenge friends',
      isNew: true,
      body: 'Wager your Bank head-to-head on the same puzzle. Score mode: most bankroll left wins. Pressure mode: a 60-second clock, so speed counts. Winner takes the pot.'
    },
    {
      icon: '🛍️',
      title: 'Shop & friends',
      isNew: true,
      body: 'Add friends by @username, then race them on the Net Worth board. Spend your Bank in the Shop on titles and name colors that show off your rank.'
    }
  ];

  let i = 0;
  $: step = steps[i];
  $: last = i === steps.length - 1;

  function next() {
    fx('tap');
    if (last) dispatch('close');
    else i += 1;
  }
  function back() {
    fx('tap');
    if (i > 0) i -= 1;
  }
  function skip() {
    dispatch('close');
  }
</script>

<div class="tut-overlay" role="dialog" aria-modal="true" aria-label="How to play WordBank">
  <div class="tut-card">
    <button class="tut-skip" on:click={skip}>Skip</button>

    {#key i}
      {#if step.isNew}<span class="tut-new">NEW</span>{/if}
      <div class="tut-icon">{step.icon}</div>
      <h2 class="tut-title">{step.title}</h2>
      <p class="tut-body">{step.body}</p>
    {/key}

    <div class="tut-dots">
      {#each steps as _, d}
        <span class="tut-dot" class:active={d === i}></span>
      {/each}
    </div>

    <div class="tut-actions">
      {#if i > 0}
        <button class="tut-btn ghost" on:click={back}>Back</button>
      {/if}
      <button class="tut-btn primary" on:click={next}>{last ? 'Play →' : 'Next'}</button>
    </div>
  </div>
</div>

<style>
  .tut-overlay {
    position: fixed;
    inset: 0;
    z-index: 3000;
    display: grid;
    place-items: center;
    padding: 20px;
    background: rgba(4, 8, 14, 0.72);
    backdrop-filter: blur(8px);
    animation: tutFade 0.25s ease;
  }
  @keyframes tutFade {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  .tut-card {
    position: relative;
    width: 100%;
    max-width: 380px;
    padding: 30px 24px 22px;
    border-radius: var(--r-lg, 20px);
    background: var(--surface-strong, rgba(20, 26, 38, 0.9));
    border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.16));
    box-shadow: var(--shadow-lg, 0 24px 60px rgba(0, 0, 0, 0.5)), var(--glow-brand, 0 0 30px rgba(52, 211, 153, 0.25));
    text-align: center;
    animation: tutPop 0.3s var(--ease-spring, cubic-bezier(0.34, 1.56, 0.64, 1));
  }
  @keyframes tutPop {
    from { transform: translateY(14px) scale(0.96); opacity: 0; }
    to { transform: translateY(0) scale(1); opacity: 1; }
  }

  .tut-skip {
    position: absolute;
    top: 12px;
    right: 14px;
    background: none;
    border: none;
    color: var(--text-muted, #9aa6b8);
    font-family: var(--font-ui, sans-serif);
    font-size: 0.78rem;
    font-weight: 600;
    cursor: pointer;
    padding: 4px 6px;
  }
  .tut-skip:hover { color: var(--text, #fff); }

  .tut-new {
    display: inline-block;
    margin-bottom: 8px;
    padding: 3px 10px;
    border-radius: 999px;
    font-family: var(--font-display, sans-serif);
    font-size: 0.68rem;
    font-weight: 800;
    letter-spacing: 0.08em;
    color: #06210f;
    background: var(--brand-grad, linear-gradient(135deg, #34d399, #a3e635));
  }
  .tut-icon {
    font-size: 3rem;
    line-height: 1;
    margin: 4px 0 14px;
    animation: tutIcon 0.4s var(--ease-spring, cubic-bezier(0.34, 1.56, 0.64, 1));
  }
  @keyframes tutIcon {
    from { transform: scale(0.4) rotate(-12deg); opacity: 0; }
    to { transform: scale(1) rotate(0); opacity: 1; }
  }

  .tut-title {
    font-family: var(--font-display, sans-serif);
    font-size: 1.4rem;
    font-weight: 700;
    margin: 0 0 10px;
    color: var(--text, #fff);
  }
  .tut-body {
    font-family: var(--font-ui, sans-serif);
    font-size: 0.95rem;
    line-height: 1.5;
    color: var(--text-muted, #c2cbd8);
    margin: 0 auto 20px;
    max-width: 320px;
    min-height: 4.5em;
  }

  .tut-dots {
    display: flex;
    justify-content: center;
    gap: 7px;
    margin-bottom: 20px;
  }
  .tut-dot {
    width: 7px;
    height: 7px;
    border-radius: 999px;
    background: var(--border-strong, rgba(255, 255, 255, 0.2));
    transition: all 0.2s ease;
  }
  .tut-dot.active {
    width: 22px;
    background: var(--brand-grad, linear-gradient(135deg, #34d399, #a3e635));
  }

  .tut-actions {
    display: flex;
    gap: 10px;
    justify-content: center;
  }
  .tut-btn {
    flex: 1;
    max-width: 160px;
    height: 46px;
    border-radius: 14px;
    font-family: var(--font-display, sans-serif);
    font-size: 1rem;
    font-weight: 700;
    cursor: pointer;
    transition: transform 0.16s var(--ease-spring, ease), filter 0.2s;
  }
  .tut-btn.primary {
    background: var(--brand-grad, linear-gradient(135deg, #34d399, #a3e635));
    color: #06210f;
    border: none;
    box-shadow: var(--glow-brand, 0 8px 24px rgba(52, 211, 153, 0.35));
  }
  .tut-btn.primary:hover { transform: translateY(-2px); filter: brightness(1.05); }
  .tut-btn.primary:active { transform: scale(0.97); }
  .tut-btn.ghost {
    background: var(--surface-2, rgba(255, 255, 255, 0.06));
    color: var(--text, #fff);
    border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.16));
  }
  .tut-btn.ghost:hover { transform: translateY(-1px); }
  .tut-btn.ghost:active { transform: scale(0.97); }
</style>
