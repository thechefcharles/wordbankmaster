<script>
  import { onMount, tick } from 'svelte';
  import { browser } from '$app/environment';
  import { supabase } from '$lib/supabaseClient';
  import { get } from 'svelte/store';

  import { gameStore, fetchDailyGame, fetchArcadeGame, arcadeContinue, fetchFreeplayGame, freeplayContinue, arcadeCashOut, startChallenge, acceptAndPlayChallenge, resumeChallenge } from '$lib/stores/GameStore.js';
  import { getMyChallenges } from '$lib/stores/statsStore.js';
  import { powerupInfo } from '$lib/powerups.js';
  import { CATEGORIES } from '$lib/categories.js';
  import { user, userProfile, fetchUserProfile, ensureProfileExists } from '$lib/stores/userStore.js';
  import { getDailyStatus, getDailyGhost, getDailyQuests, addFriend, getBank } from '$lib/stores/statsStore.js';
  import { track } from '$lib/analytics.js';
  import { modifierInfo } from '$lib/powerups.js';
  import {
    saveGameToLocalStorage,
    clearSavedGame,
    getSavedGameInfo
  } from '$lib/stores/localGameUtils.js';
  import { gameWasRestored } from '$lib/stores/GameStateFlags.js';
  import { soundEnabled, toggleSound, fx } from '$lib/sound.js';
  import { goto } from '$app/navigation';

  import PhraseDisplay from '$lib/components/PhraseDisplay.svelte';
  import Keyboard from '$lib/components/Keyboard.svelte';
  import GameButtons from '$lib/components/GameButtons.svelte';
  import FlipDigit from '$lib/components/FlipDigit.svelte';
  import Auth from '$lib/components/Auth.svelte';
  import Tutorial from '$lib/components/Tutorial.svelte';
  import PowerupTray from '$lib/components/PowerupTray.svelte';

  export let data;

  // UI state
  let showTutorial = false;
  let showResultModal = false;
  let hasTriggeredModal = false;
  let hasInitialized = false;
  /** @type {string | null} */
  let initError = null; // 🔍 Diagnostic: what failed during init
  /** Show main menu (Daily / Arcade / Leaderboard / My account) when true; game when false */
  let showMainMenu = false;
  /** When showing menu: can we show "Resume daily" / "Resume arcade"? */
  let savedGameInfo = /** @type {{ gameMode: string, gameState: string } | null} */ (null);
  /** When showing menu: has user already played daily today? */
  let menuDailyPlayed = false;
  /** Today's daily result for the menu indicator (won/lost + score). */
  let dailyStatus = /** @type {{ has_played_today: boolean, last_daily_won: boolean|null, daily_bankroll: number, arcade_bankroll: number, current_streak: number, streak_freezes: number, today_score: number } | null} */ (null);
  $: dailyDone = menuDailyPlayed && !(savedGameInfo?.gameMode === 'daily' && savedGameInfo?.gameState !== 'won' && savedGameInfo?.gameState !== 'lost');
  /** Daily-quest progress for the menu card. */
  let questProgress = { done: 0, total: 3, all_done: false, reward_claimed: false };
  async function refreshQuests() {
    try {
      const q = await getDailyQuests();
      questProgress = { done: q.quests.filter((x) => x.done).length, total: q.quests.length || 3, all_done: q.all_done, reward_claimed: q.reward_claimed };
    } catch { /* non-fatal */ }
  }
  /** Net Worth for the menu chip. */
  let netWorth = /** @type {number|null} */ (null);
  async function refreshBank() {
    try { netWorth = (await getBank()).net_worth; } catch { /* non-fatal */ }
  }

  // ✅ Load Supabase user profile and sync bankroll (creates profile if missing)
  /** @param {string} userId */
  async function loadUserProfile(userId) {
    try {
      const { data: profile, error } = await fetchUserProfile(userId);
      if (error || !profile) {
        console.warn("⚠️ Failed to load profile:", error?.message ?? error);
        // Auto-create profile for new users (no profile row yet)
        const createError = await ensureProfileExists(userId);
        if (createError) {
          console.error("❌ Failed to create profile:", createError);
          return null;
        }
        const { data: newProfile } = await fetchUserProfile(userId);
        if (!newProfile) return null;
        userProfile.set(newProfile);
        gameStore.update(state => ({ ...state, bankroll: 1000 }));
        console.log("✅ Profile created. Bankroll: 1000");
        return newProfile;
      }

      userProfile.set(profile);
      gameStore.update(state => ({
        ...state,
        bankroll: profile.arcade_bankroll ?? 1000
      }));

      console.log("✅ Profile loaded. Bankroll:", profile.current_bankroll ?? profile.arcade_bankroll);
      return profile;
    } catch (err) {
      console.error("❌ Profile load error:", err instanceof Error ? err.message : String(err));
      return null;
    }
  }

  // ✅ Main logic on initial mount
  onMount(async () => {
    initError = null;
    track('app_open');
    try {
      const { data: { session }, error } = await supabase.auth.getSession();
      if (!session || error) {
        initError = "No session (session: " + (session ? "yes" : "no") + ", error: " + (error?.message || "none") + ")";
        console.warn("⛔", initError);
        return;
      }

      user.set(/** @type {{ id: string }} */ (session.user));
      const profile = await loadUserProfile(session.user.id);
      if (!profile) {
        initError = "Profile failed to load or create. Check Supabase profiles table and RLS policies.";
        console.warn("⛔", initError);
        return;
      }

      // Daily and arcade are both server-authoritative now — start from the menu.
      showMainMenu = true;
      savedGameInfo = null;
      const ds = await getDailyStatus(session.user.id);
      dailyStatus = ds;
      menuDailyPlayed = ds.has_played_today;
      refreshQuests();
      refreshBank();

      // Friend invite link: ?add=CODE → add them, then open the Friends board.
      try {
        const addCode = new URLSearchParams(window.location.search).get('add');
        if (addCode) {
          const res = await addFriend(addCode);
          if (res?.ok) { track('friend_add', { via: 'link' }); goto('/leaderboard?mode=friends'); return; }
        }
      } catch { /* non-fatal */ }

      await tick();
      hasInitialized = true;

    } catch (err) {
      initError = "Init error: " + (err instanceof Error ? err.message : String(err));
      console.error("❌", initError);
    }
  });

  // ✅ Reactive puzzle loader if puzzle is missing (skip when showing main menu)
  $: if (
    hasInitialized &&
    loggedIn &&
    !showMainMenu &&
    $gameStore.currentPhrase === '' &&
    !$gameWasRestored
  ) {
    const gameMode = localStorage.getItem('gameMode') || 'daily';
    if (gameMode === 'arcade') {
      fetchArcadeGame().then((ok) => {
        if (!ok) initError = "Arcade failed to load.";
      });
    } else if (gameMode === 'freeplay') {
      // Free Play isn't deep-link restorable — send back to the menu to re-pick.
      showMainMenu = true;
    } else {
      fetchDailyGame().then((ok) => {
        if (!ok) initError = "Daily puzzle failed to load.";
      });
    }
  }

  // ✅ Set user from SSR if present (profile load happens once in onMount)
  $: if (data?.user) {
    user.set(/** @type {{ id: string }} */ (data.user));
  }

  // Reactive state values
  $: loggedIn = !!$user?.id;
  $: bankroll = $gameStore.bankroll || 0;
  $: digits = String(bankroll).split('');

  // ✨ Bankroll change reaction (pulse + floating delta)
  let bankrollPulse = '';
  let bankrollDelta = 0;
  /** @type {number | null} */
  let _prevBankroll = null;
  $: {
    const b = $gameStore.bankroll;
    if (_prevBankroll !== null && typeof b === 'number' && b !== _prevBankroll) {
      bankrollDelta = b - _prevBankroll;
      bankrollPulse = bankrollDelta > 0 ? 'up' : 'down';
      const token = bankrollDelta;
      setTimeout(() => { if (bankrollDelta === token) bankrollPulse = ''; }, 950);
    }
    if (typeof b === 'number') _prevBankroll = b;
  }

  // 🔥 Hot Hand flash — +$250 per 3 correct letters in a row (arcade). The
  // server sends last_bonus on the buy that pops it; flash only while playing.
  let hotHandFlash = false;
  let _prevBonus = 0;
  $: {
    const lb = $gameStore.arcadeRun?.last_bonus ?? 0;
    const playing = $gameStore.gameState !== 'won' && $gameStore.gameState !== 'lost';
    if (lb > 0 && lb !== _prevBonus && playing) {
      hotHandFlash = true;
      fx('multiplier');
      setTimeout(() => { hotHandFlash = false; }, 1300);
    }
    _prevBonus = lb;
  }

  // ---- Daily result: medal + shareable card ----
  const PUZZLE_EPOCH = Date.UTC(2026, 5, 1); // 2026-06-01
  $: puzzleNumber = Math.max(1, Math.floor((Date.now() - PUZZLE_EPOCH) / 86400000) + 1);

  /** @param {number} br @param {boolean} won */
  function medalFor(br, won) {
    if (!won) return { emoji: '💀', name: 'Busted', tier: 'none' };
    if (br >= 700) return { emoji: '🥇', name: 'Gold', tier: 'gold' };
    if (br >= 400) return { emoji: '🥈', name: 'Silver', tier: 'silver' };
    return { emoji: '🥉', name: 'Bronze', tier: 'bronze' };
  }
  $: resultWon = $gameStore.gameState === 'won';
  $: isDailyResult = $gameStore.gameMode === 'daily';
  $: isFreeplay = $gameStore.gameMode === 'freeplay';
  $: isChallenge = $gameStore.gameMode === 'challenge';
  $: resultBankroll = Math.max(0, Math.floor($gameStore.bankroll || 0));
  $: resultMedal = medalFor(resultBankroll, resultWon);
  // Arcade rolling-survival run state
  $: arun = $gameStore.arcadeRun;
  $: arcadeMult = ((arun?.multiplier ?? 100) / 100).toFixed(2);
  $: arcadePayout = Math.round(500 * (arun?.multiplier ?? 100) / 100); // next solve is worth this
  $: arcadeWinnings = Math.max(0, Math.floor(($gameStore.bankroll ?? 0) - 1500)); // bankable above the house stake
  let cashingOut = false;
  async function handleBankIt() {
    if (cashingOut || arcadeWinnings <= 0) return;
    cashingOut = true;
    try { await arcadeCashOut(); } finally { cashingOut = false; }
  }

  let shareCopied = false;
  function buildShareText() {
    const br = '$' + resultBankroll.toLocaleString();
    // Link to the live origin (never a hardcoded/deleted project URL).
    const link = typeof window !== 'undefined' ? window.location.origin : '';
    if (isDailyResult) {
      return `🏦 WordBank Daily #${puzzleNumber}\n${resultMedal.emoji} ${resultWon ? resultMedal.name + ' — ' : ''}${br} banked\n${link}`;
    }
    return `🏦 WordBank Arcade\n${resultMedal.emoji} ${br} banked\n${link}`;
  }
  async function handleShare() {
    const text = buildShareText();
    try {
      if (typeof navigator !== 'undefined' && navigator.share) { await navigator.share({ text }); return; }
    } catch { /* user cancelled native share */ }
    try {
      await navigator.clipboard.writeText(text);
      shareCopied = true;
      setTimeout(() => { shareCopied = false; }, 1800);
    } catch { /* clipboard unavailable */ }
  }

  // ✅ Auto-save whenever state is valid
  $: if (
    loggedIn &&
    $gameStore.currentPhrase &&
    $gameStore.category &&
    $gameStore.purchasedLetters.length > 0
  ) {
    saveGameToLocalStorage();
  }

  onMount(() => {
    ['click', 'mousedown', 'touchstart'].forEach(event =>
      document.addEventListener(event, removeButtonFocus, true)
    );
  });

  const TUTORIAL_KEY = 'wb_tutorial_seen';
  // First-run guided tutorial: show once a signed-in user reaches the menu.
  $: if (browser && loggedIn && hasInitialized && localStorage.getItem(TUTORIAL_KEY) !== 'true') {
    showTutorial = true;
  }
  function dismissTutorial() {
    showTutorial = false;
    if (browser) localStorage.setItem(TUTORIAL_KEY, 'true');
  }

  /** @param {Event} e */
  const removeButtonFocus = (e) => {
    if (e.target && /** @type {HTMLElement} */ (e.target).tagName === 'BUTTON') /** @type {HTMLButtonElement} */ (e.target).blur();
  };

  // ✅ Log out: clear saved game so next login always shows main menu
  const handleLogout = async () => {
    clearSavedGame();
    gameWasRestored.set(false);
    await supabase.auth.signOut();
    user.set(null);
    location.reload();
  };

  /** Start daily: resume if in progress, else show "already played" or fetch new daily.
   *  Daily has no personal power-ups — everyone shares the same Daily Modifier. */
  async function handleMenuDaily() {
    const currentUser = get(user);
    if (!currentUser?.id) return;
    // Finished today's daily already -> show streak message (server enforces one/day).
    if (menuDailyPlayed) {
      showStreakMessage = true;
      return;
    }
    await startDaily();
  }

  async function startDaily() {
    localStorage.setItem('gameMode', 'daily');
    const ok = await fetchDailyGame();
    if (ok) {
      hasInitialized = true;
      showMainMenu = false;
    } else {
      initError = "Daily puzzle failed to load.";
    }
  }

  // Today's shared Daily Modifier banner (id lives in the game store, set by fetchDailyGame).
  $: dailyMod = ($gameStore.gameMode === 'daily' && $gameStore.modifier) ? modifierInfo($gameStore.modifier) : null;

  /** Start or resume today's server-authoritative arcade gauntlet run. */
  async function handleMenuArcade() {
    const currentUser = get(user);
    if (!currentUser?.id) return;
    // Arcade is now the server-authoritative Press-Your-Luck gauntlet (start/resume today's run).
    localStorage.setItem('gameMode', 'arcade');
    const ok = await fetchArcadeGame();
    if (ok) {
      hasInitialized = true;
      showMainMenu = false;
    } else {
      initError = 'Arcade failed to load.';
    }
  }

  // After solving, advance to the next puzzle (bankroll + streak carry over).
  async function handleArcadeContinue() {
    showResultModal = false;
    hasTriggeredModal = false;
    await arcadeContinue();
  }

  // After a run ends (broke), start a fresh run.
  async function handleArcadeNewRun() {
    showResultModal = false;
    hasTriggeredModal = false;
    await fetchArcadeGame();
  }

  // ----- Free Play (unranked, pick a category) -----
  let showCategorySelect = false;
  function handleMenuFreeplay() {
    if (!get(user)?.id) return;
    showCategorySelect = true;
  }
  /** @param {string} category */
  async function startFreeplay(category) {
    showCategorySelect = false;
    localStorage.setItem('gameMode', 'freeplay');
    const ok = await fetchFreeplayGame(category);
    if (ok) {
      hasInitialized = true;
      showMainMenu = false;
    } else {
      initError = 'Free Play failed to load.';
    }
  }
  // ===== Challenges (friend wagers) =====
  let showChallenges = false;
  /** @type {any[]} */
  let myChallenges = [];
  let chCode = '';
  let chCategory = '';
  let chWager = 500;
  let chMsg = '';
  let chBusy = false;
  async function openChallenges() {
    if (!get(user)?.id) return;
    chMsg = '';
    showChallenges = true;
    myChallenges = await getMyChallenges();
  }
  async function submitNewChallenge() {
    if (chBusy) return;
    if (!chCode.trim() || !chCategory) { chMsg = 'Pick a friend code and a category.'; return; }
    chBusy = true; chMsg = 'Creating…';
    const res = await startChallenge(chCode.trim().toUpperCase(), chCategory, Math.floor(Number(chWager) || 0));
    chBusy = false;
    if (res?.ok) { launchChallengePlay(); }
    else {
      chMsg = res?.reason === 'no_friend' ? 'No player with that code.'
        : res?.reason === 'insufficient' ? "Not enough in your Bank for that wager."
        : res?.reason === 'min_wager' ? 'Minimum wager is $100.'
        : res?.reason === 'self' ? "You can't challenge yourself."
        : res?.reason === 'no_puzzle' ? 'No puzzles in that category.'
        : 'Could not create the challenge.';
    }
  }
  async function respondToChallenge(/** @type {any} */ ch) {
    if (chBusy) return;
    chBusy = true;
    let ok = false;
    if (ch.is_creator) {
      ok = await resumeChallenge(ch.id); // creators resume their own (can't "accept")
    } else {
      const res = await acceptAndPlayChallenge(ch.id);
      ok = !!res?.ok;
      if (!ok) chMsg = res?.reason === 'insufficient' ? 'Not enough in your Bank.' : 'Could not open that challenge.';
    }
    chBusy = false;
    if (ok) launchChallengePlay();
  }
  function launchChallengePlay() {
    showChallenges = false;
    localStorage.setItem('gameMode', 'challenge');
    hasInitialized = true;
    showMainMenu = false;
  }

  // After solving / going broke in Free Play, load the next puzzle in the category.
  async function handleFreeplayContinue() {
    showResultModal = false;
    hasTriggeredModal = false;
    await freeplayContinue();
  }

  function handleMenuLeaderboard() {
    goto('/leaderboard');
  }

  /** Return to main menu from game (saves and refreshes menu state) */
  function goToMainMenu() {
    const currentUser = get(user);
    if (!currentUser?.id) return;
    saveGameToLocalStorage();
    savedGameInfo = getSavedGameInfo(currentUser.id);
    showMainMenu = true;
    // Refresh the daily completion indicator (e.g. just finished today's daily).
    getDailyStatus(currentUser.id).then((s) => { dailyStatus = s; menuDailyPlayed = s.has_played_today; });
    refreshQuests();
    refreshBank();
  }

  let showMyAccount = false;
  let showStreakMessage = false;
  let accountStreak = 0;
  let accountFreezes = 0;
  async function handleMenuMyAccount() {
    showMyAccount = true;
    const u = get(user);
    if (u?.id) {
      const status = await getDailyStatus(u.id);
      accountStreak = status.current_streak ?? 0;
      accountFreezes = status.streak_freezes ?? 0;
    }
  }
  /** @param {KeyboardEvent} e */
  function handleEscape(e) {
    if (e.key !== 'Escape') return;
    if (showMyAccount) showMyAccount = false;
    if (showStreakMessage) showStreakMessage = false;
  }

  // Daily result → go to the daily leaderboard (arcade uses handleArcadeContinue instead).
  const goToDailyLeaderboard = () => {
    showResultModal = false;
    hasTriggeredModal = false;
    const currentUser = get(user);
    if (!currentUser?.id) return;
    clearSavedGame();
    gameWasRestored.set(false);
    goto('/leaderboard?mode=daily');
  };

  /** @type {null | { yesterday_played: boolean, yesterday_banked: number|null, yesterday_won: boolean, today_banked: number|null, today_players: number, today_percentile: number|null }} */
  let ghost = null;

  const onPhraseRevealComplete = () => {
    if (!hasTriggeredModal && ['won', 'lost'].includes($gameStore.gameState)) {
      hasTriggeredModal = true;
      // Daily only: fetch the "ghost of yesterday" comparison for the result modal.
      if ($gameStore.gameMode === 'daily') {
        ghost = null;
        getDailyGhost().then((g) => { ghost = g; }).catch(() => {});
      }
      setTimeout(() => {
        showResultModal = true;
      }, 1000);
    }
  };
