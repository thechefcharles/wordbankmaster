<script>
  // Pre-game "How to win" card. Shown the moment a mode starts so a first-time
  // player always knows the objective. Solo modes show it once (the parent gates
  // on localStorage); challenges show it every entry (they carry the stakes).
  import { createEventDispatcher } from 'svelte';
  const dispatch = createEventDispatcher();

  /** @type {string} */ export let mode;
  /** @type {{ opponent?: string, wager?: number, packSize?: number, fieldSize?: number }} */
  export let ctx = {};

  /** @param {string} m @param {any} c */
  function content(m, c) {
    const pk = (c.packSize ?? 1) > 1 ? `${c.packSize} puzzles` : 'the puzzle';
    const w = c.wager ? `$${Number(c.wager).toLocaleString()}` : null;
    switch (m) {
      case 'daily': return { icon: '📅', title: "Today's Daily",
        goal: 'Solve the hidden phrase.',
        win: 'Spend as little Cash as you can — your leftover is your score.',
        bar: 'Just showing up pays a streak reward.' };
      case 'climb': return { icon: '🧗', title: 'Cash Game',
        goal: 'Climb an endless ladder of puzzles.',
        win: 'Solve each one cheaply to grow your bankroll.',
        bar: "Don't go broke." };
      case 'arcade': return { icon: '🎲', title: 'Arcade Run',
        goal: 'Survival mode — keep your streak alive.',
        win: 'The bigger your streak, the bigger the payout.',
        bar: 'One slip ends the run.' };
      case 'freeplay': return { icon: '🎯', title: 'Free Play',
        goal: 'Practice with zero stakes.',
        win: 'Every solve pays a little Cash.',
        bar: 'Grind back anytime.' };
      case 'makeup': return { icon: '🗓️', title: 'Make-up Daily',
        goal: 'Play a daily you missed.',
        win: 'Same rules — solve it as cheaply as you can.',
        bar: 'Counts toward your stats.' };
      case 'match': {
        if ((c.fieldSize ?? 2) > 2) return { icon: '👥', title: 'Group Challenge',
          goal: `Solve ${pk} spending as little as possible.`,
          win: 'Least spent to solve ranks 1st — the pot is everyone’s spend.',
          bar: w ? `Your ${w} buy-in is your cap. Unspent Cash comes back.`
                 : 'Unspent Cash comes back — you only lose what you spend.' };
        return { icon: '⚔️', title: c.opponent ? `Duel vs @${c.opponent}` : 'Challenge',
          goal: `Solve ${pk} — then it comes down to who spent less.`,
          win: 'Whoever solves spending the LEAST wins the pot.',
          bar: w ? `Your ${w} buy-in is your cap. Unspent Cash comes back — you only lose what you spend.`
                 : 'Unspent Cash comes back — you only lose what you spend.' };
      }
      default: return { icon: '🎯', title: 'WordBank',
        goal: 'Solve the hidden phrase.', win: 'Spend as little as you can.', bar: '' };
    }
  }

  $: c = content(mode, ctx);
  function go() { dispatch('close'); }
</script>

<div class="obj-overlay" role="dialog" aria-modal="true" aria-label="How to win">
  <div class="obj-card">
    <span class="obj-pill">🎯 How to win</span>
    <div class="obj-icon">{c.icon}</div>
    <h2 class="obj-title">{c.title}</h2>

    <p class="obj-goal">{c.goal}</p>
    <div class="obj-win"><span class="obj-win-key">WIN</span>{c.win}</div>
    {#if c.bar}<p class="obj-bar">{c.bar}</p>{/if}

    <button class="obj-btn" on:click={go}>Let’s go →</button>
  </div>
</div>

<style>
  .obj-overlay {
    position: fixed; inset: 0; z-index: 3100;
    display: grid; place-items: center; padding: 20px;
    background: rgba(4, 8, 14, 0.72); backdrop-filter: blur(8px);
    animation: objFade 0.22s ease;
  }
  @keyframes objFade { from { opacity: 0; } to { opacity: 1; } }

  .obj-card {
    position: relative; width: 100%; max-width: 380px;
    padding: 26px 24px 22px; border-radius: var(--r-lg, 20px);
    background: var(--surface-strong, rgba(20, 26, 38, 0.92));
    border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.16));
    box-shadow: var(--shadow-lg, 0 24px 60px rgba(0, 0, 0, 0.5)), var(--glow-brand, 0 0 30px rgba(251, 191, 36, 0.25));
    text-align: center;
    animation: objPop 0.3s var(--ease-spring, cubic-bezier(0.34, 1.56, 0.64, 1));
  }
  @keyframes objPop {
    from { transform: translateY(14px) scale(0.96); opacity: 0; }
    to { transform: translateY(0) scale(1); opacity: 1; }
  }

  .obj-pill {
    display: inline-block; margin-bottom: 10px; padding: 4px 12px; border-radius: 999px;
    font-family: var(--font-display, sans-serif); font-size: 0.68rem; font-weight: 800;
    letter-spacing: 0.08em; color: #3a2a00;
    background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
  }
  .obj-icon {
    font-size: 2.8rem; line-height: 1; margin: 2px 0 10px;
    animation: objIcon 0.4s var(--ease-spring, cubic-bezier(0.34, 1.56, 0.64, 1));
  }
  @keyframes objIcon {
    from { transform: scale(0.4) rotate(-12deg); opacity: 0; }
    to { transform: scale(1) rotate(0); opacity: 1; }
  }
  .obj-title {
    font-family: var(--font-display, sans-serif); font-size: 1.35rem; font-weight: 700;
    margin: 0 0 12px; color: var(--text, #fff);
  }
  .obj-goal {
    font-family: var(--font-ui, sans-serif); font-size: 0.96rem; line-height: 1.45;
    color: var(--text, #f3f6fb); margin: 0 auto 12px; max-width: 320px;
  }
  .obj-win {
    display: flex; align-items: center; gap: 10px; text-align: left;
    margin: 0 auto 12px; max-width: 320px; padding: 11px 13px;
    border-radius: 13px; border: 1px solid rgba(253, 224, 71, 0.45);
    background: linear-gradient(135deg, rgba(251, 191, 36, 0.14), rgba(251, 191, 36, 0.05));
    font-family: var(--font-ui, sans-serif); font-size: 0.92rem; line-height: 1.4;
    color: var(--text, #fff); font-weight: 600;
  }
  .obj-win-key {
    flex: none; font-family: var(--font-display, sans-serif); font-size: 0.6rem; font-weight: 800;
    letter-spacing: 0.1em; color: #3a2a00; padding: 3px 7px; border-radius: 7px;
    background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
  }
  .obj-bar {
    font-family: var(--font-ui, sans-serif); font-size: 0.82rem; line-height: 1.4;
    color: var(--text-muted, #aeb8c6); margin: 0 auto 18px; max-width: 320px;
  }

  .obj-btn {
    width: 100%; max-width: 220px; height: 48px; border: none; border-radius: 14px;
    font-family: var(--font-display, sans-serif); font-size: 1.05rem; font-weight: 700;
    color: #3a2a00; cursor: pointer;
    background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
    box-shadow: var(--glow-brand, 0 8px 24px rgba(251, 191, 36, 0.35));
    transition: transform 0.16s var(--ease-spring, ease), filter 0.2s;
  }
  .obj-btn:hover { transform: translateY(-2px); filter: brightness(1.05); }
  .obj-btn:active { transform: scale(0.97); }
</style>
