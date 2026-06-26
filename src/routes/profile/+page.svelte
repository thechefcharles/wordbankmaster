<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { page } from '$app/stores';
  import { getProfileDetail, getMyAvatar, getUserBadges } from '$lib/stores/statsStore.js';
  import { badgeInfo } from '$lib/badges.js';
  import Avatar from '$lib/components/Avatar.svelte';
  import HistoryList from '$lib/components/HistoryList.svelte';
  import BadgesPanel from '$lib/components/BadgesPanel.svelte';
  import NotificationsPanel from '$lib/components/NotificationsPanel.svelte';
  import { unreadCount, markAllNotificationsRead } from '$lib/stores/notificationStore.js';
  import { track } from '$lib/analytics.js';

  /** @type {'overview'|'stats'|'history'|'badges'|'alerts'} */
  let tab = $state('overview');
  /** @type {any|null} */
  let d = $state(null);
  let loading = $state(true);
  let avatar = $state(null);
  /** @type {string[]} */
  let earned = $state([]);
  let earnedBadges = $derived(earned.map((id) => badgeInfo(id)).filter(Boolean));

  onMount(async () => {
    track('profile_view');
    const t = $page.url.searchParams.get('tab');
    if (t === 'stats' || t === 'history' || t === 'badges' || t === 'alerts') tab = /** @type {any} */ (t);
    getMyAvatar().then((a) => { avatar = a.config; });
    getUserBadges().then((b) => { earned = b; });
    try { d = await getProfileDetail(); } finally { loading = false; }
  });

  // Viewing your alerts clears the unread badge.
  $effect(() => { if (tab === 'alerts') markAllNotificationsRead(); });
  /** @param {any} n */
  function notifNav(n) {
    if (n?.type === 'challenge_incoming' || n?.data?.match_id || n?.data?.challenge_id) goto('/');
  }

  // Back: from a detail tab → Overview; from Overview → the menu.
  function back() {
    if (tab !== 'overview') tab = 'overview';
    else goto('/');
  }

  const fmt = (/** @type {any} */ n) => '$' + Math.round(Number(n ?? 0)).toLocaleString();
  const mult = (/** @type {any} */ x) => x ? (Number(x) / 100).toFixed(1) + '×' : '—';
  const time = (/** @type {any} */ ms) => !ms ? '—' : Number(ms) < 60000 ? Math.round(Number(ms) / 1000) + 's' : (Number(ms) / 60000).toFixed(1) + 'm';
  const pct = (/** @type {number} */ w, /** @type {number} */ n) => n > 0 ? Math.round((w / n) * 100) + '%' : '—';
</script>

<svelte:head><title>WordBank — Profile</title></svelte:head>