</script>
<svelte:window on:keydown={handleEscape} />
<!-- 🔹 Top Control Buttons -->
<div class="top-buttons">
  <!-- ❓ How to Play (replays the guided tutorial) -->
  <button class="icon-button subtle-button" title="How to play" on:click={() => showTutorial = true}>
    ❓
  </button>

  <!-- ☰ Main menu (only when in a puzzle) -->
  {#if loggedIn && !showMainMenu}
    <button class="icon-button subtle-button" title="Main menu" on:click={goToMainMenu}>
      ☰
    </button>
  {/if}

  <!-- 🏆 Leaderboard -->
  {#if loggedIn}
    <a href="/leaderboard" class="icon-button subtle-button" title="Weekly Leaderboard">🏆</a>
  {/if}

  <!-- 🔊 Sound + Haptics Toggle -->
  <button
    class="icon-button subtle-button"
    on:click={() => { toggleSound(); if ($soundEnabled) fx('select'); }}
    title={$soundEnabled ? 'Sound & haptics on' : 'Sound & haptics off'}
    aria-label="Toggle sound and haptics"
  >
    {$soundEnabled ? '🔊' : '🔇'}
  </button>

  <!-- 🚪 Logout -->
  {#if loggedIn}
    <button class="icon-button subtle-button" on:click={handleLogout}>
      🚪
    </button>
  {/if}
</div>

<!-- 📜 Guided tutorial (first run + replayable from ❓) -->
{#if showTutorial}
  <Tutorial on:close={dismissTutorial} />
{/if}

<main>
  {#if !loggedIn}
    <!-- 🔐 Login Screen -->
    <div class="auth-screen">
      <Auth />
    </div>
  {:else if !hasInitialized}
    <!-- ⏳ Loading (prevents flash of game UI / diagnostic before we know menu vs game) -->
    <div class="init-loading">Loading…</div>
  {:else if showMainMenu}
    <!-- 🏠 Main Menu (after sign-in) -->
    <div class="main-menu fade-up">
      <div class="menu-hero">
        <button class="bank-chip" on:click={() => goto('/bank')} title="Your Bank">
          <span class="bc-coin">💰</span>{netWorth == null ? '—' : '$' + Math.round(netWorth).toLocaleString()}
        </button>
        <button class="streak-chip" class:lit={(dailyStatus?.current_streak ?? 0) > 0} on:click={() => goto('/streak')} title="Your streak">
          <span class="sc-flame">🔥</span>{dailyStatus?.current_streak ?? 0}
        </button>
        <img class="menu-mark float" src="/logo-mark.png" alt="" width="84" height="84" />
        <img class="menu-wordmark" src="/wordmark-slogan.png" alt="WordBank — Spend Less. Think More." />
      </div>
      <div class="main-menu-buttons stagger">
        <button
          class="menu-card primary sheen"
          class:done={dailyDone}
          style="--i: 0"
          class:disabled={dailyDone}
          on:click={handleMenuDaily}
        >
          <span class="mc-icon">{#if dailyDone}{dailyStatus?.last_daily_won ? '✅' : '❌'}{:else}🎯{/if}</span>
          <span class="mc-body">
            <span class="mc-title">{#if savedGameInfo?.gameMode === 'daily' && savedGameInfo?.gameState !== 'won' && savedGameInfo?.gameState !== 'lost'}Resume Daily{:else if dailyDone}Daily Complete{:else}Daily Puzzle{/if}</span>
            <span class="mc-sub">
              {#if dailyDone}
                {dailyStatus?.last_daily_won ? 'Solved' : 'Missed'} · Score {dailyStatus?.today_score?.toLocaleString() ?? 0} · back tomorrow
              {:else}
                One puzzle a day · ranked
              {/if}
            </span>
          </span>
          <span class="mc-arrow">{dailyDone ? '🔒' : '→'}</span>
        </button>
        <button class="menu-card" class:done={questProgress.all_done} style="--i: 1" on:click={() => goto('/quests')}>
          <span class="mc-icon">{questProgress.all_done ? '🏆' : '📋'}</span>
          <span class="mc-body">
            <span class="mc-title">Daily Quests</span>
            <span class="mc-sub">
              {#if questProgress.all_done && !questProgress.reward_claimed}All done — claim your reward!{:else}{questProgress.done}/{questProgress.total} complete today{/if}
            </span>
          </span>
          <span class="mc-arrow">{#if questProgress.all_done && !questProgress.reward_claimed}🎁{:else}→{/if}</span>
        </button>
        <button class="menu-card" style="--i: 2" on:click={handleMenuArcade}>
          <span class="mc-icon">🕹️</span>
          <span class="mc-body">
            <span class="mc-title">{#if savedGameInfo?.gameMode === 'arcade' && savedGameInfo?.gameState !== 'won' && savedGameInfo?.gameState !== 'lost'}Resume Arcade{:else}Arcade Mode{/if}</span>
            <span class="mc-sub">Unlimited · build your bankroll</span>
          </span>
          <span class="mc-arrow">→</span>
        </button>
        <button class="menu-card" style="--i: 3" on:click={handleMenuFreeplay}>
          <span class="mc-icon">🎲</span>
          <span class="mc-body">
            <span class="mc-title">Free Play</span>
            <span class="mc-sub">Pick a category · unranked</span>
          </span>
          <span class="mc-arrow">→</span>
        </button>
        <button class="menu-card" style="--i: 4" on:click={openChallenges}>
          <span class="mc-icon">⚔️</span>
          <span class="mc-body">
            <span class="mc-title">Challenges</span>
            <span class="mc-sub">Wager your Bank vs friends</span>
          </span>
          <span class="mc-arrow">→</span>
        </button>
        <button class="menu-card" style="--i: 5" on:click={() => goto('/badges')}>
          <span class="mc-icon">🏅</span>
          <span class="mc-body">
            <span class="mc-title">Badges</span>
            <span class="mc-sub">Level up every category</span>
          </span>
          <span class="mc-arrow">→</span>
        </button>
        <button class="menu-card" style="--i: 6" on:click={handleMenuLeaderboard}>
          <span class="mc-icon">🏆</span>
          <span class="mc-body">
            <span class="mc-title">Leaderboard</span>
            <span class="mc-sub">See who's on top</span>
          </span>
          <span class="mc-arrow">→</span>
        </button>
        <button class="menu-card" style="--i: 7" on:click={handleMenuMyAccount}>
          <span class="mc-icon">👤</span>
          <span class="mc-body">
            <span class="mc-title">My Account</span>
            <span class="mc-sub">Profile &amp; sign out</span>
          </span>
          <span class="mc-arrow">→</span>
        </button>
      </div>
    </div>

    <!-- Free Play: category picker -->
    {#if showCategorySelect}
      <div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Pick a category">
        <button type="button" class="modal-backdrop" aria-label="Close" on:click={() => showCategorySelect = false}></button>
        <div class="modal-content main-menu-modal cat-modal">
          <button class="close-btn" on:click={() => showCategorySelect = false}>❌</button>
          <h2>Free Play</h2>
          <p class="cat-sub">Pick a category — solve as many as you like. Unranked.</p>
          <div class="cat-grid">
            {#each CATEGORIES as c}
              <button class="cat-tile" on:click={() => startFreeplay(c.value)}>
                <span class="cat-emoji">{c.emoji}</span>
                <span class="cat-label">{c.label}</span>
              </button>
            {/each}
          </div>
        </div>
      </div>
    {/if}

    <!-- Challenges: wager vs friends -->
    {#if showChallenges}
      <div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Challenges">
        <button type="button" class="modal-backdrop" aria-label="Close" on:click={() => showChallenges = false}></button>
        <div class="modal-content main-menu-modal ch-modal">
          <button class="close-btn" on:click={() => showChallenges = false}>❌</button>
          <h2>⚔️ Challenges</h2>
          <p class="cat-sub">Wager your Bank head-to-head — same puzzle, best score wins the pot.</p>

          <div class="ch-new">
            <div class="ch-row">
              <input class="ch-input" placeholder="Friend code" bind:value={chCode} maxlength="6" />
              <select class="ch-input" bind:value={chCategory}>
                <option value="" disabled selected>Category</option>
                {#each CATEGORIES as c}<option value={c.value}>{c.emoji} {c.label}</option>{/each}
              </select>
            </div>
            <div class="ch-row">
              <input class="ch-input" type="number" min="100" step="100" placeholder="Wager $" bind:value={chWager} />
              <button class="ch-create" disabled={chBusy} on:click={submitNewChallenge}>Send ⚔️</button>
            </div>
            {#if chMsg}<p class="add-msg">{chMsg}</p>{/if}
          </div>

          {#if myChallenges.length}
            <div class="ch-list">
              {#each myChallenges as ch}
                <div class="ch-item">
                  <div class="ch-info">
                    <span class="ch-vs">{ch.is_creator ? 'You vs' : 'From'} {ch.opponent_name}</span>
                    <span class="ch-meta">${ch.wager?.toLocaleString()} · {ch.category}</span>
                  </div>
                  {#if ch.status === 'settled'}
                    <span class="ch-result {ch.result}">{ch.result === 'win' ? 'Won 🏆' : ch.result === 'loss' ? 'Lost' : 'Tie'}{#if ch.my_score != null} · ${ch.my_score} vs ${ch.their_score}{/if}</span>
                  {:else if ch.needs_my_play}
                    <button class="ch-play" disabled={chBusy} on:click={() => respondToChallenge(ch)}>{ch.is_creator ? 'Resume' : 'Play'}</button>
                  {:else}
                    <span class="ch-waiting">Waiting…</span>
                  {/if}
                </div>
              {/each}
            </div>
          {/if}
        </div>
      </div>
    {/if}

    <!-- Streak message (when Daily is disabled and user taps it) -->
    {#if showStreakMessage}
      <div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Come back tomorrow">
        <button type="button" class="modal-backdrop" aria-label="Close" on:click={() => showStreakMessage = false}></button>
        <div class="modal-content main-menu-modal">
          <button class="close-btn" on:click={() => showStreakMessage = false}>❌</button>
          <div class="cbt-medal">{dailyStatus?.last_daily_won ? '✅' : '❌'}</div>
          <h2>{dailyStatus?.last_daily_won ? 'Daily Solved!' : 'Daily Done'}</h2>
          <p class="cbt-result">
            {dailyStatus?.last_daily_won ? 'You solved today’s puzzle.' : 'Not today — better luck next time.'}
          </p>
          <div class="cbt-stats">
            <div class="cbt-stat"><span class="cbt-val">{dailyStatus?.today_score?.toLocaleString() ?? 0}</span><span class="cbt-cap">Score</span></div>
            <div class="cbt-stat"><span class="cbt-val">${dailyStatus?.daily_bankroll?.toLocaleString() ?? 0}</span><span class="cbt-cap">Banked</span></div>
            {#if (dailyStatus?.current_streak ?? 0) > 0}
              <div class="cbt-stat"><span class="cbt-val">🔥 {dailyStatus?.current_streak}</span><span class="cbt-cap">Streak</span></div>
            {/if}
          </div>
          <p class="streak-message">
            {#if (dailyStatus?.current_streak ?? 0) > 0}Come back tomorrow for a new puzzle and keep your streak alive!{:else}Come back tomorrow for a new puzzle!{/if}
          </p>
          <button class="main-menu-btn" on:click={() => { showStreakMessage = false; goToDailyLeaderboard(); }}>View Leaderboard</button>
          <button class="main-menu-btn ghost-btn" on:click={() => showStreakMessage = false}>Close</button>
        </div>
      </div>
    {/if}
    <!-- My Account modal -->
    {#if showMyAccount}
      <div class="modal-overlay" role="dialog" aria-modal="true" aria-label="My Account">
        <button type="button" class="modal-backdrop" aria-label="Close" on:click={() => showMyAccount = false}></button>
        <div class="modal-content main-menu-modal">
          <button class="close-btn" on:click={() => showMyAccount = false}>❌</button>
          <h2>My Account</h2>
          {#if $user?.email}
            <p class="account-email">{$user.email}</p>
          {/if}

          <div class="account-stats">
            <div class="stat-chip"><span class="stat-emoji">🔥</span> {accountStreak}<span class="stat-cap">day streak</span></div>
            <div class="stat-chip" title="Auto-protects your streak across one missed day. Earn one every 7-day streak.">
              <span class="stat-emoji">🧊</span> {accountFreezes}<span class="stat-cap">freeze{accountFreezes === 1 ? '' : 's'}</span>
            </div>
          </div>

          <button class="main-menu-btn ghost-btn" on:click={() => goto('/badges')}>🏅 View Badges</button>
          <button class="main-menu-btn" on:click={() => { showMyAccount = false; handleLogout(); }}>Log Out</button>
        </div>
      </div>
    {/if}
  {:else}
    <!-- ✅ GAME UI (Visible only when logged in) -->

    <!-- 🧠 Game Logo -->
    <img class="game-logo" src="/wordmark.png" alt="WordBank" />

    <!-- 🔍 Diagnostic banner (shows when init failed) -->
    {#if initError}
      <div class="diagnostic-banner">
        <strong>⚠️ Diagnostic:</strong> {initError}
        <br />
        <small>Open DevTools (F12) → Console for details.</small>
        <button class="diagnostic-retry" on:click={() => { initError = null; location.reload(); }}>
          Retry
        </button>
      </div>
    {:else if loggedIn && hasInitialized && !$gameStore.currentPhrase && !$gameWasRestored}
      <div class="diagnostic-banner info">
        Loading puzzle… If this persists, check Console (F12).
      </div>
    {/if}

    <!-- 🕹️ Arcade gauntlet HUD -->
    {#if $gameStore.gameMode === 'arcade' && arun}
      <div class="arcade-hud">
        <div class="ah-cell"><span class="ah-val">{(arun.position ?? 0) + 1}</span><span class="ah-label">Puzzle</span></div>
        <div class="ah-cell ah-mult"><span class="ah-val">×{arcadeMult}</span><span class="ah-label">Streak</span></div>
        <div class="ah-cell"><span class="ah-val ah-gold">+${arcadePayout.toLocaleString()}</span><span class="ah-label">Solve</span></div>
      </div>
      {#if $gameStore.gameState !== 'won' && $gameStore.gameState !== 'lost' && arcadeWinnings > 0}
        <button class="bank-it-btn" on:click={handleBankIt} disabled={cashingOut}>
          💰 Bank ${arcadeWinnings.toLocaleString()} <span class="bib-sub">end run, keep winnings</span>
        </button>
      {/if}
    {/if}

    <!-- 🌍 Category + witty clue -->
    <div class="puzzle-meta">
      {#if $gameStore.category}<span class="category-chip">{$gameStore.category}</span>{/if}
    </div>
    {#if $gameStore.clue}
      <p class="puzzle-clue">{$gameStore.clue}</p>
    {/if}

    <!-- ✨ Today's shared Daily Modifier (same for every player) -->
    {#if dailyMod}
      <div class="daily-modifier" title={dailyMod.blurb}>
        <span class="dm-emoji">{dailyMod.emoji}</span>
        <span class="dm-text"><span class="dm-name">{dailyMod.name}</span><span class="dm-blurb">{dailyMod.blurb}</span></span>
      </div>
    {/if}


    <!-- 🔤 Phrase Display -->
    <section class="phrase-section">
      <PhraseDisplay on:revealComplete={onPhraseRevealComplete} />
    </section>

    <!-- 💰 Bankroll Display -->
    <section class="stats-section">
      <div class="bankroll-container">
        <div class="bankroll-box" class:pulse-up={bankrollPulse === 'up'} class:pulse-down={bankrollPulse === 'down'}>
          {#if bankrollPulse}
            <span class="bankroll-delta {bankrollPulse}">{bankrollDelta > 0 ? '+' : '−'}${Math.abs(bankrollDelta)}</span>
          {/if}
          {#if hotHandFlash}
            <span class="hot-hand-flash">🔥 Hot Hand +$250</span>
          {/if}
          <span class="bankroll-label">Balance</span>
          <span class="bankroll-amount">
            <span class="currency">$</span>
            {#each digits as d}
              <FlipDigit digit={+d} />
            {/each}
          </span>
        </div>
      </div>
    </section>

    <!-- 💎 Arcade power-up tray (earned this run) -->
    <PowerupTray />

    <!-- 🎮 Solve / Cancel Buttons -->
    <section class="buttons-section">
      <GameButtons />
    </section>

    <!-- ⌨️ Keyboard Section (keyboard disables itself via gameStore state) -->
    <section class="keyboard-section">
      <Keyboard />
    </section>

    <!-- 🏆 Game Outcome Banner -->
    {#if $gameStore.gameState === "won"}
      <div class="win-burst" aria-hidden="true"></div>
      <div class="banner win">Winner!</div>
    {:else if $gameStore.gameState === "lost"}
      <div class="banner lose">Bankrupt!</div>
    {/if}

    <!-- 🎯 Result Modal -->
    {#if showResultModal && ['won', 'lost'].includes($gameStore.gameState)}
      <div class="modal-overlay">
        <div class="modal-content result-modal">
          {#if isDailyResult}
            <div class="result-medal {resultMedal.tier}">{resultMedal.emoji}</div>
            <h2>{resultWon ? 'Solved!' : 'Busted'}</h2>
            <p class="result-sub">Daily #{puzzleNumber}{#if resultWon} · {resultMedal.name}{/if}</p>
            <div class="result-bankroll">
              <span class="rb-label">Banked</span>
              <span class="rb-amount">${resultBankroll.toLocaleString()}</span>
            </div>
            {#if ghost}
              <div class="ghost-compare">
                {#if ghost.yesterday_played}
                  {@const delta = resultBankroll - (ghost.yesterday_banked ?? 0)}
                  <p class="ghost-line">👻 Yesterday you banked <b>${(ghost.yesterday_banked ?? 0).toLocaleString()}</b></p>
                  <p class="ghost-delta {delta > 0 ? 'up' : delta < 0 ? 'down' : 'even'}">
                    {#if delta > 0}▲ ${delta.toLocaleString()} ahead of your ghost
                    {:else if delta < 0}▼ ${Math.abs(delta).toLocaleString()} behind your ghost
                    {:else}= dead even with your ghost{/if}
                  </p>
                {:else}
                  <p class="ghost-line">👻 Your first daily — you just set the ghost for tomorrow.</p>
                {/if}
                {#if ghost.today_percentile != null && (ghost.today_players ?? 0) >= 5}
                  <p class="ghost-field">Ahead of {ghost.today_percentile}% of today’s players</p>
                {/if}
              </div>
            {/if}
            <div class="result-actions">
              <button class="share-btn" on:click={handleShare}>{shareCopied ? '✓ Copied!' : 'Share'}</button>
              <button class="next-puzzle-button" on:click={goToDailyLeaderboard}>Leaderboard</button>
            </div>
          {:else if isFreeplay}
            <!-- Free Play transition (unranked) -->
            {#if resultWon}
              <div class="result-medal">✅</div>
              <h2>Solved!</h2>
              <p class="result-sub">{$gameStore.currentPhrase}</p>
            {:else}
              <div class="result-medal">💸</div>
              <h2>Out of Cash</h2>
              <p class="result-sub">The answer was {$gameStore.currentPhrase}</p>
            {/if}
            <div class="result-actions">
              <button class="share-btn" on:click={() => { showResultModal = false; showCategorySelect = true; }}>Categories</button>
              <button class="next-puzzle-button" on:click={handleFreeplayContinue}>Next</button>
            </div>
          {:else if isChallenge}
            <!-- Challenge result (settles when the friend plays) -->
            <div class="result-medal">⚔️</div>
            <h2>Challenge played!</h2>
            <p class="result-sub">You scored ${resultBankroll.toLocaleString()} · {$gameStore.currentPhrase}</p>
            <p class="arcade-gain">We'll settle the pot once your friend plays.</p>
            <div class="result-actions">
              <button class="share-btn" on:click={() => { showResultModal = false; hasTriggeredModal = false; openChallenges(); }}>Challenges</button>
              <button class="next-puzzle-button" on:click={() => { showResultModal = false; hasTriggeredModal = false; goToMainMenu(); }}>Menu</button>
            </div>
          {:else}
            <!-- Arcade rolling-bankroll survival -->
            {#if resultWon}
              <div class="result-medal">✅</div>
              <h2>Solved! +${(arun?.last_gain ?? 0).toLocaleString()}</h2>
              <p class="result-sub">Bankroll ${resultBankroll.toLocaleString()} · streak ×{arcadeMult}</p>
              {#if arun?.last_earn}
                {@const earned = powerupInfo(arun.last_earn)}
                <p class="arcade-earn">Earned {earned.emoji} {earned.name} — {earned.feat}!</p>
              {/if}
              <div class="result-actions">
                <button class="share-btn" on:click={handleShare}>{shareCopied ? '✓ Copied!' : 'Share'}</button>
                <button class="next-puzzle-button" on:click={handleArcadeContinue}>Continue</button>
              </div>
            {:else if $gameStore.arcadeCashedOut}
              <div class="result-medal">💰</div>
              <h2>Cashed Out! +${(arun?.last_gain ?? 0).toLocaleString()}</h2>
              <p class="result-sub">Banked into your account · {arun?.furthest ?? 0} {(arun?.furthest ?? 0) === 1 ? 'puzzle' : 'puzzles'} solved</p>
              <div class="result-actions">
                <button class="share-btn" on:click={() => goto('/bank')}>View Bank</button>
                <button class="next-puzzle-button" on:click={handleArcadeNewRun}>New Run</button>
              </div>
            {:else}
              <div class="result-medal">🏁</div>
              <h2>Run Over</h2>
              <p class="result-sub">Busted before you could bank it.</p>
              <div class="result-bankroll">
                <span class="rb-label">Peak Bankroll</span>
                <span class="rb-amount">${(arun?.banked ?? 0).toLocaleString()}</span>
              </div>
              <p class="arcade-gain">{arun?.furthest ?? 0} {(arun?.furthest ?? 0) === 1 ? 'puzzle' : 'puzzles'} solved</p>
              <div class="result-actions">
                <button class="share-btn" on:click={handleShare}>{shareCopied ? '✓ Copied!' : 'Share'}</button>
                <button class="next-puzzle-button" on:click={handleArcadeNewRun}>New Run</button>
              </div>
            {/if}
          {/if}
        </div>
      </div>
    {/if}
  {/if}
</main>

<style>
  @import url('https://fonts.googleapis.com/css2?family=VT323&display=swap');
  @import url('https://fonts.googleapis.com/css2?family=Montserrat:wght@500;700&display=swap');
  @import url('https://fonts.googleapis.com/css2?family=Playfair+Display:wght@400;700&display=swap');
  @import url('https://fonts.googleapis.com/css2?family=Orbitron:wght@400;700&display=swap');

  main {
    max-width: 600px;
    margin: 0 auto;
    text-align: center;
    font-family: var(--font-ui);
    padding: 16px 12px 248px; /* space so content stays above fixed Solve + keyboard */
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
  }

  .arcade-hud {
    display: flex;
    gap: 8px;
    width: 100%;
    max-width: 360px;
    margin: 0 auto 14px;
  }
  .bank-it-btn {
    display: inline-flex;
    align-items: baseline;
    gap: 8px;
    margin: 0 auto 14px;
    padding: 0.6rem 1.3rem;
    border: 1px solid rgba(163, 230, 53, 0.5);
    border-radius: 999px;
    background: linear-gradient(135deg, rgba(52,211,153,0.16), rgba(163,230,53,0.08));
    color: var(--brand-2);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 1rem;
    cursor: pointer;
    box-shadow: 0 0 16px rgba(163, 230, 53, 0.18);
    transition: transform 0.15s, box-shadow 0.2s;
  }
  .bank-it-btn:hover { transform: translateY(-1px); box-shadow: 0 0 22px rgba(163, 230, 53, 0.3); }
  .bank-it-btn:active { transform: scale(0.97); }
  .bank-it-btn:disabled { opacity: 0.6; }
  .bib-sub { font-family: var(--font-ui); font-weight: 500; font-size: 0.72rem; color: var(--text-faint); }
  .ah-cell {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
    padding: 10px 6px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-md);
  }
  .ah-mult { border-color: rgba(163, 230, 53, 0.35); background: linear-gradient(135deg, rgba(52,211,153,0.12), rgba(163,230,53,0.04)); }
  .ah-val { font-family: var(--font-display); font-weight: 700; font-size: 1.15rem; color: var(--text); font-variant-numeric: tabular-nums; }
  .ah-mult .ah-val { color: var(--brand-2); }
  .ah-gold { color: #fcd34d; }
  .ah-label { font-size: 0.55rem; letter-spacing: 0.14em; text-transform: uppercase; color: var(--text-faint); font-weight: 600; }
  .arcade-gain { font-family: var(--font-display); font-weight: 700; color: var(--brand-2); margin: -8px 0 14px; font-size: 1rem; }
  .arcade-earn {
    font-family: var(--font-display); font-weight: 700; font-size: 0.95rem;
    color: #fcd34d; margin: 10px auto 0; padding: 7px 14px;
    background: rgba(251, 191, 36, 0.12); border: 1px solid rgba(251, 191, 36, 0.4);
    border-radius: 999px; display: inline-block;
  }
  .arcade-earn { font-family: var(--font-display); font-weight: 700; color: #fcd34d; margin: -6px 0 14px; font-size: 0.95rem; text-shadow: 0 0 14px rgba(251, 191, 36, 0.35); }

  .puzzle-meta {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    justify-content: center;
    margin: 0 0 22px;
  }
  .category-chip {
    font-family: var(--font-display);
    font-weight: 600;
    font-size: 0.8rem;
    color: var(--brand-2);
    background: rgba(163, 230, 53, 0.10);
    border: 1px solid rgba(163, 230, 53, 0.28);
    padding: 6px 13px;
    border-radius: var(--r-pill);
  }
  .puzzle-clue {
    max-width: 340px;
    margin: 10px auto 18px;
    font-family: var(--font-ui);
    font-size: 0.98rem;
    font-style: italic;
    line-height: 1.4;
    color: var(--text);
    text-wrap: balance;
  }

  .daily-modifier {
    display: inline-flex;
    align-items: center;
    gap: 10px;
    margin: -10px auto 20px;
    padding: 8px 16px;
    border-radius: var(--r-pill, 999px);
    background: linear-gradient(135deg, rgba(251, 191, 36, 0.12), rgba(163, 230, 53, 0.1));
    border: 1px solid rgba(251, 191, 36, 0.32);
    box-shadow: 0 0 18px rgba(251, 191, 36, 0.12);
  }
  .dm-emoji { font-size: 1.25rem; line-height: 1; }
  .dm-text { display: flex; flex-direction: column; text-align: left; line-height: 1.2; }
  .dm-name {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 0.82rem;
    color: #fcd34d;
    letter-spacing: 0.01em;
  }
  .dm-blurb { font-family: var(--font-ui); font-size: 0.7rem; color: var(--text-muted); }

  .phrase-section {
    width: 100%;
    padding: 0;
    margin-bottom: 0;
    padding-bottom: min(1rem, 3vw);
    min-height: 0;
  }

  .stats-section {
    width: 100%;
    padding: 0;
    margin-top: 0.6rem;
    margin-bottom: 0.4rem;
    flex-shrink: 0;
  }

  @media (max-width: 600px) {
    .phrase-section {
      padding-bottom: 0.75rem;
    }
    .stats-section {
      margin-top: 0.75rem;
    }
  }

  .keyboard-section,
  .buttons-section {
    width: 100%;
    padding: 0;
  }

  .diagnostic-banner {
    background: #ffebee;
    border: 2px solid #c62828;
    border-radius: 8px;
    padding: 12px 16px;
    margin: 12px 0;
    text-align: left;
    font-size: 0.9rem;
    color: #b71c1c;
    max-width: 100%;
  }
  .diagnostic-banner.info {
    background: #e3f2fd;
    border-color: #1976d2;
    color: #0d47a1;
  }
  .diagnostic-retry {
    margin-top: 8px;
    padding: 6px 12px;
    background: #c62828;
    color: white;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    font-weight: bold;
  }
  .diagnostic-retry:hover {
    background: #b71c1c;
  }

  .init-loading {
    min-height: 200px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 1rem;
    color: #666;
  }

  /* Main menu (after sign-in) — premium dark */
  .main-menu {
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 3.5rem 1.1rem 2rem;
    gap: 2rem;
  }
  .menu-hero {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    position: relative;
  }
  .bank-chip {
    position: absolute;
    top: 0;
    left: 0;
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 6px 12px;
    border-radius: 999px;
    background: var(--surface, rgba(255,255,255,0.05));
    border: 1px solid rgba(163, 230, 53, 0.35);
    color: var(--brand-2);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 0.95rem;
    cursor: pointer;
    transition: transform 0.15s, box-shadow 0.2s;
  }
  .bank-chip:hover { transform: translateY(-1px); }
  .bank-chip:active { transform: scale(0.96); }
  .bank-chip .bc-coin { font-size: 1rem; }
  .streak-chip {
    position: absolute;
    top: 0;
    right: 0;
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 6px 12px;
    border-radius: 999px;
    background: var(--surface, rgba(255,255,255,0.05));
    border: 1px solid var(--border);
    color: var(--text-muted);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 0.95rem;
    cursor: pointer;
    transition: transform 0.15s, border-color 0.2s, box-shadow 0.2s;
  }
  .streak-chip:hover { transform: translateY(-1px); }
  .streak-chip:active { transform: scale(0.96); }
  .streak-chip .sc-flame { filter: grayscale(1) opacity(0.5); font-size: 1rem; }
  .streak-chip.lit {
    color: #fcd34d;
    border-color: rgba(251, 191, 36, 0.45);
    box-shadow: 0 0 14px rgba(251, 191, 36, 0.2);
  }
  .streak-chip.lit .sc-flame { filter: none; }
  .menu-mark {
    width: 84px;
    height: 84px;
    object-fit: contain;
    margin-bottom: 14px;
    filter: drop-shadow(0 6px 22px rgba(52, 211, 153, 0.28));
  }
  .menu-wordmark {
    width: min(80vw, 300px);
    height: auto;
    margin: 2px 0 0;
    filter: drop-shadow(0 2px 14px rgba(0, 0, 0, 0.5));
  }
  .main-menu-buttons {
    display: flex;
    flex-direction: column;
    gap: 0.85rem;
    width: 100%;
    max-width: 360px;
  }
  .menu-card {
    display: flex;
    align-items: center;
    gap: 14px;
    text-align: left;
    padding: 16px 18px;
    border-radius: var(--r-lg);
    background: var(--surface);
    border: 1px solid var(--border);
    color: var(--text);
    cursor: pointer;
    backdrop-filter: blur(14px) saturate(140%);
    -webkit-backdrop-filter: blur(14px) saturate(140%);
    transition: transform 0.16s var(--ease-spring), background 0.2s, border-color 0.2s, box-shadow 0.2s;
  }
  .menu-card:hover:not(.disabled) {
    transform: translateY(-2px);
    background: var(--surface-2);
    border-color: var(--border-strong);
    box-shadow: var(--shadow-md);
  }
  .menu-card:active:not(.disabled) { transform: scale(0.99); }
  .menu-card.primary {
    border-color: rgba(163, 230, 53, 0.4);
    background: linear-gradient(135deg, rgba(52, 211, 153, 0.16), rgba(163, 230, 53, 0.06));
    box-shadow: var(--glow-brand);
  }
  .menu-card.disabled { opacity: 0.45; cursor: not-allowed; }
  /* Completed daily: not faded like a dead disabled card — clearly "done", still
     tappable to see the result. Overrides .disabled (declared after it). */
  .menu-card.done {
    opacity: 1;
    cursor: pointer;
    border-color: rgba(255, 255, 255, 0.1);
    background: rgba(255, 255, 255, 0.03);
    box-shadow: none;
  }
  .menu-card.done.primary .mc-icon { background: rgba(255, 255, 255, 0.06); border: 1px solid var(--border); }
  .menu-card.done .mc-sub { color: var(--brand-2); font-weight: 600; }
  .mc-icon {
    width: 46px;
    height: 46px;
    flex-shrink: 0;
    display: grid;
    place-items: center;
    font-size: 1.4rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid var(--border);
    border-radius: 13px;
  }
  .menu-card.primary .mc-icon {
    background: var(--brand-grad);
    border: none;
  }
  .mc-body { display: flex; flex-direction: column; gap: 2px; flex: 1; }
  .mc-title { font-family: var(--font-display); font-weight: 600; font-size: 1.06rem; }
  .mc-sub { font-size: 0.8rem; color: var(--text-muted); }
  .mc-arrow { color: var(--text-faint); font-size: 1.1rem; transition: transform 0.2s, color 0.2s; }
  .menu-card:hover:not(.disabled) .mc-arrow { transform: translateX(3px); color: var(--brand-2); }

  /* Modal action button (reused brand button) */
  .main-menu-btn {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 1rem;
    padding: 13px 20px;
    border-radius: var(--r-md);
    border: none;
    background: var(--brand-grad);
    color: #06210f;
    cursor: pointer;
    box-shadow: var(--glow-brand);
    transition: transform 0.15s var(--ease-spring), filter 0.2s;
  }
  .main-menu-btn:hover { transform: translateY(-2px); filter: brightness(1.05); }
  .main-menu-btn.ghost-btn {
    background: var(--surface-2, rgba(255, 255, 255, 0.06));
    color: var(--text);
    border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.16));
    box-shadow: none;
  }
  .main-menu-modal { text-align: center; }
  .main-menu-modal .main-menu-btn { margin-top: 1rem; }

  /* Free Play category picker */
  .cat-modal { max-width: 420px; }
  .cat-sub { font-size: 0.85rem; color: var(--text-muted); margin: 0 0 16px; }

  /* Challenges modal */
  .ch-modal { max-width: 440px; }
  .ch-new { display: flex; flex-direction: column; gap: 0.5rem; margin-bottom: 1rem; }
  .ch-row { display: flex; gap: 0.5rem; }
  .ch-input {
    flex: 1; min-width: 0; padding: 0.6rem 0.8rem; border-radius: 10px; border: 1px solid var(--border);
    background: var(--surface); color: var(--text); font-size: 0.9rem;
  }
  .ch-create { padding: 0.6rem 1rem; border: none; border-radius: 10px; cursor: pointer; font-weight: 700; color: #06210f; background: var(--brand-grad, linear-gradient(135deg,#34d399,#a3e635)); }
  .ch-create:disabled { opacity: 0.6; }
  .ch-list { display: flex; flex-direction: column; gap: 0.5rem; max-height: 280px; overflow-y: auto; }
  .ch-item { display: flex; align-items: center; justify-content: space-between; gap: 0.6rem; padding: 0.7rem 0.8rem; background: var(--surface); border: 1px solid var(--border); border-radius: 12px; }
  .ch-info { display: flex; flex-direction: column; gap: 2px; text-align: left; min-width: 0; }
  .ch-vs { font-weight: 600; font-size: 0.9rem; }
  .ch-meta { font-size: 0.75rem; color: var(--text-faint); }
  .ch-play { padding: 0.45rem 0.9rem; border: none; border-radius: 999px; cursor: pointer; font-weight: 700; font-size: 0.85rem; color: #06210f; background: var(--brand-grad, linear-gradient(135deg,#34d399,#a3e635)); }
  .ch-play:disabled { opacity: 0.6; }
  .ch-waiting { font-size: 0.8rem; color: var(--text-faint); }
  .ch-result { font-family: var(--font-display); font-weight: 700; font-size: 0.8rem; }
  .ch-result.win { color: var(--brand-2); }
  .ch-result.loss { color: #fb7185; }
  .ch-result.tie { color: var(--text-muted); }
  .cat-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 10px;
  }
  .cat-tile {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    padding: 14px 8px;
    border-radius: var(--r-md, 14px);
    background: var(--surface, rgba(255, 255, 255, 0.05));
    border: 1px solid var(--border, rgba(255, 255, 255, 0.12));
    color: var(--text);
    cursor: pointer;
    transition: transform 0.15s var(--ease-spring, ease), border-color 0.2s, background 0.2s;
  }
  .cat-tile:hover { transform: translateY(-2px); border-color: rgba(163, 230, 53, 0.5); background: var(--surface-2, rgba(255, 255, 255, 0.07)); }
  .cat-tile:active { transform: scale(0.97); }
  .cat-emoji { font-size: 1.6rem; line-height: 1; }
  .cat-label {
    font-family: var(--font-display);
    font-weight: 600;
    font-size: 0.82rem;
    text-align: center;
    line-height: 1.1;
  }

  /* Streak + freeze chips (My Account) */
  .account-stats {
    display: flex;
    gap: 10px;
    justify-content: center;
    margin: 14px 0 4px;
  }
  .stat-chip {
    display: inline-flex;
    align-items: baseline;
    gap: 5px;
    padding: 8px 14px;
    border-radius: var(--r-pill);
    background: var(--surface);
    border: 1px solid var(--border);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 1.1rem;
    color: var(--text);
  }
  .stat-emoji { font-size: 1rem; }
  .stat-cap {
    font-family: var(--font-ui);
    font-weight: 600;
    font-size: 0.62rem;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--text-faint);
  }

  .streak-message {
    margin: 1rem 0 0 0;
    font-size: 1.05rem;
    color: var(--text-muted);
  }
  .cbt-medal { font-size: 2.6rem; line-height: 1; margin-bottom: 0.3rem; }
  .cbt-result { font-size: 0.95rem; color: var(--text-muted); margin: 0.2rem 0 0; }
  .cbt-stats {
    display: flex;
    justify-content: center;
    gap: 0.6rem;
    margin: 1.1rem 0 0.2rem;
  }
  .cbt-stat {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
    min-width: 78px;
    padding: 0.6rem 0.5rem;
    background: rgba(255, 255, 255, 0.04);
    border: 1px solid var(--border);
    border-radius: 13px;
  }
  .cbt-val { font-family: var(--font-display); font-weight: 700; font-size: 1.15rem; color: var(--brand-2); }
  .cbt-cap { font-size: 0.68rem; text-transform: uppercase; letter-spacing: 0.05em; color: var(--text-faint); }
  .account-email {
    font-size: 0.95rem;
    color: var(--text-muted);
    margin: 0.5rem 0 0 0;
  }

  .bankroll-container {
    display: flex;
    justify-content: center;
    align-items: center;
    width: 100%;
    margin: 0 auto;
  }

  .bankroll-box {
    position: relative;
    display: inline-flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
    padding: 12px 30px;
    background: var(--surface-strong);
    border: 1px solid var(--border);
    border-radius: var(--r-lg);
    box-shadow: var(--shadow-md), inset 0 1px 0 rgba(255, 255, 255, 0.06);
    backdrop-filter: blur(14px);
    -webkit-backdrop-filter: blur(14px);
  }
  .bankroll-box.pulse-up { animation: bankPulseUp 0.7s var(--ease-spring); }
  .bankroll-box.pulse-down { animation: bankPulseDown 0.6s var(--ease-spring); }
  @keyframes bankPulseUp {
    0%, 100% { transform: scale(1); box-shadow: var(--shadow-md), inset 0 1px 0 rgba(255,255,255,0.06); }
    40% { transform: scale(1.07); box-shadow: var(--shadow-md), 0 0 30px rgba(163,230,53,0.55); }
  }
  @keyframes bankPulseDown {
    0%, 100% { transform: scale(1); }
    35% { transform: scale(0.96); }
  }
  .bankroll-delta {
    position: absolute;
    top: 2px;
    right: 12px;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 0.95rem;
    font-variant-numeric: tabular-nums;
    pointer-events: none;
    text-shadow: 0 0 12px currentColor;
  }
  .bankroll-delta.up { color: var(--brand-2); animation: deltaFloatUp 0.95s var(--ease-out) forwards; }
  .bankroll-delta.down { color: #fb7185; animation: deltaFloatDown 0.95s var(--ease-out) forwards; }
  @keyframes deltaFloatUp {
    0% { opacity: 0; transform: translateY(8px); }
    25% { opacity: 1; }
    100% { opacity: 0; transform: translateY(-28px); }
  }
  @keyframes deltaFloatDown {
    0% { opacity: 0; transform: translateY(-8px); }
    25% { opacity: 1; }
    100% { opacity: 0; transform: translateY(24px); }
  }
  .hot-hand-flash {
    position: absolute;
    top: -14px;
    left: 50%;
    transform: translateX(-50%);
    white-space: nowrap;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 0.9rem;
    color: #fcd34d;
    background: rgba(120, 53, 15, 0.85);
    border: 1px solid rgba(251, 191, 36, 0.55);
    border-radius: 999px;
    padding: 4px 12px;
    pointer-events: none;
    text-shadow: 0 0 10px rgba(251, 191, 36, 0.6);
    box-shadow: 0 0 18px rgba(251, 191, 36, 0.35);
    animation: hotHandPop 1.3s var(--ease-out) forwards;
    z-index: 5;
  }
  @keyframes hotHandPop {
    0% { opacity: 0; transform: translateX(-50%) translateY(8px) scale(0.8); }
    18% { opacity: 1; transform: translateX(-50%) translateY(0) scale(1.05); }
    32% { transform: translateX(-50%) translateY(0) scale(1); }
    80% { opacity: 1; }
    100% { opacity: 0; transform: translateX(-50%) translateY(-22px) scale(1); }
  }

  .bankroll-label {
    font-family: var(--font-ui);
    font-size: 0.62rem;
    font-weight: 600;
    letter-spacing: 0.2em;
    text-transform: uppercase;
    color: var(--text-faint);
  }

  .bankroll-amount {
    display: inline-flex;
    align-items: center;
  }

  .currency {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 1.55rem;
    margin-right: 3px;
    color: #fcd34d;
    text-shadow: 0 0 14px rgba(251, 191, 36, 0.45);
  }

  .game-logo {
    display: block;
    width: min(64vw, 230px);
    height: auto;
    margin: 6px auto 16px;
    filter: drop-shadow(0 2px 12px rgba(0, 0, 0, 0.5));
  }

  .logo-container {
    display: flex;
    justify-content: center;
    align-items: center;
    margin-top: -20px;
    margin-bottom: 0;
  }

  :global(html, body) {
    overflow-x: hidden;
    touch-action: manipulation;
  }

  @keyframes winPulse {
    0%, 100% { transform: scale(1) rotate(0deg); text-shadow: 0px 0px 10px green; }
    25% { transform: scale(1.2) rotate(3deg); text-shadow: 0px 0px 20px limegreen; }
    50% { transform: scale(1.5) rotate(-3deg); text-shadow: 0px 0px 30px limegreen; }
    75% { transform: scale(1.2) rotate(3deg); text-shadow: 0px 0px 20px green; }
  }

  @keyframes winFlash {
    0% { opacity: 1; }
    50% { opacity: 0.2; }
    100% { opacity: 1; }
  }

  .win-burst {
    position: fixed;
    inset: 0;
    z-index: 998;
    pointer-events: none;
    background: radial-gradient(circle at 50% 45%, rgba(163, 230, 53, 0.35), rgba(52, 211, 153, 0.18) 35%, transparent 60%);
    animation: winBurst 1s var(--ease-out) forwards;
  }
  @keyframes winBurst {
    0% { opacity: 0; transform: scale(0.4); }
    30% { opacity: 1; }
    100% { opacity: 0; transform: scale(1.6); }
  }

  .banner.win {
    font-family: var(--font-display);
    font-size: 1.6rem;
    font-weight: 700;
    letter-spacing: 0.02em;
    color: #06210f;
    text-transform: uppercase;
    background: var(--brand-grad);
    text-align: center;
    padding: 14px 28px;
    border-radius: var(--r-pill);
    box-shadow: var(--glow-brand);
    animation: bannerPop 0.5s var(--ease-spring) both;
  }
  @keyframes bannerPop {
    from { transform: scale(0.8); opacity: 0; }
    to { transform: scale(1); opacity: 1; }
  }

  @keyframes gameOverPulse {
    0%, 100% { transform: scale(1) rotate(0deg); text-shadow: 0px 0px 10px red; }
    25% { transform: scale(1.2) rotate(3deg); text-shadow: 0px 0px 20px red; }
    50% { transform: scale(1.5) rotate(-3deg); text-shadow: 0px 0px 30px red; }
    75% { transform: scale(1.2) rotate(3deg); text-shadow: 0px 0px 20px red; }
  }

  @keyframes gameOverFlash {
    0% { opacity: 1; }
    50% { opacity: 0.2; }
    100% { opacity: 1; }
  }

  .banner.lose {
    font-family: var(--font-display);
    font-size: 1.6rem;
    font-weight: 700;
    letter-spacing: 0.02em;
    color: #fff;
    text-transform: uppercase;
    background: linear-gradient(135deg, #fb5a5a, #c81e1e);
    text-align: center;
    padding: 14px 28px;
    border-radius: var(--r-pill);
    box-shadow: 0 8px 28px rgba(200, 30, 30, 0.4);
    animation: bannerPop 0.5s var(--ease-spring) both;
  }

  button:focus,
  button:active {
    outline: none !important;
    box-shadow: none !important;
    background: inherit !important;
  }

  button:focus-visible {
    outline: none !important;
  }

  .top-buttons {
    position: fixed;
    top: 12px;
    left: 50%;
    transform: translateX(-50%);
    width: calc(100% - 24px);
    max-width: 600px;
    display: flex;
    justify-content: space-between;
    z-index: 1000;
  }

  .icon-button, a.icon-button {
    width: 40px;
    height: 40px;
    display: grid;
    place-items: center;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-pill);
    text-decoration: none;
    font-size: 18px;
    line-height: 1;
    cursor: pointer;
    color: var(--text);
    backdrop-filter: blur(10px);
    -webkit-backdrop-filter: blur(10px);
    transition: transform 0.18s var(--ease-spring), background 0.2s, border-color 0.2s;
  }

  .icon-button:hover, a.icon-button:hover {
    background: var(--surface-2);
    border-color: var(--border-strong);
    transform: translateY(-1px) scale(1.05);
  }

  .subtle-button { opacity: 0.95; }

  .modal-overlay {
    position: fixed;
    inset: 0;
    background: rgba(4, 7, 12, 0.66);
    backdrop-filter: blur(8px);
    -webkit-backdrop-filter: blur(8px);
    display: flex;
    justify-content: center;
    align-items: center;
    z-index: 9999;
    animation: fadeIn 0.25s ease-out;
  }
  .modal-backdrop {
    position: absolute;
    inset: 0;
    background: transparent;
    border: none;
    cursor: pointer;
  }

  .modal-content {
    background: var(--surface-strong);
    padding: 28px 24px;
    border-radius: var(--r-xl);
    width: 90%;
    max-width: 400px;
    text-align: center;
    box-shadow: var(--shadow-lg);
    animation: slideIn 0.35s var(--ease-out);
    border: 1px solid var(--border-strong);
    color: var(--text);
    backdrop-filter: blur(20px) saturate(140%);
    -webkit-backdrop-filter: blur(20px) saturate(140%);
    position: relative;
    z-index: 1;
  }
  .modal-content :global(h2) { font-family: var(--font-display); }

  .close-btn {
    position: absolute;
    top: 12px;
    right: 12px;
    width: 32px;
    height: 32px;
    display: grid;
    place-items: center;
    font-size: 13px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-pill);
    cursor: pointer;
    transition: background 0.2s, border-color 0.2s;
  }
  .close-btn:hover { background: rgba(251, 90, 90, 0.16); border-color: rgba(251, 90, 90, 0.4); }

  @keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes slideIn {
    from { transform: translateY(-20px); }
    to { transform: translateY(0); }
  }

  .next-puzzle-button {
    margin-top: 12px;
    background: var(--brand-grad);
    color: #06210f;
    font-family: var(--font-display);
    font-weight: 700;
    border: none;
    padding: 13px 28px;
    border-radius: var(--r-md);
    font-size: 1rem;
    cursor: pointer;
    box-shadow: var(--glow-brand);
    transition: transform 0.16s var(--ease-spring), filter 0.2s;
  }
  .next-puzzle-button:hover { transform: translateY(-2px); filter: brightness(1.05); }
  .next-puzzle-button:active { transform: scale(0.97); }

  /* Result modal (daily/arcade) */
  .result-modal h2 { font-size: 1.7rem; margin: 4px 0 2px; }
  .result-medal {
    font-size: 3.4rem;
    line-height: 1;
    margin-bottom: 6px;
    animation: wb-pop-in 0.6s var(--ease-spring) both;
    filter: drop-shadow(0 6px 18px rgba(0, 0, 0, 0.5));
  }
  .result-medal.gold { filter: drop-shadow(0 0 22px rgba(251, 191, 36, 0.6)); }
  .result-medal.silver { filter: drop-shadow(0 0 18px rgba(203, 213, 225, 0.5)); }
  .result-medal.bronze { filter: drop-shadow(0 0 18px rgba(217, 119, 60, 0.5)); }
  .result-sub {
    color: var(--text-muted);
    font-family: var(--font-display);
    font-weight: 600;
    font-size: 0.92rem;
    margin: 0 0 16px;
  }
  .result-bankroll {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
    padding: 14px;
    margin: 0 0 18px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-lg);
  }
  .rb-label {
    font-size: 0.6rem;
    letter-spacing: 0.2em;
    text-transform: uppercase;
    color: var(--text-faint);
    font-weight: 600;
  }
  .rb-amount {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 2rem;
    color: #fcd34d;
    text-shadow: 0 0 18px rgba(251, 191, 36, 0.4);
  }
  .ghost-compare {
    margin: 2px auto 16px;
    padding: 10px 14px;
    max-width: 300px;
    border-radius: 14px;
    background: var(--surface-2, rgba(255, 255, 255, 0.05));
    border: 1px solid var(--border, rgba(255, 255, 255, 0.1));
  }
  .ghost-line {
    font-family: var(--font-ui);
    font-size: 0.86rem;
    color: var(--text-muted, #c2cbd8);
    margin: 0 0 4px;
  }
  .ghost-line b { color: var(--text, #fff); }
  .ghost-delta {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 0.95rem;
    margin: 0;
  }
  .ghost-delta.up { color: #34d399; }
  .ghost-delta.down { color: #fb7185; }
  .ghost-delta.even { color: var(--text-muted, #c2cbd8); }
  .ghost-field {
    font-family: var(--font-ui);
    font-size: 0.76rem;
    color: var(--text-faint, #8a94a6);
    margin: 8px 0 0;
    padding-top: 8px;
    border-top: 1px solid var(--border, rgba(255, 255, 255, 0.08));
  }
  .result-actions {
    display: flex;
    gap: 10px;
  }
  .result-actions > * { flex: 1; margin-top: 0; }
  .share-btn {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 1rem;
    padding: 13px 18px;
    border-radius: var(--r-md);
    background: var(--surface-2);
    color: var(--text);
    border: 1px solid var(--border-strong);
    cursor: pointer;
    transition: transform 0.15s var(--ease-spring), background 0.2s, border-color 0.2s;
  }
  .share-btn:hover { transform: translateY(-2px); background: rgba(56, 189, 248, 0.14); border-color: rgba(56, 189, 248, 0.4); }
  .share-btn:active { transform: scale(0.97); }

  .subcategory-hint {
  font-size: 1rem;
  font-style: italic;
  color: #999;
  margin-bottom: 12px;
}




</style>