<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { getProfileStats } from '$lib/stores/statsStore.js';
  import { badgeInfo } from '$lib/badges.js';
  import { track } from '$lib/analytics.js';

  /** @type {any|null} */
  let s = $state(null);
  let loading = $state(true);

  onMount(async () => { track('profile_view'); try { s = await getProfileStats(); } finally { loading = false; } });

  const fmt = (/** @type {any} */ n) => '$' + Math.round(Number(n ?? 0)).toLocaleString();
  let winPct = $derived(s && s.games_played > 0 ? Math.round((s.games_won / s.games_played) * 100) : 0);
</script>

<svelte:head><title>WordBank — Profile</title></svelte:head>

<main class="profile-page">
  <button class="back-btn" onclick={() => goto('/')}>← Menu</button>

  {#if loading}
    <p class="muted">Loading…</p>
  {:else if s}
    <h1>{s.username ? '@' + s.username : 'Your Profile'}</h1>
    <p class="nw-label">Net Worth</p>
    <div class="nw" class:neg={s.net_worth < 0}>{fmt(s.net_worth)}</div>
    <p class="nw-sub">{fmt(s.cash)} Cash · {fmt(s.loan)} owed</p>

    <div class="grid">
      <div class="stat"><span class="sv">🔥 {s.current_streak}</span><span class="sc">Day streak</span></div>
      <div class="stat"><span class="sv">{s.longest_streak}</span><span class="sc">Longest streak</span></div>
      <div class="stat"><span class="sv">{winPct}%</span><span class="sc">Daily win rate</span></div>
      <div class="stat"><span class="sv">{(s.puzzles_solved ?? 0).toLocaleString()}</span><span class="sc">Puzzles solved</span></div>
      <div class="stat"><span class="sv">#{s.climb_position}</span><span class="sc">Climb position</span></div>
      <div class="stat"><span class="sv">{s.challenge_wins}</span><span class="sc">Challenge wins</span></div>
    </div>

    <h2 class="sec">Badges</h2>
    {#if (s.badges ?? []).length === 0}
      <p class="muted small">No badges yet — win dailies, climb, and complete weeks to earn them.</p>
    {:else}
      <div class="badges">
        {#each s.badges as id}
          {@const b = badgeInfo(id)}
          <div class="badge" title={b.desc}><span class="b-emoji">{b.emoji}</span><span class="b-name">{b.name}</span></div>
        {/each}
      </div>
    {/if}

    <div class="links">
      <button class="lnk" onclick={() => goto('/badges')}>🏅 All badges</button>
      <button class="lnk" onclick={() => goto('/leaderboard')}>🏆 Leaderboard</button>
    </div>
  {/if}
</main>

<style>
  .profile-page { max-width: 480px; margin: 0 auto; padding: 1.5rem 1rem 3rem; text-align: center; }
  .back-btn { display: inline-block; margin-bottom: 1rem; padding: 0.55rem 1.1rem; background: var(--surface); color: var(--text); border: 1px solid var(--border); border-radius: 12px; cursor: pointer; font-weight: 600; font-size: 0.9rem; }
  .muted { color: var(--text-muted); padding: 1.5rem 0; }
  .muted.small { font-size: 0.85rem; padding: 0.5rem 0; }
  h1 { font-family: var(--font-display); font-size: 1.6rem; margin: 0.3rem 0 0.8rem; }
  .nw-label { color: var(--text-faint); font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.08em; margin: 0; }
  .nw { font-family: var(--font-display); font-weight: 800; font-size: 2.6rem; line-height: 1.1; color: var(--brand-2); }
  .nw.neg { color: #fb7185; }
  .nw-sub { color: var(--text-faint); font-size: 0.82rem; margin: 0.2rem 0 1.4rem; }
  .grid { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 0.6rem; }
  .stat { display: flex; flex-direction: column; gap: 3px; padding: 0.8rem 0.4rem; background: var(--surface); border: 1px solid var(--border); border-radius: 14px; }
  .sv { font-family: var(--font-display); font-weight: 700; font-size: 1.1rem; color: var(--text); }
  .sc { font-size: 0.6rem; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-faint); }
  .sec { font-family: var(--font-display); font-size: 1.05rem; margin: 1.6rem 0 0.7rem; text-align: left; }
  .badges { display: flex; flex-wrap: wrap; gap: 0.5rem; }
  .badge { display: flex; align-items: center; gap: 0.4rem; padding: 0.5rem 0.8rem; background: var(--surface); border: 1px solid rgba(163,230,53,0.35); border-radius: 999px; }
  .b-emoji { font-size: 1rem; }
  .b-name { font-size: 0.8rem; font-weight: 600; }
  .links { display: flex; gap: 0.5rem; margin-top: 1.6rem; }
  .lnk { flex: 1; padding: 0.65rem; border-radius: 12px; border: 1px solid var(--border); background: var(--surface); color: var(--text); cursor: pointer; font-weight: 600; font-size: 0.88rem; }
</style>
