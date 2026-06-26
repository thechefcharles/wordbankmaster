<script>
  import { onMount, onDestroy, tick } from 'svelte';
  import { browser } from '$app/environment';
  import { supabase } from '$lib/supabaseClient';
  import { get } from 'svelte/store';
  import { tweened } from 'svelte/motion';
  import { cubicOut } from 'svelte/easing';

  import { gameStore, fetchDailyGame, useDailyTwist, useDailyBoost, fetchFreeplayGame, fetchFreeplayResume, freeplayContinue, startChallenge, acceptAndPlayChallenge, resumeChallenge, challengeTimeoutCheck, fetchMakeupGame, fetchClimbGame, climbAdvance, climbLeaveGame, climbSkipPuzzle, climbArmDoubleOrNothing, climbPowerup, startMatch, acceptAndPlayMatch, resumeMatch, matchTimeoutCheck, matchPowerup, matchSabotageOpponent, dailyFold, matchFold } from '$lib/stores/GameStore.js';
  import { getMyChallenges, getPowerups, getDailyAvailBoosts, getMyMatches, getMyGroups, getMatch, getMatchDetail, declineMatch } from '$lib/stores/statsStore.js';
  import { CATEGORIES } from '$lib/categories.js';
  import { user, userProfile, fetchUserProfile, ensureProfileExists } from '$lib/stores/userStore.js';
  import { getDailyStatus, getOpenGames, expireStaleDailies, getDailyGhost, getMyDailyRank, addFriend, searchUsers, getMyUsername, setUsername, getBank, getDailyBoard, getMatchMessages, sendMatchMessage, getFriendRequestCount, respondFriendRequest, listFriendRequests, getFreeplayCashoutStatus, freeplayCashout, getDailyModifier } from '$lib/stores/statsStore.js';
  import { unreadCount, refreshNotifications, inboxRequest, inboxTarget, markChallengeNotifRead, markFriendNotifRead } from '$lib/stores/notificationStore.js';
  import { track } from '$lib/analytics.js';
  import { modifierInfo } from '$lib/powerups.js';
  import {
    saveGameToLocalStorage,
    clearSavedGame,
    getSavedGameInfo
  } from '$lib/stores/localGameUtils.js';
  import { gameWasRestored } from '$lib/stores/GameStateFlags.js';
  import { soundEnabled, toggleSound, fx } from '$lib/sound.js';
  import { startMusic, stopMusic, musicEnabled, musicVolume, setMusicVolume, toggleMusic, TRACKS, currentTrackId, selectTrack } from '$lib/music.js';
  import PinGate from '$lib/components/PinGate.svelte';
  import { pinLocked, hasPinFor, clearPin, markUnlocked, sessionIsUnlocked, markPinSkipped, pinSkipped, clearPinSkipped } from '$lib/pin.js';
  import { requirePin } from '$lib/pinConfirm.js';
  import { goto } from '$app/navigation';

  import PhraseDisplay from '$lib/components/PhraseDisplay.svelte';
  import InventoryList from '$lib/components/InventoryList.svelte';
  import VaultReveal from '$lib/components/VaultReveal.svelte';
  import Keyboard from '$lib/components/Keyboard.svelte';
  import GameButtons from '$lib/components/GameButtons.svelte';
  import FlipDigit from '$lib/components/FlipDigit.svelte';
  import Auth from '$lib/components/Auth.svelte';
  import Tutorial from '$lib/components/Tutorial.svelte';
  import ObjectiveCard from '$lib/components/ObjectiveCard.svelte';
  import StandingStrip from '$lib/components/StandingStrip.svelte';
  import MatchDetailModal from '$lib/components/MatchDetailModal.svelte';
  import LeaderboardPanel from '$lib/components/LeaderboardPanel.svelte';
  import ActivityPanel from '$lib/components/ActivityPanel.svelte';
  import FriendsPanel from '$lib/components/FriendsPanel.svelte';
  import GroupsPanel from '$lib/components/GroupsPanel.svelte';

  export let data;

  // UI state
  let showTutorial = false;
  let showLaunchWelcome = false;
  let menuView = 'home'; // 'home' | 'play' | 'challenge' | 'progress'
  let blitzSoon = false;
  let showResultModal = false;
  let hasTriggeredModal = false;
  let hasInitialized = false;
  let sessionUid = '';     // current session user id (for the PIN gate)
  let pinNotSet = false;   // logged in on this device with no PIN yet → prompt setup
  /** @type {string | null} */
  let initError = null; // 🔍 Diagnostic: what failed during init
  /** Show main menu (Daily / Arcade / Leaderboard / My account) when true; game when false */
  let showMainMenu = false;
  /** When showing menu: can we show "Resume daily" / "Resume arcade"? */
  let savedGameInfo = /** @type {{ gameMode: string, gameState: string } | null} */ (null);
  /** When showing menu: has user already played daily today? */
  let menuDailyPlayed = false;
  /** Today's daily result for the menu indicator (won/lost + score). */
  let dailyStatus = /** @type {{ has_played_today: boolean, last_daily_won: boolean|null, daily_bankroll: number, arcade_bankroll: number, current_streak: number, streak_freezes: number, today_score: number, win_streak: number, daily_in_progress?: boolean } | null} */ (null);
  // 🎮 Live solo games from SERVER truth (daily/climb/freeplay), newest first. The old
  // single localStorage save slot got overwritten whenever you played another mode, which
  // made a live Daily show as "complete + lost". openGames lets every mode resume independently.
  /** @type {{mode:string, updated_at:string}[]} */
  let openGames = [];
  async function refreshOpenGames() {
    const u = get(user); if (!u?.id) return;
    try { openGames = await getOpenGames(); } catch { /* keep last */ }
  }
  // "In progress" must come from SERVER truth, not the clobberable localStorage slot.
  $: dailyInProgress = openGames.some((g) => g.mode === 'daily') || (dailyStatus?.daily_in_progress ?? false);
  $: dailyDone = menuDailyPlayed && !dailyInProgress;
  $: climbInProgress = openGames.some((g) => g.mode === 'climb');
  // 🔁 Resume shortcut: jump back to your most-recently-played live game.
  const RESUME_LABEL = /** @type {Record<string,string>} */ ({ daily: 'Daily', climb: 'Cash Game', freeplay: 'Free Play' });
  $: resumeGame = openGames[0] ?? null;
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
    // Safety net: never strand a logged-in user on the loading screen if a slow or
    // failed secondary call blocks init.
    const initFallback = setTimeout(() => {
      if (!hasInitialized) { showMainMenu = true; hasInitialized = true; }
    }, 6000);
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
        showMainMenu = true; hasInitialized = true;  // surface the menu instead of hanging
        return;
      }

      // Device PIN gate (approach A): if a PIN is set on this device, lock until it's
      // entered; otherwise mark that we should prompt to set one (after username).
      sessionUid = session.user.id;
      // Lock only on a cold open (close → reopen), not on in-app navigation back
      // to the menu — sessionIsUnlocked() persists the unlock for this app session.
      if (hasPinFor(sessionUid)) { if (!sessionIsUnlocked()) pinLocked.set(true); }
      else pinNotSet = !pinSkipped(sessionUid); // don't re-nag if they chose "Skip for now"

      // Make-up daily launched from the streak calendar → drop straight into the board.
      if (localStorage.getItem('gameMode') === 'makeup' && localStorage.getItem('makeupDate')) {
        showMainMenu = false;
        hasInitialized = true;
        await fetchMakeupGame();
        return;
      }

      // Into the menu immediately — the loading screen only gates on auth + profile.
      showMainMenu = true;
      // Load any in-progress game so the menu shows "Resume" (not "Missed") after
      // returning from another route (e.g. the Store).
      savedGameInfo = getSavedGameInfo(session.user.id);
      hasInitialized = true;

      // Secondary menu data: must NOT block the loading screen or each other.
      // Finalize any unfinished Daily from a prior day (no timer → it expires as a loss)
      // BEFORE reading status/open games, so the menu reflects it.
      expireStaleDailies().catch(() => {}).finally(() => {
        getDailyStatus(session.user.id)
          .then((ds) => { dailyStatus = ds; menuDailyPlayed = ds.has_played_today; })
          .catch((e) => console.error('daily status:', e));
        refreshOpenGames();
      });
      refreshBank();
      refreshChallengeCount();
      // First-run username gate: prompt if this account hasn't claimed one yet.
      getMyUsername().then((u) => { needsUsername = !u; }).catch(() => {});

      // Friend invite link: ?add=USERNAME → add them, then open the Friends board.
      try {
        const params = new URLSearchParams(window.location.search);
        const addName = params.get('add');
        if (addName) {
          const res = await addFriend(addName);
          if (res?.ok) { track('friend_add', { via: 'link' }); goto('/leaderboard?mode=friends'); }
        } else if (params.get('challenges')) {
          openChallenges();
        }
      } catch { /* non-fatal */ }

    } catch (err) {
      initError = "Init error: " + (err instanceof Error ? err.message : String(err));
      console.error("❌", initError);
      showMainMenu = true; hasInitialized = true;  // don't hang on a transient error
    } finally {
      clearTimeout(initFallback);
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
    if (gameMode === 'freeplay') {
      // Free Play isn't deep-link restorable — send back to the menu to re-pick.
      showMainMenu = true;
    } else if (gameMode === 'makeup') {
      fetchMakeupGame().then((ok) => { if (!ok) showMainMenu = true; });
    } else if (gameMode === 'climb') {
      fetchClimbGame().then((ok) => { if (!ok) showMainMenu = true; });
    } else if (gameMode === 'match') {
      // Matches aren't deep-link restorable (need the active id) — return to the menu.
      localStorage.setItem('gameMode', 'daily');
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
  // PIN gate: unlock screen for returning users; set-PIN after username for new ones.
  $: showPinUnlock = loggedIn && hasInitialized && $pinLocked;
  $: showPinSetup = loggedIn && hasInitialized && !$pinLocked && pinNotSet && !needsUsername;
  // ===== Home "act-now" banner: the single most-urgent thing needing me =====
  /** @type {any[]} incoming friend requests [{id,name,username}] */
  let friendRequests = [];
  // When a new notification lands (badge ticks up), refresh the act-now banner's
  // matches/requests too — so a fresh challenge shows up live, not just the count.
  let _prevUnread = 0;
  $: handleUnreadRise($unreadCount);
  function handleUnreadRise(/** @type {number} */ n) {
    if (browser && loggedIn && hasInitialized && n > _prevUnread) refreshChallengeCount();
    _prevUnread = n;
  }
  // Challenges where it's my turn, soonest-to-expire first.
  $: turnMatches = (myMatches ?? [])
    .filter((m) => m.status === 'open' && m.my_state !== 'done')
    .slice()
    .sort((a, b) => new Date(a.settles_at || 0).getTime() - new Date(b.settles_at || 0).getTime());
  // Priority: your-turn challenge → friend request → "challenge a friend" CTA.
  $: actNow = (() => {
    // Name is the bold title (short, never cuts a word); the verb is the muted sub.
    if (turnMatches.length) {
      const m = turnMatches[0];
      const invited = m.my_state === 'invited';
      return { kind: 'match', icon: '⚔️',
        title: m.host,
        sub: invited ? 'Challenged you' : 'Your turn',
        cta: (invited ? 'Play' : 'Resume') + ' →',
        more: turnMatches.length - 1, // other challenges waiting
        primary: () => respondToMatch(m), moreAction: () => openChallenges() };
    }
    if (friendRequests.length) {
      const r = friendRequests[0];
      return { kind: 'friend', icon: '👋',
        title: r.name || '@' + r.username, sub: 'Wants to be friends',
        cta: 'Accept →', more: friendRequests.length - 1,
        primary: () => acceptFriend(r), moreAction: () => goto('/friends') };
    }
    return { kind: 'empty', icon: '⚔️', title: 'Challenge a friend', sub: '', cta: '→',
      more: 0, primary: () => openChallenges('new'), moreAction: null };
  })();
  /** @param {any} r */
  async function acceptFriend(r) {
    fx('tap');
    await respondFriendRequest(r.id, true);
    markFriendNotifRead(r.id);
    await refreshChallengeCount();
  }
  function onPinUnlocked() { markUnlocked(); pinLocked.set(false); }
  function onPinSet() { markUnlocked(); clearPinSkipped(); pinNotSet = false; }
  function onPinSkip() { markUnlocked(); markPinSkipped(sessionUid); pinNotSet = false; } // remember the skip so it doesn't nag every open
  function onPinLogout() { clearPin(); clearPinSkipped(); pinLocked.set(false); pinNotSet = false; handleLogout(); }
  // Lobby music: play in the menu only — not while locked, setting a PIN, or in-game.
  $: if (browser) { (loggedIn && hasInitialized && showMainMenu && !showPinUnlock && !showPinSetup) ? startMusic() : stopMusic(); }
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


  // ---- Daily result: shareable card ----
  // Each day is its own puzzle (one per date), so show the date — not a counter.
  $: todayLabel = browser ? new Date().toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' }) : '';

  /** @param {number} br @param {boolean} won */
  function medalFor(br, won) {
    if (!won) return { emoji: '💀', name: 'Busted', tier: 'none' };
    if (br >= 700) return { emoji: '🥇', name: 'Gold', tier: 'gold' };
    if (br >= 400) return { emoji: '🥈', name: 'Silver', tier: 'silver' };
    return { emoji: '🥉', name: 'Bronze', tier: 'bronze' };
  }
  $: resultWon = $gameStore.gameState === 'won';
  $: isDailyResult = $gameStore.gameMode === 'daily';
  // Live Daily HUD metrics (only while actively playing the daily).
  $: dLive = (($gameStore.gameMode === 'daily' || $gameStore.gameMode === 'makeup') && $gameStore.gameState !== 'won' && $gameStore.gameState !== 'lost')
    ? $gameStore.dailyLive : null;
  $: isFreeplay = $gameStore.gameMode === 'freeplay';
  $: isChallenge = $gameStore.gameMode === 'challenge';
  $: isMakeup = $gameStore.gameMode === 'makeup';
  // Auto-dismiss the Cash-earned toast after a few seconds.
  /** @type {ReturnType<typeof setTimeout>|undefined} */
  let _attTimer;
  $: if ($gameStore.cashToast) {
    clearTimeout(_attTimer);
    _attTimer = setTimeout(() => gameStore.update(s => ({ ...s, cashToast: null })), 4000);
  }
  $: isClimb = $gameStore.gameMode === 'climb';
  $: climb = $gameStore.climbInfo; // { bounty, heat, spent, position, stuck, last_gain, state, pups_locked, equipped }
  // 🏷️ Which mode you're in — a consistent pill under the wordmark on every game screen.
  $: modeLabel = ({
    daily:     { emoji: '📅', name: 'Daily' },
    climb:     { emoji: '🎰', name: 'Cash Game' },
    freeplay:  { emoji: '🎯', name: 'Free Play' },
    makeup:    { emoji: '📅', name: 'Make-up' },
    match:     { emoji: '⚔️', name: 'Challenge' },
    challenge: { emoji: '⚔️', name: 'Challenge' }
  })[$gameStore.gameMode] ?? null;
  $: isMatch = $gameStore.gameMode === 'match';
  $: matchInfo = $gameStore.matchInfo; // { position, pack_size, total_score, last_score, done, mode, solved, spent, budget, wager, items_allowed, used_powerups, started_at, clock_seconds, combo }
  $: matchBlitz = isMatch && matchInfo?.mode === 'blitz' && !matchInfo?.done;
  $: matchCombo = ((matchInfo?.combo ?? 100) / 100).toFixed(2);
  let matchExpiredFired = false;
  // 💥 Double or Nothing (Cash Game): server exposes don_armed + don_available (heat ≥ ×1.5).
  $: donArmed = !!climb?.don_armed;
  $: donAvailable = !!climb?.don_available;
  // The doubled target payout (matches server: bounty ×2, then × heat, rounded).
  $: donTarget = (isClimb && climb) ? Math.round((climb.bounty ?? 0) * 2 * (climb.heat ?? 100) / 100) : 0;
  // Climb live: Spent · Payout (bounty × heat, doubled while armed) · Net.
  $: climbLive = (isClimb && climb && climb.state === 'active')
    ? (() => { const m = climb.don_armed ? 2 : 1; const pay = Math.round((climb.bounty ?? 0) * m * (climb.heat ?? 100) / 100); const sp = climb.spent ?? 0; return { spent: sp, payout: pay, net: pay - sp }; })()
    : null;
  // Win banner needs to know the solve was a Double-or-Nothing (server clears don_armed on solve).
  let donArmedThisPuzzle = false;
  $: if (isClimb && climb) {
    if (climb.don_armed) donArmedThisPuzzle = true;
    else if (climb.state === 'stuck' || (climb.state === 'active' && (climb.spent ?? 0) === 0)) donArmedThisPuzzle = false;
  }
  // Challenge live: Spent of your wager budget — lowest spend wins (standard only).
  $: matchLive = (isMatch && matchInfo && !matchInfo.done && matchInfo.mode !== 'blitz')
    ? { spent: matchInfo.spent ?? 0, budget: matchInfo.budget ?? 0 } : null;
  // Free Play live: clean status + the trickle you'd earn.
  $: freeLive = ($gameStore.gameMode === 'freeplay' && $gameStore.gameState !== 'won' && $gameStore.gameState !== 'lost')
    ? { clean: ($gameStore.incorrectLetters?.length ?? 0) === 0 } : null;
  // Unified solo money hero (Daily · Makeup · Cash Game): net you keep if you solve now.
  $: soloHero = climbLive ? { net: climbLive.net } : (dLive ? { net: dLive.net } : null);

  // 🎰 Slot-machine money feel: count up/down the bankroll + the green "Solve to Earn",
  // and float a -$X by the number each time you spend.
  const tweenBank = tweened(0, { duration: 550, easing: cubicOut });
  const tweenNet = tweened(0, { duration: 900, easing: cubicOut });
  // 🏆 Win-banner animations: profit counts up, then Cash scrolls to the new total.
  const resultProfit = tweened(0, { duration: 1100, easing: cubicOut });
  const resultBankAnim = tweened(0, { duration: 1300, easing: cubicOut });
  /** @type {{rank:number,total:number,score:number}|null} */
  let resultRank = null;
  $: tweenBank.set(Math.round($gameStore.bankroll ?? 0));
  // While the opening reveal is landing boxes, hold the bounty at $0 so it can
  // dramatically count up at the climax (introDone).
  $: tweenNet.set(introBuilding ? 0 : (soloHero ? Math.round(soloHero.net) : 0));

  // 🎰 Daily opening reveal coordination (boxes land → bounty counts up × multiplier).
  // fetchDailyGame ARMS it (dailyIntro token); we only PLAY it once the board is
  // actually on screen — i.e. the "How to win" card is dismissed — by bumping
  // dailyIntroGo, which PhraseDisplay watches.
  let introBuilding = false;
  let _introFired = 0;
  let introCountPop = false;
  // Play the armed opening reveal — but only when the board is truly on screen
  // (no objective card up, not on the menu). Called from dismissObjective and,
  // when the card is suppressed, right after the board renders.
  function playDailyIntroIfArmed() {
    const st = get(gameStore);
    const tok = st.dailyIntro;
    // Play once per FRESH open (token). dailyIntroPlayed lives in the store so it
    // survives remounts (e.g. back from the leaderboard); the auto-applied Twist
    // revealing letters no longer wrongly suppresses the reveal.
    if (!browser || !tok || tok === st.dailyIntroPlayed) return;
    if (objective || showMainMenu) return;
    gameStore.update((s) => ({ ...s, dailyIntroPlayed: tok, dailyIntroGo: (s.dailyIntroGo || 0) + 1 }));
    introBuilding = true;
    tweenNet.set(0, { duration: 0 });
  }
  function onDailyIntroDone() {
    introBuilding = false; // releases the reactive above → bounty counts 0 → net
    introCountPop = true;
    setTimeout(() => { introCountPop = false; }, 1200);
  }

  // 💰 In-game bank: a modal (not a route) so closing it returns to the game, not the menu.
  let showBank = false;
  /** @type {{ bank:number, net_worth:number, ledger:any[] }|null} */
  let bankData = null;
  async function openBankModal() {
    fx('tap');
    showBank = true;
    try { bankData = await getBank(); } catch { bankData = null; }
  }
  const fmtCash = (/** @type {number} */ n) => '$' + Math.round(n ?? 0).toLocaleString();
  /** @param {string} reason */
  const bankReason = (reason) => (/** @type {Record<string,string>} */ ({
    quest_reward: 'Daily quests reward', daily_win: 'Daily reward', daily_reward: 'Daily reward',
    attendance: 'Daily attendance reward', arcade_cashout: 'Cash Game cash-out', climb_bounty: 'Climb bounty',
    freeplay_reward: 'Free Play reward', cosmetic_buy: 'Shop purchase', powerup_buy: 'Power-up purchase',
    wager_win: 'Won a wager', wager_stake: 'Wager staked', wager_refund: 'Wager refunded'
  }))[reason] || reason;

  // 🔐 My Vault — owned inventory; use power-ups in-game (mode-eligible only).
  let showBag = false;
  let vaultVideo = false;
  /** @type {any[]} */ let vaultOwned = [];
  /** @type {Record<string,number>} */ let dailyAvailBoosts = {};
  let vaultMsg = '';
  /** @type {ReturnType<typeof setTimeout>|undefined} */ let _vaultMsgTimer;
  async function loadVault() {
    try { vaultOwned = ((await getPowerups()).items ?? []).filter((/** @type {any} */ i) => (i.owned ?? 0) > 0); } catch { vaultOwned = []; }
    if (!showMainMenu && $gameStore.gameMode === 'daily') {
      try { dailyAvailBoosts = await getDailyAvailBoosts(); } catch { dailyAvailBoosts = {}; }
    }
  }
  function openBag() { fx('tap'); showBag = true; loadVault(); }
  // From the main menu: require the device PIN (if set), play the safe-open reveal, then open.
  async function openVaultFromMenu() {
    fx('tap');
    try { await requirePin('Open your Vault'); } catch { return; }
    loadVault();
    vaultVideo = true;
  }
  function onVaultVideoEnd() { if (vaultVideo) { vaultVideo = false; showBag = true; } }

  // In-game vault contents: every item, with the mode-eligible ones usable and the
  // rest grayed out (with a reason on tap).
  $: vaultItems = (!showBag || showMainMenu) ? [] : (() => {
    const out = [];
    if ($gameStore.gameMode === 'daily' && dailyMod && !$gameStore.twistUsed && gameActive) {
      out.push({ id: 'twist', emoji: dailyMod.emoji, name: dailyMod.name, blurb: dailyMod.blurb, count: 1, usable: true, reason: '' });
    }
    for (const it of vaultOwned) {
      if (it.kind === 'daily') {
        const avail = ($gameStore.gameMode === 'daily') && (dailyAvailBoosts[it.id] ?? 0) > 0 && gameActive;
        out.push({ id: it.id, emoji: BOOST_META[it.id]?.emoji ?? '💥', name: it.name, blurb: BOOST_META[it.id]?.blurb ?? '', count: it.owned,
          usable: avail, reason: avail ? '' : 'Bought after you started — usable on your next puzzle.' });
      } else if (it.kind === 'climb') {
        const used = (climb?.equipped ?? []).includes(it.id);
        const avail = $gameStore.gameMode === 'climb' && gameActive && !used && (it.owned ?? 0) > 0;
        out.push({ id: it.id, emoji: PUP_ICON[it.id] ?? '✨', name: it.name, blurb: avail ? 'Tap to use now' : '', count: it.owned, usable: avail,
          reason: used ? 'Already used on this puzzle.' : ($gameStore.gameMode === 'climb' ? '' : 'For the Cash Game — not this mode.') });
      } else {
        out.push({ id: it.id, emoji: PUP_ICON[it.id] ?? '✨', name: it.name, blurb: '', count: it.owned, usable: false,
          reason: it.kind === 'sabotage' ? 'For challenges — sabotage an opponent there, not the Daily.' : 'For the Cash Game or challenges — not the Daily.' });
      }
    }
    return out;
  })();
  /** @param {any} item */
  function tapVaultItem(item) {
    if (item.usable) { useFromBag(item); return; }
    vaultMsg = item.reason || "This item can't be used for this puzzle.";
    clearTimeout(_vaultMsgTimer);
    _vaultMsgTimer = setTimeout(() => { vaultMsg = ''; }, 2600);
  }
  /** @param {any} item */
  function useFromBag(item) {
    if (item?.id === 'twist') useTwist();
    else if (item?.id === 'bounty_boost' || item?.id === 'jackpot_boost') { useBoost(item.id); loadVault(); }
    else if ($gameStore.gameMode === 'climb') { climbPowerup(item.id).then(() => { refreshClimbPups(); loadVault(); }); }
    showBag = false;
  }

  // ℹ️ Daily explainers: ×N badge, Solve-to-Earn, 🏆 streak, or today's Twist.
  /** @type {'mult'|'bounty'|'streak'|'twist'|null} */
  let dailyInfo = null;
  $: dlReward = $gameStore.dailyLive?.reward ?? 0;        // base × multiplier (the full bounty)
  $: dlSpent = $gameStore.dailyLive?.spent ?? 0;
  $: dlMult = Number($gameStore.bountyMult ?? 1);
  $: dlBase = dlMult > 0 ? Math.round(dlReward / dlMult) : dlReward;
  $: dlNet = dlReward - dlSpent;
  $: dlWinStreak = dailyStatus?.win_streak ?? 0;
  $: dlStreakBonus = Math.min(0.1 * dlWinStreak, 0.5);
  $: dlBoost = Math.max(0, Math.round((dlMult - 1 - dlStreakBonus) * 10) / 10);
  const fmtMult = (/** @type {number} */ n) => '×' + n.toFixed(1);
  let _prevBank = /** @type {number|null} */ (null);
  let _floatId = 0;
  /** @type {{id:number,text:string}[]} */
  let spendFloaters = [];
  $: trackSpend($gameStore.bankroll, $gameStore.gameMode, showMainMenu);
  /** @param {number|null|undefined} b @param {string} mode @param {boolean} onMenu */
  function trackSpend(b, mode, onMenu) {
    if (browser && !onMenu && _prevBank != null && b != null && b < _prevBank && ['daily', 'makeup', 'climb'].includes(mode)) {
      const amt = _prevBank - b;
      if (amt > 0 && amt <= 300) {
        const id = ++_floatId;
        spendFloaters = [...spendFloaters, { id, text: '−$' + amt.toLocaleString() }];
        setTimeout(() => { spendFloaters = spendFloaters.filter((f) => f.id !== id); }, 1100);
      }
    }
    _prevBank = b;
  }

  // 💥 Dramatic bank pop on a big swing (win payout / big change).
  let bankFlash = '';
  let _bankFxPrev = /** @type {number|null} */ (null);
  /** @type {ReturnType<typeof setTimeout>|undefined} */
  let _bankFxTimer;
  $: bankFx($gameStore.bankroll, showMainMenu);
  /** @param {number|null|undefined} b @param {boolean} onMenu */
  function bankFx(b, onMenu) {
    if (!browser || b == null) { _bankFxPrev = b ?? _bankFxPrev; return; }
    if (!onMenu && _bankFxPrev != null && Math.abs(b - _bankFxPrev) >= 150) {
      bankFlash = b > _bankFxPrev ? 'up' : 'down';
      clearTimeout(_bankFxTimer);
      _bankFxTimer = setTimeout(() => { bankFlash = ''; }, 1100);
    }
    _bankFxPrev = b;
  }


  // ── Fold + broke-timer (Daily + Challenges) ──────────────────────────────
  // You're "broke" when you can't afford the cheapest still-buyable letter →
  // a 60s clock starts; guess it or you auto-Fold (lose the puzzle).
  // Mirror of the server-authoritative public.letter_cost() (economy v3.2: −25%, cheapest $20).
  const LETTER_COSTS = { Q:20,W:40,E:100,R:90,T:90,Y:50,U:60,I:80,O:70,P:60,A:100,S:90,D:60,F:50,G:50,H:50,J:20,K:40,L:60,Z:30,X:30,C:60,V:40,B:50,N:80,M:50 };
  // foldMode = modes with a "Give up" button (Daily + Challenges).
  $: foldMode = ($gameStore.gameMode === 'daily' || $gameStore.gameMode === 'match');
  // brokeMode = modes with the out-of-Cash auto-fold CLOCK. The Daily has NO timer —
  // guesses are free + unlimited, so being broke isn't a dead end; you solve it or you
  // don't (an unfinished Daily expires as a loss at day's end). Only live challenges,
  // where stalling stalls a real opponent, keep the broke clock.
  $: brokeMode = ($gameStore.gameMode === 'match');
  $: gameActive = $gameStore.gameState !== 'won' && $gameStore.gameState !== 'lost';
  $: isBroke = (() => {
    // Only while actively on a game screen — never on the menu.
    if (!brokeMode || !gameActive || showMainMenu) return false;
    const mod = $gameStore.modifier, discount = mod === 'discount', vowelHalf = mod === 'vowel_vision';
    const purchased = new Set(($gameStore.purchasedLetters || []).filter(Boolean));
    const incorrect = new Set($gameStore.incorrectLetters || []);
    let minCost = Infinity;
    for (const [L, base] of Object.entries(LETTER_COSTS)) {
      if (purchased.has(L) || incorrect.has(L)) continue;
      let c = base;
      if (discount) c = Math.ceil(c * 0.75);
      if (vowelHalf && 'AEIOU'.includes(L)) c = Math.ceil(c * 0.5);
      if (c < minCost) minCost = c;
    }
    return minCost !== Infinity && ($gameStore.bankroll || 0) < minCost;
  })();
  let brokeDeadline = 0, brokeLeft = 0, brokeTimer = null, brokeFiring = false;
  $: if (browser) manageBrokeTimer(isBroke);
  function manageBrokeTimer(broke) {
    if (broke && !brokeTimer) {
      brokeDeadline = Date.now() + 60000; brokeLeft = 60;
      brokeTimer = setInterval(() => {
        brokeLeft = Math.max(0, Math.ceil((brokeDeadline - Date.now()) / 1000));
        if (brokeLeft <= 0) { clearInterval(brokeTimer); brokeTimer = null; doFold(true); }
      }, 250);
    } else if (!broke && brokeTimer) {
      clearInterval(brokeTimer); brokeTimer = null;
    }
  }
  /** @param {boolean} auto */
  async function doFold(auto = false) {
    if (brokeFiring) return;
    brokeFiring = true;
    if (brokeTimer) { clearInterval(brokeTimer); brokeTimer = null; }
    try {
      fx(auto ? 'bust' : 'tap');
      if ($gameStore.gameMode === 'daily') await dailyFold();
      else if ($gameStore.gameMode === 'match') await matchFold();
      else if ($gameStore.gameMode === 'freeplay') await freeplayContinue(); // skip to a fresh puzzle
      else if ($gameStore.gameMode === 'climb') { await climbSkipPuzzle(); await tick(); playDailyIntroIfArmed(); } // fresh puzzle; heat resets; replay the dramatic build
    } finally { brokeFiring = false; }
  }
  // Give-up confirm layer (in-app, not window.confirm).
  let showGiveUp = false;
  function confirmFold() { fx('tap'); showGiveUp = true; }
  function cancelGiveUp() { fx('tap'); showGiveUp = false; }
  function doGiveUp() { showGiveUp = false; doFold(false); }

  // 💥 Double or Nothing confirm layer (Cash Game). Solve → ×2; get stuck → forfeit.
  let showDon = false;
  let donBusy = false;
  function openDon() { fx('tap'); showDon = true; }
  function cancelDon() { fx('tap'); showDon = false; }
  async function armDon() {
    if (donBusy) return;
    donBusy = true;
    try { fx('tap'); await climbArmDoubleOrNothing(); }
    finally { donBusy = false; showDon = false; }
  }

  // Free Play: cash out credits → real Cash right from the board (40:1, $50/day cap).
  let fpCashBusy = false;
  // Tapping the credits number cashes out when you're above the $1 floor.
  function tapCredits() {
    if (($gameStore.bankroll ?? 0) - 2000 >= 40) doFreeplayCashout();
    else gameStore.update((s) => ({ ...s, cashToast: { amount: 0, label: 'Reach 2,040 credits to cash out for real Cash' } }));
  }
  async function doFreeplayCashout() {
    if (fpCashBusy) return;
    fpCashBusy = true;
    const st = await getFreeplayCashoutStatus();
    fpCashBusy = false;
    if (!st) return;
    const amt = Math.min(st.max_cash ?? 0, st.cap_remaining ?? 0);
    if (amt <= 0) {
      gameStore.update((s) => ({ ...s, cashToast: { amount: 0, label: "Daily $50 cash-out cap reached — back tomorrow" } }));
      return;
    }
    try {
      await requirePin(`Cash out ${(amt * 40).toLocaleString()} credits → $${amt}`, [
        { label: 'Credits', value: (amt * 40).toLocaleString() },
        { label: 'You receive', value: '$' + amt }
      ]);
    } catch { return; }
    fpCashBusy = true;
    const res = await freeplayCashout(amt);
    fpCashBusy = false;
    if (res?.ok) {
      fx('win');
      gameStore.update((s) => ({ ...s, bankroll: res.bankroll, cashToast: { amount: res.cashed, label: 'Cashed out to your Cash!' } }));
      await refreshBank();
    }
  }
  $: matchRemaining = (() => {
    if (!matchBlitz || !matchInfo?.started_at) return 0;
    const start = new Date(matchInfo.started_at).getTime();
    const clockMs = (matchInfo.clock_seconds ?? 60) * 1000;
    return Math.max(0, Math.ceil((start + clockMs - pressureNow) / 1000));
  })();
  $: if (matchBlitz && matchRemaining > 0) matchExpiredFired = false;
  $: if (matchBlitz && matchRemaining <= 0 && !matchExpiredFired) fireMatchTimeout();
  async function fireMatchTimeout() {
    matchExpiredFired = true;
    await matchTimeoutCheck();
  }
  $: climbHeat = ((climb?.heat ?? 100) / 100).toFixed(1);
  // Heat IS the Cash Game win streak: each solve +0.1× (cap ×2.0), reset to ×1.0 when stuck.
  $: climbStreak = Math.max(0, Math.round(((climb?.heat ?? 100) - 100) / 10));
  // 🔥 The run: solves + cumulative profit since heat last reset (run_profit can be negative early).
  $: climbRun = (isClimb && climb) ? { solves: climb.run_solves ?? 0, profit: climb.run_profit ?? 0, best: climb.best_run_profit ?? 0 } : null;
  $: climbRunIsBest = climbRun != null && climbRun.profit > 0 && climbRun.profit >= climbRun.best;
  // Owned, not-yet-used climb buffs — drives the vault badge by the Solve button.
  $: usableClimbPups = isClimb ? selfPups.filter((/** @type {any} */ i) => (i.owned ?? 0) > 0 && !((climb?.equipped ?? []).includes(i.id))).length : 0;
  /** @type {'heat'|'earn'|null} ℹ️ Cash Game explainers (mirror of dailyInfo). */
  let climbInfo = null;
  $: dr = $gameStore.dailyResult; // { score, clean, no_vowels, first_try, no_reveals }
  /** @type {{rank:number, total:number}|null} */
  let dailyPlacement = null;
  $: if (showResultModal && isDailyResult && resultWon && dr && dailyPlacement === null) loadDailyPlacement();
  async function loadDailyPlacement() {
    dailyPlacement = { rank: 0, total: 0 }; // guard against re-fire
    try {
      const board = await getDailyBoard('friends');
      const me = board.find((/** @type {any} */ r) => r.is_me);
      dailyPlacement = { rank: me?.rank ?? 0, total: board.length };
    } catch { dailyPlacement = { rank: 0, total: 0 }; }
  }
  /** @type {any[]} */
  let climbPups = [];
  const PUP_ICON = /** @type {Record<string,string>} */ ({
    free_reveal: '🔍', half_off: '🏷️', vowel_vision: '👁️', extra_hint: '💡', reveal_word: '📖', free_vowel: '🅰️', last_letters: '🔚',
    sabotage_tax: '💸', sabotage_fog: '🌫️', sabotage_toll: '🚧', sabotage_vowel_block: '🚫', sabotage_lock: '🔒'
  });
  const DEBUFF_LABEL = /** @type {Record<string,string>} */ ({
    tax: '💸 Taxed (letters +50%)', fog: '🌫️ Fogged (clue hidden)',
    toll: '🚧 Tolled (next letter 3×)', vowel_block: '🚫 Vowel-blocked (vowels 3×)'
  });
  let pendingSabotage = /** @type {string|null} */ (null); // sabotage powerup id awaiting a target
  async function refreshClimbPups() {
    try { const r = await getPowerups(); climbPups = r.items ?? []; } catch { /* non-fatal */ }
  }
  $: selfPups = climbPups.filter((/** @type {any} */ i) => i.kind === 'climb');   // buffs (use on yourself)
  $: sabPups = climbPups.filter((/** @type {any} */ i) => i.kind === 'sabotage'); // sabotage (target an opponent)
  /** @param {any} item */
  async function tapSabotage(item) {
    const opps = matchInfo?.opponents ?? [];
    if ((item.owned ?? 0) <= 0 || opps.length === 0) return;
    if (opps.length === 1) { await matchSabotageOpponent(opps[0].id, item.id); await refreshClimbPups(); }
    else { pendingSabotage = pendingSabotage === item.id ? null : item.id; }
  }
  /** @param {string} oppId */
  async function pickSabTarget(oppId) {
    if (!pendingSabotage) return;
    const pid = pendingSabotage; pendingSabotage = null;
    await matchSabotageOpponent(oppId, pid); await refreshClimbPups();
  }

  // --- per-match chat (1v1 + group challenges) ---
  let matchChatOpen = false;
  let matchChatUnread = false;
  /** @type {string|null} id of the newest message you've already seen */
  let matchChatSeenId = null;
  /** @type {any[]} */
  let matchMessages = [];
  let matchChatInput = '';
  let matchChatBusy = false;
  /** @type {string|null} */
  let matchChatId = null;
  /** @type {any} */
  let matchChannel = null;
  /** @type {ReturnType<typeof setInterval>|undefined} */
  let matchChatPoll;
  /** @type {HTMLElement|undefined} */
  let matchChatScroll;

  async function loadMatchMsgs() {
    if (!matchChatId) return;
    const m = await getMatchMessages(matchChatId);
    if (matchChatId == null) return;
    matchMessages = m;
    const newest = m.length ? m[m.length - 1] : null;
    if (matchChatOpen) {
      // Reading the thread = caught up.
      if (newest) matchChatSeenId = newest.id;
      matchChatUnread = false;
      tick().then(() => { if (matchChatScroll) matchChatScroll.scrollTop = matchChatScroll.scrollHeight; });
    } else if (matchChatSeenId === null) {
      // First sync: treat the existing backlog as already seen (don't nag).
      if (newest) matchChatSeenId = newest.id;
    } else if (newest && !newest.is_me && newest.id !== matchChatSeenId) {
      // Light up only for a NEW message from someone else you haven't opened.
      matchChatUnread = true;
    }
  }
  function teardownMatchChat() {
    if (matchChannel) { supabase.removeChannel(matchChannel); matchChannel = null; }
    clearInterval(matchChatPoll);
    matchChatId = null; matchMessages = []; matchChatOpen = false; matchChatUnread = false; matchChatSeenId = null;
  }
  /** @param {string|null|undefined} id */
  function syncMatchChat(id) {
    if (id === matchChatId) return;
    teardownMatchChat();
    if (!id) return;
    matchChatId = id;
    loadMatchMsgs();
    matchChannel = supabase.channel(`match:${id}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'match_messages', filter: `match_id=eq.${id}` }, loadMatchMsgs)
      .subscribe();
    matchChatPoll = setInterval(loadMatchMsgs, 20000);
  }
  $: syncMatchChat((isMatch && !showMainMenu) ? matchInfo?.id : null);
  function openMatchChat() { matchChatOpen = true; matchChatUnread = false; loadMatchMsgs(); }
  async function sendMatchChat() {
    const body = matchChatInput.trim();
    if (!body || matchChatBusy || !matchChatId) return;
    matchChatBusy = true;
    const res = await sendMatchMessage(matchChatId, body);
    matchChatBusy = false;
    if (res.ok) { matchChatInput = ''; await loadMatchMsgs(); }
  }
  onDestroy(teardownMatchChat);

  $: makeupLabel = (() => {
    const d = $gameStore.makeupDate;
    if (!d) return '';
    const dt = new Date(d + 'T00:00:00');
    return dt.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  })();
  $: chScore = ($gameStore.challengeInfo?.score ?? Math.floor($gameStore.bankroll || 0));
  $: resultBankroll = Math.max(0, Math.floor($gameStore.bankroll || 0));
  $: resultMedal = medalFor(resultBankroll, resultWon);

  // ⏱️ Pressure-mode challenge clock (server-authoritative; this just displays + triggers the check)
  let pressureNow = browser ? Date.now() : 0;
  /** @type {ReturnType<typeof setInterval>|undefined} */
  let pressureTimer;
  let pressureFired = false;
  $: chInfo = $gameStore.gameMode === 'challenge' ? $gameStore.challengeInfo : null;
  $: isPressure = chInfo?.mode === 'pressure';
  $: pressureActive = isPressure && $gameStore.gameState !== 'won' && $gameStore.gameState !== 'lost';
  $: pressureRemaining = (() => {
    if (!isPressure || !chInfo?.started_at) return 0;
    const start = new Date(chInfo.started_at).getTime();
    const limitMs = (chInfo.limit_seconds ?? 60) * 1000;
    return Math.max(0, Math.ceil((start + limitMs - pressureNow) / 1000));
  })();
  $: if (pressureActive && pressureRemaining > 0) pressureFired = false;
  $: if (pressureActive && pressureRemaining <= 0 && !pressureFired) firePressureTimeout();
  async function firePressureTimeout() {
    pressureFired = true;
    await challengeTimeoutCheck();
    // tolerate minor client/server clock skew — retry shortly if the play didn't settle
    if ($gameStore.gameState !== 'won' && $gameStore.gameState !== 'lost') {
      setTimeout(() => { pressureFired = false; }, 1500);
    }
  }

  let shareCopied = false;
  function buildShareText() {
    const br = '$' + resultBankroll.toLocaleString();
    // Link to the live origin (never a hardcoded/deleted project URL).
    const link = typeof window !== 'undefined' ? window.location.origin : '';
    if (isDailyResult) {
      if (resultWon && dr) {
        return `🧠 WordBank Daily · ${todayLabel}\nProfit ${(dr.net ?? 0) >= 0 ? '+' : '−'}$${Math.abs(dr.net ?? 0).toLocaleString()} — beat that 👀\n${link}`;
      }
      return `🧠 WordBank Daily · ${todayLabel}\nDidn't crack it today 😬\n${link}`;
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

  // ✅ Auto-save the moment a board is live (even before the first letter) so you
  // can always resume — and keep saving as you play.
  $: if (
    loggedIn &&
    $gameStore.currentPhrase &&
    $gameStore.category &&
    Array.isArray($gameStore.purchasedLetters)
  ) {
    saveGameToLocalStorage();
  }

  onMount(() => {
    ['click', 'mousedown', 'touchstart'].forEach(event =>
      document.addEventListener(event, removeButtonFocus, true)
    );
    pressureTimer = setInterval(() => { pressureNow = Date.now(); }, 250);
  });
  onDestroy(() => { clearInterval(pressureTimer); if (brokeTimer) clearInterval(brokeTimer); });

  // Bump this key whenever the tutorial gains new content — it re-shows for
  // everyone on next login (v3 = persistent Cash, spend-the-least, attendance, no loans).
  const TUTORIAL_KEY = 'wb_tutorial_v3';
  // First-run guided tutorial: show once a signed-in user is past the username/PIN
  // gates and on the menu (not while those full-screen gates are up).
  $: if (browser && loggedIn && hasInitialized && !needsUsername && !showPinUnlock && !showPinSetup && localStorage.getItem(TUTORIAL_KEY) !== 'true') {
    showTutorial = true;
  }

  // One-time launch welcome for returning players (we reset everyone to a fresh
  // Day-1 start). New users get the tutorial instead (it sets this key on dismiss).
  const LAUNCH_KEY = 'wb_launch_welcome_v1';
  $: if (browser && loggedIn && hasInitialized && showMainMenu && !needsUsername && !showPinUnlock && !showPinSetup
         && !showTutorial && localStorage.getItem(TUTORIAL_KEY) === 'true' && localStorage.getItem(LAUNCH_KEY) !== '1') {
    showLaunchWelcome = true;
  }
  function dismissLaunchWelcome() {
    showLaunchWelcome = false;
    if (browser) localStorage.setItem(LAUNCH_KEY, '1');
  }

  // Deep link from a public profile's "⚔️ Challenge" button: /?challenge=<username>
  let challengeDeepLinkDone = false;
  $: if (browser && loggedIn && hasInitialized && !needsUsername && !showPinUnlock && !showPinSetup && !challengeDeepLinkDone) {
    challengeDeepLinkDone = true;
    try {
      const params = new URLSearchParams(window.location.search);
      const ch = params.get('challenge');
      if (ch) {
        newChallenge().then(() => { mbTarget = 'friend'; mbOpponent = ch; });
        params.delete('challenge');
      }
      // Settings/account deep link from the Profile page's ⚙️ gear (/?account=1)
      if (params.get('account')) {
        handleMenuMyAccount();
        params.delete('account');
      }
      const qs = params.toString();
      window.history.replaceState({}, '', window.location.pathname + (qs ? '?' + qs : ''));
    } catch { /* non-fatal */ }
  }
  // A tapped challenge toast / deep-link opens Community ▸ Challenges (people fallback).
  let _inboxSeen = 0;
  $: if (browser && $inboxRequest > _inboxSeen && loggedIn && hasInitialized && !needsUsername && !showPinUnlock && !showPinSetup) {
    _inboxSeen = $inboxRequest;
    if ($inboxTarget === 'people') { openCommunity('people'); peopleTab = 'friends'; }
    else openCommunity('challenges');
  }
  function dismissTutorial() {
    showTutorial = false;
    // New users just onboarded — they don't also need the launch welcome.
    if (browser) { localStorage.setItem(TUTORIAL_KEY, 'true'); localStorage.setItem(LAUNCH_KEY, '1'); }
  }

  // ===== Pre-game "How to win" objective card =====
  // Shows the objective the moment a mode starts. Solo modes show once (per mode,
  // localStorage); challenges show every entry. One reactive latch detects the
  // menu→game transition so we don't have to wire every scattered start site.
  /** @type {{ mode: string, ctx: any } | null} */
  let objective = null;
  let _wasMenu = true;
  const SOLO_MODES = ['daily', 'climb', 'freeplay', 'makeup'];

  function buildObjectiveCtx(/** @type {string} */ mode) {
    if (mode !== 'match') return {};
    const mi = get(gameStore).matchInfo || {};
    const opps = mi.opponents ?? [];
    return { opponent: opps.length === 1 ? opps[0]?.name : undefined,
      wager: mi.wager, packSize: mi.pack_size, fieldSize: opps.length + 1 };
  }
  /** @param {boolean} [forced] re-opened via the board ⓘ button — bypass the once-seen gate */
  function showObjectiveFor(/** @type {string} */ mode, forced = false) {
    if (!mode || showTutorial) return;
    if (!forced && SOLO_MODES.includes(mode) && browser && localStorage.getItem('wb_obj_' + mode) === '1') return;
    objective = { mode, ctx: buildObjectiveCtx(mode) };
  }
  function dismissObjective() {
    if (objective && browser && SOLO_MODES.includes(objective.mode)) localStorage.setItem('wb_obj_' + objective.mode, '1');
    objective = null;
    tick().then(playDailyIntroIfArmed); // board is now visible → play the opening reveal
  }

  // Detect entering a game from the menu (latch flips once per entry).
  $: if (browser && loggedIn && hasInitialized && !needsUsername && !showPinUnlock && !showPinSetup) {
    if (showMainMenu) { _wasMenu = true; }
    else if (_wasMenu && $gameStore.gameMode && $gameStore.gameState !== 'won' && $gameStore.gameState !== 'lost') {
      _wasMenu = false;
      showObjectiveFor($gameStore.gameMode);
      refreshBank(); // keep the on-board "Cash" fresh (e.g. a challenge buy-in was just paid)
    }
  }

  /** @param {Event} e */
  const removeButtonFocus = (e) => {
    if (e.target && /** @type {HTMLElement} */ (e.target).tagName === 'BUTTON') /** @type {HTMLButtonElement} */ (e.target).blur();
  };

  // ✅ Log out: clear saved game so next login always shows main menu
  const handleLogout = async () => {
    clearSavedGame();
    clearPin(); // forget this device's PIN so the next person can't unlock the account
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
    // Status loads non-blocking after login — make sure we know it before deciding,
    // so an already-completed daily shows the summary instead of re-opening + "winning".
    if (!dailyStatus) {
      dailyStatus = await getDailyStatus(currentUser.id);
      menuDailyPlayed = dailyStatus.has_played_today;
    }
    // Resume an active Daily based on SERVER truth, not the clobberable local save slot.
    const inProgress = (dailyStatus?.daily_in_progress ?? false) || (savedGameInfo?.gameMode === 'daily' && savedGameInfo?.gameState !== 'won' && savedGameInfo?.gameState !== 'lost');
    if (dailyStatus?.has_played_today && !inProgress) {
      showStreakMessage = true;  // already solved today → come-back summary
      return;
    }
    // Today's Twist is auto-given on the board — no pre-game popup. Just play.
    await startDaily();
  }

  // ⚡ Power-up hotbar feed. Daily: today's Twist (mode allows only the Twist).
  // Cash Game / Challenges will feed mode-eligible inventory power-ups here later.
  // Daily hotbar = today's Twist (if unused) + any owned Bounty Boosts you carry.
  /** @type {{id:string,emoji:string,name:string,blurb:string,count:number}[]} */
  let dailyBoosts = [];
  const BOOST_META = /** @type {Record<string,{emoji:string,blurb:string}>} */ ({
    bounty_boost: { emoji: '💥', blurb: 'Adds ×0.5 to your bounty' },
    jackpot_boost: { emoji: '💎', blurb: 'Adds ×1.0 to your bounty' }
  });
  async function loadDailyBoosts() {
    try {
      const r = await getPowerups();
      dailyBoosts = (r.items ?? [])
        .filter((/** @type {any} */ i) => i.kind === 'daily' && (i.owned ?? 0) > 0)
        .map((/** @type {any} */ i) => ({ id: i.id, emoji: BOOST_META[i.id]?.emoji ?? '💥', name: i.name, blurb: BOOST_META[i.id]?.blurb ?? '', count: i.owned }));
    } catch { dailyBoosts = []; }
  }
  $: trayPowerups = ($gameStore.gameMode === 'daily' && gameActive)
    ? [
        ...((dailyMod && !$gameStore.twistUsed) ? [{ id: 'twist', emoji: dailyMod.emoji, name: dailyMod.name, blurb: dailyMod.blurb, count: 1 }] : []),
        ...dailyBoosts
      ]
    : [];
  /** @param {CustomEvent<any>} e */
  function onUsePowerup(e) {
    const item = e.detail;
    if (item?.id === 'twist') { useTwist(); return; }
    if (item?.id === 'bounty_boost' || item?.id === 'jackpot_boost') { useBoost(item.id); return; }
  }

  // Use today's Daily Twist power-up (tap the tray slot).
  let dailyTwistBusy = false;
  let dailyBoostBusy = false;
  async function useTwist() {
    if (dailyTwistBusy || $gameStore.twistUsed) return;
    dailyTwistBusy = true;
    fx('select');
    await useDailyTwist();
    dailyTwistBusy = false;
  }
  /** @param {string} id */
  async function useBoost(id) {
    if (dailyBoostBusy) return;
    dailyBoostBusy = true;
    fx('multiplier');
    await useDailyBoost(id);
    await loadDailyBoosts();
    dailyBoostBusy = false;
  }
  async function startDaily() {
    localStorage.setItem('gameMode', 'daily');
    const ok = await fetchDailyGame();
    if (ok) {
      hasInitialized = true;
      showMainMenu = false;
      loadDailyBoosts(); // surface any owned Bounty Boosts in the hotbar
      // refresh streaks so the 📅 attendance chip includes today's check-in
      const uid = get(user)?.id;
      if (uid) getDailyStatus(uid).then((s) => { dailyStatus = s; }).catch(() => {});
      // If the "How to win" card is suppressed (already seen), the board is now
      // visible — play the opening reveal once reactives settle. If the card DOES
      // show, this no-ops (objective set) and the reveal fires on its dismiss.
      await tick();
      playDailyIntroIfArmed();
    } else {
      initError = "Daily puzzle failed to load.";
    }
  }

  // Today's shared Daily Modifier banner (id lives in the game store, set by fetchDailyGame).
  $: dailyMod = ($gameStore.gameMode === 'daily' && $gameStore.modifier) ? modifierInfo($gameStore.modifier) : null;

  /** Start or resume the Cash Game (the persistent real-Cash Climb). */
  async function handleMenuClimb() {
    const currentUser = get(user);
    if (!currentUser?.id) return;
    localStorage.setItem('gameMode', 'climb');
    const ok = await fetchClimbGame();
    if (ok) {
      hasInitialized = true;
      showMainMenu = false;
      refreshClimbPups();
      // Play the dramatic opening reveal once reactives settle (no-ops if the
      // "How it works" card shows — it then fires on dismiss).
      await tick();
      playDailyIntroIfArmed();
    } else {
      initError = 'Cash Game failed to load.';
    }
  }

  // ----- Free Play (unranked, pick a category) -----
  let showCategorySelect = false;
  $: freeplayInProgress = openGames.some((g) => g.mode === 'freeplay');
  async function handleMenuFreeplay() {
    if (!get(user)?.id) return;
    // Resume the exact in-progress puzzle if there is one; otherwise pick a category.
    if (freeplayInProgress) {
      localStorage.setItem('gameMode', 'freeplay');
      const ok = await fetchFreeplayResume();
      if (ok) { hasInitialized = true; showMainMenu = false; return; }
    }
    showCategorySelect = true;
  }
  /** ▶ Resume the most-recently-played live game (the top-level menu shortcut). */
  function resumeOpen() {
    if (!resumeGame) return;
    fx('tap');
    if (resumeGame.mode === 'daily') handleMenuDaily();
    else if (resumeGame.mode === 'climb') handleMenuClimb();
    else if (resumeGame.mode === 'freeplay') handleMenuFreeplay();
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
  // ===== Challenge Builder (configurable packs vs friends/groups) =====
  let showChallenges = false; // the New-Challenge builder modal
  /** Which Community hub tab is showing. */
  let communityTab = /** @type {'challenges'|'leaderboard'|'activity'|'people'} */ ('challenges');
  /** Which People sub-tab (when communityTab === 'people'). */
  let peopleTab = /** @type {'friends'|'groups'} */ ('friends');
  /** Start a challenge with a friend from the People list. @param {string} username */
  function challengeFriend(username) {
    newChallenge().then(() => { mbTarget = 'friend'; mbOpponent = username; });
  }
  /** @type {any[]} */
  let myMatches = [];
  /** @type {any[]} */
  let myGroups = [];
  let challengeCount = 0; // matches awaiting my play (badge on the Challenges card)
  let friendReqCount = 0; // incoming friend requests (badge on Friends)
  /** @type {any|null} */
  let matchResults = null; // a settled match's results being viewed
  // Builder form
  let mbTarget = 'friend'; // 'friend' | 'group'
  let mbMode = 'standard'; // 'standard' | 'blitz'
  let mbOpponent = '';
  let mbGroupId = '';
  /** @type {string[]} */
  let mbCategories = [];
  let mbPackSize = 3;
  let mbWager = 0;
  let mbPayout = 'winner'; // 'winner' | 'top3' | 'even'
  let mbWindow = 172800; // seconds
  let mbItemsAllowed = false; // host toggle: allow power-ups in this challenge
  let mbMsg = '';
  let mbBusy = false;
  /** @type {{username:string,is_friend:boolean}[]} */
  let mbResults = [];
  /** @type {ReturnType<typeof setTimeout>|undefined} */
  let mbSearchTimer;
  const WINDOWS = [{ s: 3600, l: '1 hour' }, { s: 21600, l: '6 hours' }, { s: 86400, l: '24 hours' }, { s: 172800, l: '48 hours' }, { s: 604800, l: '1 week' }];

  /** Refresh the data behind the home act-now banner (matches + friend requests). */
  async function refreshChallengeCount() {
    if (!get(user)?.id) return;
    try {
      const [matches, reqs] = await Promise.all([getMyMatches(), listFriendRequests()]);
      myMatches = matches;
      friendRequests = reqs.incoming ?? [];
      challengeCount = myMatches.filter((m) => m.status === 'open' && m.my_state !== 'done').length;
      friendReqCount = friendRequests.length;
    } catch { /* non-fatal */ }
  }
  /** Open the New-Challenge builder modal. */
  async function newChallenge() {
    if (!get(user)?.id) return;
    mbMsg = '';
    myGroups = await getMyGroups();
    showChallenges = true;
  }
  /** Go to the Community hub. @param {'challenges'|'leaderboard'|'activity'|'people'} [tab] */
  // When the People tab is opened straight from the home menu (👥+ button), its
  // back button returns to the main menu; when opened from inside Community, back
  // returns to Community.
  let peopleBackToHome = false;
  async function openCommunity(tab) {
    if (!get(user)?.id) return;
    matchResults = null;
    peopleBackToHome = tab === 'people';
    communityTab = tab ?? 'challenges';
    menuView = 'community';
    showMainMenu = true;
    [myMatches, myGroups] = await Promise.all([getMyMatches(), getMyGroups()]);
    challengeCount = myMatches.filter((m) => m.status === 'open' && m.my_state !== 'done').length;
  }
  /** Back-compat shim for existing callers (banner "+N more", toasts, result modal). */
  async function openChallenges(forceTab) {
    if (forceTab === 'new') return newChallenge();
    return openCommunity('challenges');
  }

  function onMbOppInput() {
    clearTimeout(mbSearchTimer);
    const q = mbOpponent.trim();
    if (q.length < 2) { mbResults = []; return; }
    mbSearchTimer = setTimeout(async () => { mbResults = await searchUsers(q); }, 220);
  }
  /** @param {string} username */
  function pickMbOpp(username) { mbOpponent = username; mbResults = []; }
  /** @param {string} c */
  function toggleCategory(c) { mbCategories = mbCategories.includes(c) ? mbCategories.filter((x) => x !== c) : [...mbCategories, c]; }

  async function submitNewMatch() {
    if (mbBusy) return;
    if (mbTarget === 'friend' && !mbOpponent.trim()) { mbMsg = 'Pick an opponent.'; return; }
    if (mbTarget === 'group' && !mbGroupId) { mbMsg = 'Pick a group.'; return; }
    const w = Math.floor(Number(mbWager) || 0);
    const createStakes = [
      { label: mbTarget === 'group' ? 'Group' : 'Opponent', value: mbTarget === 'group' ? (myGroups.find((g) => g.id === mbGroupId)?.name || 'Group') : '@' + mbOpponent.trim() },
      { label: 'Puzzles', value: String(mbPackSize) },
      { label: 'Buy-in', value: w > 0 ? '$' + w.toLocaleString() : 'Friendly' },
      { label: 'Payout', value: mbPayout === 'podium' ? 'Podium 3·2·1' : 'Winner takes all' }
    ];
    try { await requirePin(w > 0 ? 'Send & stake your buy-in' : 'Send this challenge', createStakes); } catch { return; }
    mbBusy = true; mbMsg = 'Creating…';
    const res = await startMatch({
      opponent: mbTarget === 'friend' ? mbOpponent.trim() : null,
      group_id: mbTarget === 'group' ? mbGroupId : null,
      categories: mbCategories, pack_size: mbPackSize, mode: mbMode,
      wager: Math.floor(Number(mbWager) || 0), payout: mbPayout, window_seconds: mbWindow,
      items_allowed: mbItemsAllowed
    });
    mbBusy = false;
    if (res?.ok) { launchMatchPlay(); }
    else {
      mbMsg = res?.reason === 'no_opponent' ? 'No player with that username.'
        : res?.reason === 'insufficient' ? 'Not enough Cash for that wager.'
        : res?.reason === 'min_wager' ? 'Minimum wager is $500 (or $0 for a friendly).'
        : res?.reason === 'self' ? "You can't challenge yourself."
        : res?.reason === 'not_member' ? "You're not in that group."
        : res?.reason === 'no_puzzles' ? 'No puzzles in those categories.'
        : 'Could not create the challenge.';
    }
  }
  /** Stakes shown on the PIN confirm. @param {any} m */
  function matchStakes(m) {
    const s = [
      { label: m.is_host ? 'Players' : 'Opponent', value: m.is_host ? `${m.players}` : '@' + m.host },
      { label: 'Puzzles', value: String(m.pack_size) },
      { label: 'Buy-in', value: Number(m.wager) > 0 ? '$' + Number(m.wager).toLocaleString() : 'Friendly' },
      { label: 'Payout', value: m.payout === 'podium' ? 'Podium 3·2·1' : 'Winner takes all' }
    ];
    if (Number(m.wager) > 0 && netWorth != null) s.push({ label: 'Your Cash', value: '$' + Math.round(netWorth).toLocaleString() });
    return s;
  }
  /** A challenge whose buy-in I can't fully afford — drives the play-or-decline sheet. */
  let shortMatch = /** @type {any|null} */ (null);
  /** @param {any} m */
  async function respondToMatch(m) {
    if (mbBusy) return;
    if (m.status === 'settled') { matchResults = { loading: true }; matchResults = await getMatchDetail(m.id); return; }
    // Accepting an invite commits your buy-in → confirm with PIN (resuming doesn't).
    if (m.my_state === 'invited') {
      // Can't afford the full buy-in → offer "play with what you have" or decline.
      if (Number(m.wager) > 0 && netWorth != null && netWorth < Number(m.wager)) { shortMatch = m; return; }
      try { await requirePin(`Accept @${m.host}'s challenge`, matchStakes(m)); } catch { return; }
    }
    mbBusy = true;
    const ok = m.my_state === 'invited' ? await acceptAndPlayMatch(m.id) : await resumeMatch(m.id);
    mbBusy = false;
    if (ok) { markChallengeNotifRead(m.id); launchMatchPlay(); }
    else mbMsg = 'Could not open that challenge.';
  }
  /** Play a challenge with a budget capped at your current Cash. @param {any} m */
  async function playReduced(m) {
    shortMatch = null;
    const cap = Math.round(netWorth ?? 0);
    const stakes = matchStakes(m).map((s) => s.label === 'Buy-in' ? { label: 'Buy-in (capped)', value: '$' + cap.toLocaleString() } : s);
    try { await requirePin(`Play with $${cap.toLocaleString()}`, stakes); } catch { return; }
    mbBusy = true;
    const ok = await acceptAndPlayMatch(m.id, true);
    mbBusy = false;
    if (ok) launchMatchPlay();
    else mbMsg = 'Could not open that challenge.';
  }
  /** Decline an invited challenge (refunds the host if it can't proceed). @param {any} m */
  async function declineChallenge(m) {
    shortMatch = null;
    mbBusy = true;
    await declineMatch(m.id);
    await refreshChallengeCount();
    mbBusy = false;
  }
  function launchMatchPlay() {
    showChallenges = false;
    localStorage.setItem('gameMode', 'match');
    hasInitialized = true;
    showMainMenu = false;
    refreshClimbPups(); // load owned power-ups for the match tray
  }
  /** @param {any} item */
  async function handleMatchPup(item) {
    const used = (matchInfo?.used_powerups ?? []).includes(item.id);
    if ((item.owned ?? 0) <= 0 || used) return;
    await matchPowerup(item.id);
    await refreshClimbPups();
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
    dailyPlacement = null;
    // Leaving a make-up: clear it so we land on the menu, not back in the make-up.
    if ($gameStore.gameMode === 'makeup') {
      localStorage.setItem('gameMode', 'daily');
      localStorage.removeItem('makeupDate');
    }
    // Leaving the Cash Game clears heat (position + Cash persist server-side).
    if ($gameStore.gameMode === 'climb') {
      climbLeaveGame();
      localStorage.setItem('gameMode', 'daily');
    }
    // Leaving a challenge match — progress persists server-side; refresh the inbox count.
    if ($gameStore.gameMode === 'match') {
      localStorage.setItem('gameMode', 'daily');
      refreshChallengeCount();
    }
    saveGameToLocalStorage();
    savedGameInfo = getSavedGameInfo(currentUser.id);
    showMainMenu = true;
    // Refresh the daily completion indicator (e.g. just finished today's daily).
    getDailyStatus(currentUser.id).then((s) => { dailyStatus = s; menuDailyPlayed = s.has_played_today; });
    refreshOpenGames();
    refreshBank();
    refreshChallengeCount();
    refreshNotifications();
  }

  let showMyAccount = false;
  let showStreakMessage = false;
  let accountStreak = 0;
  let accountFreezes = 0;
  let maUsername = '';
  let maInput = '';
  let maEditing = false;
  let maMsg = '';

  // First-run "pick your username" gate (new accounts that have no username yet).
  let needsUsername = false;
  let claimInput = '';
  let claimMsg = '';
  let claimBusy = false;
  async function claimUsername() {
    const name = claimInput.trim();
    if (!name || claimBusy) return;
    claimBusy = true; claimMsg = '';
    const res = await setUsername(name);
    claimBusy = false;
    if (res.ok) {
      maUsername = res.username ?? name;
      needsUsername = false;
      track('username_set', { at: 'signup' });
      fx('win');
    } else {
      claimMsg = res.reason === 'taken' ? 'That username is taken — try another.'
        : res.reason === 'reserved' ? 'That one’s reserved — try another.'
        : res.reason === 'invalid' ? '3–15 characters: letters, numbers, or _.'
        : 'Could not set that username.';
    }
  }
  async function handleMenuMyAccount() {
    showMyAccount = true;
    maMsg = '';
    const u = get(user);
    if (u?.id) {
      const status = await getDailyStatus(u.id);
      accountStreak = status.current_streak ?? 0;
      accountFreezes = status.streak_freezes ?? 0;
      maUsername = (await getMyUsername()) ?? '';
      maEditing = !maUsername;
      maInput = maUsername;
    }
  }
  async function saveMaUsername() {
    const name = maInput.trim();
    if (!name) return;
    maMsg = 'Saving…';
    const res = await setUsername(name);
    if (res.ok) { maUsername = res.username ?? name; maEditing = false; maMsg = ''; track('username_set'); }
    else {
      maMsg = res.reason === 'taken' ? 'That username is taken.'
        : res.reason === 'reserved' ? 'That username is reserved.'
        : res.reason === 'invalid' ? '3–15 letters, numbers or _ only.'
        : 'Could not save username.';
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
      const won = $gameStore.gameState === 'won';
      if ($gameStore.gameMode === 'daily' && won) {
        resultRank = null;
        getMyDailyRank().then((r) => { resultRank = r; }).catch(() => {});
        const uid = get(user)?.id;
        if (uid) getDailyStatus(uid).then((s) => { dailyStatus = s; }).catch(() => {});
      }
      setTimeout(() => {
        showResultModal = true;
        // 🏆 Win banner: count the profit up, then scroll Cash to the new total.
        if ($gameStore.gameMode === 'daily' && won) {
          const profit = $gameStore.dailyResult?.net ?? 0;
          const newBank = Math.round($gameStore.bankroll ?? 0);
          resultProfit.set(0, { duration: 0 });
          resultBankAnim.set(newBank - profit, { duration: 0 });
          setTimeout(() => { resultProfit.set(profit); fx('win'); }, 350);
          setTimeout(() => { resultBankAnim.set(newBank); }, 1100);
        } else if ($gameStore.gameMode === 'climb' && won) {
          const c = $gameStore.climbInfo || {};
          const profit = Math.round((c.last_gain ?? 0) - (c.spent ?? 0));
          const newBank = Math.round($gameStore.bankroll ?? 0);
          resultProfit.set(0, { duration: 0 });
          resultBankAnim.set(newBank - profit, { duration: 0 });
          setTimeout(() => { resultProfit.set(profit); fx('win'); }, 350);
          setTimeout(() => { resultBankAnim.set(newBank); }, 1100);
        }
      }, 1000);
    }
  };
</script>
<svelte:window on:keydown={handleEscape} />
<!-- ☰ Main menu (top-left) -->
{#if loggedIn && hasInitialized && !showMainMenu}
  <button class="menu-back-btn" title="Main menu" aria-label="Main menu" on:click={goToMainMenu}><span class="hamburger"></span></button>
{/if}
<!-- ❓ How to play THIS game type (top-center) -->
{#if loggedIn && hasInitialized && !showMainMenu && $gameStore.gameMode}
  <button class="help-btn" title="How to play" aria-label="How to play this game" on:click={() => showObjectiveFor($gameStore.gameMode, true)}>?</button>
{/if}
<!-- 🏳️ Give up (top-right) — Daily / Challenges / Free Play -->
{#if loggedIn && hasInitialized && !showMainMenu && (foldMode || isFreeplay) && gameActive}
  <button class="giveup-btn" title="Give up" aria-label="Give up" on:click={confirmFold}>↪</button>
{/if}
<!-- ⏭️ Skip (top-right) — Cash Game only; resets heat. Hidden once Double-or-Nothing is armed (committed). -->
{#if loggedIn && hasInitialized && !showMainMenu && isClimb && gameActive && !donArmed && (climb?.state === 'active' || climb?.state === 'stuck')}
  <button class="giveup-btn" title="Skip this puzzle" aria-label="Skip this puzzle" on:click={confirmFold}>↪</button>
{/if}

<!-- 💬 Match chat (1v1 + group challenges) — only inside a live match, never on the menu -->
{#if isMatch && matchInfo && !showMainMenu}
  <button class="match-chat-btn" class:unread={matchChatUnread} title="Trash talk" on:click={openMatchChat}>
    💬 <span class="mcb-label">Chat</span>{#if matchChatUnread}<span class="mc-dot"></span>{/if}
  </button>
{/if}
{#if matchChatOpen && !showMainMenu}
  <div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Match chat">
    <button type="button" class="modal-backdrop" aria-label="Close" on:click={() => matchChatOpen = false}></button>
    <div class="modal-content chat-modal">
      <button class="close-btn" on:click={() => matchChatOpen = false}>❌</button>
      <h2 class="chat-h">💬 Trash talk</h2>
      <div class="chat-msgs" bind:this={matchChatScroll}>
        {#if matchMessages.length}
          {#each matchMessages as m}
            <div class="cmsg" class:mine={m.is_me}>
              <span class="cm-name">{m.is_me ? 'You' : m.name}</span>
              <span class="cm-body">{m.body}</span>
            </div>
          {/each}
        {:else}
          <p class="chat-empty">No messages yet — start the smack talk 👀</p>
        {/if}
      </div>
      <div class="chat-input-row">
        <input class="chat-input" placeholder="Message…" maxlength="500" bind:value={matchChatInput}
          on:keydown={(e) => { if (e.key === 'Enter') sendMatchChat(); }} />
        <button class="chat-send" on:click={sendMatchChat} disabled={matchChatBusy || !matchChatInput.trim()}>Send</button>
      </div>
    </div>
  </div>
{/if}

<!-- 🏳️ Give-up confirm layer -->
{#if showGiveUp}
  <div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Give up">
    <button type="button" class="modal-backdrop" aria-label="Cancel" on:click={cancelGiveUp}></button>
    <div class="modal-content giveup-modal">
      <h2 class="gu-title">{isClimb ? 'Skip this puzzle?' : `Give up ${$gameStore.gameMode === 'match' ? 'this puzzle' : $gameStore.gameMode === 'freeplay' ? 'this one' : "today's Daily"}?`}</h2>
      <p class="gu-text">{isClimb
        ? `Your heat resets to ×1.0${(climb?.spent ?? 0) > 0 ? ` and you forfeit the $${(climb?.spent ?? 0).toLocaleString()} spent on this one` : ''} — then a fresh puzzle.`
        : $gameStore.gameMode === 'match'
        ? 'You lose this puzzle and move on — your unspent budget is refunded to your Cash.'
        : $gameStore.gameMode === 'freeplay'
        ? 'You’ll skip to a fresh puzzle — you keep your credits (you only lose what you spent on this one).'
        : 'It counts as a loss and reveals the answer.'}</p>
      <div class="gu-actions">
        <button class="gu-cancel" on:click={cancelGiveUp}>Keep playing</button>
        <button class="gu-confirm" on:click={doGiveUp}>{isClimb ? '⏭️ Skip' : '🏳️ Give up'}</button>
      </div>
    </div>
  </div>
{/if}

<!-- 💥 Double or Nothing confirm layer (Cash Game) -->
{#if showDon}
  <div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Double or Nothing">
    <button type="button" class="modal-backdrop" aria-label="Cancel" on:click={cancelDon}></button>
    <div class="modal-content giveup-modal don-modal">
      <h2 class="gu-title">💥 Double or Nothing?</h2>
      <p class="gu-text">
        Solve this puzzle and your payout <b>doubles</b> to <b class="don-win">${donTarget.toLocaleString()}</b>.
        But you're all in — you <b>can't skip</b>, and if you get stuck you walk away with <b class="don-loss">$0</b>{(climb?.spent ?? 0) > 0 ? ` and forfeit the $${(climb?.spent ?? 0).toLocaleString()} you've spent` : ''}.
      </p>
      <div class="gu-actions">
        <button class="gu-cancel" on:click={cancelDon}>Not now</button>
        <button class="gu-confirm don-confirm" on:click={armDon} disabled={donBusy}>💥 Double it</button>
      </div>
    </div>
  </div>
{/if}

<!-- 🎉 One-time launch welcome (returning players after the fresh-start reset) -->
{#if showLaunchWelcome}
  <div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Welcome to WordBank">
    <div class="modal-content welcome-modal">
      <img class="wc-coin" src="/logo-coin.png" alt="" width="76" height="76" />
      <h2 class="wc-title">Welcome to WordBank 🎉</h2>
      <p class="wc-sub">We’ve officially launched — and everyone’s starting fresh.</p>
      <ul class="wc-list">
        <li><span>💰</span> <b>$2,000</b> in the bank to play with</li>
        <li><span>📅</span> Today is <b>Day 1</b> of the Daily</li>
        <li><span>🎰</span> Fresh puzzles waiting in the Cash Game</li>
        <li><span>🏆</span> Leaderboards are wide open — go claim a spot</li>
      </ul>
      <button class="wc-btn" on:click={dismissLaunchWelcome}>Let’s play →</button>
    </div>
  </div>
{/if}

<!-- 📜 Guided tutorial (first run + replayable from ❓) -->
{#if showTutorial}
  <Tutorial on:close={dismissTutorial} />
{/if}

{#if objective && !showTutorial}
  <ObjectiveCard mode={objective.mode} ctx={objective.ctx} on:close={dismissObjective} />
{/if}

{#if $gameStore.cashToast}
  <button class="attendance-toast" on:click={() => gameStore.update(s => ({ ...s, cashToast: null }))}>
    {#if $gameStore.cashToast.amount > 0}<strong>+${$gameStore.cashToast.amount.toLocaleString()}</strong> · {/if}{$gameStore.cashToast.label}
  </button>
{/if}

<!-- 🎰 Pure-solve ×1.5 multiplier fly-in -->
<!-- 💰 In-game bank modal: same info as /bank, but closing returns to the game -->
{#if showBank}
  <div class="modal-overlay info-overlay" role="button" tabindex="0" aria-label="Close"
    on:click={() => showBank = false} on:keydown={(e) => { if (e.key === 'Escape' || e.key === 'Enter') showBank = false; }}>
    <div class="info-card bank-card" on:click|stopPropagation role="dialog" aria-modal="true">
      <button class="modal-x" on:click={() => showBank = false} aria-label="Close">✕</button>
      <p class="bm-label">Net Worth</p>
      <div class="info-big">{fmtCash(bankData?.bank ?? netWorth ?? 0)}</div>
      <p class="info-sub">Your Cash — this is your score</p>
      {#if bankData}
        <div class="bm-hist-h">Recent activity</div>
        {#if (bankData.ledger ?? []).length === 0}
          <p class="info-note" style="text-align:center">No transactions yet. Win the Daily, show up for attendance, or climb the Cash Game to grow your Cash.</p>
        {:else}
          <div class="bm-ledger">
            {#each bankData.ledger.slice(0, 8) as e}
              <div class="bm-row">
                <span class="bm-reason">{bankReason(e.reason)}</span>
                <span class="bm-delta" class:pos={e.delta > 0} class:neg={e.delta < 0}>{e.delta > 0 ? '+' : '−'}{fmtCash(Math.abs(e.delta))}</span>
              </div>
            {/each}
          </div>
        {/if}
      {/if}
      <button class="info-close" on:click={() => showBank = false}>Back to game</button>
    </div>
  </div>
{/if}

<!-- 🔐 Vault door-open animation (from the main menu, after the PIN) → then items -->
{#if vaultVideo}
  <VaultReveal on:done={onVaultVideoEnd} />
{/if}

<!-- 🔐 My Vault: use power-ups in-game + view inventory + Store link -->
{#if showBag}
  <div class="modal-overlay info-overlay" role="button" tabindex="0" aria-label="Close"
    on:click={() => showBag = false} on:keydown={(e) => { if (e.key === 'Escape') showBag = false; }}>
    <div class="info-card bag-modal" on:click|stopPropagation role="dialog" aria-modal="true">
      <button class="modal-x" on:click={() => showBag = false} aria-label="Close">✕</button>
      <h3 class="info-title"><img src="/vault.png" alt="" class="vault-ic-xs" /> My Vault</h3>
      {#if showMainMenu}
        <div class="bag-inv"><InventoryList /></div>
        <button class="bag-store" on:click={() => goto('/shop')}>🛍️ Go to the Store →</button>
      {:else}
        <div class="bag-use-h">Your items</div>
        {#if vaultItems.length}
          <div class="bag-use-grid">
            {#each vaultItems as it}
              <button class="bag-use" class:locked={!it.usable} disabled={(dailyTwistBusy || dailyBoostBusy) && it.usable} on:click={() => tapVaultItem(it)} title={it.usable ? it.blurb : it.reason}>
                <span class="bag-use-e">{it.emoji}</span>
                {#if (it.count ?? 1) > 1}<span class="bag-use-n">×{it.count}</span>{/if}
                <span class="bag-use-name">{it.name}</span>
                <span class="bag-use-d">{it.usable ? it.blurb : '🔒 tap for why'}</span>
              </button>
            {/each}
          </div>
        {:else}
          <p class="bag-note">Nothing usable here right now.</p>
        {/if}
        <p class="bag-note">🔒 No shopping mid‑puzzle — items you buy now can't be used until your next puzzle.</p>
      {/if}
      {#if vaultMsg}<div class="bag-msg">{vaultMsg}</div>{/if}
    </div>
  </div>
{/if}

<!-- ℹ️ Daily explainers: multiplier breakdown / Solve-to-Earn calculation -->
{#if dailyInfo}
  <div class="modal-overlay info-overlay" role="button" tabindex="0" aria-label="Close"
    on:click={() => dailyInfo = null} on:keydown={(e) => { if (e.key === 'Escape' || e.key === 'Enter') dailyInfo = null; }}>
    <div class="info-card" on:click|stopPropagation role="dialog" aria-modal="true">
      <button class="modal-x" on:click={() => dailyInfo = null} aria-label="Close">✕</button>
      {#if dailyInfo === 'mult'}
        <div class="info-big">{fmtMult(dlMult)}</div>
        <h3 class="info-title">Bounty Multiplier</h3>
        <p class="info-sub">Everything you can earn from this puzzle is multiplied by this.</p>
        <div class="info-rows">
          <div class="info-row"><span>Base</span><b>×1.0</b></div>
          {#if dlStreakBonus > 0}<div class="info-row"><span>🏆 Win streak ({dlWinStreak} in a row)</span><b class="pos">+{dlStreakBonus.toFixed(1)}</b></div>{/if}
          <div class="info-row total"><span>Your multiplier</span><b>{fmtMult(dlMult)}</b></div>
        </div>
        <p class="info-note">It grows with your <button class="info-inline" on:click|stopPropagation={() => dailyInfo = 'streak'}>win streak</button> — <b>+0.1×</b> per consecutive solve, up to <b>×1.5</b>. Pure skill, same for everyone.</p>
      {:else if dailyInfo === 'twist'}
        <div class="info-big">{dailyMod?.emoji ?? '🎁'}</div>
        <h3 class="info-title">{dailyMod?.name ?? "Today's Twist"}</h3>
        <p class="info-sub">Today's special — applied automatically. ✓</p>
        <p class="info-twist-do">{dailyMod?.blurb ?? ''}</p>
        <p class="info-note">A different special every weekday. Everyone gets the <b>same</b> one — free and auto‑applied — so the Daily stays a fair, same‑for‑all puzzle.</p>
      {:else if dailyInfo === 'streak'}
        <div class="info-big">🏆 {dlWinStreak}</div>
        <h3 class="info-title">Win Streak</h3>
        <p class="info-sub">Daily puzzles you've solved in a row.</p>
        <div class="info-rows">
          <div class="info-row"><span>Solve today's Daily</span><b class="pos">+1</b></div>
          <div class="info-row"><span>Lose or give up</span><b class="neg">back to 0</b></div>
        </div>
        <p class="info-note">It also <b>boosts your bounty</b> — <b>+0.1×</b> per win (up to +0.5×; a 5-day streak = ×1.5). See the full <button class="info-inline" on:click|stopPropagation={() => dailyInfo = 'mult'}>multiplier</button> breakdown.</p>
      {:else}
        <div class="info-big green">${Math.max(0, dlNet).toLocaleString()}</div>
        <h3 class="info-title">Solve to Earn</h3>
        <p class="info-sub">What you pocket if you solve right now.</p>
        <div class="info-rows">
          <div class="info-row"><span>Bounty (base ${dlBase.toLocaleString()} × {fmtMult(dlMult)})</span><b class="pos">${dlReward.toLocaleString()}</b></div>
          <div class="info-row"><span>− Spent on letters</span><b class="neg">−${dlSpent.toLocaleString()}</b></div>
          <div class="info-row total"><span>You keep</span><b class="green">${dlNet.toLocaleString()}</b></div>
        </div>
        <p class="info-note">The base bounty comes from the letters' value. Spend less on letters to keep more — and grow the <button class="info-inline" on:click|stopPropagation={() => dailyInfo = 'mult'}>multiplier</button>.</p>
      {/if}
      <button class="info-close" on:click={() => dailyInfo = null}>Got it</button>
    </div>
  </div>
{/if}

<!-- ℹ️ Cash Game explainers: heat (= win streak) / Solve-to-Earn calculation -->
{#if climbInfo}
  <div class="modal-overlay info-overlay" role="button" tabindex="0" aria-label="Close"
    on:click={() => climbInfo = null} on:keydown={(e) => { if (e.key === 'Escape' || e.key === 'Enter') climbInfo = null; }}>
    <div class="info-card" on:click|stopPropagation role="dialog" aria-modal="true">
      <button class="modal-x" on:click={() => climbInfo = null} aria-label="Close">✕</button>
      {#if climbInfo === 'heat'}
        <div class="info-big">🔥 ×{climbHeat}</div>
        <h3 class="info-title">Heat — your multiplier</h3>
        <p class="info-sub">Everything you earn from a puzzle is multiplied by your heat.</p>
        <div class="info-rows">
          <div class="info-row"><span>Base</span><b>×1.0</b></div>
          <div class="info-row"><span>Each solve in a row</span><b class="pos">+0.1×</b></div>
          <div class="info-row"><span>Maxes out at</span><b>×2.0</b></div>
          <div class="info-row total"><span>Your heat</span><b>×{climbHeat}</b></div>
        </div>
        <p class="info-note">Heat climbs with your <button class="info-inline" on:click|stopPropagation={() => climbInfo = 'streak'}>win streak</button> and resets to ×1.0 if you get stuck or skip.</p>
      {:else if climbInfo === 'streak'}
        <div class="info-big">🏆 {climbStreak}</div>
        <h3 class="info-title">Win Streak</h3>
        <p class="info-sub">Cash Game puzzles you've solved in a row.</p>
        <div class="info-rows">
          <div class="info-row"><span>Solve a puzzle</span><b class="pos">+1</b></div>
          <div class="info-row"><span>Get stuck or skip</span><b class="neg">back to 0</b></div>
        </div>
        <p class="info-note">Your streak powers your <button class="info-inline" on:click|stopPropagation={() => climbInfo = 'heat'}>heat</button> — every win adds <b>+0.1×</b> to your payout (up to ×2.0).</p>
      {:else}
        <div class="info-big green">${Math.max(0, climbLive?.net ?? 0).toLocaleString()}</div>
        <h3 class="info-title">Solve to Earn</h3>
        <p class="info-sub">What you pocket if you solve right now.</p>
        <div class="info-rows">
          <div class="info-row"><span>Bounty × heat ({fmtMult(Number(climbHeat))})</span><b class="pos">${(climbLive?.payout ?? 0).toLocaleString()}</b></div>
          <div class="info-row"><span>− Spent on letters</span><b class="neg">−${(climbLive?.spent ?? 0).toLocaleString()}</b></div>
          <div class="info-row total"><span>You keep</span><b class="green">${(climbLive?.net ?? 0).toLocaleString()}</b></div>
        </div>
        <p class="info-note">Spend less on letters to keep more — and grow your <button class="info-inline" on:click|stopPropagation={() => climbInfo = 'heat'}>heat</button>.</p>
      {/if}
      <button class="info-close" on:click={() => climbInfo = null}>Got it</button>
    </div>
  </div>
{/if}

<main>
  <!-- 👤 First-run: pick a username (required to play socially) -->
  {#if loggedIn && hasInitialized && needsUsername}
    <div class="modal-overlay username-gate" role="dialog" aria-modal="true" aria-label="Pick your username">
      <div class="modal-content main-menu-modal claim-card">
        <img class="claim-coin" src="/logo-coin.png" alt="" width="84" height="84" />
        <h2>Pick your username</h2>
        <p class="claim-sub">This is your @handle — how friends find you and challenge you. You can change it later in My Account.</p>
        <div class="claim-row">
          <span class="claim-at">@</span>
          <input class="claim-input" placeholder="username" bind:value={claimInput} maxlength="15" autocomplete="off"
            on:keydown={(e) => { if (e.key === 'Enter') claimUsername(); }} />
        </div>
        {#if claimMsg}<p class="claim-msg">{claimMsg}</p>{/if}
        <button class="claim-btn" disabled={claimBusy || !claimInput.trim()} on:click={claimUsername}>
          {claimBusy ? 'Claiming…' : 'Claim username'}
        </button>
        <p class="claim-hint">3–15 characters · letters, numbers, or _</p>
      </div>
    </div>
  {/if}

  <!-- 🔐 PIN gate: unlock (returning) or set (new), full-screen over everything -->
  {#if showPinUnlock}
    <PinGate mode="unlock" uid={sessionUid} name={maUsername} balance={netWorth}
      on:unlocked={onPinUnlocked} on:logout={onPinLogout} />
  {:else if showPinSetup}
    <PinGate mode="set" uid={sessionUid} name={maUsername}
      on:pinset={onPinSet} on:skip={onPinSkip} on:logout={onPinLogout} />
  {/if}

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
        <div class="hero-top">
          <button class="streak-chip bag-chip" on:click={openVaultFromMenu} title="My Vault" aria-label="My Vault">
            <img src="/vault.png" alt="🔐" class="vault-ic-sm" />
          </button>
          <button class="bank-chip" on:click={() => goto('/bank')} title="Your Cash">
            <span class="bc-coin">💰</span>{netWorth == null ? '—' : '$' + Math.round(netWorth).toLocaleString()}
          </button>
          <button class="account-ic" on:click={() => goto($unreadCount > 0 ? '/profile?tab=alerts' : '/profile')} title="Profile">
            👤{#if $unreadCount > 0}<span class="account-count" title="{$unreadCount} new">{$unreadCount > 99 ? '99+' : $unreadCount}</span>{/if}
          </button>
        </div>
        <video class="menu-mark" src="/coin.mp4" poster="/coin-poster.jpg" autoplay loop muted playsinline disablepictureinpicture></video>
        <img class="menu-wordmark" src="/wordmark-slogan.png" alt="WordBank — Spend Less. Think More." />
      </div>
      {#if menuView === 'home'}
        <div class="main-menu-buttons stagger">
          <!-- 🎯 Act-now banner above Play: only a pending challenge / friend request -->
          {#if actNow.kind !== 'empty'}
            <button class="ab-main" on:click={actNow.primary}>
              <span class="ab-icon">{actNow.icon}</span>
              <span class="ab-text">
                <strong>{actNow.title}</strong>
                {#if actNow.sub}<small>{actNow.sub}</small>{/if}
              </span>
              <span class="ab-cta">{actNow.cta}</span>
            </button>
          {/if}
          <!-- ▶ Resume your most-recent live game (multiple games can be open at once) -->
          {#if resumeGame}
            <button class="menu-card resume-card" style="--i: 0" on:click={resumeOpen}>
              <span class="mc-title">▶ Resume {RESUME_LABEL[resumeGame.mode] ?? 'game'}</span>
              {#if openGames.length > 1}<span class="resume-more">+{openGames.length - 1} more in progress</span>{/if}
            </button>
          {/if}
          <button class="menu-card primary" style="--i: 0" on:click={() => { menuView = 'play'; fx('tap'); }}>
            <span class="mc-title">Play Now!</span>
          </button>
          <!-- 🤝 Challenge A Friend — sits right under Play Now -->
          <div class="vs-cta-group">
            <button class="vs-main" on:click={() => { fx('tap'); newChallenge(); }}>Challenge Friends</button>
            <button class="vs-people" title="Friends &amp; Groups" aria-label="Friends and groups" on:click={() => { fx('tap'); openCommunity('people'); }}>
              <span class="vs-ppl">👥</span><span class="vs-ppl-plus">+</span>
            </button>
          </div>
          <button class="menu-card" style="--i: 1" on:click={() => { fx('tap'); openCommunity('challenges'); }}>
            <span class="mc-title">Community</span>
          </button>
          <button class="menu-card" style="--i: 2" on:click={() => goto('/shop')}>
            <span class="mc-title">Store</span>
          </button>
        </div>

      {:else if menuView === 'play'}
        <div class="sub-head">
          <button class="sub-back" on:click={() => { menuView = 'home'; fx('tap'); }}>← Back</button>
          <h2 class="sub-title">Play</h2>
        </div>
        <div class="main-menu-buttons stagger">
          <button class="menu-card" class:done={dailyDone} class:resumable={dailyInProgress} style="--i: 0" on:click={handleMenuDaily}>
            <span class="mc-streak left" title="Attendance streak — days in a row">📅 {dailyStatus?.current_streak ?? 0}</span>
            <span class="mc-title">{dailyInProgress ? 'Resume Daily' : 'Daily'}</span>
            <span class="mc-streak right" title="Win streak — solves in a row">🏆 {dailyStatus?.win_streak ?? 0}</span>
            {#if dailyDone}
              {#if dailyStatus?.last_daily_won}
                <span class="daily-chip won">✅ +${(dailyStatus?.today_score ?? 0).toLocaleString()}</span>
              {:else}
                <span class="daily-chip lost">❌{dailyStatus?.today_score ? ' −$' + Math.abs(dailyStatus.today_score).toLocaleString() : ''}</span>
              {/if}
            {:else if dailyInProgress}
              <span class="daily-chip prog">▶ Resume</span>
            {/if}
          </button>
          <button class="menu-card" class:resumable={climbInProgress} style="--i: 1" on:click={handleMenuClimb}>
            <span class="mc-title">Cash Game</span>
            {#if climbInProgress}<span class="daily-chip prog">▶ Resume</span>{/if}
          </button>
          <button class="menu-card" class:resumable={freeplayInProgress} style="--i: 2" on:click={handleMenuFreeplay}>
            <span class="mc-title">{freeplayInProgress ? 'Resume Free Play' : 'Free Play'}</span>
            {#if freeplayInProgress}<span class="daily-chip prog">▶ Resume</span>{/if}
          </button>
          <button class="menu-card" style="--i: 3" on:click={() => { blitzSoon = true; fx('tap'); setTimeout(() => blitzSoon = false, 2500); }}>
            <span class="mc-title">Blitz</span><span class="mc-stat">Soon</span>
          </button>
          {#if blitzSoon}<p class="pm-soon-note">⚡ Solo Blitz is coming soon!</p>{/if}
        </div>

      {:else if menuView === 'community'}
        <div class="sub-head">
          {#if communityTab === 'people'}
            {#if peopleBackToHome}
              <button class="sub-back" on:click={() => { menuView = 'home'; fx('tap'); }}>← Back</button>
            {:else}
              <button class="sub-back" on:click={() => { communityTab = 'challenges'; fx('tap'); }}>← Community</button>
            {/if}
            <h2 class="sub-title">People</h2>
          {:else}
            <button class="sub-back" on:click={() => { menuView = 'home'; fx('tap'); }}>← Back</button>
            <h2 class="sub-title">Community</h2>
            <button class="sub-people" title="Friends & Groups" aria-label="Friends & Groups" on:click={() => { communityTab = 'people'; peopleBackToHome = false; fx('tap'); }}>👥</button>
          {/if}
        </div>
        {#if communityTab === 'people'}
          <div class="comm-tabs">
            <button class="comm-tab" class:active={peopleTab === 'friends'} on:click={() => { peopleTab = 'friends'; fx('tap'); }}>Friends{#if friendReqCount > 0} · {friendReqCount}{/if}</button>
            <button class="comm-tab" class:active={peopleTab === 'groups'} on:click={() => { peopleTab = 'groups'; fx('tap'); }}>Groups</button>
          </div>
        {:else}
          <div class="comm-tabs">
            <button class="comm-tab" class:active={communityTab === 'challenges'} on:click={() => { communityTab = 'challenges'; fx('tap'); }}>Challenges</button>
            <button class="comm-tab" class:active={communityTab === 'leaderboard'} on:click={() => { communityTab = 'leaderboard'; fx('tap'); }}>Leaderboard</button>
            <button class="comm-tab" class:active={communityTab === 'activity'} on:click={() => { communityTab = 'activity'; fx('tap'); }}>Activity</button>
          </div>
        {/if}

        {#if communityTab === 'challenges'}
          <div class="comm-body">
            <button class="ch-new-btn" on:click={newChallenge}>＋ New Challenge</button>
            {#if myMatches.length}
              <div class="ch-list">
                {#each myMatches as m}
                  <div class="ch-item">
                    <div class="ch-info">
                      <span class="ch-vs">{m.is_host ? 'You hosted' : m.host + ' invited you'}</span>
                      <span class="ch-meta">{m.pack_size} puzzle{m.pack_size === 1 ? '' : 's'} · {m.players} players{#if m.wager > 0} · ${m.wager?.toLocaleString()}{/if}</span>
                    </div>
                    {#if m.status === 'settled'}
                      <button class="ch-play ghost" disabled={mbBusy} on:click={() => respondToMatch(m)}>Results</button>
                    {:else if m.my_state !== 'done'}
                      <button class="ch-play" disabled={mbBusy} on:click={() => respondToMatch(m)}>{m.my_state === 'invited' ? 'Play' : 'Resume'}</button>
                    {:else}
                      <span class="ch-waiting">Waiting…</span>
                    {/if}
                  </div>
                {/each}
              </div>
            {:else}
              <p class="ch-empty">No challenges yet. Tap <b>＋ New Challenge</b> to start one.</p>
            {/if}
          </div>
        {:else if communityTab === 'leaderboard'}
          <div class="comm-body"><LeaderboardPanel /></div>
        {:else if communityTab === 'activity'}
          <div class="comm-body"><ActivityPanel /></div>
        {:else}
          <div class="comm-body">
            {#if peopleTab === 'friends'}
              <FriendsPanel onChallenge={challengeFriend} />
            {:else}
              <GroupsPanel />
            {/if}
          </div>
        {/if}
      {/if}
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
      <div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Challenge Friends">
        <button type="button" class="modal-backdrop" aria-label="Close" on:click={() => showChallenges = false}></button>
        <div class="modal-content main-menu-modal ch-modal">
          <button class="close-btn" on:click={() => showChallenges = false}>❌</button>

          <h2>⚔️ New Challenge</h2>
          <p class="cat-sub">Build a match — a pack of puzzles vs a friend or a group. Same puzzles for everyone.</p>

          <div class="ch-new">
              <!-- Opponent: friend or group -->
              <div class="ch-modes">
                <button type="button" class="ch-mode" class:active={mbTarget === 'friend'} on:click={() => mbTarget = 'friend'}>👤 A friend<small>by username</small></button>
                <button type="button" class="ch-mode" class:active={mbTarget === 'group'} on:click={() => mbTarget = 'group'}>👥 A group<small>everyone in it</small></button>
              </div>
              {#if mbTarget === 'friend'}
                <div class="ch-search-wrap">
                  <input class="ch-input" placeholder="Opponent username" bind:value={mbOpponent} on:input={onMbOppInput} autocomplete="off" />
                  {#if mbResults.length}
                    <div class="ch-results">
                      {#each mbResults as r}
                        <button type="button" class="ch-result-item" on:click={() => pickMbOpp(r.username)}>@{r.username}{#if r.is_friend} <span class="ch-friend-tag">friend</span>{/if}</button>
                      {/each}
                    </div>
                  {/if}
                </div>
              {:else}
                <select class="ch-input" bind:value={mbGroupId}>
                  <option value="" disabled selected>Pick a group</option>
                  {#each myGroups as g}<option value={g.id}>{g.name} ({g.members})</option>{/each}
                </select>
              {/if}

              <!-- Standard vs Blitz -->
              <div class="ch-modes">
                <button type="button" class="ch-mode" class:active={mbMode === 'standard'} on:click={() => mbMode = 'standard'}>🧠 Standard<small>efficiency · spend less</small></button>
                <button type="button" class="ch-mode" class:active={mbMode === 'blitz'} on:click={() => mbMode = 'blitz'}>⚡ Blitz<small>timed · combo speed</small></button>
              </div>

              <!-- Categories (optional) -->
              <div class="ch-cats">
                {#each CATEGORIES as c}
                  <button type="button" class="ch-cat" class:on={mbCategories.includes(c.value)} on:click={() => toggleCategory(c.value)}>{c.emoji}</button>
                {/each}
              </div>
              <p class="ch-hint">{mbCategories.length ? mbCategories.length + ' categories' : 'Any category'}</p>

              <!-- Pack size + payout + window -->
              <div class="ch-row">
                <label class="ch-field"><span>Puzzles</span>
                  <select class="ch-input" bind:value={mbPackSize}>{#each [1, 3, 5, 10] as n}<option value={n}>{n}</option>{/each}</select>
                </label>
                <label class="ch-field"><span>Payout</span>
                  <select class="ch-input" bind:value={mbPayout}><option value="winner">Winner takes all</option><option value="podium">Podium (3·2·1)</option></select>
                </label>
              </div>
              <div class="ch-row">
                <label class="ch-field"><span>Buy-in ($0 = friendly)</span>
                  <input class="ch-input" type="number" min="0" step="100" bind:value={mbWager} />
                </label>
                <label class="ch-field"><span>Respond within</span>
                  <select class="ch-input" bind:value={mbWindow}>{#each WINDOWS as w}<option value={w.s}>{w.l}</option>{/each}</select>
                </label>
              </div>
              <button class="ch-toggle" class:on={mbItemsAllowed} on:click={() => { mbItemsAllowed = !mbItemsAllowed; fx('tap'); }}>
                <span class="ch-tog-box">{mbItemsAllowed ? '✓' : ''}</span>
                ⚡ Allow power-ups — players can bring & use items they own
              </button>
              <p class="ch-objective">Your buy-in (min $500) is your spending cap. Buy as few letters as you can — <strong>unspent cash comes back, the pot is everyone’s spend, and the most efficient solver takes it.</strong> You only ever lose what you spend. Guesses are free.</p>
              <button class="ch-create" disabled={mbBusy} on:click={submitNewMatch} style="width:100%;">Send challenge ⚔️</button>
              {#if mbMsg}<p class="add-msg">{mbMsg}</p>{/if}
            </div>
        </div>
      </div>
    {/if}

    <!-- Settled-challenge results (shared with /history) -->
    <MatchDetailModal detail={matchResults} on:close={() => matchResults = null} />

    <!-- 💸 Can't afford the full buy-in: play with what you have, or decline -->
    {#if shortMatch}
      <div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Not enough Cash">
        <button type="button" class="modal-backdrop" aria-label="Close" on:click={() => shortMatch = null}></button>
        <div class="modal-content sm-modal">
          <div class="sm-icon">💸</div>
          <h2>Not enough for the full buy-in</h2>
          <div class="sm-rows">
            <div class="sm-row"><span>This challenge</span><b>${Number(shortMatch.wager).toLocaleString()} buy-in</b></div>
            <div class="sm-row"><span>You have</span><b>${Math.round(netWorth ?? 0).toLocaleString()}</b></div>
          </div>
          <p class="sm-note">You only ever lose what you spend — play with a smaller budget, or decline.</p>
          <button class="sm-play" disabled={mbBusy} on:click={() => playReduced(shortMatch)}>Play with ${Math.round(netWorth ?? 0).toLocaleString()}</button>
          <button class="sm-decline" disabled={mbBusy} on:click={() => declineChallenge(shortMatch)}>Decline challenge</button>
        </div>
      </div>
    {/if}

    <!-- Streak message (when Daily is disabled and user taps it) -->
    {#if showStreakMessage}
      <div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Come back tomorrow">
        <button type="button" class="modal-backdrop" aria-label="Close" on:click={() => showStreakMessage = false}></button>
        <div class="modal-content main-menu-modal">
          <button class="close-btn" on:click={() => showStreakMessage = false}>❌</button>
          <div class="cbt-medal">{dailyStatus?.last_daily_won ? '✅' : '🏁'}</div>
          <h2>{dailyStatus?.last_daily_won ? 'Daily Solved!' : "Today's Daily Done"}</h2>
          <p class="cbt-result">
            {dailyStatus?.last_daily_won ? "Nice work — you've finished today's puzzle." : "You've already played today's puzzle."}
          </p>
          <div class="cbt-stats">
            <div class="cbt-stat"><span class="cbt-val">+${dailyStatus?.today_score?.toLocaleString() ?? 0}</span><span class="cbt-cap">Profit</span></div>
            {#if (dailyStatus?.current_streak ?? 0) > 0}
              <div class="cbt-stat"><span class="cbt-val">🔥 {dailyStatus?.current_streak}</span><span class="cbt-cap">Day streak</span></div>
            {/if}
          </div>
          <p class="streak-message">
            {#if (dailyStatus?.current_streak ?? 0) > 0}Come back tomorrow for a new puzzle to keep your 🔥 {dailyStatus?.current_streak}-day streak alive!{:else}Come back tomorrow for a fresh puzzle and start a streak!{/if}
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

          <div class="ma-username">
            {#if maUsername && !maEditing}
              <span class="ma-uname">@{maUsername}</span>
              <button class="ma-edit" on:click={() => { maEditing = true; maInput = maUsername; maMsg = ''; }}>edit</button>
            {:else}
              <input class="ma-input" placeholder="pick a username" bind:value={maInput} maxlength="15"
                on:keydown={(e) => { if (e.key === 'Enter') saveMaUsername(); }} />
              <button class="ma-save" on:click={saveMaUsername}>Save</button>
            {/if}
          </div>
          {#if maMsg}<p class="ma-msg">{maMsg}</p>{/if}

          <div class="account-stats">
            <div class="stat-chip"><span class="stat-emoji">🔥</span> {accountStreak}<span class="stat-cap">day streak</span></div>
            <div class="stat-chip" title="Auto-protects your streak across one missed day. Earn one every 7-day streak.">
              <span class="stat-emoji">🧊</span> {accountFreezes}<span class="stat-cap">freeze{accountFreezes === 1 ? '' : 's'}</span>
            </div>
          </div>

          <button class="main-menu-btn ghost-btn" on:click={() => goto('/groups')}>👥 Groups</button>

          <div class="ma-section-label">Settings</div>
          <button class="main-menu-btn ghost-btn ma-toggle" on:click={() => { toggleSound(); if ($soundEnabled) fx('select'); }}>
            <span>{$soundEnabled ? '🔊' : '🔇'} Sound &amp; Haptics</span>
            <span class="ma-toggle-state">{$soundEnabled ? 'On' : 'Off'}</span>
          </button>

          <button class="main-menu-btn ghost-btn ma-toggle" on:click={toggleMusic}>
            <span>{$musicEnabled ? '🎵' : '🔕'} Lobby Music</span>
            <span class="ma-toggle-state">{$musicEnabled ? 'On' : 'Off'}</span>
          </button>
          {#if $musicEnabled}
            <div class="ma-music-ctl">
              <span class="mmc-ic">🔈</span>
              <input class="mmc-slider" type="range" min="0" max="100" step="1"
                value={Math.round($musicVolume * 100)}
                on:input={(e) => setMusicVolume(Number(e.currentTarget.value) / 100)} />
              <span class="mmc-pct">{Math.round($musicVolume * 100)}%</span>
            </div>
            {#if TRACKS.length > 1}
              <select class="ma-track-select" value={$currentTrackId} on:change={(e) => selectTrack(e.currentTarget.value)}>
                {#each TRACKS as t}<option value={t.id}>{t.title}</option>{/each}
              </select>
            {/if}
          {/if}
          <button class="main-menu-btn ghost-btn" on:click={() => { showMyAccount = false; showTutorial = true; }}>❓ How to Play</button>

          <button class="main-menu-btn" on:click={() => { showMyAccount = false; handleLogout(); }}>Log Out</button>
        </div>
      </div>
    {/if}
  {:else}
    <!-- ✅ GAME UI (Visible only when logged in) -->

    <!-- 🧠 Game Logo -->
    <img class="game-logo" src="/wordmark.png" alt="WordBank" />

    <!-- 🏷️ Game-mode pill — same spot & style for every mode; tap to see the rules -->
    {#if $gameStore.currentPhrase && $gameStore.gameMode && modeLabel}
      <button class="mode-pill" title="How {modeLabel.name} works" on:click={() => { fx('tap'); showObjectiveFor($gameStore.gameMode, true); }}>
        <span class="mp-emoji">{modeLabel.emoji}</span>{modeLabel.name}<span class="mp-info">ⓘ</span>
      </button>
    {/if}

    <!-- 💰 Bankroll — top of every mode. Challenge/1v1 = one number (left to spend) + one depleting bar. -->
    {#if $gameStore.currentPhrase && $gameStore.gameMode}
      {#if isMatch && matchInfo && !matchBlitz && !matchInfo.done}
        {@const buyin = matchInfo.budget ?? 0}
        {@const left = Math.max(0, buyin - (matchInfo.spent ?? 0))}
        <div class="top-bank">
          <div class="tb-row"><span class="tb-cap">💰 Left to spend</span><span class="tb-amt">${left.toLocaleString()}</span></div>
          <div class="tb-bar"><span class="tb-fill" style="width:{buyin > 0 ? Math.max(0, Math.min(100, (left / buyin) * 100)) : 100}%"></span></div>
          <div class="tb-sub">of your ${buyin.toLocaleString()} buy-in</div>
        </div>
      {:else if isFreeplay}
        <button class="top-bank tap" disabled={fpCashBusy} on:click={tapCredits}>
          <div class="tb-row"><span class="tb-cap">🎟️ Credits</span><span class="tb-amt cr">{Math.round($gameStore.bankroll ?? 0).toLocaleString()}</span></div>
          <div class="tb-sub">tap to cash out at 40:1</div>
        </button>
      {:else if !matchBlitz}
        <button class="top-bank solo" class:pop-up={bankFlash === 'up'} class:pop-down={bankFlash === 'down'} title="Your Cash" on:click={openBankModal}>
          <span class="tb-solo">💰 ${Math.round($tweenBank).toLocaleString()}</span>
        </button>
      {/if}
    {/if}

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
    <!-- ⏱️ Pressure-mode challenge clock -->
    {#if pressureActive}
      <div class="pressure-hud" class:danger={pressureRemaining <= 10}>
        <span class="ph-clock">⏱️ {pressureRemaining}s</span>
        <span class="ph-label">Pressure — solve fast for a bigger score</span>
      </div>
    {/if}

    <!-- 🗓️ Make-up daily banner -->
    {#if isMakeup}
      <div class="makeup-banner">
        <span class="mb-tag">🗓️ Make-up</span>
        <span class="mb-text">Playing {makeupLabel} · fills your calendar · earns the puzzle's Cash (no streak)</span>
      </div>
    {/if}

    <!-- 🎰 Cash Game (Climb) HUD — number-free so it feels random. Heat lives in the
         Solve-to-Earn box; power-ups live in the vault beside Solve. -->
    {#if isClimb && climb}
      {#if climb.stuck && $gameStore.gameState !== 'won'}
        <div class="climb-stuck">
          <span class="cs-text">Out of Cash for this one — leave and earn in the Daily, then come back to finish it.</span>
          <div class="cs-actions">
            <button class="cs-leave" on:click={goToMainMenu}>Leave &amp; earn</button>
          </div>
        </div>
      {/if}
    {/if}

    <!-- ⚔️ Challenge match HUD -->
    {#if isMatch && matchInfo && !matchInfo.done}
      {#if matchBlitz}
        <div class="climb-hud">
          <div class="ch-cell"><span class="ch-val">{matchInfo.position}/{matchInfo.pack_size}</span><span class="ch-label">Puzzle</span></div>
          <div class="ch-cell"><span class="ch-val ch-gold">{(matchInfo.total_score ?? 0).toLocaleString()}</span><span class="ch-label">Score</span></div>
          <div class="ch-cell"><span class="ch-val">×{matchCombo}</span><span class="ch-label">Combo</span></div>
          <div class="ch-cell" class:hot={matchRemaining <= 10}><span class="ch-val">⏱️{matchRemaining}</span><span class="ch-label">Time</span></div>
        </div>
      {:else}
        {#if matchInfo.pack_size > 1}<p class="match-pos">Puzzle {matchInfo.position}/{matchInfo.pack_size}</p>{/if}
        <StandingStrip standing={matchInfo.standing ?? null} />
      {/if}
      {#if (matchInfo.my_debuffs ?? []).length}
        <p class="debuff-banner">{(matchInfo.my_debuffs ?? []).map((/** @type {string} */ d) => DEBUFF_LABEL[d] ?? d).join(' · ')}</p>
      {/if}
      {#if matchInfo.items_allowed}
        {@const ownedSelf = selfPups.filter((/** @type {any} */ i) => (i.owned ?? 0) > 0)}
        {@const ownedSab = sabPups.filter((/** @type {any} */ i) => (i.owned ?? 0) > 0)}
        {#if ownedSelf.length}
          <p class="cp-hint">Your power-ups · tap to use — the group is notified</p>
          <div class="climb-pups">
            {#each ownedSelf as item}
              {@const used = (matchInfo.used_powerups ?? []).includes(item.id)}
              <button class="cp" class:equipped={used} disabled={used}
                on:click={() => handleMatchPup(item)} title={item.name}>
                <span class="cp-ic">{PUP_ICON[item.id] ?? '✨'}</span>
                <span class="cp-tag">{used ? '✓' : '×' + item.owned}</span>
              </button>
            {/each}
          </div>
        {/if}
        {#if ownedSab.length && (matchInfo.opponents ?? []).length}
          <p class="cp-hint sab">😈 Sabotage · tap an item, then pick who to hit</p>
          <div class="climb-pups">
            {#each ownedSab as item}
              <button class="cp sab" class:arming={pendingSabotage === item.id}
                on:click={() => tapSabotage(item)} title={item.name}>
                <span class="cp-ic">{PUP_ICON[item.id] ?? '✨'}</span>
                <span class="cp-tag">×{item.owned}</span>
              </button>
            {/each}
          </div>
          {#if pendingSabotage}
            <div class="sab-targets">
              <span class="sab-pick">Hit who?</span>
              {#each matchInfo.opponents ?? [] as opp}
                <button class="sab-target" on:click={() => pickSabTarget(opp.id)}>{opp.name}</button>
              {/each}
            </div>
          {/if}
        {/if}
        {#if !ownedSelf.length && !ownedSab.length}
          <p class="cp-hint">⚡ Power-ups are on — you don't own any yet. Grab some in the Store to use them here.</p>
        {/if}
      {/if}
    {/if}

    <!-- 🌍 Category + today's auto-applied Twist chip + witty clue -->
    <div class="puzzle-meta">
      {#if $gameStore.category}<span class="category-chip">{$gameStore.category}</span>{/if}
      {#if $gameStore.gameMode === 'daily' && dailyMod}
        <button class="twist-chip" title="Today's special — tap to see" on:click={() => { fx('tap'); dailyInfo = 'twist'; }}>{dailyMod.emoji}</button>
      {/if}
    </div>
    {#if $gameStore.clue}
      <p class="puzzle-clue">{$gameStore.clue}</p>
    {/if}


    <!-- 🎁 Announce today's auto-applied Twist during the dramatic load -->
    {#if introBuilding && $gameStore.gameMode === 'daily' && dailyMod}
      <div class="twist-announce" aria-hidden="true">
        <span class="ta-label">Today's special</span>
        <span class="ta-name">{dailyMod.emoji} {dailyMod.name}</span>
        <span class="ta-blurb">{dailyMod.blurb} · applied automatically</span>
      </div>
    {/if}

    <!-- 🔤 Phrase Display -->
    <section class="phrase-section">
      <PhraseDisplay on:revealComplete={onPhraseRevealComplete} on:introDone={onDailyIntroDone} />
    </section>

    <!-- ⏱ Out-of-Cash broke-timer — live Challenges only (Daily has no timer) -->
    {#if brokeMode && gameActive && isBroke}
      <div class="fold-bar broke">
        <span class="fold-timer">⏱ 0:{String(brokeLeft).padStart(2, '0')}</span>
        <span class="fold-warn">Out of Cash — guess in time or you give up this one</span>
      </div>
    {/if}

    <!-- 💰 Money hero -->
    <section class="stats-section">
      {#if soloHero}
        <!-- Daily · Makeup · Cash Game: the number you keep if you solve now (bankroll is up top) -->
        <div class="bounty-panel" class:loss={soloHero.net < 0} class:count-pop={introCountPop}>
          {#if $gameStore.gameMode === 'daily'}
            <button class="bp-mult-badge" title="How your multiplier works" on:click={() => { fx('tap'); dailyInfo = 'mult'; }}>×{Number($gameStore.bountyMult ?? 1).toFixed(1)}</button>
            <button class="bp-winstreak" title="Win streak" on:click={() => { fx('tap'); dailyInfo = 'streak'; }}>🏆 {dailyStatus?.win_streak ?? 0}</button>
          {:else if isClimb}
            <button class="bp-mult-badge" title="Heat — your payout multiplier" on:click={() => { fx('tap'); climbInfo = 'heat'; }}>🔥 ×{climbHeat}</button>
            <button class="bp-winstreak" title="Win streak" on:click={() => { fx('tap'); climbInfo = 'streak'; }}>🏆 {climbStreak}</button>
          {/if}
          <span class="bp-label">{soloHero.net >= 0 ? 'Solve to Earn' : '⚠️ You’re losing money'}</span>
          {#if $gameStore.gameMode === 'daily'}
            <button class="bp-amount bp-amount-btn" title="How this is calculated" on:click={() => { fx('tap'); dailyInfo = 'bounty'; }}>{$tweenNet >= 0 ? '$' : '−$'}{Math.abs(Math.round($tweenNet)).toLocaleString()}</button>
          {:else if isClimb}
            <button class="bp-amount bp-amount-btn" title="How this is calculated" on:click={() => { fx('tap'); climbInfo = 'earn'; }}>{$tweenNet >= 0 ? '$' : '−$'}{Math.abs(Math.round($tweenNet)).toLocaleString()}</button>
          {:else}
            <span class="bp-amount">{$tweenNet >= 0 ? '$' : '−$'}{Math.abs(Math.round($tweenNet)).toLocaleString()}</span>
          {/if}
          {#each spendFloaters as f (f.id)}<span class="spend-float">{f.text}</span>{/each}
        </div>
        {#if isClimb && climbRun && climbRun.solves >= 2}
          <p class="climb-run-line" class:best={climbRunIsBest}>
            🔥 {climbRun.solves}-solve run · <b class="run-profit" class:neg={climbRun.profit < 0}>{climbRun.profit >= 0 ? '+' : '−'}${Math.abs(climbRun.profit).toLocaleString()}</b> this run{#if climbRunIsBest} · 🏆 personal best{/if}
          </p>
        {/if}
      {:else if isFreeplay}
        <!-- Free Play: credits are up top; here just the cash-out + your Cash + reward -->
        <div class="credits-panel">
          {#if (($gameStore.bankroll ?? 0) - 2000) >= 40}
            <button class="cr-cashout" disabled={fpCashBusy} on:click={doFreeplayCashout}>
              💵 Cash out ${Math.min(50, Math.floor((($gameStore.bankroll ?? 0) - 2000) / 40))}
            </button>
          {:else}
            <span class="cr-note">Play money · cash out at 40:1</span>
          {/if}
          <span class="cr-wallet">💰 Cash {netWorth == null ? '—' : '$' + Math.round(netWorth).toLocaleString()}</span>
        </div>
        {#if freeLive}
          <p class="live-line">Solve {freeLive.clean ? 'clean ' : ''}for <b>+{freeLive.clean ? 250 : 120}</b> credits</p>
        {/if}
      {/if}
    </section>

    <!-- 💥 Double or Nothing — Cash Game only, when heat ≥ ×1.5. Arm to double the payout. -->
    {#if isClimb && climb && $gameStore.gameState !== 'won'}
      {#if donAvailable}
        <button class="don-cta" on:click={openDon}>
          <span class="don-cta-title">💥 Double or Nothing</span>
          <span class="don-cta-sub">Solve for <b>${donTarget.toLocaleString()}</b> — but get stuck and you forfeit it all</span>
        </button>
      {:else if donArmed}
        <div class="don-armed" role="status">
          <span class="don-armed-title">💥 Doubled — all in</span>
          <span class="don-armed-sub">Solve for <b>${donTarget.toLocaleString()}</b> · no skip, no backing out</span>
        </div>
      {/if}
    {/if}

    <!-- 🎮 Solve / Cancel Buttons (Cash Game gets a vault to the left for power-ups) -->
    <section class="buttons-section">
      <GameButtons>
        <svelte:fragment slot="left">
          {#if isClimb && climb?.state === 'active'}
            <button class="solve-vault" on:click={openBag} title="Your power-ups" aria-label="Open your vault">
              <img src="/vault.png" alt="" />
              {#if usableClimbPups > 0}<span class="solve-vault-badge">{usableClimbPups}</span>{/if}
            </button>
          {/if}
        </svelte:fragment>
      </GameButtons>
    </section>

    <!-- ⌨️ Keyboard Section (keyboard disables itself via gameStore state) -->
    <section class="keyboard-section">
      <Keyboard />
    </section>

    <!-- 🏆 Game Outcome Banner (win celebration handled by the slot-machine reveal) -->
    {#if $gameStore.gameState === "lost"}
      <div class="banner lose">Bankrupt!</div>
    {/if}

    <!-- 🎯 Result Modal -->
    {#if showResultModal && ['won', 'lost'].includes($gameStore.gameState)}
      <div class="modal-overlay">
        <div class="modal-content result-modal">
          {#if isDailyResult && resultWon && dr}
            {@const mult = Number(dr.mult ?? $gameStore.bountyMult ?? 1)}
            {@const base = dr.base ?? (mult > 0 ? Math.round((dr.reward ?? 0) / mult) : (dr.reward ?? 0))}
            <h2 class="win-h">🎉 Solved!</h2>
            <p class="result-sub">{todayLabel}</p>
            <!-- 3-line math -->
            <div class="win-math">
              <div class="wm-row"><span>Bounty {#if mult > 1}<small>(${base.toLocaleString()} × {fmtMult(mult)})</small>{/if}</span><b>${(dr.reward ?? 0).toLocaleString()}</b></div>
              <div class="wm-row"><span>− Spent on letters</span><b class="neg">−${(dr.spent ?? 0).toLocaleString()}</b></div>
              <div class="wm-row total"><span>Profit</span><b class="profit">{$resultProfit >= 0 ? '+' : '−'}${Math.abs(Math.round($resultProfit)).toLocaleString()}</b></div>
            </div>
            {#if dailyMod}
              <p class="win-twist">{dailyMod.emoji} <b>{dailyMod.name}</b> — applied for everyone</p>
            {/if}
            <!-- bankroll scrolls to the new total -->
            <div class="win-bank">
              <span class="wb-label">💰 Your Cash</span>
              <span class="wb-amount">${Math.round($resultBankAnim).toLocaleString()}</span>
            </div>
            <p class="win-rank">
              {#if resultRank && resultRank.total > 0}<b>🏆 #{resultRank.rank}</b> of {resultRank.total.toLocaleString()} today{/if}
              {#if (dailyStatus?.win_streak ?? 0) > 0} · 🔥 {dailyStatus?.win_streak} win streak{/if}
            </p>
            <div class="result-actions">
              <button class="share-btn" on:click={handleShare}>{shareCopied ? '✓ Copied!' : 'Share'}</button>
              <button class="next-puzzle-button" on:click={goToDailyLeaderboard}>Leaderboard</button>
            </div>
            <button class="win-menu" on:click={() => { showResultModal = false; hasTriggeredModal = false; goToMainMenu(); }}>Back to menu</button>
          {:else if isDailyResult}
            <div class="result-medal lose">😖</div>
            <h2>Busted</h2>
            <p class="result-sub">{todayLabel}</p>
            <div class="result-bankroll">
              <span class="rb-label">Your Cash</span>
              <span class="rb-amount">${resultBankroll.toLocaleString()}</span>
            </div>
            <p class="win-rank">No profit this time — your win streak resets. Come back tomorrow.</p>
            <div class="result-actions">
              <button class="share-btn" on:click={handleShare}>{shareCopied ? '✓ Copied!' : 'Share'}</button>
              <button class="next-puzzle-button" on:click={goToDailyLeaderboard}>Leaderboard</button>
            </div>
          {:else if isClimb && resultWon}
            <!-- 🎰 Cash Game win banner (mirrors Daily): bounty × heat − spent = profit -->
            {@const payout = climb?.last_gain ?? 0}
            {@const cspent = climb?.spent ?? 0}
            {@const earnedMult = (climb?.bounty ?? 0) > 0 ? (payout / climb.bounty) : ((climb?.heat ?? 100) / 100)}
            {@const heatMult = donArmedThisPuzzle ? earnedMult / 2 : earnedMult}
            <h2 class="win-h">{donArmedThisPuzzle ? '💥 Doubled!' : '🎉 Solved!'}</h2>
            <p class="result-sub">{$gameStore.currentPhrase}</p>
            <div class="win-math">
              <div class="wm-row"><span>Bounty <small>(🔥 ×{heatMult.toFixed(1)} heat{#if donArmedThisPuzzle} · 💥 ×2{/if})</small></span><b>${payout.toLocaleString()}</b></div>
              <div class="wm-row"><span>− Spent on letters</span><b class="neg">−${cspent.toLocaleString()}</b></div>
              <div class="wm-row total"><span>Profit</span><b class="profit">{$resultProfit >= 0 ? '+' : '−'}${Math.abs(Math.round($resultProfit)).toLocaleString()}</b></div>
            </div>
            <p class="win-twist">🔥 Heat now ×{climbHeat}{#if climbStreak > 0} · 🏆 {climbStreak} win streak{/if}{#if (climb?.heat ?? 100) >= 200} · maxed{/if}</p>
            <div class="win-bank">
              <span class="wb-label">💰 Your Cash</span>
              <span class="wb-amount">${Math.round($resultBankAnim).toLocaleString()}</span>
            </div>
            <div class="result-actions">
              <button class="share-btn" on:click={() => { showResultModal = false; hasTriggeredModal = false; goToMainMenu(); }}>Leave</button>
              <button class="next-puzzle-button" on:click={() => { showResultModal = false; hasTriggeredModal = false; climbAdvance().then(() => tick().then(playDailyIntroIfArmed)); }}>Next →</button>
            </div>
          {:else if isMatch}
            <!-- Challenge match: finished the whole pack -->
            <div class="result-medal">⚔️</div>
            <h2>Challenge complete!</h2>
            <p class="result-sub">{#if matchInfo?.mode === 'blitz'}You scored {(matchInfo?.total_score ?? 0).toLocaleString()} across {matchInfo?.pack_size} puzzle{matchInfo?.pack_size === 1 ? '' : 's'}{:else}You solved {matchInfo?.solved ?? 0}/{matchInfo?.pack_size} spending ${(matchInfo?.spent ?? 0).toLocaleString()}{/if}</p>
            <p class="arcade-gain">{matchInfo?.status === 'settled' ? 'Settled — check the results.' : "Lowest spend wins — we'll settle once everyone plays."}</p>
            <div class="result-actions">
              {#if matchInfo?.status === 'settled'}
                <button class="share-btn" on:click={async () => { const id = matchInfo?.id; showResultModal = false; hasTriggeredModal = false; goToMainMenu(); matchResults = { loading: true }; matchResults = await getMatchDetail(id); }}>View Results</button>
              {:else}
                <button class="share-btn" on:click={() => { showResultModal = false; hasTriggeredModal = false; goToMainMenu(); newChallenge(); }}>Challenge Friends</button>
              {/if}
              <button class="next-puzzle-button" on:click={() => { showResultModal = false; hasTriggeredModal = false; goToMainMenu(); }}>Menu</button>
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
          {:else if isMakeup}
            <!-- Make-up daily result (calendar fill; no streak/Bank) -->
            {#if resultWon}
              <div class="result-medal">🗓️</div>
              <h2>Made it up!</h2>
              <p class="result-sub">{makeupLabel} is on your calendar · {$gameStore.currentPhrase}</p>
              <p class="arcade-gain">Counts toward 🗓️ Perfect Week / 📅 Perfect Month.</p>
            {:else}
              <div class="result-medal">💸</div>
              <h2>Out of Cash</h2>
              <p class="result-sub">The answer was {$gameStore.currentPhrase}</p>
            {/if}
            <div class="result-actions">
              <button class="share-btn" on:click={() => { showResultModal = false; hasTriggeredModal = false; goToMainMenu(); goto('/streak'); }}>Calendar</button>
              <button class="next-puzzle-button" on:click={() => { showResultModal = false; hasTriggeredModal = false; goToMainMenu(); }}>Menu</button>
            </div>
          {:else if isChallenge}
            <!-- Challenge result (settles when the friend plays) -->
            <div class="result-medal">{resultWon ? (isPressure ? '⏱️' : '⚔️') : '⌛'}</div>
            <h2>{resultWon ? 'Challenge played!' : "Time's up!"}</h2>
            {#if resultWon}
              <p class="result-sub">You scored ${chScore.toLocaleString()} · {$gameStore.currentPhrase}</p>
              {#if isPressure}<p class="arcade-earn">Bankroll ${resultBankroll.toLocaleString()} + speed bonus</p>{/if}
            {:else}
              <p class="result-sub">Ran out of time — scored $0 · {$gameStore.currentPhrase}</p>
            {/if}
            <p class="arcade-gain">We'll settle the pot once your friend plays.</p>
            <div class="result-actions">
              <button class="share-btn" on:click={() => { showResultModal = false; hasTriggeredModal = false; goToMainMenu(); newChallenge(); }}>Challenge Friends</button>
              <button class="next-puzzle-button" on:click={() => { showResultModal = false; hasTriggeredModal = false; goToMainMenu(); }}>Menu</button>
            </div>
          {/if}
        </div>
      </div>
    {/if}
  {/if}
</main>

<style>
  @import url('https://fonts.googleapis.com/css2?family=VT323&display=swap');
  @import url('https://fonts.googleapis.com/css2?family=Montserrat:wght@500;700&display=swap');

  .attendance-toast {
    position: fixed; top: 14px; left: 50%; transform: translateX(-50%);
    z-index: 2000; padding: 0.6rem 1.1rem; border-radius: 999px; cursor: pointer;
    font-family: var(--font-ui); font-size: 0.85rem; color: #3a2a00;
    background: var(--brand-grad, linear-gradient(135deg,#fbbf24,#fde047));
    border: none; box-shadow: var(--glow-brand, 0 8px 24px rgba(251, 191, 36,0.4));
    animation: attDrop 0.4s var(--ease-spring, ease) both;
  }
  .attendance-toast strong { font-family: var(--font-display); }
  /* 🎰 Pure-solve ×1.5 multiplier fly-in */
  @keyframes attDrop { from { transform: translate(-50%, -60px); opacity: 0; } to { transform: translate(-50%, 0); opacity: 1; } }
  @import url('https://fonts.googleapis.com/css2?family=Playfair+Display:wght@400;700&display=swap');
  @import url('https://fonts.googleapis.com/css2?family=Orbitron:wght@400;700&display=swap');

  main {
    max-width: 600px;
    margin: 0 auto;
    text-align: center;
    font-family: var(--font-ui);
    padding: 16px 12px calc(env(safe-area-inset-bottom, 0px) + 244px); /* space so content stays above fixed Solve + keyboard */
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
  .pressure-hud {
    display: flex; flex-direction: column; align-items: center; gap: 2px;
    width: 100%; max-width: 360px; margin: 0 auto 14px; padding: 0.5rem 1rem;
    border: 1px solid rgba(251,191,36,0.4); border-radius: 14px;
    background: linear-gradient(135deg, rgba(251,191,36,0.12), rgba(251,191,36,0.03));
  }
  .pressure-hud .ph-clock { font-family: var(--font-display); font-weight: 800; font-size: 1.5rem; color: #fbbf24; line-height: 1; font-variant-numeric: tabular-nums; }
  .pressure-hud .ph-label { font-size: 0.72rem; color: var(--text-muted); }
  .pressure-hud.danger { border-color: rgba(248,113,113,0.6); background: linear-gradient(135deg, rgba(248,113,113,0.16), rgba(248,113,113,0.04)); animation: pressurePulse 1s ease-in-out infinite; }
  .pressure-hud.danger .ph-clock { color: #f87171; }
  @keyframes pressurePulse { 0%,100% { box-shadow: 0 0 0 rgba(248,113,113,0); } 50% { box-shadow: 0 0 16px rgba(248,113,113,0.35); } }
  .makeup-banner {
    display: flex; align-items: center; gap: 8px; justify-content: center;
    width: 100%; max-width: 360px; margin: 0 auto 12px; padding: 0.5rem 0.9rem;
    border: 1px solid rgba(56,189,248,0.4); border-radius: 12px;
    background: linear-gradient(135deg, rgba(56,189,248,0.12), rgba(56,189,248,0.03));
  }
  .makeup-banner .mb-tag { font-family: var(--font-display); font-weight: 800; font-size: 0.8rem; color: #38bdf8; white-space: nowrap; }
  .makeup-banner .mb-text { font-size: 0.74rem; color: var(--text-muted); }
  .bank-it-btn {
    display: inline-flex;
    align-items: baseline;
    gap: 8px;
    margin: 0 auto 14px;
    padding: 0.6rem 1.3rem;
    border: 1px solid rgba(253, 224, 71, 0.5);
    border-radius: 999px;
    background: linear-gradient(135deg, rgba(251, 191, 36,0.16), rgba(253, 224, 71,0.08));
    color: var(--brand-2);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 1rem;
    cursor: pointer;
    box-shadow: 0 0 16px rgba(253, 224, 71, 0.18);
    transition: transform 0.15s, box-shadow 0.2s;
  }
  .bank-it-btn:hover { transform: translateY(-1px); box-shadow: 0 0 22px rgba(253, 224, 71, 0.3); }
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
  .ah-mult { border-color: rgba(253, 224, 71, 0.35); background: linear-gradient(135deg, rgba(251, 191, 36,0.12), rgba(253, 224, 71,0.04)); }
  .ah-val { font-family: var(--font-display); font-weight: 700; font-size: 1.15rem; color: var(--text); font-variant-numeric: tabular-nums; }
  .ah-mult .ah-val { color: var(--brand-2); }
  .ah-gold { color: #fcd34d; }
  .ah-label { font-size: 0.55rem; letter-spacing: 0.14em; text-transform: uppercase; color: var(--text-faint); font-weight: 600; }
  /* Cash Game (Climb) HUD */
  .climb-hud { display: flex; gap: 8px; width: 100%; max-width: 360px; margin: 0 auto 12px; }
  .match-pos { text-align: center; font-family: var(--font-display); font-weight: 700; font-size: 0.8rem; color: var(--text-muted); margin: 0 0 8px; }
  .ch-cell {
    flex: 1; display: flex; flex-direction: column; align-items: center; gap: 2px; padding: 10px 6px;
    background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-md, 12px);
  }
  .ch-cell.hot { border-color: rgba(251,191,36,0.5); background: linear-gradient(135deg, rgba(251,191,36,0.14), rgba(251,191,36,0.04)); }
  .ch-val { font-family: var(--font-display); font-weight: 700; font-size: 1.15rem; color: var(--text); font-variant-numeric: tabular-nums; }
  .ch-cell.hot .ch-val { color: #fbbf24; }
  .ch-gold { color: #fcd34d; }
  .ch-label { font-size: 0.55rem; letter-spacing: 0.14em; text-transform: uppercase; color: var(--text-faint); font-weight: 600; }
  .cp-hint { font-size: 0.66rem; color: var(--text-faint); text-align: center; margin: 0 0 5px; }
  .climb-pups { display: flex; gap: 6px; width: 100%; max-width: 360px; margin: 0 auto 12px; justify-content: space-between; }
  .cp {
    flex: 1; display: flex; flex-direction: column; align-items: center; gap: 1px; padding: 7px 2px;
    border-radius: 10px; cursor: pointer; border: 1px solid var(--border); background: var(--surface);
    transition: transform 0.1s, border-color 0.15s;
  }
  .cp:hover:not(:disabled) { transform: translateY(-1px); border-color: rgba(251,191,36,0.5); }
  .cp:disabled { opacity: 0.4; cursor: default; }
  .cp.equipped { border-color: var(--brand-2); background: rgba(253, 224, 71,0.12); opacity: 1; }
  .cp.equipped .cp-tag { color: var(--brand-2); }
  .cp.empty { opacity: 0.35; }
  .cp.sab { border-color: rgba(244,114,182,0.3); }
  .cp.sab:hover:not(:disabled) { border-color: rgba(244,114,182,0.6); }
  .cp.sab.arming { border-color: #f472b6; box-shadow: 0 0 12px rgba(244,114,182,0.4); }
  .cp-hint.sab { color: #f472b6; }
  .debuff-banner {
    text-align: center; font-size: 0.76rem; font-weight: 700; color: #fb7185; margin: 0 auto 8px;
    max-width: 340px; padding: 5px 10px; border-radius: 999px;
    background: rgba(251,113,133,0.1); border: 1px solid rgba(251,113,133,0.3);
  }
  .sab-targets { display: flex; flex-wrap: wrap; gap: 6px; justify-content: center; align-items: center; margin: 2px auto 10px; max-width: 340px; }
  .sab-pick { font-size: 0.74rem; color: #f472b6; font-weight: 700; }
  .sab-target {
    padding: 4px 11px; border-radius: 999px; cursor: pointer; font-weight: 700; font-size: 0.8rem;
    color: #fff; border: none; background: linear-gradient(135deg, #f472b6, #db2777);
  }
  .cp-ic { font-size: 1.1rem; line-height: 1; }
  .cp-tag { font-size: 0.6rem; font-weight: 700; color: var(--text-faint); }
  .climb-stuck {
    display: flex; flex-direction: column; gap: 8px; width: 100%; max-width: 360px; margin: 0 auto 12px; padding: 0.8rem;
    border: 1px solid rgba(248,113,113,0.45); border-radius: 14px; background: rgba(248,113,113,0.08); text-align: center;
  }
  .cs-text { font-size: 0.82rem; color: #fca5a5; }
  .cs-actions { display: flex; gap: 8px; justify-content: center; }
  .cs-leave { padding: 0.5rem 1rem; border: 1px solid var(--border); border-radius: 10px; cursor: pointer; font-weight: 700; color: var(--text-muted); background: transparent; }
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
    margin: 0 0 12px;
  }
  .category-chip {
    font-family: var(--font-display);
    font-weight: 600;
    font-size: 0.8rem;
    color: var(--brand-2);
    background: rgba(253, 224, 71, 0.10);
    border: 1px solid rgba(253, 224, 71, 0.28);
    padding: 6px 13px;
    border-radius: var(--r-pill);
  }
  /* 🎁 today's auto-applied Twist chip (tap to see what it does) */
  .twist-chip { display: inline-grid; place-items: center; width: 32px; height: 32px; border-radius: 999px; cursor: pointer;
    border: 1px solid rgba(253,224,71,0.55); background: rgba(251,191,36,0.16); font-size: 1.1rem; line-height: 1;
    box-shadow: 0 0 10px rgba(251,191,36,0.25); }
  .twist-chip:active { transform: scale(0.92); }
  /* ⓘ re-open the "How to win" card */
  .fold-bar { display: flex; align-items: center; justify-content: center; gap: 10px; flex-wrap: wrap; margin: 6px auto 2px; }
  .fold-bar.broke {
    padding: 8px 14px; border-radius: 12px; max-width: 340px;
    background: rgba(248,113,113,0.12); border: 1px solid rgba(248,113,113,0.5);
    animation: pressurePulse 1s ease-in-out infinite;
  }
  .fold-timer { font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 1.25rem; color: #f87171; }
  .fold-warn { font-size: 0.76rem; color: #fca5a5; flex: 1 1 140px; text-align: left; }
  .puzzle-clue {
    max-width: 340px;
    margin: 8px auto 12px;
    font-family: var(--font-ui);
    font-size: 0.98rem;
    font-style: italic;
    line-height: 1.4;
    color: var(--text);
    text-wrap: balance;
  }

  /* Today's shared modifier — a small chip next to the category */
  .mod-chip {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 0.74rem;
    color: #fcd34d;
    background: rgba(251, 191, 36, 0.12);
    border: 1px solid rgba(251, 191, 36, 0.32);
    padding: 5px 11px;
    border-radius: var(--r-pill, 999px);
    white-space: nowrap;
  }
  .mod-chip.pure { color: #6ee7b7; background: rgba(16, 185, 129, 0.12); border-color: rgba(110, 231, 183, 0.4); }

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
  /* ⚡ Power-up tray (above the keyboard) */

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
    padding: 2rem 1.1rem 1.2rem;
    gap: 1.2rem;
  }
  .sub-head {
    width: 100%; display: flex; align-items: center; gap: 0.6rem; margin-bottom: 0.2rem;
  }
  .sub-back {
    display: inline-flex; align-items: center; gap: 4px; padding: 0.5rem 0.9rem;
    background: var(--surface); border: 1px solid var(--border); border-radius: 12px;
    color: var(--text); font-weight: 700; font-size: 0.9rem; cursor: pointer;
    transition: transform 0.15s, border-color 0.2s, background 0.2s;
  }
  .sub-back:hover { transform: translateX(-2px); border-color: var(--border-strong); background: var(--surface-2); }
  .sub-title { font-family: var(--font-display); font-size: 1.15rem; font-weight: 800; }
  .sub-people {
    margin-left: auto; width: 40px; height: 40px; display: grid; place-items: center; font-size: 1.1rem;
    background: var(--surface); border: 1px solid var(--border); border-radius: 12px; cursor: pointer;
  }
  .sub-people:hover { border-color: var(--brand-2); }
  /* Community hub tabs + body */
  .comm-tabs { display: flex; gap: 8px; width: 100%; margin: 12px 0 14px; }
  .comm-tab { flex: 1; padding: 9px 0; border-radius: 12px; border: 1px solid var(--border); background: var(--surface);
    color: var(--text-muted); font-family: var(--font-display); font-weight: 700; font-size: 0.86rem; cursor: pointer; }
  .comm-tab.active { background: linear-gradient(135deg, #fde047, #f59e0b); color: #3a2a00; border-color: transparent; }
  /* Unread-count badges (Activity tab + Community card) */
  .comm-count { display: inline-grid; place-items: center; min-width: 18px; height: 18px; padding: 0 5px;
    border-radius: 999px; background: #f43f5e; color: #fff; font-family: var(--font-display);
    font-weight: 800; font-size: 0.68rem; margin-left: 6px; vertical-align: middle; }
  .menu-card .mc-count { position: absolute; top: 10px; right: 12px; display: grid; place-items: center;
    min-width: 20px; height: 20px; padding: 0 6px; border-radius: 999px; background: #f43f5e; color: #fff;
    font-family: var(--font-display); font-weight: 800; font-size: 0.72rem; box-shadow: 0 0 0 2px var(--bg, #0a0e14); }
  .act-sec { font-family: var(--font-display); font-size: 0.72rem; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: var(--gold); text-align: left; margin: 6px 2px 8px; }
  .act-sec:not(:first-child) { margin-top: 20px; }
  .comm-body { width: 100%; }
  .comm-body.people { display: flex; flex-direction: column; gap: 0.6rem; }
  /* Subtle "play with friends" nudge under the solo modes */
  /* Challenge A Friend — one on-brand gold pill, split by a divider into CTA + friends */
  .vs-cta-group { display: flex; width: 100%; margin-top: 8px;
    border-radius: 12px; overflow: hidden;
    box-shadow: 0 3px 10px rgba(245,158,11,0.3), inset 0 1px 0 rgba(255,255,255,0.4); }
  .vs-main, .vs-people { border: none; cursor: pointer; color: #3a2a00;
    background: linear-gradient(135deg, #fde047, #f59e0b); }
  .vs-main { flex: 1; padding: 12px 14px 12px 72px; text-align: center; /* left pad offsets the people button so the label centers over the whole group */
    font-family: var(--font-display); font-weight: 800; font-size: 0.94rem; letter-spacing: 0.01em; }
  .vs-main:hover { filter: brightness(1.05); }
  .vs-main:active { transform: scale(0.99); }
  .vs-people { position: relative; width: 58px; flex: none; display: grid; place-items: center;
    border-left: 1.5px solid rgba(120,80,0,0.45); } /* just the vertical divider line */
  .vs-people:hover { filter: brightness(1.06); }
  .vs-people:active { transform: scale(0.97); }
  .vs-ppl { font-size: 1.35rem; line-height: 1; }
  .vs-ppl-plus { position: absolute; top: 7px; right: 9px; width: 14px; height: 14px; border-radius: 50%;
    background: #3a2a00; color: #fde047; font-weight: 900; font-size: 0.6rem; line-height: 1; display: grid; place-items: center;
    box-shadow: 0 1px 2px rgba(0,0,0,0.4); }
  .ch-new-btn {
    width: 100%; margin-bottom: 12px; padding: 12px; border-radius: 14px; border: none; cursor: pointer;
    font-family: var(--font-display); font-weight: 800; font-size: 0.95rem; color: #3a2a00;
    background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
    box-shadow: 0 6px 18px rgba(251, 191, 36, 0.25);
  }
  .ch-new-btn:hover { filter: brightness(1.05); }
  /* Short-on-Cash sheet */
  .sm-modal { max-width: 360px; text-align: center; }
  .sm-icon { font-size: 2.4rem; margin-bottom: 6px; }
  .sm-modal h2 { font-family: var(--font-display); font-size: 1.2rem; margin: 0 0 14px; }
  .sm-rows { display: flex; flex-direction: column; gap: 6px; margin: 0 0 12px; padding: 12px 14px;
    border-radius: 14px; border: 1px solid var(--border); background: var(--surface); }
  .sm-row { display: flex; justify-content: space-between; align-items: center; gap: 12px; font-size: 0.88rem; color: var(--text-muted); }
  .sm-row b { font-family: var(--font-display); color: var(--text); }
  .sm-note { font-size: 0.8rem; color: var(--text-faint); margin: 0 0 16px; }
  .sm-play { width: 100%; padding: 13px; border: none; border-radius: 14px; cursor: pointer; margin-bottom: 8px;
    font-family: var(--font-display); font-weight: 800; font-size: 0.98rem; color: #3a2a00;
    background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047)); box-shadow: 0 6px 18px rgba(251,191,36,0.25); }
  .sm-play:disabled { opacity: 0.5; }
  .sm-decline { width: 100%; padding: 11px; border-radius: 14px; cursor: pointer;
    border: 1px solid rgba(251,113,133,0.4); background: transparent; color: #fb7185; font-weight: 700; font-size: 0.9rem; }
  .sm-decline:disabled { opacity: 0.5; }
  .menu-hero {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    width: 100%;
  }
  .hero-top {
    display: grid;
    grid-template-columns: 1fr auto 1fr;
    align-items: center;
    width: 100%;
    max-width: 360px;
    margin-bottom: 1.4rem;
  }
  .hero-top .streak-chip { justify-self: start; }
  .hero-top .bank-chip { justify-self: center; }
  .account-ic {
    position: relative;
    justify-self: end;
    display: inline-grid; place-items: center;
    width: 54px; height: 54px; border-radius: 50%;
    background: var(--surface, rgba(255,255,255,0.05)); border: 1px solid var(--border);
    cursor: pointer; font-size: 1.7rem; transition: transform 0.15s, border-color 0.2s;
  }
  .account-ic:hover { transform: translateY(-1px); border-color: rgba(251,191,36,0.5); }
  .account-ic:active { transform: scale(0.94); }
  /* unread notification count, off the top-right of the avatar */
  .account-count {
    position: absolute; top: -4px; right: -4px; display: grid; place-items: center;
    min-width: 19px; height: 19px; padding: 0 5px; border-radius: 999px;
    background: #f43f5e; color: #fff; font-family: var(--font-display); font-weight: 800; font-size: 0.68rem;
    box-shadow: 0 0 0 2px var(--bg, #0a0e14);
  }
  .bank-chip {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    padding: 8px 16px;
    border-radius: 12px;
    background: rgba(0, 0, 0, 0.38);
    border: 1px solid rgba(251, 191, 36, 0.5);
    color: #fde047;
    font-family: 'Orbitron', var(--font-display);
    font-weight: 700;
    font-size: 1.25rem;
    letter-spacing: 0.04em;
    font-variant-numeric: tabular-nums;
    text-shadow: 0 0 10px rgba(251, 191, 36, 0.65), 0 0 22px rgba(251, 191, 36, 0.35);
    box-shadow: inset 0 0 14px rgba(251, 191, 36, 0.1);
    cursor: pointer;
    transition: transform 0.15s, box-shadow 0.2s;
  }
  .bank-chip:hover { transform: translateY(-1px); }
  .bank-chip:active { transform: scale(0.96); }
  .bank-chip .bc-coin { font-size: 1.1rem; text-shadow: none; }
  .streak-chip {
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
  .menu-mark {
    width: min(46vw, 172px);
    aspect-ratio: 1;
    height: auto;
    object-fit: cover;
    border-radius: 50%;
    margin-bottom: 4px;
    box-shadow: 0 0 26px rgba(251, 191, 36, 0.55), 0 10px 44px rgba(251, 191, 36, 0.4);
  }
  /* Mario-style coin spin: flat horizontal flip (edge-on at 90°/270°) + a gentle bob */
  .menu-mark.spin { animation: coinSpin 2.6s linear infinite; will-change: transform; backface-visibility: visible; }
  @keyframes coinSpin {
    0%   { transform: translateY(0)    rotateY(0deg); }
    25%  { transform: translateY(-5px) rotateY(90deg); }
    50%  { transform: translateY(-7px) rotateY(180deg); }
    75%  { transform: translateY(-5px) rotateY(270deg); }
    100% { transform: translateY(0)    rotateY(360deg); }
  }
  @media (prefers-reduced-motion: reduce) {
    .menu-mark.spin { animation: none; }
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
  /* ── Gold bullion bars ─────────────────────────────────────────────── */
  .menu-card {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
    text-align: center;
    padding: 17px 22px;
    border-radius: 14px;
    /* brushed-silver chrome plate (CSS) with a beveled chrome frame + gold engraved label */
    background: linear-gradient(180deg, #fdfefe 0%, #e7ecf1 10%, #c4cdd7 50%, #9ba7b4 78%, #c1cad4 100%);
    border: 1px solid #8794a2;
    color: #b8860b;
    cursor: pointer;
    overflow: hidden;
    box-shadow:
      inset 0 0 0 1.5px rgba(255, 255, 255, 0.85),   /* bright chrome inner edge */
      inset 0 0 0 3.5px rgba(92, 106, 122, 0.28),     /* groove → recessed brushed panel */
      inset 0 2px 2px rgba(255, 255, 255, 0.9),       /* top catch-light */
      inset 0 -3px 6px rgba(70, 85, 100, 0.45),       /* bottom depth */
      0 5px 12px rgba(0, 0, 0, 0.55),                 /* drop shadow */
      0 0 16px rgba(205, 222, 240, 0.25);             /* soft glow */
    transition: transform 0.16s var(--ease-spring), box-shadow 0.2s, filter 0.2s;
  }
  /* glossy chrome sheen */
  .menu-card::before {
    content: ''; position: absolute; inset: 0; border-radius: inherit; z-index: 0; pointer-events: none;
    background:
      linear-gradient(180deg, rgba(255,255,255,0.7) 0%, rgba(255,255,255,0.15) 14%, rgba(255,255,255,0) 42%, rgba(255,255,255,0.1) 100%),
      radial-gradient(130% 60% at 50% -10%, rgba(255,255,255,0.55), rgba(255,255,255,0) 60%);
    mix-blend-mode: screen;
  }
  /* moving shine streak */
  .menu-card::after {
    content: ''; position: absolute; top: 0; bottom: 0; left: 0; width: 55%;
    background: linear-gradient(105deg, transparent 25%, rgba(255,255,255,0.25) 42%, rgba(255,255,255,0.95) 50%, rgba(255,255,255,0.25) 58%, transparent 75%);
    transform: translateX(-180%) skewX(-12deg);
    animation: barShine 5s ease-in-out infinite;
    animation-delay: calc(var(--i, 0) * 0.45s);
    pointer-events: none;
  }
  @keyframes barShine {
    0%, 58% { transform: translateX(-180%) skewX(-12deg); }
    78%, 100% { transform: translateX(330%) skewX(-12deg); }
  }
  @media (hover: hover) and (pointer: fine) {
    .menu-card:hover:not(.disabled) {
      transform: translateY(-2px);
      filter: brightness(1.05);
      box-shadow:
        inset 0 0 0 1.5px rgba(255, 255, 255, 0.9),
        inset 0 0 0 3.5px rgba(92, 106, 122, 0.28),
        inset 0 -3px 6px rgba(70, 85, 100, 0.45),
        0 7px 16px rgba(0, 0, 0, 0.55), 0 0 24px rgba(210, 225, 240, 0.4);
    }
  }
  .menu-card.gold-flash:not(.disabled) { transform: translateY(1px) scale(0.99); }
  .menu-card.gold-flash:not(.disabled),
  .menu-card:focus-visible:not(.disabled) {
    outline: none;
    box-shadow:
      inset 0 0 0 1.5px rgba(255, 255, 255, 0.85),
      0 0 0 2px rgba(255, 240, 190, 0.9), 0 0 22px rgba(255, 220, 110, 0.7), 0 6px 14px rgba(0, 0, 0, 0.5);
  }
  .menu-card.primary {
    filter: brightness(1.04);
    box-shadow:
      inset 0 0 0 1.5px rgba(255, 255, 255, 0.9),
      inset 0 0 0 3.5px rgba(92, 106, 122, 0.28),
      inset 0 2px 2px rgba(255, 255, 255, 0.9),
      inset 0 -3px 6px rgba(70, 85, 100, 0.45),
      0 6px 14px rgba(0, 0, 0, 0.55), 0 0 22px rgba(210, 225, 240, 0.4);
  }
  .menu-card.disabled { opacity: 0.5; cursor: not-allowed; }
  .mc-title {
    position: relative; z-index: 1;
    font-family: var(--font-display); font-weight: 800; font-size: 1.2rem; letter-spacing: 0.02em;
    /* embossed gold to match the reference button */
    background: linear-gradient(180deg, #fff1a8 0%, #f6cd4d 38%, #dd9c1b 66%, #b3760b 100%);
    -webkit-background-clip: text; background-clip: text;
    -webkit-text-fill-color: transparent; color: transparent;
    text-shadow: 0 1px 1px rgba(70, 44, 0, 0.45), 0 0 1px rgba(120, 80, 0, 0.4);
  }
  .mc-stat { position: relative; z-index: 1; font-family: var(--font-display); font-weight: 800; font-size: 0.9rem; color: #b8860b; }
  /* notification badge — top-right corner of the bar */
  .mc-badge {
    position: absolute; top: -7px; right: -6px; z-index: 3;
    min-width: 22px; height: 22px; padding: 0 6px; border-radius: 999px;
    display: inline-grid; place-items: center;
    font-family: var(--font-display); font-weight: 800; font-size: 0.76rem; line-height: 1;
    color: #fff; background: #ef4444; border: 2px solid #1a1407;
    box-shadow: 0 0 10px rgba(239, 68, 68, 0.6);
  }
  .mc-badge.gift { background: transparent; border: none; box-shadow: none; font-size: 1.1rem; top: -10px; right: -8px; }
  /* home "you've been challenged" banner */
  /* Home act-now banner: most-urgent item + optional "+N more" chip */
  .ab-main {
    width: 100%; min-width: 0; display: flex; align-items: center; gap: 12px;
    padding: 13px 16px; border-radius: 14px; cursor: pointer; text-align: left;
    background: linear-gradient(135deg, rgba(251, 191, 36, 0.18), rgba(251, 191, 36, 0.12));
    border: 1px solid rgba(251, 191, 36, 0.5);
    animation: invitePulse 1.8s ease-in-out infinite;
  }
  @keyframes invitePulse { 0%,100% { box-shadow: 0 0 16px rgba(251, 191, 36, 0.18); } 50% { box-shadow: 0 0 30px rgba(251, 191, 36, 0.42); } }
  .ab-icon { font-size: 1.6rem; flex: none; }
  .ab-text { flex: 1; display: flex; flex-direction: column; gap: 1px; min-width: 0; }
  .ab-text strong { font-family: var(--font-display); font-weight: 800; font-size: 1rem; color: var(--text);
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .ab-text small { font-size: 0.78rem; color: var(--text-muted); }
  .ab-cta { font-family: var(--font-display); font-weight: 800; color: var(--brand-2); font-size: 0.9rem; white-space: nowrap; flex: none; }
  /* Empty state = subtle CTA, no pulse/glow */
  /* Daily status chip on the Play Now card */
  .daily-chip {
    font-size: 0.68rem; font-weight: 800; padding: 3px 9px; border-radius: 999px; white-space: nowrap;
    border: 1px solid var(--border); background: rgba(0,0,0,0.25); color: var(--text);
  }
  /* 📅 / 🏆 streak chips on the Daily card */
  .mc-streak { position: absolute; top: 50%; transform: translateY(-50%); z-index: 1;
    font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 0.82rem; color: #463413;
    text-shadow: 0 1px 0 rgba(255,255,255,0.35); }
  .mc-streak.left { left: 13px; }
  .mc-streak.right { right: 13px; }
  .menu-card.done .mc-streak, .menu-card.resumable .mc-streak { color: rgba(255,255,255,0.85); text-shadow: none; }
  /* solid fills so chips read clearly */
  .daily-chip.won   { color: #052e16; border-color: rgba(22,163,74,0.85); background: linear-gradient(135deg, #4ade80, #16a34a); box-shadow: 0 1px 6px rgba(22,163,74,0.5); }
  .daily-chip.lost  { color: #fff; border-color: rgba(225,80,100,0.85); background: linear-gradient(135deg, #fb7185, #e11d48); box-shadow: 0 1px 6px rgba(225,29,72,0.45); text-shadow: 0 1px 1px rgba(0,0,0,0.25); }
  .daily-chip.prog  { color: #fff; border-color: rgba(5,150,105,0.85); background: linear-gradient(135deg, #34d399, #059669); box-shadow: 0 1px 6px rgba(5,150,105,0.5); text-shadow: 0 1px 1px rgba(0,0,0,0.25); }

  /* ✅ Completed Daily — grayed-out plate (no chrome shine), result chip shows the score */
  .menu-card.done {
    background: linear-gradient(180deg, #39414c 0%, #2b323b 100%);
    border-color: #49525e;
    box-shadow: inset 0 1px 0 rgba(255,255,255,0.06), inset 0 -2px 4px rgba(0,0,0,0.4), 0 3px 8px rgba(0,0,0,0.45);
  }
  .menu-card.done::before, .menu-card.done::after { display: none; } /* kill chrome sheen + shine streak */
  .menu-card.done .mc-title {
    background: linear-gradient(180deg, #aeb7c2, #7f8893); -webkit-background-clip: text; background-clip: text;
    -webkit-text-fill-color: transparent; color: transparent; text-shadow: none;
  }
  /* ▶ Resumable mode — clean green accent instead of the gold chrome */
  .menu-card.resumable {
    background: linear-gradient(180deg, #16352b 0%, #0f2a22 100%);
    border-color: rgba(16,185,129,0.55);
    box-shadow: inset 0 1px 0 rgba(110,231,183,0.18), inset 0 0 0 1px rgba(16,185,129,0.25), 0 4px 12px rgba(0,0,0,0.5), 0 0 16px rgba(16,185,129,0.18);
  }
  .menu-card.resumable::before, .menu-card.resumable::after { display: none; }
  .menu-card.resumable .mc-title {
    background: linear-gradient(180deg, #d1fae5, #6ee7b7); -webkit-background-clip: text; background-clip: text;
    -webkit-text-fill-color: transparent; color: transparent; text-shadow: none;
  }
  /* ▶ Resume shortcut card (home menu) — green, mirrors the in-progress accent */
  .menu-card.resume-card {
    flex-direction: column; gap: 2px;
    background: linear-gradient(180deg, #16352b 0%, #0f2a22 100%);
    border-color: rgba(16,185,129,0.6);
    box-shadow: inset 0 1px 0 rgba(110,231,183,0.2), inset 0 0 0 1px rgba(16,185,129,0.3), 0 4px 14px rgba(0,0,0,0.5), 0 0 20px rgba(16,185,129,0.25);
  }
  .menu-card.resume-card::before, .menu-card.resume-card::after { display: none; }
  .menu-card.resume-card .mc-title {
    background: linear-gradient(180deg, #d1fae5, #6ee7b7); -webkit-background-clip: text; background-clip: text;
    -webkit-text-fill-color: transparent; color: transparent; text-shadow: none;
  }
  .resume-more { position: relative; z-index: 1; font-size: 0.72rem; color: rgba(167,243,208,0.82); font-weight: 600; }
  .progress-modes { border-left-color: rgba(251,191,36,0.3); }
  .mc-arrow { color: var(--text-faint); font-size: 1.1rem; transition: transform 0.2s, color 0.2s; }
  .mc-count {
    min-width: 22px; height: 22px; padding: 0 6px; border-radius: 999px;
    display: inline-grid; place-items: center; font-family: var(--font-display);
    font-weight: 800; font-size: 0.78rem; color: #3a2a00; line-height: 1;
    background: var(--brand-grad, linear-gradient(135deg,#fbbf24,#fde047));
    box-shadow: 0 0 12px rgba(251, 191, 36,0.4);
  }
  /* Play accordion */
  .menu-card.open .mc-arrow { color: var(--brand-2); }
  .play-modes { display: flex; flex-direction: column; gap: 0.5rem; margin: -0.35rem 0 0.3rem; padding-left: 0.5rem; border-left: 2px solid rgba(253, 224, 71,0.25); }
  .play-mode {
    display: flex; align-items: center; gap: 0.8rem; width: 100%; padding: 0.75rem 0.95rem;
    border-radius: 12px; cursor: pointer; text-align: left;
    background: rgba(255,255,255,0.07); border: 1px solid rgba(255,255,255,0.14);
    transition: transform 0.12s, border-color 0.15s, background 0.15s;
  }
  .play-mode:hover:not(:disabled) { transform: translateX(2px); background: rgba(255,255,255,0.11); }
  .play-mode:disabled { cursor: not-allowed; }
  .play-mode.done { opacity: 0.7; }
  /* per-mode accent so they pop on the dark background */
  .play-mode.daily { border-left: 3px solid #fbbf24; }
  .play-mode.cash  { border-left: 3px solid #fbbf24; }
  .play-mode.free  { border-left: 3px solid #60a5fa; }
  .play-mode.blitz { border-left: 3px solid #f472b6; }
  .play-mode:hover.daily { border-color: #fbbf24; }
  .play-mode:hover.cash  { border-color: #fbbf24; }
  .play-mode:hover.free  { border-color: #60a5fa; }
  .play-mode:hover.blitz { border-color: #f472b6; }
  .pm-ic { font-size: 1.3rem; width: 1.6rem; text-align: center; }
  .pm-t { flex: 1; font-family: var(--font-display); font-weight: 600; font-size: 0.98rem; color: #fff; }
  .pm-tag { font-size: 0.65rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; color: #f472b6; border: 1px solid rgba(244,114,182,0.4); border-radius: 999px; padding: 2px 7px; }
  .pm-soon-note { text-align: center; font-size: 0.78rem; color: #f472b6; margin: 2px 0 0; }
  /* utility footer (replaces the old floating icon cluster) */
  .menu-footer { display: flex; justify-content: center; gap: 1.2rem; margin-top: 0.4rem; }
  .menu-footer button {
    background: none; border: none; cursor: pointer; color: var(--text-faint);
    font-size: 0.78rem; font-weight: 600; padding: 4px;
  }
  .menu-footer button:hover { color: var(--text-muted); }
  /* back-to-menu button on game/sub screens */
  /* ☰ hamburger main-menu (top-left) */
  .menu-back-btn {
    position: fixed; top: 14px; left: 14px; z-index: 1000;
    width: 38px; height: 38px; border-radius: 999px; cursor: pointer;
    display: grid; place-items: center; color: var(--text);
    background: var(--surface-strong, rgba(20,28,40,0.85)); border: 1px solid var(--border-strong, var(--border)); backdrop-filter: blur(10px);
  }
  .menu-back-btn:hover { border-color: var(--brand-2); color: var(--brand-2); }
  .hamburger, .hamburger::before, .hamburger::after {
    content: ''; display: block; width: 18px; height: 2px; border-radius: 2px; background: currentColor;
  }
  .hamburger { position: relative; }
  .hamburger::before { position: absolute; top: -6px; left: 0; }
  .hamburger::after { position: absolute; top: 6px; left: 0; }
  /* how-to-play (top-center) */
  .help-btn {
    position: fixed; top: 14px; left: 50%; transform: translateX(-50%); z-index: 1000;
    width: 38px; height: 38px; border-radius: 999px; cursor: pointer; font-weight: 800; font-size: 1.1rem; line-height: 1;
    display: grid; place-items: center; color: var(--text);
    background: var(--surface-strong, rgba(20,28,40,0.85)); border: 1px solid var(--border-strong, var(--border)); backdrop-filter: blur(10px);
  }
  .help-btn:hover { border-color: var(--brand-2); color: var(--brand-2); }
  /* 🏳️ give up (top-right) — red exit arrow */
  .giveup-btn {
    position: fixed; top: 14px; right: 14px; z-index: 1000;
    width: 38px; height: 38px; border-radius: 999px; cursor: pointer; font-size: 1.25rem; line-height: 1; font-weight: 800;
    display: grid; place-items: center; color: #f87171;
    background: var(--surface-strong, rgba(20,28,40,0.85)); border: 1px solid rgba(248,113,113,0.5); backdrop-filter: blur(10px);
  }
  .giveup-btn:hover { border-color: #f87171; background: rgba(248,113,113,0.16); }
  .giveup-btn:active { transform: scale(0.93); }
  /* match chat — sits just below the help button so they never overlap */
  .match-chat-btn {
    position: fixed; top: 60px; right: 14px; z-index: 1000;
    display: flex; align-items: center; gap: 5px; padding: 9px 14px; border-radius: 999px; cursor: pointer;
    font-size: 1.02rem; font-weight: 700; color: var(--text);
    background: var(--surface-strong, rgba(20,28,40,0.9)); border: 1px solid rgba(251,191,36,0.5); backdrop-filter: blur(10px);
    box-shadow: 0 2px 12px rgba(0,0,0,0.4), 0 0 12px rgba(251,191,36,0.15);
  }
  .match-chat-btn:hover { border-color: var(--brand-2); }
  .match-chat-btn.unread { border-color: #f43f5e; animation: chatPulse 1.6s ease-in-out infinite; }
  @keyframes chatPulse { 0%,100% { box-shadow: 0 2px 12px rgba(0,0,0,0.4), 0 0 0 0 rgba(244,63,94,0.5); } 50% { box-shadow: 0 2px 12px rgba(0,0,0,0.4), 0 0 0 6px rgba(244,63,94,0); } }
  .mcb-label { font-family: var(--font-display); font-size: 0.84rem; }
  .mc-dot { position: absolute; top: 3px; right: 3px; width: 10px; height: 10px; border-radius: 999px; background: #f43f5e; box-shadow: 0 0 0 2px var(--bg, #0a0e14); }
  .welcome-modal { max-width: 380px; text-align: center; }
  .wc-coin { display: block; margin: 0 auto 0.5rem; }
  .wc-title { font-family: var(--font-display); font-size: 1.4rem; margin: 0 0 0.35rem; }
  .wc-sub { font-size: 0.92rem; color: var(--text-muted); margin: 0 0 1rem; }
  .wc-list { list-style: none; padding: 0; margin: 0 0 1.2rem; display: flex; flex-direction: column; gap: 0.55rem; text-align: left; }
  .wc-list li { display: flex; align-items: center; gap: 0.6rem; font-size: 0.9rem; color: var(--text);
    background: var(--surface-2, rgba(255,255,255,0.04)); border: 1px solid var(--border); border-radius: 12px; padding: 0.6rem 0.8rem; }
  .wc-list li span { font-size: 1.15rem; }
  .wc-list b { color: #fde047; }
  .wc-btn { width: 100%; padding: 0.85rem; border-radius: 13px; border: none; cursor: pointer; font-weight: 800; font-size: 1rem;
    color: #3a2a00; background: linear-gradient(135deg, #fde047, #f59e0b); }
  .giveup-modal { max-width: 360px; text-align: center; }
  .gu-title { font-family: var(--font-display); font-size: 1.2rem; margin: 0 0 0.5rem; }
  .gu-text { font-size: 0.88rem; color: var(--text-muted); margin: 0 0 1.2rem; line-height: 1.4; }
  .gu-actions { display: flex; gap: 0.6rem; }
  .gu-actions button { flex: 1; padding: 0.75rem 0.7rem; border-radius: 12px; cursor: pointer; font-weight: 800; font-size: 0.9rem; }
  .gu-cancel { border: 1px solid var(--border-strong, var(--border)); background: var(--surface-2, rgba(255,255,255,0.05)); color: var(--text); }
  .gu-confirm { border: none; background: rgba(248,113,113,0.18); border: 1px solid rgba(248,113,113,0.5); color: #fca5a5; }
  .gu-confirm:hover { background: rgba(248,113,113,0.28); }
  /* 💥 Double or Nothing — high-stakes gold/amber accent (distinct from the red Skip/Give-up) */
  .don-modal .don-win { color: #fbbf24; }
  .don-modal .don-loss { color: #fca5a5; }
  .don-confirm { background: rgba(251,191,36,0.16) !important; border: 1px solid rgba(251,191,36,0.6) !important; color: #fcd34d !important; }
  .don-confirm:hover { background: rgba(251,191,36,0.28) !important; }
  .don-confirm:disabled { opacity: 0.55; cursor: default; }
  /* CTA shown in the Cash Game when heat ≥ ×1.5 */
  .don-cta {
    display: flex; flex-direction: column; align-items: center; gap: 2px;
    width: 100%; margin: 0 auto 0.5rem; padding: 0.6rem 0.9rem; border-radius: 14px; cursor: pointer;
    background: linear-gradient(180deg, rgba(251,191,36,0.16), rgba(245,158,11,0.10));
    border: 1px solid rgba(251,191,36,0.55); color: #fcd34d;
    box-shadow: 0 0 18px rgba(251,191,36,0.18); animation: donPulse 1.8s ease-in-out infinite;
  }
  .don-cta:active { transform: scale(0.98); }
  .don-cta-title { font-family: var(--font-display); font-weight: 900; font-size: 1rem; letter-spacing: 0.02em; }
  .don-cta-sub { font-size: 0.74rem; color: var(--text-muted); }
  .don-cta-sub b, .don-armed-sub b { color: #fbbf24; }
  /* 🔥 Cash Game run line — momentum under the money hero */
  .climb-run-line { margin: 0.35rem auto 0; text-align: center; font-size: 0.8rem; color: var(--text-muted); }
  .climb-run-line .run-profit { color: #4ade80; }
  .climb-run-line .run-profit.neg { color: #fca5a5; }
  .climb-run-line.best { color: #fcd34d; }
  @keyframes donPulse {
    0%, 100% { box-shadow: 0 0 14px rgba(251,191,36,0.16); }
    50% { box-shadow: 0 0 26px rgba(251,191,36,0.36); }
  }
  /* Armed (committed) indicator */
  .don-armed {
    display: flex; flex-direction: column; align-items: center; gap: 2px;
    width: 100%; margin: 0 auto 0.5rem; padding: 0.55rem 0.9rem; border-radius: 14px;
    background: rgba(251,191,36,0.12); border: 1px solid rgba(251,191,36,0.7);
  }
  .don-armed-title { font-family: var(--font-display); font-weight: 900; font-size: 0.95rem; color: #fcd34d; }
  .don-armed-sub { font-size: 0.74rem; color: var(--text-muted); }
  .chat-modal { max-width: 440px; }
  .chat-h { font-family: var(--font-display); font-size: 1.15rem; margin: 0 0 0.8rem; }
  .chat-msgs {
    display: flex; flex-direction: column; gap: 6px; height: 300px; overflow-y: auto;
    padding: 0.8rem; border-radius: 14px; border: 1px solid var(--border); background: var(--surface); text-align: left;
  }
  .chat-empty { color: var(--text-faint); font-size: 0.85rem; text-align: center; margin: auto; }
  .cmsg {
    max-width: 80%; align-self: flex-start; display: flex; flex-direction: column; gap: 1px;
    padding: 0.45rem 0.7rem; border-radius: 12px; background: var(--surface-2, rgba(255,255,255,0.05)); border: 1px solid var(--border);
  }
  .cmsg.mine { align-self: flex-end; background: rgba(253, 224, 71,0.12); border-color: rgba(253, 224, 71,0.3); }
  .cm-name { font-size: 0.66rem; font-weight: 700; color: var(--brand-2); }
  .cmsg.mine .cm-name { align-self: flex-end; color: var(--text-faint); }
  .cm-body { font-size: 0.88rem; color: var(--text); word-break: break-word; }
  .chat-input-row { display: flex; gap: 0.5rem; margin-top: 0.7rem; }
  .chat-input { flex: 1; min-width: 0; padding: 0.6rem 0.9rem; border-radius: 12px; border: 1px solid var(--border); background: var(--surface); color: var(--text); font-size: 0.95rem; }
  .chat-send { padding: 0.6rem 1.1rem; border: none; border-radius: 12px; cursor: pointer; font-weight: 700; color: #3a2a00; background: var(--brand-grad, linear-gradient(135deg,#fbbf24,#fde047)); }
  .chat-send:disabled { opacity: 0.5; }
  /* notification bell */
  .bell-button { position: relative; }
  .bell-badge {
    position: absolute; top: -4px; right: -4px; min-width: 17px; height: 17px;
    padding: 0 4px; border-radius: 999px; display: grid; place-items: center;
    font-size: 0.62rem; font-weight: 800; color: #fff; line-height: 1;
    background: #f43f5e; box-shadow: 0 0 0 2px var(--bg, #0a0e14);
  }
  /* notifications panel */
  .notif-list { display: flex; flex-direction: column; gap: 0.5rem; max-height: 60vh; overflow-y: auto; }
  .notif-item {
    padding: 0.7rem 0.85rem; border-radius: 12px;
    background: var(--surface); border: 1px solid var(--border); color: var(--text);
  }
  .notif-item.fresh { border-color: rgba(253, 224, 71,0.45); background: linear-gradient(135deg, rgba(251, 191, 36,0.08), rgba(253, 224, 71,0.03)); }
  .ni-main { text-align: left; display: flex; flex-direction: column; gap: 2px; width: 100%; background: none; border: none; color: inherit; cursor: pointer; padding: 0; }
  .ni-title { font-family: var(--font-display); font-weight: 700; font-size: 0.92rem; }
  .ni-body { font-size: 0.82rem; color: var(--text-muted); }
  .ni-actions { display: flex; gap: 0.5rem; margin-top: 0.55rem; }
  .ni-act { flex: 1; padding: 0.45rem 0.7rem; border-radius: 9px; font-weight: 800; font-size: 0.82rem; cursor: pointer; border: 1px solid var(--border); }
  .ni-act.accept { color: #3a2a00; border: none; background: var(--brand-grad, linear-gradient(135deg,#fbbf24,#fde047)); }
  .ni-act.decline { color: #f87171; background: transparent; border-color: rgba(248,113,113,0.4); }
  .ni-done { display: inline-block; margin-top: 0.5rem; font-size: 0.8rem; font-weight: 800; }
  .ni-done.accepted { color: var(--brand-2); }
  .ni-done.declined { color: var(--text-faint); }
  @media (hover: hover) and (pointer: fine) {
    .menu-card:hover:not(.disabled) .mc-arrow { transform: translateX(3px); color: var(--brand-2); }
  }

  /* Modal action button (reused brand button) */
  .main-menu-btn {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 1rem;
    padding: 13px 20px;
    border-radius: var(--r-md);
    border: none;
    background: var(--brand-grad);
    color: #3a2a00;
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
  .ch-tabs { display: flex; gap: 8px; margin: 4px 0 14px; }
  .ch-tab { flex: 1; padding: 9px 0; border-radius: 12px; border: 1px solid var(--border); background: var(--surface);
    color: var(--text-muted); font-family: var(--font-display); font-weight: 700; font-size: 0.9rem; cursor: pointer; }
  .ch-tab.active { background: linear-gradient(135deg, #fde047, #f59e0b); color: #3a2a00; border-color: transparent; }
  .ch-empty { color: var(--text-muted); font-size: 0.92rem; padding: 2rem 1rem; }
  .ch-empty b { color: var(--brand-2); }
  .ch-new { display: flex; flex-direction: column; gap: 0.5rem; margin-bottom: 1rem; }
  .ch-modes { display: flex; gap: 0.5rem; }
  .ch-mode {
    flex: 1; display: flex; flex-direction: column; gap: 0.15rem; align-items: flex-start;
    padding: 0.55rem 0.7rem; border-radius: 10px; cursor: pointer; text-align: left;
    border: 1px solid var(--border); background: var(--surface); color: var(--text);
    font-weight: 700; font-size: 0.9rem; transition: border-color 0.15s, background 0.15s;
  }
  .ch-mode small { font-weight: 500; font-size: 0.68rem; color: var(--text-muted); }
  .ch-mode.active { border-color: rgba(251,191,36,0.6); background: linear-gradient(135deg, rgba(251,191,36,0.14), rgba(251,191,36,0.04)); box-shadow: 0 0 12px rgba(251,191,36,0.15); }
  .ch-search-wrap { position: relative; display: flex; flex-direction: column; }
  .ch-search-wrap .ch-input { width: 100%; }
  .ch-results {
    display: flex; flex-direction: column; gap: 2px; margin-top: 4px;
    border: 1px solid var(--border); border-radius: 10px; padding: 4px; background: var(--surface);
  }
  .ch-result-item {
    text-align: left; padding: 0.45rem 0.6rem; border: none; border-radius: 8px; cursor: pointer;
    background: none; color: var(--text); font-weight: 600; font-size: 0.9rem;
  }
  .ch-result-item:hover { background: rgba(255,255,255,0.06); }
  .ch-friend-tag { font-size: 0.7rem; color: var(--brand-2); font-weight: 700; }
  .ch-row { display: flex; gap: 0.5rem; }
  .ch-input {
    flex: 1; min-width: 0; padding: 0.6rem 0.8rem; border-radius: 10px; border: 1px solid var(--border);
    background: var(--surface); color: var(--text); font-size: 0.9rem;
  }
  .ch-create { padding: 0.6rem 1rem; border: none; border-radius: 10px; cursor: pointer; font-weight: 700; color: #3a2a00; background: var(--brand-grad, linear-gradient(135deg,#fbbf24,#fde047)); }
  .ch-create:disabled { opacity: 0.6; }
  .ch-objective { font-size: 0.74rem; line-height: 1.4; color: var(--text-muted); margin: 0 0 10px; }
  .ch-objective strong { color: var(--brand-2); }
  .ch-toggle {
    display: flex; align-items: center; gap: 8px; width: 100%; margin: 2px 0 10px; padding: 0;
    background: none; border: none; cursor: pointer; color: var(--text-muted); font-size: 0.8rem; text-align: left; font-weight: 600;
  }
  .ch-toggle.on { color: var(--brand-2); }
  .ch-tog-box {
    width: 20px; height: 20px; flex-shrink: 0; border-radius: 6px; display: grid; place-items: center;
    border: 1px solid var(--border); background: var(--surface-2, rgba(255,255,255,0.04)); color: #3a2a00; font-size: 0.75rem; font-weight: 800;
  }
  .ch-toggle.on .ch-tog-box { background: var(--brand-grad, linear-gradient(135deg,#fbbf24,#fde047)); border-color: transparent; }
  .ch-cats { display: flex; flex-wrap: wrap; gap: 4px; justify-content: center; }
  .ch-cat { width: 34px; height: 34px; border-radius: 9px; cursor: pointer; font-size: 1rem; border: 1px solid var(--border); background: var(--surface); opacity: 0.5; transition: opacity 0.15s, border-color 0.15s; }
  .ch-cat.on { opacity: 1; border-color: rgba(253, 224, 71,0.55); background: rgba(253, 224, 71,0.08); }
  .ch-hint { font-size: 0.72rem; color: var(--text-faint); text-align: center; margin: 0; }
  .ch-field { flex: 1; display: flex; flex-direction: column; gap: 3px; text-align: left; min-width: 0; }
  .ch-field > span { font-size: 0.62rem; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-faint); font-weight: 600; }
  .ch-play.ghost { color: var(--brand-2); background: transparent; border: 1px solid rgba(253, 224, 71,0.4); }
  .ch-list { display: flex; flex-direction: column; gap: 0.5rem; max-height: 280px; overflow-y: auto; }
  .ch-item { display: flex; align-items: center; justify-content: space-between; gap: 0.6rem; padding: 0.7rem 0.8rem; background: var(--surface); border: 1px solid var(--border); border-radius: 12px; }
  .ch-info { display: flex; flex-direction: column; gap: 2px; text-align: left; min-width: 0; }
  .ch-vs { font-weight: 600; font-size: 0.9rem; }
  .ch-meta { font-size: 0.75rem; color: var(--text-faint); }
  .ch-play { padding: 0.45rem 0.9rem; border: none; border-radius: 999px; cursor: pointer; font-weight: 700; font-size: 0.85rem; color: #3a2a00; background: var(--brand-grad, linear-gradient(135deg,#fbbf24,#fde047)); }
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
  .cat-tile:hover { transform: translateY(-2px); border-color: rgba(253, 224, 71, 0.5); background: var(--surface-2, rgba(255, 255, 255, 0.07)); }
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
  .ma-section-label {
    text-align: left; font-size: 0.72rem; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase;
    color: var(--text-faint); margin: 1rem 0 0.1rem; padding-left: 0.2rem;
  }
  .ma-toggle { display: flex; align-items: center; gap: 0.5rem; }
  .ma-toggle-state {
    margin-left: auto; font-size: 0.72rem; font-weight: 800; color: var(--brand-2);
    background: rgba(253, 224, 71,0.12); border: 1px solid rgba(253, 224, 71,0.35);
    padding: 2px 8px; border-radius: 999px;
  }
  .ma-music-ctl {
    display: flex; align-items: center; gap: 0.6rem; margin: 0.4rem 0.2rem 0;
    padding: 0.3rem 0.2rem;
  }
  .mmc-ic { font-size: 0.95rem; }
  .mmc-slider { flex: 1; accent-color: #fbbf24; height: 4px; cursor: pointer; }
  .mmc-pct { font-size: 0.72rem; font-weight: 800; color: var(--text-muted); min-width: 34px; text-align: right; }
  .ma-track-select {
    width: 100%; margin-top: 0.5rem; padding: 0.6rem 0.8rem; border-radius: 12px;
    background: var(--surface); border: 1px solid var(--border); color: var(--text); font-weight: 600;
  }
  .ma-username { display: flex; align-items: center; justify-content: center; gap: 0.5rem; margin: 0.7rem 0 0.2rem; }
  .ma-uname { font-family: var(--font-display); font-weight: 800; font-size: 1.1rem; color: var(--brand-2); }
  .ma-edit { background: none; border: none; color: var(--text-faint); font-size: 0.8rem; cursor: pointer; text-decoration: underline; }
  .ma-input {
    padding: 0.5rem 0.8rem; border-radius: 10px; border: 1px solid var(--border);
    background: var(--surface); color: var(--text); font-size: 0.95rem; max-width: 180px;
  }
  .ma-save { padding: 0.5rem 1rem; border: none; border-radius: 10px; cursor: pointer; font-weight: 700; color: #3a2a00; background: var(--brand-grad, linear-gradient(135deg,#fbbf24,#fde047)); }
  .ma-msg { text-align: center; font-size: 0.82rem; color: #f87171; margin: 0.2rem 0 0; }

  /* First-run username gate */
  .username-gate { z-index: 3000; }
  .claim-card { text-align: center; max-width: 360px; }
  .claim-coin { display: block; margin: 0 auto 0.4rem; filter: drop-shadow(0 6px 20px rgba(251,191,36,0.4)); }
  .claim-sub { color: var(--text-muted); font-size: 0.88rem; line-height: 1.45; margin: 0.4rem 0 1.1rem; }
  .claim-row {
    display: flex; align-items: center; gap: 4px; padding: 0 0.9rem;
    background: var(--surface); border: 1px solid rgba(251,191,36,0.4); border-radius: 12px;
  }
  .claim-row:focus-within { border-color: #fde047; }
  .claim-at { font-family: var(--font-display); font-weight: 800; color: #fbbf24; font-size: 1.15rem; }
  .claim-input {
    flex: 1; min-width: 0; padding: 0.8rem 0.2rem; border: none; background: transparent;
    color: var(--text); font-size: 1.1rem; font-family: var(--font-display); font-weight: 700;
  }
  .claim-input:focus { outline: none; }
  .claim-msg { color: #f87171; font-size: 0.82rem; margin: 0.6rem 0 0; }
  .claim-btn {
    width: 100%; margin-top: 1rem; padding: 0.85rem; border: none; border-radius: 12px; cursor: pointer;
    font-weight: 800; font-size: 1rem; color: #3a2a00;
    background: linear-gradient(135deg, #fde047, #f59e0b);
  }
  .claim-btn:disabled { opacity: 0.5; cursor: default; }
  .claim-hint { color: var(--text-faint); font-size: 0.74rem; margin: 0.7rem 0 0; }

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
    40% { transform: scale(1.07); box-shadow: var(--shadow-md), 0 0 30px rgba(253, 224, 71,0.55); }
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

  /* Live "spent · profit" line (all modes) */
  .live-line { margin: 9px auto 0; text-align: center; font-size: 0.82rem; color: var(--text-muted); }
  .live-line b { display: inline-block; font-family: var(--font-display); font-weight: 800; font-size: 1.05rem; color: var(--brand-2); }
  .live-line b.lose { color: #fb7185; }
  /* Cash Game bounty panel: one hero number (what you keep) that ticks down as you spend */
  .bounty-panel { position: relative; display: flex; flex-direction: column; align-items: center; gap: 2px;
    width: 100%; max-width: 340px; margin: 0 auto; padding: 14px 18px; border-radius: var(--r-lg, 18px);
    border: 1px solid rgba(253, 224, 71, 0.4); background: linear-gradient(135deg, rgba(251, 191, 36, 0.14), rgba(251, 191, 36, 0.04));
    box-shadow: 0 0 22px rgba(251, 191, 36, 0.16); }
  .bounty-panel.loss { border-color: rgba(251,113,133,0.5); background: linear-gradient(135deg, rgba(251,113,133,0.13), rgba(251,113,133,0.03)); box-shadow: none; }
  .bp-label { font-size: 0.7rem; font-weight: 700; letter-spacing: 0.04em; text-transform: uppercase; color: var(--brand-2); }
  .bounty-panel.loss .bp-label { color: #fb7185; }
  .bp-amount { font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 2.3rem; line-height: 1.05; color: #4ade80;
    text-shadow: 0 0 18px rgba(52,211,153,0.5); font-variant-numeric: tabular-nums; transition: color 0.2s; }
  .bp-amount-btn { background: none; border: none; padding: 0; cursor: pointer; }
  .bounty-panel.loss .bp-amount { color: #fb7185; text-shadow: none; }
  /* lit gold bounty multiplier badge (left of the bounty) — ×1.0 today, boostable later */
  .bp-mult-badge { position: absolute; left: 12px; top: 50%; transform: translateY(-50%);
    font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 1.05rem; line-height: 1;
    padding: 5px 9px; border-radius: 9px; color: #3a2a00;
    background: linear-gradient(135deg, #fff1a8, #f6cd4d 45%, #e0a312);
    border: 1px solid rgba(180,130,15,0.95); cursor: pointer;
    box-shadow: 0 0 14px rgba(251,191,36,0.65), inset 0 1px 0 rgba(255,255,255,0.6), inset 0 -2px 3px rgba(120,80,0,0.35); }
  .bp-mult-badge:active { transform: translateY(-50%) scale(0.94); }
  /* 🏆 win streak — mirror of the multiplier badge, on the right of the bounty (boosts mult) */
  .bp-winstreak { position: absolute; right: 12px; top: 50%; transform: translateY(-50%); cursor: pointer;
    font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 0.95rem; line-height: 1;
    padding: 5px 9px; border-radius: 9px; color: #3a2a00;
    background: linear-gradient(135deg, #fff1a8, #f6cd4d 45%, #e0a312); border: 1px solid rgba(180,130,15,0.95);
    box-shadow: 0 0 12px rgba(251,191,36,0.5), inset 0 1px 0 rgba(255,255,255,0.5); }
  .bp-winstreak:active { transform: translateY(-50%) scale(0.94); }
  /* ℹ️ Daily explainer modal (multiplier / Solve-to-Earn breakdown) */
  .info-overlay { border: none; cursor: pointer; }
  .info-card { position: relative; width: 100%; max-width: 330px; cursor: default; text-align: center;
    background: var(--surface-strong, #141c28); border: 1px solid var(--border-strong, rgba(255,255,255,0.14));
    border-radius: 18px; padding: 22px 20px; box-shadow: 0 20px 60px rgba(0,0,0,0.6); }
  /* reusable red close ✕ (top-right) — returns to the game */
  .modal-x { position: absolute; top: 10px; right: 10px; z-index: 2; width: 30px; height: 30px; border-radius: 50%;
    display: grid; place-items: center; cursor: pointer; font-size: 0.8rem; font-weight: 900; color: #fff;
    background: linear-gradient(135deg, #fb5a5a, #c81e1e); border: 1px solid rgba(0,0,0,0.25); box-shadow: 0 2px 6px rgba(200,30,30,0.4); }
  .modal-x:hover { filter: brightness(1.08); }
  .modal-x:active { transform: scale(0.92); }
  /* 🎒 Bag button left of Solve (in-game) */
  .bag-fab { position: fixed; z-index: 998; bottom: calc(env(safe-area-inset-bottom, 0px) + 188px);
    right: calc(50% + 108px); width: 46px; height: 46px; border-radius: 12px; cursor: pointer; display: grid; place-items: center;
    font-size: 1.5rem; color: var(--text); background: var(--surface-strong, rgba(20,28,40,0.9));
    border: 1px solid rgba(253,224,71,0.5); backdrop-filter: blur(10px); box-shadow: 0 4px 12px rgba(0,0,0,0.4); }
  .bag-fab:active { transform: scale(0.93); }
  .bag-fab-badge { position: absolute; top: -5px; right: -5px; min-width: 18px; height: 18px; padding: 0 4px; border-radius: 999px;
    background: #ea580c; color: #fff; font-family: var(--font-display); font-weight: 800; font-size: 0.66rem; display: grid; place-items: center; }
  .bag-chip { width: 54px; height: 54px; padding: 0; border-radius: 50%; display: grid; place-items: center; }
  /* 🔐 Cash Game vault — sits to the left of Solve; absolute so Solve stays centered */
  .solve-vault { position: absolute; right: 100%; margin-right: 12px; top: 50%; transform: translateY(-50%);
    width: 50px; height: 50px; border-radius: 14px; display: grid; place-items: center; cursor: pointer;
    background: var(--surface-strong, rgba(20,28,40,0.9)); border: 1px solid rgba(253,224,71,0.5);
    backdrop-filter: blur(10px); box-shadow: 0 4px 12px rgba(0,0,0,0.4); transition: transform 0.16s var(--ease-spring); }
  .solve-vault:active { transform: translateY(-50%) scale(0.93); }
  .solve-vault img { width: 34px; height: 34px; object-fit: contain; }
  .solve-vault-badge { position: absolute; top: -6px; right: -6px; min-width: 18px; height: 18px; padding: 0 4px; border-radius: 999px;
    background: var(--brand-grad, linear-gradient(135deg,#fbbf24,#fde047)); color: #3a2a00;
    font-family: var(--font-display); font-weight: 800; font-size: 0.66rem; display: grid; place-items: center; }
  .vault-ic { width: 34px; height: 34px; object-fit: contain; }
  .vault-ic-sm { width: 46px; height: 46px; object-fit: contain; display: block; }
  .vault-ic-xs { width: 22px; height: 22px; object-fit: contain; vertical-align: -5px; }
  /* 🎒 Bag modal */
  .bag-modal { max-width: 360px; max-height: 84vh; overflow-y: auto; }
  .bag-use-h { font-family: var(--font-display); font-weight: 700; font-size: 0.78rem; text-transform: uppercase; letter-spacing: 0.04em;
    color: var(--brand-2); margin: 6px 0 8px; text-align: left; }
  .bag-use-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-bottom: 16px; }
  .bag-use { position: relative; display: flex; flex-direction: column; align-items: center; text-align: center; gap: 3px; cursor: pointer;
    padding: 0.9rem 0.5rem; border-radius: 14px; color: var(--text);
    background: linear-gradient(135deg, rgba(251,191,36,0.2), rgba(251,191,36,0.05)); border: 1px solid rgba(253,224,71,0.55); }
  .bag-use:active { transform: scale(0.96); }
  .bag-use:disabled { opacity: 0.5; cursor: default; }
  .bag-use.locked { background: var(--surface); border: 1px solid var(--border); filter: grayscale(0.7); }
  .bag-use.locked .bag-use-e { opacity: 0.55; }
  .bag-use.locked .bag-use-d { color: var(--text-faint); }
  .bag-msg { margin-top: 12px; padding: 10px 12px; border-radius: 11px; text-align: center; font-size: 0.82rem; line-height: 1.35;
    color: var(--text); background: rgba(251,191,36,0.14); border: 1px solid rgba(253,224,71,0.45); }
  .bag-use-e { font-size: 1.7rem; line-height: 1; }
  .bag-use-n { position: absolute; top: 7px; right: 9px; font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 0.78rem; color: #fde047; }
  .bag-use-name { font-family: var(--font-display); font-weight: 700; font-size: 0.86rem; }
  .bag-use-d { font-size: 0.72rem; color: var(--text-muted); line-height: 1.3; }
  .bag-inv { margin-bottom: 14px; }
  .bag-store { width: 100%; padding: 11px; border-radius: 12px; border: none; cursor: pointer;
    font-family: var(--font-display); font-weight: 800; color: #3a2a00; background: linear-gradient(135deg, #fde047, #f59e0b); }
  /* in-game bank modal */
  .bm-label { font-size: 0.72rem; text-transform: uppercase; letter-spacing: 0.08em; color: var(--text-faint); margin: 0 0 2px; }
  .bm-hist-h { font-family: var(--font-display); font-size: 0.78rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em;
    color: var(--brand-2); text-align: left; margin: 16px 0 6px; }
  .bm-ledger { display: flex; flex-direction: column; gap: 1px; background: var(--border); border-radius: 12px; overflow: hidden;
    max-height: 40vh; overflow-y: auto; margin-bottom: 14px; }
  .bm-row { display: flex; justify-content: space-between; gap: 10px; padding: 9px 11px; background: var(--surface); }
  .bm-reason { color: var(--text-muted); font-size: 0.84rem; text-align: left; }
  .bm-delta { font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 0.84rem; font-variant-numeric: tabular-nums; }
  .bm-delta.pos { color: #4ade80; } .bm-delta.neg { color: #fb7185; }
  .info-big { font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 2.6rem; line-height: 1; color: #fde047;
    text-shadow: 0 0 22px rgba(251,191,36,0.5); }
  .info-big.green { color: #4ade80; text-shadow: 0 0 22px rgba(74,222,128,0.45); }
  .info-title { font-family: var(--font-display); font-size: 1.15rem; margin: 8px 0 2px; }
  .info-sub { font-size: 0.84rem; color: var(--text-muted); margin: 0 0 14px; }
  .info-rows { display: flex; flex-direction: column; gap: 7px; text-align: left; margin-bottom: 14px; }
  .info-row { display: flex; justify-content: space-between; align-items: center; gap: 10px; font-size: 0.88rem; color: var(--text); }
  .info-row b { font-family: 'Orbitron', var(--font-display); font-variant-numeric: tabular-nums; }
  .info-row .pos { color: #4ade80; } .info-row .neg { color: #fb7185; } .info-row .green { color: #4ade80; }
  .info-row.total { border-top: 1px solid var(--border); padding-top: 8px; margin-top: 2px; font-weight: 700; }
  .info-note { font-size: 0.76rem; color: var(--text-faint); line-height: 1.45; margin: 0 0 16px; }
  .info-twist-do { font-family: var(--font-display); font-weight: 700; font-size: 1.02rem; color: #4ade80; margin: 0 0 14px; }
  /* 🎁 Twist announcement during the opening reveal */
  .twist-announce { display: flex; flex-direction: column; align-items: center; gap: 3px; text-align: center; margin: 2px auto 6px;
    animation: twistAnnounceIn 0.5s cubic-bezier(0.34,1.56,0.64,1); }
  .ta-label { font-size: 0.66rem; letter-spacing: 0.14em; text-transform: uppercase; color: var(--brand-2); }
  .ta-name { font-family: var(--font-display); font-weight: 800; font-size: 1.35rem; color: #fde047; text-shadow: 0 0 16px rgba(251,191,36,0.5); }
  .ta-blurb { font-size: 0.78rem; color: var(--text-muted); }
  @keyframes twistAnnounceIn { 0% { opacity: 0; transform: translateY(-10px) scale(0.9); } 100% { opacity: 1; transform: none; } }
  .info-note b { color: var(--brand-2); }
  .info-inline { background: none; border: none; padding: 0; color: var(--brand-2); font: inherit; font-weight: 700; text-decoration: underline; cursor: pointer; }
  .info-close { width: 100%; padding: 11px; border-radius: 12px; border: none; cursor: pointer;
    font-family: var(--font-display); font-weight: 800; color: #3a2a00; background: linear-gradient(135deg, #fde047, #f59e0b); }
  /* 🎰 Opening-reveal climax: bounty number pops + glows as it counts up */
  .bounty-panel.count-pop { animation: bountyGlow 1.1s ease-out; }
  .bounty-panel.count-pop .bp-amount { animation: bountyCount 1.1s cubic-bezier(0.34, 1.56, 0.64, 1); }
  @keyframes bountyGlow {
    0%   { box-shadow: 0 0 22px rgba(251,191,36,0.16); }
    35%  { box-shadow: 0 0 16px 4px rgba(74,222,128,0.6), 0 0 40px rgba(74,222,128,0.4); border-color: rgba(74,222,128,0.7); }
    100% { box-shadow: 0 0 22px rgba(251,191,36,0.16); }
  }
  @keyframes bountyCount {
    0%   { transform: scale(0.7); opacity: 0.5; }
    45%  { transform: scale(1.32); text-shadow: 0 0 30px rgba(74,222,128,0.95); }
    100% { transform: scale(1); }
  }
  /* floating -$X spend feedback by the green number */
  .spend-float { position: absolute; right: 16px; top: 8px; pointer-events: none;
    font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 1.05rem; color: #fb7185;
    text-shadow: 0 0 8px rgba(248,113,133,0.55); animation: spendFloat 1.1s ease-out forwards; }
  @keyframes spendFloat {
    0% { opacity: 0; transform: translateY(8px) scale(0.9); }
    16% { opacity: 1; transform: translateY(0) scale(1.06); }
    100% { opacity: 0; transform: translateY(-28px) scale(1); }
  }
  /* 💰 Top bankroll bar (very top, all modes) */
  .top-bank { width: 100%; max-width: 340px; margin: 0 auto 12px; padding: 9px 16px; border-radius: 14px;
    border: 1px solid rgba(253, 224, 71, 0.4); background: linear-gradient(135deg, rgba(251, 191, 36, 0.12), rgba(251, 191, 36, 0.03)); }
  /* solo bankroll = a centered gold chip below WordBank (matches the menu) — tap → /bank */
  .top-bank.solo { width: fit-content; max-width: none; margin: 0 auto 12px; padding: 7px 18px; text-align: center; cursor: pointer; }
  .top-bank.solo:active { transform: scale(0.97); }
  /* 💥 dramatic pop when the bankroll swings big (win payout / loss) */
  .top-bank.solo.pop-up { animation: bankPopUp 1.1s cubic-bezier(0.34, 1.56, 0.64, 1); }
  .top-bank.solo.pop-down { animation: bankPopDown 1.1s cubic-bezier(0.34, 1.56, 0.64, 1); }
  @keyframes bankPopUp {
    0% { transform: scale(1); border-color: rgba(253,224,71,0.4); }
    22% { transform: scale(1.4); border-color: rgba(74,222,128,0.9); box-shadow: 0 0 30px rgba(74,222,128,0.7); }
    55% { transform: scale(0.96); }
    100% { transform: scale(1); }
  }
  @keyframes bankPopDown {
    0% { transform: scale(1); }
    18% { transform: scale(0.8) translateX(-3px); border-color: rgba(251,113,133,0.9); box-shadow: 0 0 22px rgba(251,113,133,0.6); }
    36% { transform: scale(0.86) translateX(3px); }
    100% { transform: scale(1); }
  }
  .top-bank.solo.pop-up .tb-solo { animation: bankColorUp 1.1s ease-out; }
  .top-bank.solo.pop-down .tb-solo { animation: bankColorDown 1.1s ease-out; }
  @keyframes bankColorUp { 0%,100% { color: #fcd34d; } 25% { color: #4ade80; text-shadow: 0 0 24px rgba(74,222,128,0.95); } }
  @keyframes bankColorDown { 0%,100% { color: #fcd34d; } 25% { color: #fb7185; text-shadow: 0 0 20px rgba(251,113,133,0.9); } }
  .tb-solo { font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 1.55rem; color: #fcd34d; font-variant-numeric: tabular-nums; }
  .top-bank.tap { cursor: pointer; display: block; text-align: left;
    border-color: rgba(167, 139, 250, 0.55); border-style: dashed;
    background: linear-gradient(135deg, rgba(167, 139, 250, 0.13), rgba(167, 139, 250, 0.03)); }
  .top-bank.tap:disabled { cursor: default; opacity: 0.6; }
  .tb-row { display: flex; align-items: baseline; justify-content: space-between; gap: 10px; }
  .tb-cap { font-size: 0.72rem; font-weight: 700; letter-spacing: 0.04em; text-transform: uppercase; color: var(--brand-2); }
  .tb-amt { font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 1.7rem; line-height: 1; color: #fcd34d; font-variant-numeric: tabular-nums; }
  .tb-amt.cr { color: #c4b5fd; }
  .top-bank.tap .tb-cap { color: #c4b5fd; }
  .tb-bar { margin-top: 7px; height: 9px; border-radius: 999px; background: rgba(255,255,255,0.10); overflow: hidden; }
  .tb-fill { display: block; height: 100%; border-radius: 999px; background: linear-gradient(90deg, #fbbf24, #fde047); transition: width 0.35s ease; }
  .tb-sub { margin-top: 5px; font-size: 0.66rem; color: var(--text-faint); }
  /* Free Play play-money "Credits" — violet + dashed so it reads as not-real-Cash */
  .credits-panel { display: flex; flex-direction: column; align-items: center; gap: 1px;
    width: 100%; max-width: 320px; margin: 0 auto; padding: 13px 18px; border-radius: var(--r-lg, 18px);
    border: 1px dashed rgba(167, 139, 250, 0.55); background: linear-gradient(135deg, rgba(167, 139, 250, 0.13), rgba(167, 139, 250, 0.03)); }
  .cr-note { margin-top: 2px; font-size: 0.68rem; color: var(--text-faint); }
  .cr-cashout { margin-top: 5px; padding: 0.4rem 0.9rem; border-radius: 999px; cursor: pointer; font-weight: 800; font-size: 0.8rem;
    color: #04240f; background: linear-gradient(135deg, #6ee7b7, #34d399); border: none; }
  .cr-cashout:disabled { opacity: 0.5; cursor: default; }
  .cr-wallet { margin-top: 4px; font-size: 0.66rem; color: var(--text-faint); }
  /* 🏷️ Game-mode pill — centered under the wordmark, same for every mode */
  .mode-pill {
    display: inline-flex; align-items: center; gap: 6px; margin: -2px auto 10px;
    padding: 4px 14px; border-radius: 999px; white-space: nowrap; cursor: pointer;
    font-family: var(--font-display); font-weight: 800; font-size: 0.72rem;
    text-transform: uppercase; letter-spacing: 0.1em; color: var(--brand-2);
    background: rgba(253, 224, 71, 0.08); border: 1px solid rgba(253, 224, 71, 0.3);
    transition: transform 0.16s var(--ease-spring), background 0.2s, border-color 0.2s;
  }
  .mode-pill:hover { background: rgba(253, 224, 71, 0.14); border-color: rgba(253, 224, 71, 0.5); }
  .mode-pill:active { transform: scale(0.95); }
  .mp-emoji { font-size: 0.9rem; letter-spacing: 0; }
  .mp-info { font-size: 0.72rem; opacity: 0.6; letter-spacing: 0; }


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
    width: min(52vw, 180px);
    height: auto;
    margin: 2px auto 10px;
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


  .banner.win {
    font-family: var(--font-display);
    font-size: 1.6rem;
    font-weight: 700;
    letter-spacing: 0.02em;
    color: #3a2a00;
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
    /* Never taller than the screen — scroll internally so the close button and
       all controls stay reachable (was trapping users on tall forms). */
    max-height: calc(100dvh - 24px);
    overflow-y: auto;
    -webkit-overflow-scrolling: touch;
    overscroll-behavior: contain;
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
    color: #3a2a00;
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
  /* 🏆 Win banner */
  .win-h { font-family: var(--font-display); font-weight: 800; font-size: 1.7rem; margin: 0 0 2px;
    animation: winPunch 0.5s cubic-bezier(0.34,1.56,0.64,1); }
  @keyframes winPunch { 0% { opacity: 0; transform: scale(0.6); } 60% { transform: scale(1.12); } 100% { opacity: 1; transform: scale(1); } }
  .win-math { display: flex; flex-direction: column; gap: 7px; text-align: left; margin: 14px auto 12px; max-width: 300px;
    padding: 14px 16px; border-radius: 16px; border: 1px solid rgba(253,224,71,0.4);
    background: linear-gradient(135deg, rgba(251,191,36,0.12), rgba(251,191,36,0.04)); }
  .wm-row { display: flex; justify-content: space-between; align-items: baseline; gap: 10px; font-size: 0.92rem; color: var(--text); }
  .wm-row small { color: var(--text-faint); font-size: 0.72rem; }
  .wm-row b { font-family: 'Orbitron', var(--font-display); font-variant-numeric: tabular-nums; }
  .wm-row .neg { color: #fb7185; }
  .wm-row.total { border-top: 1px solid rgba(253,224,71,0.3); padding-top: 9px; margin-top: 2px; font-weight: 700; font-size: 1rem; }
  .wm-row .profit { font-size: 1.8rem; color: #4ade80; text-shadow: 0 0 18px rgba(74,222,128,0.5); }
  .win-twist { font-size: 0.82rem; color: var(--text-muted); margin: 0 0 12px; }
  .win-twist b { color: var(--brand-2); }
  .win-bank { display: flex; flex-direction: column; align-items: center; gap: 2px; margin: 0 0 10px; }
  .wb-label { font-size: 0.66rem; letter-spacing: 0.12em; text-transform: uppercase; color: var(--text-faint); }
  .wb-amount { font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 1.9rem; color: #fde047;
    text-shadow: 0 0 18px rgba(251,191,36,0.45); font-variant-numeric: tabular-nums; }
  .win-rank { font-size: 0.86rem; color: var(--text-muted); margin: 0 0 14px; }
  .win-rank b { color: #fde047; font-family: var(--font-display); }
  .win-menu { margin-top: 10px; background: none; border: none; color: var(--text-faint); font-size: 0.84rem; text-decoration: underline; cursor: pointer; }
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