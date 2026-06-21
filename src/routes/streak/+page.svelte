<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { getStreakOverview } from '$lib/stores/statsStore.js';
  import { track } from '$lib/analytics.js';

  /** @type {{ current_streak:number, highest_streak:number, freezes:number, days:{d:string,won:boolean}[] }|null} */
  let ov = null;
  let loading = true;

  onMount(async () => {
    track('streak_view');
    try { ov = await getStreakOverview(); }
    finally { loading = false; }
  });

  // Motivational line (Duolingo-style).
  $: nudge = (() => {
    if (!ov) return '';
    const c = ov.current_streak, h = ov.highest_streak;
    if (c === 0) return 'Win today’s Daily to start a streak!';
    if (c >= h) return 'You’re on your longest streak ever — keep it alive!';
    const away = (h + 1) - c;
    return `You’re ${away} day${away === 1 ? '' : 's'} from a new personal best (${h}).`;
  })();

  // ---- Current-month calendar heatmap ----
  const WD = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
  const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December'];
  const now = new Date();
  const year = now.getFullYear(), month = now.getMonth(), todayDate = now.getDate();
  const pad = (/** @type {number} */ n) => String(n).padStart(2, '0');

  /** @type {Map<string, boolean>} date 'YYYY-MM-DD' -> won */
  $: dayMap = (() => {
    const m = new Map();
    for (const e of ov?.days ?? []) m.set(String(e.d).slice(0, 10), !!e.won);
    return m;
  })();

  // grid cells: leading blanks for the first weekday, then each day with a status
  $: cells = (() => {
    const firstWeekday = new Date(year, month, 1).getDay();
    const daysInMonth = new Date(year, month + 1, 0).getDate();
    /** @type {{blank?:boolean, day?:number, status?:string, isToday?:boolean}[]} */
    const out = [];
    for (let i = 0; i < firstWeekday; i++) out.push({ blank: true });
    for (let d = 1; d <= daysInMonth; d++) {
      const key = `${year}-${pad(month + 1)}-${pad(d)}`;
      let status = 'none';
      if (d > todayDate) status = 'future';
      else if (dayMap.has(key)) status = dayMap.get(key) ? 'won' : 'lost';
      out.push({ day: d, status, isToday: d === todayDate });
    }
    return out;
  })();
</script>

<svelte:head><title>WordBank — Streak</title></svelte:head>