{#snippet chip(value, label)}
  <div class="stat"><span class="sv">{value}</span><span class="sc">{label}</span></div>
{/snippet}
{#snippet chipLink(/** @type {any} */ value, /** @type {string} */ label, /** @type {string} */ href)}
  <button class="stat stat-link" onclick={() => goto(href)}><span class="sv">{value}</span><span class="sc">{label} ›</span></button>
{/snippet}

<main class="you-page">
  <div class="topbar">
    <button class="back-btn" onclick={back}>← {tab === 'overview' ? 'Menu' : 'Back'}</button>
    <h1 class="page-title">Profile</h1>
    <button class="gear" onclick={() => goto('/?account=1')} title="Settings" aria-label="Settings">⚙️</button>
  </div>

  {#if loading}
    <p class="muted">Loading…</p>
  {:else if d}
    <div class="tabs">
      <button class="tab" class:active={tab === 'overview'} onclick={() => tab = 'overview'}>Overview</button>
      <button class="tab" class:active={tab === 'stats'} onclick={() => tab = 'stats'}>Stats</button>
      <button class="tab" class:active={tab === 'history'} onclick={() => tab = 'history'}>History</button>
      <button class="tab" class:active={tab === 'badges'} onclick={() => tab = 'badges'}>Badges</button>
      <button class="tab" class:active={tab === 'alerts'} onclick={() => tab = 'alerts'}>🔔{#if $unreadCount > 0}<span class="tab-count">{$unreadCount > 99 ? '99+' : $unreadCount}</span>{/if}</button>
    </div>

    {#if tab === 'overview'}
      <div class="ov-hero">
        <button class="prof-avatar" onclick={() => goto('/avatar')}>
          <Avatar config={avatar} fx size={120} />
          <span class="prof-avatar-edit">🎨 Edit Avatar</span>
        </button>
        <div class="ov-id">
          <div class="uname">{d.username ? '@' + d.username : 'You'}</div>
          <div class="nw">{fmt(d.net_worth)}<span class="nw-sub"> Cash</span></div>
          <button class="ov-people" onclick={() => goto('/?people=1')} aria-label="Friends & groups">
            <span class="vs-ppl">👥</span><span class="vs-ppl-plus">+</span><span class="ov-people-lbl">Friends</span>
          </button>
        </div>
      </div>

      <div class="grid ov-summary">
        {@render chip((d.overall.puzzles_solved ?? 0).toLocaleString(), 'Puzzles')}
        {@render chip(d.overall.games_played ?? 0, 'Games')}
        {@render chipLink('🔥 ' + (d.daily.current_streak ?? 0), 'Streak', '/streak')}
        {@render chip('🏆 ' + (d.daily.win_streak ?? 0), 'Win streak')}
        {@render chip(pct(d.daily.won ?? 0, d.daily.played ?? 0), 'Daily win%')}
        {@render chip(d.overall.clean_solves ?? 0, 'Clean solves')}
      </div>

      {#if earnedBadges.length}
        <div class="sec-title">🏅 Badges <button class="sec-link" onclick={() => tab = 'badges'}>View all ›</button></div>
        <div class="ov-badges">
          {#each earnedBadges.slice(0, 12) as bdg}<span class="ov-badge" title={bdg.name}>{bdg.emoji}</span>{/each}
        </div>
      {/if}

      <div class="ov-nav">
        <button class="ov-link" onclick={() => tab = 'stats'}>📊 Full stats <span class="arrow">›</span></button>
        <button class="ov-link" onclick={() => tab = 'history'}>📜 Play history <span class="arrow">›</span></button>
        <button class="ov-link" onclick={() => goto('/streak')}>🔥 Streak &amp; calendar <span class="arrow">›</span></button>
      </div>
    {:else if tab === 'stats'}
      <div class="sec-title">📊 Overall</div>
      <div class="grid">
        {@render chip((d.overall.puzzles_solved ?? 0).toLocaleString(), 'Puzzles solved')}
        {@render chip(d.overall.games_played ?? 0, 'Games played')}
        {@render chip(d.overall.clean_solves ?? 0, 'Clean solves')}
        {@render chip(mult(d.overall.avg_multiple), 'Avg multiple')}
        {@render chip(mult(d.overall.best_multiple), 'Best multiple')}
        {@render chip(fmt(d.overall.earned), 'Earned')}
      </div>
      <p class="spent-line">Lifetime spent: <b>{fmt(d.overall.spent)}</b></p>

      <div class="sec-title">📅 Daily</div>
      <div class="grid">
        {@render chipLink('🔥 ' + (d.daily.current_streak ?? 0), 'Play streak', '/streak')}
        {@render chip(d.daily.best_streak ?? 0, 'Best play')}
        {@render chipLink('🏆 ' + (d.daily.win_streak ?? 0), 'Win streak', '/streak')}
        {@render chip(d.daily.best_win_streak ?? 0, 'Best win')}
        {@render chip(pct(d.daily.won ?? 0, d.daily.played ?? 0), 'Win rate')}
        {@render chip(d.daily.won ?? 0, 'Dailies won')}
        {@render chip(mult(d.daily.best_multiple), 'Best ×')}
        {@render chip(time(d.daily.fastest_ms), 'Fastest')}
      </div>

      <div class="sec-title">🎰 Cash Game</div>
      <div class="grid">
        {@render chip('#' + (d.cash_game.position ?? 0), 'Furthest')}
        {@render chip(d.cash_game.solved ?? 0, 'Solved')}
        {@render chip(fmt(d.cash_game.earned), 'Earned')}
        {@render chip(mult(d.cash_game.best_multiple), 'Best ×')}
        {@render chip(time(d.cash_game.fastest_ms), 'Fastest')}
      </div>

      <div class="sec-title">⚔️ 1-on-1</div>
      <div class="grid">
        {@render chip(`${d.challenges_1v1.wins ?? 0}-${d.challenges_1v1.losses ?? 0}-${d.challenges_1v1.ties ?? 0}`, 'W-L-T')}
        {@render chip(pct(d.challenges_1v1.wins ?? 0, d.challenges_1v1.played ?? 0), 'Win rate')}
        {@render chip(fmt(d.challenges_1v1.biggest_pot), 'Biggest pot')}
      </div>

      <div class="sec-title">👥 Group challenges</div>
      <div class="grid">
        {@render chip(d.challenges_group.played ?? 0, 'Played')}
        {@render chip(d.challenges_group.wins ?? 0, 'Wins (1st)')}
        {@render chip(d.challenges_group.podiums ?? 0, 'Podiums')}
      </div>

      {#if (d.rivals ?? []).length}
        <div class="sec-title">🤺 Rivals <span class="sec-hint">(tap for the full head-to-head)</span></div>
        <div class="cats">
          {#each d.rivals as r}
            <button class="cat-row rival" onclick={() => goto('/u/' + encodeURIComponent(r.name || ''))}>
              <span class="cat-name">@{r.name}</span>
              <span class="rival-rec">
                <b class="w">{r.wins}W</b> <b class="l">{r.losses}L</b>{#if r.ties}<b class="t">{r.ties}T</b>{/if}
                <span class="arrow">›</span>
              </span>
            </button>
          {/each}
        </div>
      {/if}

      {#if (d.categories ?? []).length}
        <div class="sec-title">🗂️ Categories</div>
        <div class="cats">
          {#each d.categories as c}
            <div class="cat-row">
              <span class="cat-name">{c.category}</span>
              <span class="cat-meta">{c.solves} solved{#if c.best_multiple} · best {mult(c.best_multiple)}{/if}</span>
            </div>
          {/each}
        </div>
      {/if}
    {:else if tab === 'history'}
      <HistoryList />
    {:else if tab === 'badges'}
      <BadgesPanel />
    {:else}
      <NotificationsPanel onNavigate={notifNav} />
    {/if}
  {/if}
</main>

<style>
  .you-page { max-width: 520px; margin: 0 auto; padding: 16px 14px 60px; }
  .topbar { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
  .back-btn { background: none; border: none; color: var(--text-muted); font-size: 0.92rem; cursor: pointer; padding: 6px 0; }
  .page-title { font-family: var(--font-display); font-size: 1.2rem; margin: 0; }
  .gear { background: none; border: none; font-size: 1.1rem; cursor: pointer; padding: 6px; opacity: 0.85; }
  .gear:hover { opacity: 1; }
  .muted { color: var(--text-muted); text-align: center; padding: 2rem 0; }

  .head { text-align: center; margin: 8px 0 18px; }
  .coin { width: 64px; height: 64px; margin: 0 auto 8px; border-radius: 50%; display: grid; place-items: center;
    font-family: var(--font-display); font-weight: 800; font-size: 1.6rem; color: #3a2a00;
    background: linear-gradient(135deg, var(--c, #fde047), #f59e0b); box-shadow: 0 0 24px rgba(251,191,36,0.4); }
  .uname { font-family: var(--font-display); font-weight: 700; font-size: 1.3rem; }
  .nw { font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 2.1rem; color: #fde047;
    margin-top: 10px; text-shadow: 0 0 18px rgba(251,191,36,0.5); }
  .nw-sub { font-size: 0.72rem; color: var(--text-faint); text-transform: uppercase; letter-spacing: 0.1em; }

  .tabs { display: flex; gap: 8px; margin: 0 0 16px; }
  .tab { flex: 1; padding: 9px 0; border-radius: 12px; border: 1px solid var(--border); background: var(--surface);
    color: var(--text-muted); font-weight: 700; font-size: 0.88rem; cursor: pointer; }
  .tab.active { background: linear-gradient(135deg, #fde047, #f59e0b); color: #3a2a00; border-color: transparent; }
  .tab-count { display: inline-grid; place-items: center; min-width: 16px; height: 16px; padding: 0 4px; margin-left: 3px;
    border-radius: 999px; background: #f43f5e; color: #fff; font-size: 0.62rem; font-weight: 800; vertical-align: middle; }

  .sec-title { font-family: var(--font-display); font-size: 0.78rem; font-weight: 700; letter-spacing: 0.06em;
    text-transform: uppercase; color: var(--gold); text-align: left; margin: 18px 2px 8px; }
  .grid { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 8px; }
  .prof-avatar { display: flex; flex-direction: column; align-items: center; gap: 6px; margin: 0 auto 14px; background: none; border: none; cursor: pointer; }
  .prof-avatar-edit { font-size: 0.82rem; font-weight: 700; color: var(--brand-2); }
  /* Overview tab */
  .ov-hero { display: flex; align-items: center; gap: 16px; margin: 6px 0 16px; }
  .ov-hero .prof-avatar { margin: 0; }
  .ov-id { display: flex; flex-direction: column; align-items: flex-start; gap: 2px; min-width: 0; }
  .ov-id .uname { font-size: 1.15rem; }
  .ov-id .nw { font-size: 1.7rem; }
  .ov-id .nw-sub { font-size: 0.8rem; color: var(--text-faint); -webkit-text-fill-color: var(--text-faint); }
  .ov-people { display: inline-flex; align-items: center; gap: 6px; margin-top: 6px; padding: 7px 14px 7px 30px; position: relative;
    border-radius: 999px; cursor: pointer; font-weight: 800; font-size: 0.85rem; color: #3a2a00;
    background: linear-gradient(135deg, #fde047, #f59e0b); border: none; }
  .ov-people .vs-ppl { position: absolute; left: 11px; font-size: 0.95rem; }
  .ov-people .vs-ppl-plus { position: absolute; left: 22px; top: 6px; font-size: 0.7rem; font-weight: 900; }
  .ov-people:active { transform: scale(0.97); }
  .ov-summary { margin-bottom: 4px; }
  .sec-link { float: right; background: none; border: none; color: var(--brand-2); font-weight: 700; font-size: 0.72rem; cursor: pointer; text-transform: none; letter-spacing: 0; }
  .ov-badges { display: flex; flex-wrap: wrap; gap: 8px; padding: 4px 0; }
  .ov-badge { font-size: 1.5rem; line-height: 1; }
  .ov-nav { display: flex; flex-direction: column; gap: 8px; margin-top: 18px; }
  .ov-link { display: flex; justify-content: space-between; align-items: center; padding: 13px 15px; border-radius: 14px; cursor: pointer;
    background: var(--surface); border: 1px solid var(--border); color: var(--text); font-weight: 700; font-size: 0.95rem; text-align: left; }
  .ov-link:hover { border-color: var(--brand-2); }
  .ov-link .arrow { color: var(--text-faint); }
  .stat { display: flex; flex-direction: column; gap: 3px; padding: 0.85rem 0.4rem; background: var(--surface); border: 1px solid var(--border); border-radius: 14px; text-align: center; }
  .stat-link { cursor: pointer; color: var(--text); font: inherit; }
  .stat-link:hover { border-color: var(--brand-2); }
  .stat-link:active { transform: scale(0.97); }
  .stat-link .sc { color: var(--brand-2); }
  .sv { font-family: var(--font-display); font-weight: 800; font-size: 1.02rem; color: var(--text); }
  .sc { font-size: 0.58rem; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-faint); }
  .spent-line { text-align: center; color: var(--text-muted); font-size: 0.82rem; margin: 10px 0 0; }
  .spent-line b { color: var(--text); }

  .cats { display: flex; flex-direction: column; gap: 6px; }
  .cat-row { display: flex; justify-content: space-between; align-items: center; gap: 10px; padding: 9px 11px;
    background: var(--surface); border: 1px solid var(--border); border-radius: 10px; }
  .cat-name { font-weight: 600; color: var(--text); font-size: 0.86rem; }
  .cat-meta { color: var(--text-faint); font-size: 0.74rem; }
  .sec-hint { font-family: var(--font-ui); font-weight: 500; font-size: 0.62rem; color: var(--text-faint); text-transform: none; letter-spacing: 0; }
  .rival { width: 100%; cursor: pointer; }
  .rival-rec { display: flex; align-items: center; gap: 7px; font-size: 0.8rem; font-variant-numeric: tabular-nums; }
  .rival-rec .w { color: #7ee0a8; } .rival-rec .l { color: #fb7185; } .rival-rec .t { color: var(--text-muted); }
  .rival-rec .arrow { color: var(--text-faint); font-size: 1rem; margin-left: 2px; }
</style>