<main class="streak-page">
  <button class="back-btn" on:click={() => goto('/')}>← Menu</button>

  {#if loading}
    <p class="loading">Loading…</p>
  {:else}
    <div class="hero">
      <div class="flame" class:lit={ov && ov.current_streak > 0}>🔥</div>
      <div class="count">{ov?.current_streak ?? 0}</div>
      <div class="count-label">day streak</div>
    </div>

    {#if nudge}<p class="nudge">{nudge}</p>{/if}

    <div class="stat-row">
      <div class="stat"><span class="sv">{ov?.highest_streak ?? 0}</span><span class="sc">Longest</span></div>
      <div class="stat"><span class="sv">❄️ {ov?.freezes ?? 0}</span><span class="sc">Freezes</span></div>
      <div class="stat"><span class="sv">{dayMap.size}</span><span class="sc">Days played</span></div>
    </div>

    <div class="cal">
      <h2 class="cal-title">{MONTHS[month]} {year}</h2>
      <div class="cal-grid">
        {#each WD as w}<div class="wd">{w}</div>{/each}
        {#each cells as c}
          {#if c.blank}
            <div class="cell blank"></div>
          {:else}
            <div class="cell {c.status}" class:today={c.isToday} title={`${MONTHS[month]} ${c.day}`}>
              {#if c.status === 'won'}🔥{:else}{c.day}{/if}
            </div>
          {/if}
        {/each}
      </div>
      <div class="legend">
        <span><i class="dot won"></i> Won</span>
        <span><i class="dot lost"></i> Missed</span>
        <span><i class="dot none"></i> No play</span>
      </div>
    </div>
  {/if}
</main>

<style>
  .streak-page { max-width: 460px; margin: 0 auto; padding: 1.5rem 1rem 3rem; text-align: center; }
  .back-btn {
    display: inline-block; margin-bottom: 1.2rem; padding: 0.55rem 1.1rem;
    background: var(--surface); color: var(--text); border: 1px solid var(--border);
    border-radius: var(--r-md, 12px); cursor: pointer; font-weight: 600; font-size: 0.9rem;
  }
  .loading { color: var(--text-muted); padding: 2rem; }

  .hero { display: flex; flex-direction: column; align-items: center; gap: 2px; margin-top: 0.5rem; }
  .flame { font-size: 4.2rem; line-height: 1; filter: grayscale(1) opacity(0.4); }
  .flame.lit { filter: none; animation: flamePulse 2.2s ease-in-out infinite; }
  @keyframes flamePulse { 0%,100% { transform: scale(1); } 50% { transform: scale(1.08); } }
  .count { font-family: var(--font-display); font-weight: 800; font-size: 3.4rem; line-height: 1; color: var(--brand-2); }
  .count-label { color: var(--text-muted); font-size: 0.95rem; text-transform: uppercase; letter-spacing: 0.06em; }

  .nudge {
    margin: 1.1rem auto 0; max-width: 340px; padding: 0.8rem 1rem;
    background: rgba(251, 191, 36, 0.1); border: 1px solid rgba(251, 191, 36, 0.35);
    border-radius: 14px; color: #fcd34d; font-weight: 600; font-size: 0.95rem;
  }

  .stat-row { display: flex; justify-content: center; gap: 0.6rem; margin: 1.4rem 0 0.5rem; }
  .stat {
    flex: 1; max-width: 120px; display: flex; flex-direction: column; align-items: center; gap: 3px;
    padding: 0.7rem 0.4rem; background: var(--surface); border: 1px solid var(--border); border-radius: 14px;
  }
  .sv { font-family: var(--font-display); font-weight: 700; font-size: 1.2rem; color: var(--text); }
  .sc { font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.05em; color: var(--text-faint); }

  .cal { margin-top: 1.8rem; }
  .cal-title { font-family: var(--font-display); font-size: 1.05rem; margin: 0 0 0.8rem; }
  .cal-grid { display: grid; grid-template-columns: repeat(7, 1fr); gap: 6px; }
  .wd { font-size: 0.7rem; color: var(--text-faint); padding-bottom: 2px; }
  .cell {
    aspect-ratio: 1; display: grid; place-items: center; border-radius: 9px;
    font-size: 0.8rem; font-weight: 600; color: var(--text-muted);
    background: rgba(255,255,255,0.03); border: 1px solid var(--border);
  }
  .cell.blank { background: none; border: none; }
  .cell.won { background: var(--brand-grad, linear-gradient(135deg,#34d399,#a3e635)); border-color: transparent; color: #06210f; }
  .cell.lost { background: rgba(251, 113, 133, 0.12); border-color: rgba(251,113,133,0.3); color: #fb7185; }
  .cell.none { color: var(--text-faint); }
  .cell.future { opacity: 0.3; }
  .cell.today { box-shadow: 0 0 0 2px var(--brand-2); }

  .legend { display: flex; justify-content: center; gap: 1rem; margin-top: 1rem; font-size: 0.75rem; color: var(--text-faint); }
  .legend span { display: inline-flex; align-items: center; gap: 5px; }
  .dot { width: 11px; height: 11px; border-radius: 4px; display: inline-block; }
  .dot.won { background: linear-gradient(135deg,#34d399,#a3e635); }
  .dot.lost { background: rgba(251,113,133,0.4); }
  .dot.none { background: rgba(255,255,255,0.08); border: 1px solid var(--border); }
</style>
