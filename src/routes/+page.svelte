<script>
	import { onMount, onDestroy, tick } from 'svelte';
	import { browser } from '$app/environment';
	import { supabase } from '$lib/supabaseClient';
	import { get } from 'svelte/store';
	import { tweened } from 'svelte/motion';
	import { cubicOut } from 'svelte/easing';

	import {
		gameStore,
		fetchDailyGame,
		useDailyTwist,
		useDailyBoost,
		challengeTimeoutCheck,
		fetchMakeupGame,
		fetchClimbGame,
		startCashGame,
		cashOutClimb,
		climbAdvance,
		climbLeaveGame,
		climbSkipPuzzle,
		climbArmDoubleOrNothing,
		climbPowerup,
		startBlitz,
		endBlitz,
		blitzSkipPuzzle,
		startMatch,
		acceptAndPlayMatch,
		resumeMatch,
		matchTimeoutCheck,
		matchPowerup,
		matchSabotageOpponent,
		dailyFold,
		matchFold
	} from '$lib/stores/GameStore.js';
	import {
		getPowerups,
		getDailyAvailBoosts,
		getMyMatches,
		getMyGroups,
		getMatchDetail,
		getMatchDebuffs,
		getMatchOpponents,
		declineMatch
	} from '$lib/stores/statsStore.js';
	import { CATEGORIES } from '$lib/categories.js';
	import {
		user,
		userProfile,
		fetchUserProfile,
		ensureProfileExists
	} from '$lib/stores/userStore.js';
	import {
		getDailyStatus,
		getOpenGames,
		expireStaleDailies,
		getMyDailyRank,
		addFriend,
		searchUsers,
		getMyUsername,
		setUsername,
		getBank,
		takeLoan,
		getDailyBoard,
		getMatchMessages,
		sendMatchMessage,
		listFriendRequests,
		deleteMyAccount,
		getMyAvatar,
		getCashgameMeta,
		getBlitzMeta
	} from '$lib/stores/statsStore.js';
	import Avatar from '$lib/components/Avatar.svelte';
	import {
		unreadCount,
		refreshNotifications,
		inboxRequest,
		inboxTarget,
		markChallengeNotifRead
	} from '$lib/stores/notificationStore.js';
	import { track } from '$lib/analytics.js';
	import { modifierInfo } from '$lib/powerups.js';
	import {
		saveGameToLocalStorage,
		clearSavedGame,
		getSavedGameInfo
	} from '$lib/stores/localGameUtils.js';
	import { gameWasRestored } from '$lib/stores/GameStateFlags.js';
	import { soundEnabled, toggleSound, hapticsEnabled, toggleHaptics, fx } from '$lib/sound.js';
	import {
		startMusic,
		stopMusic,
		musicEnabled,
		musicVolume,
		setMusicVolume,
		toggleMusic,
		TRACKS,
		currentTrackId,
		selectTrack
	} from '$lib/music.js';
	import PinGate from '$lib/components/PinGate.svelte';
	import {
		pinLocked,
		hasPinFor,
		clearPin,
		markUnlocked,
		sessionIsUnlocked,
		markPinSkipped,
		pinSkipped,
		clearPinSkipped
	} from '$lib/pin.js';
	import { requirePin } from '$lib/pinConfirm.js';
	import { requireConfirm } from '$lib/confirm.js';
	import { goto } from '$app/navigation';

	import PhraseDisplay from '$lib/components/PhraseDisplay.svelte';
	import InventoryList from '$lib/components/InventoryList.svelte';
	import VaultReveal from '$lib/components/VaultReveal.svelte';
	import LoanPanel from '$lib/components/LoanPanel.svelte';
	import Keyboard from '$lib/components/Keyboard.svelte';
	import GameButtons from '$lib/components/GameButtons.svelte';
	import Auth from '$lib/components/Auth.svelte';
	import Tutorial from '$lib/components/Tutorial.svelte';
	import ObjectiveCard from '$lib/components/ObjectiveCard.svelte';
	import StandingStrip from '$lib/components/StandingStrip.svelte';
	import MatchDetailModal from '$lib/components/MatchDetailModal.svelte';
	import LeaderboardPanel from '$lib/components/LeaderboardPanel.svelte';
	import FriendsPanel from '$lib/components/FriendsPanel.svelte';
	import GroupsPanel from '$lib/components/GroupsPanel.svelte';

	export let data;

	// UI state
	let showTutorial = false;
	let showLaunchWelcome = false;
	let menuView = 'home'; // 'home' | 'play' | 'challenge' | 'progress'
	let showResultModal = false;
	let hasTriggeredModal = false;
	let hasInitialized = false;
	let sessionUid = ''; // current session user id (for the PIN gate)
	let pinNotSet = false; // logged in on this device with no PIN yet → prompt setup
	/** @type {string | null} */
	let initError = null; // 🔍 Diagnostic: what failed during init
	/** Show main menu (Daily / Cash Game / Leaderboard / My account) when true; game when false */
	let showMainMenu = false;
	/** When showing menu: can we show "Resume daily" / "Resume in-progress game"? */
	let savedGameInfo = /** @type {{ gameMode: string, gameState: string } | null} */ (null);
	/** When showing menu: has user already played daily today? */
	let menuDailyPlayed = false;
	/** Today's daily result for the menu indicator (won/lost + score). */
	let dailyStatus =
		/** @type {{ has_played_today: boolean, last_daily_won: boolean|null, daily_bankroll: number, bank: number, current_streak: number, streak_freezes: number, today_score: number, win_streak: number, daily_in_progress?: boolean } | null} */ (
			null
		);
	// 🎮 Live solo games from SERVER truth (daily/climb), newest first. The old
	// single localStorage save slot got overwritten whenever you played another mode, which
	// made a live Daily show as "complete + lost". openGames lets every mode resume independently.
	/** @type {{mode:string, updated_at:string}[]} */
	let openGames = [];
	async function refreshOpenGames() {
		const u = get(user);
		if (!u?.id) return;
		// Filter out any legacy Free Play rows the server may still return (mode retired in V2).
		try {
			openGames = (await getOpenGames()).filter((/** @type {any} */ g) => g.mode !== 'freeplay');
		} catch {
			/* keep last */
		}
	}
	// "In progress" must come from SERVER truth, not the clobberable localStorage slot.
	$: dailyInProgress =
		openGames.some((g) => g.mode === 'daily') || (dailyStatus?.daily_in_progress ?? false);
	$: dailyDone = menuDailyPlayed && !dailyInProgress;
	$: climbInProgress = openGames.some((g) => g.mode === 'climb');
	// 🔁 Resume: every in-progress game — solo modes AND challenges you've started.
	const RESUME_LABEL = /** @type {Record<string,string>} */ ({
		daily: 'Daily',
		climb: 'Cash Game'
	});
	$: resumables = [
		...openGames.map((/** @type {any} */ g) => ({
			key: 'solo-' + g.mode,
			label: RESUME_LABEL[g.mode] ?? 'Game',
			icon: /** @type {Record<string,string>} */ ({ daily: '📅', climb: '🎰' })[g.mode] ?? '▶',
			go: () => resumeSolo(g.mode)
		})),
		...(myMatches ?? [])
			.filter((/** @type {any} */ m) => m.status === 'open' && m.my_state === 'active')
			.map((/** @type {any} */ m) => ({
				key: 'match-' + m.id,
				label: m.group_name || (m.opponent ? '@' + m.opponent : 'Challenge'),
				icon: '⚔️',
				go: () => respondToMatch(m)
			}))
	];
	let showResumeMenu = false;
	function resumeSolo(/** @type {string} */ mode) {
		if (mode === 'daily') handleMenuDaily();
		else if (mode === 'climb') handleMenuClimb();
	}
	function onResume() {
		fx('tap');
		if (resumables.length === 1) resumables[0].go();
		else showResumeMenu = true;
	}
	/** Net Worth (bank − loan) — used for wager affordability; can go negative in debt. */
	let netWorth = /** @type {number|null} */ (null);
	/** Spendable Bank balance (never negative) — what the top chip shows. */
	let menuBank = /** @type {number|null} */ (null);
	let menuLoan = 0; // outstanding loan → drives the menu debt banner + chip badge
	async function refreshBank() {
		try {
			const gb = await getBank();
			netWorth = gb.net_worth;
			menuBank = gb.bank ?? 0;
			menuLoan = gb.loan ?? 0;
		} catch {
			/* non-fatal */
		}
	}

	// ✅ Load Supabase user profile and sync bankroll (creates profile if missing)
	/** @param {string} userId */
	async function loadUserProfile(userId) {
		try {
			const { data: profile, error } = await fetchUserProfile(userId);
			if (error || !profile) {
				console.warn('⚠️ Failed to load profile:', error?.message ?? error);
				// Auto-create profile for new users (no profile row yet)
				const createError = await ensureProfileExists(userId);
				if (createError) {
					console.error('❌ Failed to create profile:', createError);
					return null;
				}
				const { data: newProfile } = await fetchUserProfile(userId);
				if (!newProfile) return null;
				userProfile.set(newProfile);
				gameStore.update((state) => ({ ...state, bankroll: 2000 }));
				console.log('✅ Profile created. Bankroll: 2000');
				return newProfile;
			}

			userProfile.set(profile);
			gameStore.update((state) => ({
				...state,
				bankroll: profile.bank ?? 2000
			}));

			console.log('✅ Profile loaded. Bankroll:', profile.current_bankroll ?? profile.bank);
			return profile;
		} catch (err) {
			console.error('❌ Profile load error:', err instanceof Error ? err.message : String(err));
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
			if (!hasInitialized) {
				showMainMenu = true;
				hasInitialized = true;
			}
		}, 6000);
		try {
			const {
				data: { session },
				error
			} = await supabase.auth.getSession();
			if (!session || error) {
				initError =
					'No session (session: ' +
					(session ? 'yes' : 'no') +
					', error: ' +
					(error?.message || 'none') +
					')';
				console.warn('⛔', initError);
				return;
			}

			user.set(/** @type {{ id: string }} */ (session.user));
			const profile = await loadUserProfile(session.user.id);
			if (!profile) {
				initError =
					'Profile failed to load or create. Check Supabase profiles table and RLS policies.';
				console.warn('⛔', initError);
				showMainMenu = true;
				hasInitialized = true; // surface the menu instead of hanging
				return;
			}

			// Device PIN gate (approach A): if a PIN is set on this device, lock until it's
			// entered; otherwise mark that we should prompt to set one (after username).
			sessionUid = session.user.id;
			// Lock only on a cold open (close → reopen), not on in-app navigation back
			// to the menu — sessionIsUnlocked() persists the unlock for this app session.
			if (hasPinFor(sessionUid)) {
				if (!sessionIsUnlocked()) pinLocked.set(true);
			} else pinNotSet = !pinSkipped(sessionUid); // don't re-nag if they chose "Skip for now"

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
			expireStaleDailies()
				.catch(() => {})
				.finally(() => {
					getDailyStatus(session.user.id)
						.then((ds) => {
							dailyStatus = ds;
							menuDailyPlayed = ds.has_played_today;
						})
						.catch((e) => console.error('daily status:', e));
					refreshOpenGames();
				});
			refreshBank();
			refreshChallengeCount();
			// First-run username gate: prompt if this account hasn't claimed one yet.
			getMyUsername()
				.then((u) => {
					needsUsername = !u;
				})
				.catch(() => {});

			// Friend invite link: ?add=USERNAME → add them, then open the Friends board.
			try {
				const params = new URLSearchParams(window.location.search);
				const addName = params.get('add');
				if (addName) {
					const res = await addFriend(addName);
					if (res?.ok) {
						track('friend_add', { via: 'link' });
						goto('/leaderboard?mode=friends');
					}
				} else if (params.get('challenges')) {
					openChallenges();
				}
			} catch {
				/* non-fatal */
			}
		} catch (err) {
			initError = 'Init error: ' + (err instanceof Error ? err.message : String(err));
			console.error('❌', initError);
			showMainMenu = true;
			hasInitialized = true; // don't hang on a transient error
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
		if (gameMode === 'makeup') {
			fetchMakeupGame().then((ok) => {
				if (!ok) showMainMenu = true;
			});
		} else if (gameMode === 'climb') {
			fetchClimbGame().then((ok) => {
				if (!ok) showMainMenu = true;
			});
		} else if (gameMode === 'match' || gameMode === 'blitz') {
			// Matches (need the active id) + Blitz (a live timed run) aren't deep-link restorable.
			localStorage.setItem('gameMode', 'daily');
			showMainMenu = true;
		} else {
			fetchDailyGame().then((ok) => {
				if (!ok) initError = 'Daily puzzle failed to load.';
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
	// (Resume + challenge-invite + friend-request notifications now live as their own
	//  top-of-menu buttons — see resumables / challengeInvites / friendRequests.)
	function onPinUnlocked() {
		markUnlocked();
		pinLocked.set(false);
	}
	function onPinSet() {
		markUnlocked();
		clearPinSkipped();
		pinNotSet = false;
	}
	function onPinSkip() {
		markUnlocked();
		markPinSkipped(sessionUid);
		pinNotSet = false;
	} // remember the skip so it doesn't nag every open
	function onPinLogout() {
		clearPin();
		clearPinSkipped();
		pinLocked.set(false);
		pinNotSet = false;
		handleLogout();
	}
	// Background music: play continuously through the whole session — menu AND in-game
	// (it loops seamlessly across screens) — pausing only while locked / setting a PIN.
	$: if (browser) {
		if (loggedIn && hasInitialized && !showPinUnlock && !showPinSetup) startMusic();
		else stopMusic();
	}

	// ---- Daily result: shareable card ----
	// Each day is its own puzzle (one per date), so show the date — not a counter.
	// Pinned to UTC — the server schedules the Daily/Twist by UTC CURRENT_DATE, so the
	// label must match it (otherwise it disagrees near local midnight).
	$: todayLabel = browser
		? new Date().toLocaleDateString(undefined, {
				weekday: 'long',
				month: 'long',
				day: 'numeric',
				timeZone: 'UTC'
			})
		: '';

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
	$: dLive =
		($gameStore.gameMode === 'daily' || $gameStore.gameMode === 'makeup') &&
		$gameStore.gameState !== 'won' &&
		$gameStore.gameState !== 'lost'
			? $gameStore.dailyLive
			: null;
	$: isChallenge = $gameStore.gameMode === 'challenge';
	$: isMakeup = $gameStore.gameMode === 'makeup';
	// Auto-dismiss the Cash-earned toast after a few seconds.
	/** @type {ReturnType<typeof setTimeout>|undefined} */
	let _attTimer;
	$: if ($gameStore.cashToast) {
		clearTimeout(_attTimer);
		_attTimer = setTimeout(() => gameStore.update((s) => ({ ...s, cashToast: null })), 4000);
	}
	$: isClimb = $gameStore.gameMode === 'climb';
	$: climb = $gameStore.climbInfo; // { wallet, bounty, budget_left, solve_reward, spent, heat, must_guess, cheapest, last_gain, state, run_solves, wiped, pups_locked, equipped }
	// ⚡ Blitz — the live client clock counts down to blitzInfo.remaining_ms (server-authoritative);
	// each action resyncs it. At 0 we call endBlitz() once.
	$: isBlitz = $gameStore.gameMode === 'blitz';
	$: blitz = $gameStore.blitzInfo; // { remaining_ms, combo, solved, winnings, tier, buy_in, base, state }
	let blitzClockMs = 0;
	/** @type {ReturnType<typeof setInterval>|undefined} */
	let blitzTimer;
	let blitzEnding = false;
	// Resync the local clock whenever the server sends a fresh remaining_ms.
	$: if (isBlitz && blitz && blitz.state !== 'ended' && blitz.remaining_ms != null) {
		blitzClockMs = blitz.remaining_ms;
	}
	$: if (isBlitz && blitz && blitz.state !== 'ended') {
		if (!blitzTimer) {
			blitzEnding = false;
			blitzTimer = setInterval(() => {
				blitzClockMs = Math.max(0, blitzClockMs - 100);
				if (blitzClockMs <= 0 && !blitzEnding) {
					blitzEnding = true;
					clearInterval(blitzTimer);
					blitzTimer = undefined;
					endBlitz();
				}
			}, 100);
		}
	} else if (blitzTimer) {
		clearInterval(blitzTimer);
		blitzTimer = undefined;
	}
	onDestroy(() => {
		if (blitzTimer) clearInterval(blitzTimer);
	});
	$: blitzSec = Math.ceil(blitzClockMs / 1000);
	// 🏷️ Which mode you're in — a consistent pill under the wordmark on every game screen.
	$: modeLabel =
		{
			daily: { emoji: '📅', name: 'Daily' },
			climb: { emoji: '🎰', name: 'Cash Game' },
			blitz: { emoji: '⚡', name: 'Blitz' },
			makeup: { emoji: '📅', name: 'Make-up' },
			match: { emoji: '⚔️', name: 'Challenge' },
			challenge: { emoji: '⚔️', name: 'Challenge' }
		}[$gameStore.gameMode] ?? null;
	$: isMatch = $gameStore.gameMode === 'match';
	$: matchInfo = $gameStore.matchInfo; // { position, pack_size, total_score, last_score, done, mode, solved, spent, budget, wager, items_allowed, used_powerups, started_at, clock_seconds, combo }
	$: matchBlitz = isMatch && matchInfo?.mode === 'blitz' && !matchInfo?.done;
	$: matchCombo = ((matchInfo?.combo ?? 100) / 100).toFixed(2);
	let matchExpiredFired = false;
	// 💥 Double or Nothing (Cash Game): server exposes don_armed + don_available (heat ≥ ×1.5).
	$: donArmed = !!climb?.don_armed;
	$: donAvailable = !!climb?.don_available;
	// The doubled target payout (matches server: bounty ×2, then × heat, rounded).
	$: donTarget =
		isClimb && climb ? Math.round(((climb.bounty ?? 0) * 2 * (climb.heat ?? 100)) / 100) : 0;
	// Climb live (Accumulator): "Solve to Earn" = leftover budget × heat, banked into the
	// Wallet on solve. Server-computed as solve_reward.
	$: climbLive =
		isClimb && climb && climb.state === 'active'
			? {
					spent: climb.spent ?? 0,
					payout: climb.solve_reward ?? 0,
					net: climb.solve_reward ?? 0
				}
			: null;
	// Challenge live: Spent of your ante budget — lowest spend wins (standard only).
	$: matchLive =
		isMatch && matchInfo && !matchInfo.done && matchInfo.mode !== 'blitz'
			? { spent: matchInfo.spent ?? 0, budget: matchInfo.budget ?? 0 }
			: null;
	$: matchLeft = matchLive ? Math.max(0, (matchLive.budget ?? 0) - (matchLive.spent ?? 0)) : 0;
	// Unified money hero (Daily · Cash Game = net you keep; Challenge = ante left to spend).
	$: soloHero = climbLive
		? { net: climbLive.net }
		: dLive
			? { net: dLive.winnings }
			: matchLive
				? { net: matchLeft }
				: null;

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
	$: tweenNet.set(introBuilding ? 0 : soloHero ? Math.round(soloHero.net) : 0);

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
		gameStore.update((s) => ({
			...s,
			dailyIntroPlayed: tok,
			dailyIntroGo: (s.dailyIntroGo || 0) + 1
		}));
		introBuilding = true;
		tweenNet.set(0, { duration: 0 });
	}
	function onDailyIntroDone() {
		introBuilding = false; // releases the reactive above → bounty counts 0 → net
		introCountPop = true;
		setTimeout(() => {
			introCountPop = false;
		}, 1200);
	}
	// 🎬 Challenges auto-advance through a pack, so play the armed opening reveal on each
	// new puzzle (and on first entry). Resets between matches so a new pack re-triggers.
	let _lastMatchPos = -1;
	$: if (!isMatch) {
		_lastMatchPos = -1;
	} else if (matchInfo && (matchInfo.position ?? 1) !== _lastMatchPos && !showMainMenu) {
		_lastMatchPos = matchInfo.position ?? 1;
		tick().then(playDailyIntroIfArmed);
	}

	// 💰 Bank Account hub: a modal (not a route) so closing it returns to where you were.
	let showBank = false;
	/** @type {{ bank:number, net_worth:number, loan:number, loan_cap:number, in_the_red:boolean, ledger:any[] }|null} */
	let bankData = null;
	async function openBankModal() {
		fx('tap');
		showBank = true;
		try {
			bankData = await getBank();
		} catch {
			bankData = null;
		}
	}
	// After a borrow/repay inside the hub: refresh the sheet + the top Bank Account chip.
	async function reloadBank() {
		try {
			bankData = await getBank();
		} catch {
			/* keep last */
		}
		refreshBank();
	}
	const fmtCash = (/** @type {number} */ n) => '$' + Math.round(n ?? 0).toLocaleString();
	/** @param {string} reason */
	const bankReason = (reason) =>
		/** @type {Record<string,string>} */ ({
			daily_win: 'Daily reward',
			daily_reward: 'Daily reward',
			attendance: 'Daily attendance reward',
			makeup_reward: 'Make-up Daily',
			cashgame_buyin: 'Cash Game invest',
			cashgame_cashout: 'Cash Game deposit',
			climb_bounty: 'Cash Game credit',
			climb_letter: 'Cash Game letter',
			blitz_buyin: 'Blitz entry',
			blitz_payout: 'Blitz payout',
			challenge_payout: 'Challenge payout',
			cosmetic_buy: 'Store purchase',
			powerup_buy: 'Power-up purchase',
			loan_take: 'Loan received',
			loan_repay: 'Loan repayment',
			loan_skim: 'Loan auto-payment',
			wager_win: 'Won a wager',
			wager_stake: 'Wager staked',
			wager_refund: 'Wager refunded'
		})[reason] || reason;

	// 🔐 My Vault — owned inventory; use power-ups in-game (mode-eligible only).
	let showBag = false;
	let vaultVideo = false;
	/** @type {any[]} */ let vaultOwned = [];
	/** @type {Record<string,number>} */ let dailyAvailBoosts = {};
	let vaultMsg = '';
	/** @type {ReturnType<typeof setTimeout>|undefined} */ let _vaultMsgTimer;
	const BOOST_META = /** @type {Record<string,{emoji:string,blurb:string}>} */ ({
		bounty_boost: { emoji: '💥', blurb: 'Adds ×0.5 to your bounty' },
		jackpot_boost: { emoji: '💎', blurb: 'Adds ×1.0 to your bounty' }
	});
	async function loadVault() {
		try {
			vaultOwned = ((await getPowerups()).items ?? []).filter(
				(/** @type {any} */ i) => (i.owned ?? 0) > 0
			);
		} catch {
			vaultOwned = [];
		}
		if (!showMainMenu && $gameStore.gameMode === 'daily') {
			try {
				dailyAvailBoosts = await getDailyAvailBoosts();
			} catch {
				dailyAvailBoosts = {};
			}
		}
	}
	function openBag() {
		fx('tap');
		showBag = true;
		loadVault();
	}
	// From the main menu: require the device PIN (if set), play the safe-open reveal, then open.
	function onVaultVideoEnd() {
		if (vaultVideo) {
			vaultVideo = false;
			showBag = true;
		}
	}

	// In-game vault contents: every item, with the mode-eligible ones usable and the
	// rest grayed out (with a reason on tap).
	$: vaultItems =
		!showBag || showMainMenu
			? []
			: (() => {
					const out = [];
					if ($gameStore.gameMode === 'daily' && dailyMod && !$gameStore.twistUsed && gameActive) {
						out.push({
							id: 'twist',
							emoji: dailyMod.emoji,
							name: dailyMod.name,
							blurb: dailyMod.blurb,
							count: 1,
							usable: true,
							reason: ''
						});
					}
					for (const it of vaultOwned) {
						if (it.kind === 'daily') {
							const avail =
								$gameStore.gameMode === 'daily' && (dailyAvailBoosts[it.id] ?? 0) > 0 && gameActive;
							out.push({
								id: it.id,
								emoji: BOOST_META[it.id]?.emoji ?? '💥',
								name: it.name,
								blurb: BOOST_META[it.id]?.blurb ?? '',
								count: it.owned,
								usable: avail,
								reason: avail ? '' : 'Bought after you started — usable on your next puzzle.'
							});
						} else if (it.kind === 'climb') {
							// Self-buffs work in BOTH the Cash Game and Challenges.
							const climbUsed = (climb?.equipped ?? []).includes(it.id);
							const matchUsed = (matchInfo?.used_powerups ?? []).includes(it.id);
							const climbAvail =
								$gameStore.gameMode === 'climb' && gameActive && !climbUsed && (it.owned ?? 0) > 0;
							const matchAvail =
								isMatch &&
								!!matchInfo?.items_allowed &&
								gameActive &&
								!matchUsed &&
								(it.owned ?? 0) > 0;
							const avail = climbAvail || matchAvail;
							out.push({
								id: it.id,
								emoji: PUP_ICON[it.id] ?? '✨',
								name: it.name,
								blurb: avail ? 'Tap to use now' : '',
								count: it.owned,
								usable: avail,
								reason:
									climbUsed || matchUsed
										? 'Already used on this puzzle.'
										: $gameStore.gameMode === 'climb' || isMatch
											? ''
											: 'For the Cash Game or Challenges — not this mode.'
							});
						} else if (it.kind === 'sabotage') {
							const sabAvail =
								isMatch && !!matchInfo?.items_allowed && gameActive && (it.owned ?? 0) > 0;
							out.push({
								id: it.id,
								emoji: PUP_ICON[it.id] ?? '😈',
								name: it.name,
								blurb: sabAvail ? '😈 Tap to aim at an opponent' : '',
								count: it.owned,
								usable: sabAvail,
								kind: 'sabotage',
								reason: sabAvail ? '' : 'For Challenges — use it during a challenge.'
							});
						} else {
							out.push({
								id: it.id,
								emoji: PUP_ICON[it.id] ?? '✨',
								name: it.name,
								blurb: '',
								count: it.owned,
								usable: false,
								reason: 'For the Cash Game or Challenges — not this mode.'
							});
						}
					}
					return out;
				})();
	/** @param {any} item */
	function tapVaultItem(item) {
		if (item.usable) {
			useFromBag(item);
			return;
		}
		vaultMsg = item.reason || "This item can't be used for this puzzle.";
		clearTimeout(_vaultMsgTimer);
		_vaultMsgTimer = setTimeout(() => {
			vaultMsg = '';
		}, 2600);
	}
	/** @param {any} item */
	function useFromBag(item) {
		if (item?.id === 'twist') useTwist();
		else if (item?.id === 'bounty_boost' || item?.id === 'jackpot_boost') {
			useBoost(item.id);
			loadVault();
		} else if ($gameStore.gameMode === 'climb') {
			climbPowerup(item.id).then(() => {
				refreshClimbPups();
				loadVault();
			});
		} else if (isMatch && item?.kind === 'sabotage') {
			openSabotagePicker(item);
			return;
		} // keeps flow for the target step
		else if (isMatch) {
			matchPowerup(item.id).then(() => {
				refreshClimbPups();
				loadVault();
			});
		}
		showBag = false;
	}
	// 😈 Sabotage from the bag → pick a target (auto-applies vs a single opponent).
	/** @type {{ item:any, opponents:any[] }|null} */
	let sabPicker = null;
	/** @param {any} item */
	async function openSabotagePicker(item) {
		showBag = false;
		const id = matchInfo?.id;
		if (!id) return;
		const opps = (await getMatchOpponents(id)).filter((/** @type {any} */ o) => !o.done);
		if (opps.length === 0) {
			vaultMsg = 'No opponents left to hit.';
			return;
		}
		if (opps.length === 1) {
			await matchSabotageOpponent(opps[0].id, item.id);
			await refreshClimbPups();
			return;
		}
		sabPicker = { item, opponents: opps };
	}
	/** @param {string} targetId */
	async function applySabotage(targetId) {
		if (!sabPicker) return;
		const item = sabPicker.item;
		sabPicker = null;
		await matchSabotageOpponent(targetId, item.id);
		await refreshClimbPups();
	}

	// ℹ️ Daily explainers: ×N badge, Solve-to-Earn, 🏆 streak, or today's Twist.
	/** @type {'mult'|'bounty'|'streak'|'twist'|null} */
	let dailyInfo = null;
	$: dlMult = Number($gameStore.dailyLive?.mult ?? $gameStore.bountyMult ?? 1);
	$: dlRemaining = $gameStore.dailyLive?.remaining ?? 0; // Prize budget left
	$: dlWinnings = $gameStore.dailyLive?.winnings ?? Math.round(dlRemaining * dlMult); // banked if you solve now
	$: dlWinStreak = dailyStatus?.win_streak ?? 0;
	$: dlStreakBonus = Math.min(0.1 * dlWinStreak, 0.5);
	$: dlWrong = $gameStore.wrongGuesses ?? 0;
	$: dlPenalty = Math.min(0.2 * dlWrong, Math.max(0, dlMult - 1)); // shown penalty, can't push below ×1.0 floor
	$: dlBoost = Math.max(0, Math.round((dlMult - 1 - dlStreakBonus + dlPenalty) * 10) / 10);
	const fmtMult = (/** @type {number} */ n) => '×' + n.toFixed(1);
	let _prevBank = /** @type {number|null} */ (null);
	let _floatId = 0;
	/** @type {{id:number,text:string}[]} */
	let spendFloaters = [];
	$: trackSpend($gameStore.bankroll, $gameStore.gameMode, showMainMenu);
	/** @param {number|null|undefined} b @param {string} mode @param {boolean} onMenu */
	function trackSpend(b, mode, onMenu) {
		if (
			browser &&
			!onMenu &&
			_prevBank != null &&
			b != null &&
			b < _prevBank &&
			['daily', 'makeup', 'climb'].includes(mode)
		) {
			const amt = _prevBank - b;
			if (amt > 0 && amt <= 300) {
				const id = ++_floatId;
				spendFloaters = [...spendFloaters, { id, text: '−$' + amt.toLocaleString() }];
				setTimeout(() => {
					spendFloaters = spendFloaters.filter((f) => f.id !== id);
				}, 1100);
			}
		}
		_prevBank = b ?? null;
	}

	// 💥 Dramatic bank pop on a big swing (win payout / big change).
	let bankFlash = '';
	let _bankFxPrev = /** @type {number|null} */ (null);
	/** @type {ReturnType<typeof setTimeout>|undefined} */
	let _bankFxTimer;
	$: bankFx($gameStore.bankroll, showMainMenu);
	/** @param {number|null|undefined} b @param {boolean} onMenu */
	function bankFx(b, onMenu) {
		if (!browser || b == null) {
			_bankFxPrev = b ?? _bankFxPrev;
			return;
		}
		if (!onMenu && _bankFxPrev != null && Math.abs(b - _bankFxPrev) >= 150) {
			bankFlash = b > _bankFxPrev ? 'up' : 'down';
			clearTimeout(_bankFxTimer);
			_bankFxTimer = setTimeout(() => {
				bankFlash = '';
			}, 1100);
		}
		_bankFxPrev = b;
	}

	// ── Fold + broke-timer (Daily + Challenges) ──────────────────────────────
	// You're "broke" when you can't afford the cheapest still-buyable letter →
	// a 60s clock starts; guess it or you auto-Fold (lose the puzzle).
	// Mirror of the server-authoritative public.letter_cost() (economy v3.2: −25%, cheapest $20).
	const LETTER_COSTS = {
		Q: 20,
		W: 40,
		E: 100,
		R: 90,
		T: 90,
		Y: 50,
		U: 60,
		I: 80,
		O: 70,
		P: 60,
		A: 100,
		S: 90,
		D: 60,
		F: 50,
		G: 50,
		H: 50,
		J: 20,
		K: 40,
		L: 60,
		Z: 30,
		X: 30,
		C: 60,
		V: 40,
		B: 50,
		N: 80,
		M: 50
	};
	// foldMode = modes with a "Give up" button (Daily + Challenges).
	$: foldMode = $gameStore.gameMode === 'daily' || $gameStore.gameMode === 'match';
	// brokeMode = modes with the out-of-Cash auto-fold CLOCK. The Daily has NO timer —
	// guesses are free + unlimited, so being broke isn't a dead end; you solve it or you
	// don't (an unfinished Daily expires as a loss at day's end). Only live challenges,
	// where stalling stalls a real opponent, keep the broke clock.
	$: brokeMode = $gameStore.gameMode === 'match';
	$: gameActive = $gameStore.gameState !== 'won' && $gameStore.gameState !== 'lost';
	$: isBroke = (() => {
		// Only while actively on a game screen — never on the menu.
		if (!brokeMode || !gameActive || showMainMenu) return false;
		const mod = $gameStore.modifier,
			discount = mod === 'discount',
			vowelHalf = mod === 'vowel_vision';
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
	let brokeDeadline = 0,
		brokeLeft = 0,
		brokeFiring = false;
	/** @type {ReturnType<typeof setInterval>|null} */
	let brokeTimer = null;
	$: if (browser) manageBrokeTimer(isBroke);
	/** @param {boolean} broke */
	function manageBrokeTimer(broke) {
		if (broke && !brokeTimer) {
			brokeDeadline = Date.now() + 60000;
			brokeLeft = 60;
			brokeTimer = setInterval(() => {
				brokeLeft = Math.max(0, Math.ceil((brokeDeadline - Date.now()) / 1000));
				if (brokeLeft <= 0) {
					if (brokeTimer) clearInterval(brokeTimer);
					brokeTimer = null;
					doFold(true);
				}
			}, 250);
		} else if (!broke && brokeTimer) {
			if (brokeTimer) clearInterval(brokeTimer);
			brokeTimer = null;
		}
	}
	/** @param {boolean} auto */
	async function doFold(auto = false) {
		if (brokeFiring) return;
		brokeFiring = true;
		if (brokeTimer) {
			if (brokeTimer) clearInterval(brokeTimer);
			brokeTimer = null;
		}
		try {
			fx(auto ? 'bust' : 'tap');
			if ($gameStore.gameMode === 'daily') await dailyFold();
			else if ($gameStore.gameMode === 'match') await matchFold();
			else if ($gameStore.gameMode === 'climb') {
				await climbSkipPuzzle();
				await tick();
				playDailyIntroIfArmed();
			} // fresh puzzle; heat resets; replay the dramatic build
		} finally {
			brokeFiring = false;
		}
	}
	// Give-up confirm layer (in-app, not window.confirm).
	let showGiveUp = false;
	function confirmFold() {
		fx('tap');
		showGiveUp = true;
	}
	function cancelGiveUp() {
		fx('tap');
		showGiveUp = false;
	}
	function doGiveUp() {
		showGiveUp = false;
		doFold(false);
	}

	// 💥 Double or Nothing confirm layer (Cash Game). Solve → ×2; get stuck → forfeit.
	let showDon = false;
	let donBusy = false;
	function openDon() {
		fx('tap');
		showDon = true;
	}
	function cancelDon() {
		fx('tap');
		showDon = false;
	}
	async function armDon() {
		if (donBusy) return;
		donBusy = true;
		try {
			fx('tap');
			await climbArmDoubleOrNothing();
		} finally {
			donBusy = false;
			showDon = false;
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
	// Cash Game "Yield" = heat expressed as a % gain (heat ×1.3 → +30%).
	$: climbYield = Math.round((climb?.heat ?? 100) - 100);
	// Heat IS the Cash Game win streak: each solve +0.1× (cap ×2.0), reset to ×1.0 when stuck.
	$: climbStreak = Math.max(0, Math.round(((climb?.heat ?? 100) - 100) / 10));
	// 🔥 The run: solves + cumulative profit since heat last reset (run_profit can be negative early).
	$: climbRun =
		isClimb && climb
			? {
					solves: climb.run_solves ?? 0,
					profit: climb.run_profit ?? 0,
					best: climb.best_run_profit ?? 0
				}
			: null;
	$: climbRunIsBest = climbRun != null && climbRun.profit > 0 && climbRun.profit >= climbRun.best;
	// Owned, not-yet-used climb buffs — drives the vault badge by the Solve button.
	$: usableClimbPups = isClimb
		? selfPups.filter(
				(/** @type {any} */ i) => (i.owned ?? 0) > 0 && !(climb?.equipped ?? []).includes(i.id)
			).length
		: 0;
	$: usableMatchPups =
		isMatch && matchInfo?.items_allowed
			? selfPups.filter(
					(/** @type {any} */ i) =>
						(i.owned ?? 0) > 0 && !(matchInfo?.used_powerups ?? []).includes(i.id)
				).length
			: 0;
	/** @type {'heat'|'earn'|'streak'|null} ℹ️ Cash Game explainers (mirror of dailyInfo). */
	let climbInfo = null;
	$: dr = $gameStore.dailyResult; // { score, clean, no_vowels, first_try, no_reveals }
	/** @type {{rank:number, total:number}|null} */
	let dailyPlacement = null;
	$: if (showResultModal && isDailyResult && resultWon && dr && dailyPlacement === null)
		loadDailyPlacement();
	async function loadDailyPlacement() {
		dailyPlacement = { rank: 0, total: 0 }; // guard against re-fire
		try {
			const board = await getDailyBoard('friends');
			const me = board.find((/** @type {any} */ r) => r.is_me);
			dailyPlacement = { rank: me?.rank ?? 0, total: board.length };
		} catch {
			dailyPlacement = { rank: 0, total: 0 };
		}
	}
	/** @type {any[]} */
	let climbPups = [];
	const PUP_ICON = /** @type {Record<string,string>} */ ({
		free_reveal: '🔍',
		half_off: '🏷️',
		vowel_vision: '👁️',
		extra_hint: '💡',
		reveal_word: '📖',
		free_vowel: '🅰️',
		last_letters: '🔚',
		sabotage_tax: '💸',
		sabotage_fog: '🌫️',
		sabotage_toll: '🚧',
		sabotage_vowel_block: '🚫',
		sabotage_lock: '🔒'
	});
	const DEBUFF_LABEL = /** @type {Record<string,string>} */ ({
		tax: '💸 Taxed (letters +50%)',
		fog: '🌫️ Fogged (clue hidden)',
		toll: '🚧 Tolled (next letter 3×)',
		vowel_block: '🚫 Vowel-blocked (vowels 3×)'
	});
	const DEBUFF_DESC = /** @type {Record<string,string>} */ ({
		tax: 'Every letter you buy costs +50% while this is active.',
		fog: 'Your clue is hidden — you have to solve it blind.',
		toll: 'Your next letter purchase costs 3×, then it clears.',
		vowel_block: 'Vowels cost 3× while this is active.'
	});
	// 💥 Tappable debuff banner → what each sabotage does + who hit you.
	/** @type {{effect:string, by:string|null}[]|null} */
	let debuffModal = null;
	async function openDebuffInfo() {
		fx('tap');
		const id = matchInfo?.id;
		if (!id) return;
		debuffModal = await getMatchDebuffs(id);
	}
	// ℹ️ Tappable "Left to Spend" hero → explains the challenge ante.
	let showAnteInfo = false;
	async function refreshClimbPups() {
		try {
			const r = await getPowerups();
			climbPups = r.items ?? [];
		} catch {
			/* non-fatal */
		}
	}
	$: selfPups = climbPups.filter((/** @type {any} */ i) => i.kind === 'climb'); // buffs (use on yourself)

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
			tick().then(() => {
				if (matchChatScroll) matchChatScroll.scrollTop = matchChatScroll.scrollHeight;
			});
		} else if (matchChatSeenId === null) {
			// First sync: treat the existing backlog as already seen (don't nag).
			if (newest) matchChatSeenId = newest.id;
		} else if (newest && !newest.is_me && newest.id !== matchChatSeenId) {
			// Light up only for a NEW message from someone else you haven't opened.
			matchChatUnread = true;
		}
	}
	function teardownMatchChat() {
		if (matchChannel) {
			supabase.removeChannel(matchChannel);
			matchChannel = null;
		}
		clearInterval(matchChatPoll);
		matchChatId = null;
		matchMessages = [];
		matchChatOpen = false;
		matchChatUnread = false;
		matchChatSeenId = null;
	}
	/** @param {string|null|undefined} id */
	function syncMatchChat(id) {
		if (id === matchChatId) return;
		teardownMatchChat();
		if (!id) return;
		matchChatId = id;
		loadMatchMsgs();
		matchChannel = supabase
			.channel(`match:${id}`)
			.on(
				'postgres_changes',
				{ event: 'INSERT', schema: 'public', table: 'match_messages', filter: `match_id=eq.${id}` },
				loadMatchMsgs
			)
			.subscribe();
		matchChatPoll = setInterval(loadMatchMsgs, 20000);
	}
	$: syncMatchChat(isMatch && !showMainMenu ? matchInfo?.id : null);
	function openMatchChat() {
		matchChatOpen = true;
		matchChatUnread = false;
		loadMatchMsgs();
	}
	async function sendMatchChat() {
		const body = matchChatInput.trim();
		if (!body || matchChatBusy || !matchChatId) return;
		matchChatBusy = true;
		const res = await sendMatchMessage(matchChatId, body);
		matchChatBusy = false;
		if (res.ok) {
			matchChatInput = '';
			await loadMatchMsgs();
		}
	}
	onDestroy(teardownMatchChat);

	$: makeupLabel = (() => {
		const d = $gameStore.makeupDate;
		if (!d) return '';
		const dt = new Date(d + 'T00:00:00');
		return dt.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
	})();
	$: chScore = $gameStore.challengeInfo?.score ?? Math.floor($gameStore.bankroll || 0);
	$: resultBankroll = Math.max(0, Math.floor($gameStore.bankroll || 0));
	$: resultMedal = medalFor(resultBankroll, resultWon);

	// ⏱️ Pressure-mode challenge clock (server-authoritative; this just displays + triggers the check)
	let pressureNow = browser ? Date.now() : 0;
	/** @type {ReturnType<typeof setInterval>|undefined} */
	let pressureTimer;
	let pressureFired = false;
	$: chInfo = $gameStore.gameMode === 'challenge' ? $gameStore.challengeInfo : null;
	$: isPressure = chInfo?.mode === 'pressure';
	$: pressureActive =
		isPressure && $gameStore.gameState !== 'won' && $gameStore.gameState !== 'lost';
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
			setTimeout(() => {
				pressureFired = false;
			}, 1500);
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
		return `🏦 WordBank\n${resultMedal.emoji} ${br} banked\n${link}`;
	}
	async function handleShare() {
		const text = buildShareText();
		try {
			if (typeof navigator !== 'undefined' && navigator.share) {
				await navigator.share({ text });
				return;
			}
		} catch {
			/* user cancelled native share */
		}
		try {
			await navigator.clipboard.writeText(text);
			shareCopied = true;
			setTimeout(() => {
				shareCopied = false;
			}, 1800);
		} catch {
			/* clipboard unavailable */
		}
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
		['click', 'mousedown', 'touchstart'].forEach((event) =>
			document.addEventListener(event, removeButtonFocus, true)
		);
		pressureTimer = setInterval(() => {
			pressureNow = Date.now();
		}, 250);
	});
	onDestroy(() => {
		clearInterval(pressureTimer);
		if (brokeTimer) if (brokeTimer) clearInterval(brokeTimer);
	});

	// Bump this key whenever the tutorial gains new content — it re-shows for
	// everyone on next login (v3 = persistent Cash, spend-the-least, attendance, no loans).
	const TUTORIAL_KEY = 'wb_tutorial_v3';
	// First-run guided tutorial: show once a signed-in user is past the username/PIN
	// gates and on the menu (not while those full-screen gates are up).
	$: if (
		browser &&
		loggedIn &&
		hasInitialized &&
		!needsUsername &&
		!showPinUnlock &&
		!showPinSetup &&
		localStorage.getItem(TUTORIAL_KEY) !== 'true'
	) {
		showTutorial = true;
	}

	// One-time launch welcome for returning players (we reset everyone to a fresh
	// Day-1 start). New users get the tutorial instead (it sets this key on dismiss).
	const LAUNCH_KEY = 'wb_launch_welcome_v1';
	$: if (
		browser &&
		loggedIn &&
		hasInitialized &&
		showMainMenu &&
		!needsUsername &&
		!showPinUnlock &&
		!showPinSetup &&
		!showTutorial &&
		localStorage.getItem(TUTORIAL_KEY) === 'true' &&
		localStorage.getItem(LAUNCH_KEY) !== '1'
	) {
		showLaunchWelcome = true;
	}
	function dismissLaunchWelcome() {
		showLaunchWelcome = false;
		if (browser) localStorage.setItem(LAUNCH_KEY, '1');
	}

	// Deep link from a public profile's "⚔️ Challenge" button: /?challenge=<username>
	let challengeDeepLinkDone = false;
	$: if (
		browser &&
		loggedIn &&
		hasInitialized &&
		!needsUsername &&
		!showPinUnlock &&
		!showPinSetup &&
		!challengeDeepLinkDone
	) {
		challengeDeepLinkDone = true;
		try {
			const params = new URLSearchParams(window.location.search);
			const ch = params.get('challenge');
			if (ch) {
				newChallenge().then(() => {
					mbTarget = 'friend';
					mbOpponent = ch;
				});
				params.delete('challenge');
			}
			// Settings/account deep link from the Profile page's ⚙️ gear (/?account=1)
			if (params.get('account')) {
				handleMenuMyAccount();
				params.delete('account');
			}
			// Friends & Groups deep link (Profile 👥+ button → /?people=1)
			if (params.get('people')) {
				openCommunity('people');
				params.delete('people');
			}
			const qs = params.toString();
			window.history.replaceState({}, '', window.location.pathname + (qs ? '?' + qs : ''));
		} catch {
			/* non-fatal */
		}
	}
	// A tapped challenge toast / deep-link opens Community ▸ Challenges (people fallback).
	let _inboxSeen = 0;
	$: if (
		browser &&
		$inboxRequest > _inboxSeen &&
		loggedIn &&
		hasInitialized &&
		!needsUsername &&
		!showPinUnlock &&
		!showPinSetup
	) {
		_inboxSeen = $inboxRequest;
		if ($inboxTarget === 'people') {
			openCommunity('people');
			peopleTab = 'friends';
		} else openCommunity('challenges');
	}
	function dismissTutorial() {
		showTutorial = false;
		// New users just onboarded — they don't also need the launch welcome.
		if (browser) {
			localStorage.setItem(TUTORIAL_KEY, 'true');
			localStorage.setItem(LAUNCH_KEY, '1');
		}
	}

	// ===== Pre-game "How to win" objective card =====
	// Shows the objective the moment a mode starts. Solo modes show once (per mode,
	// localStorage); challenges show every entry. One reactive latch detects the
	// menu→game transition so we don't have to wire every scattered start site.
	/** @type {{ mode: string, ctx: any } | null} */
	let objective = null;
	let _wasMenu = true;
	const SOLO_MODES = ['daily', 'climb', 'makeup'];

	function buildObjectiveCtx(/** @type {string} */ mode) {
		if (mode !== 'match') return {};
		const mi = get(gameStore).matchInfo || {};
		const opps = mi.opponents ?? [];
		return {
			opponent: opps.length === 1 ? opps[0]?.name : undefined,
			wager: mi.wager,
			packSize: mi.pack_size,
			fieldSize: opps.length + 1
		};
	}
	// once-seen localStorage key: per-mode for solo modes, per-match for challenges
	// (so the "How to win" card shows on the FIRST entry only, never on resume).
	function objSeenKey(/** @type {string} */ mode) {
		if (mode === 'match') {
			const id = get(gameStore).matchInfo?.id;
			return id ? 'wb_obj_match_' + id : null;
		}
		return SOLO_MODES.includes(mode) ? 'wb_obj_' + mode : null;
	}
	/** @param {boolean} [forced] re-opened via the board ⓘ button — bypass the once-seen gate */
	function showObjectiveFor(/** @type {string} */ mode, forced = false) {
		if (!mode || showTutorial) return;
		const key = objSeenKey(mode);
		if (!forced && key && browser && localStorage.getItem(key) === '1') return;
		objective = { mode, ctx: buildObjectiveCtx(mode) };
	}
	function dismissObjective() {
		if (objective && browser) {
			const key = objSeenKey(objective.mode);
			if (key) localStorage.setItem(key, '1');
		}
		objective = null;
		tick().then(playDailyIntroIfArmed); // board is now visible → play the opening reveal
	}

	// Detect entering a game from the menu (latch flips once per entry).
	$: if (
		browser &&
		loggedIn &&
		hasInitialized &&
		!needsUsername &&
		!showPinUnlock &&
		!showPinSetup
	) {
		if (showMainMenu) {
			_wasMenu = true;
		} else if (
			_wasMenu &&
			$gameStore.gameMode &&
			$gameStore.gameState !== 'won' &&
			$gameStore.gameState !== 'lost'
		) {
			_wasMenu = false;
			showObjectiveFor($gameStore.gameMode);
			refreshBank(); // keep the on-board "Cash" fresh (e.g. a challenge buy-in was just paid)
		}
	}

	// Keep the menu pinned to the top. The tall menu + the login→menu height change can
	// leave the window scrolled (browser scroll-anchoring), which then read as a "jump"
	// when navigating to /profile. Reset to top whenever the menu becomes visible.
	let _menuPinned = false;
	$: if (browser) {
		if (showMainMenu) {
			if (!_menuPinned) {
				_menuPinned = true;
				tick().then(() => window.scrollTo(0, 0));
			}
		} else _menuPinned = false;
	}

	/** @param {Event} e */
	const removeButtonFocus = (e) => {
		if (e.target && /** @type {HTMLElement} */ (e.target).tagName === 'BUTTON')
			/** @type {HTMLButtonElement} */ (e.target).blur();
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

	// 🔑 PIN: show "Change PIN" only when one is set; require the CURRENT PIN first.
	$: hasPin = browser && $user?.id ? hasPinFor($user.id) : false;
	async function changePin() {
		fx('tap');
		try {
			await requirePin('Enter your current PIN to set a new one');
		} catch {
			return;
		}
		showMyAccount = false;
		clearPin();
		clearPinSkipped();
		pinNotSet = true; // → the create-new-PIN screen
	}
	// 🔓 Forgot PIN (from Settings) — verify by email + password, then set a new PIN.
	async function forgotPin() {
		if (
			!(await requireConfirm({
				title: 'Reset PIN?',
				message: 'You’ll sign back in with your email & password, then set a new PIN.',
				confirmText: 'Reset PIN',
				danger: true
			}))
		)
			return;
		showMyAccount = false;
		clearPin();
		clearPinSkipped();
		handleLogout();
	}

	// 🗑️ Permanent account deletion (App Store 5.1.1(v)) — requires typing DELETE.
	const APP_VERSION = '1.0.0';
	const SUPPORT_EMAIL = 'charlieforeman77@gmail.com';
	let showDeleteConfirm = false;
	let deleteBusy = false;
	let deleteInput = '';
	$: deleteArmed = deleteInput.trim().toUpperCase() === 'DELETE';
	async function confirmDeleteAccount() {
		if (!deleteArmed || deleteBusy) return;
		deleteBusy = true;
		const { ok } = await deleteMyAccount();
		if (!ok) {
			deleteBusy = false;
			maMsg = 'Could not delete your account — try again.';
			return;
		}
		clearSavedGame();
		clearPin();
		gameWasRestored.set(false);
		await supabase.auth.signOut().catch(() => {});
		user.set(null);
		location.reload();
	}

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
		const inProgress =
			(dailyStatus?.daily_in_progress ?? false) ||
			(savedGameInfo?.gameMode === 'daily' &&
				savedGameInfo?.gameState !== 'won' &&
				savedGameInfo?.gameState !== 'lost');
		if (dailyStatus?.has_played_today && !inProgress) {
			showStreakMessage = true; // already solved today → come-back summary
			return;
		}
		// Today's Twist is auto-given on the board — no pre-game popup. Just play.
		await startDaily();
	}

	// ⚡ Power-up hotbar feed. Daily: today's Twist (mode allows only the Twist).
	// Cash Game / Challenges will feed mode-eligible inventory power-ups here later.
	/** @param {CustomEvent<any>} e */

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
		dailyBoostBusy = false;
	}
	async function startDaily() {
		localStorage.setItem('gameMode', 'daily');
		const ok = await fetchDailyGame();
		if (ok) {
			hasInitialized = true;
			showMainMenu = false;
			// refresh streaks so the 📅 attendance chip includes today's check-in
			const uid = get(user)?.id;
			if (uid)
				getDailyStatus(uid)
					.then((s) => {
						dailyStatus = s;
					})
					.catch(() => {});
			// If the "How to win" card is suppressed (already seen), the board is now
			// visible — play the opening reveal once reactives settle. If the card DOES
			// show, this no-ops (objective set) and the reveal fires on its dismiss.
			await tick();
			playDailyIntroIfArmed();
		} else {
			initError = 'Daily puzzle failed to load.';
		}
	}

	// Today's shared Daily Modifier banner (id lives in the game store, set by fetchDailyGame).
	$: dailyMod =
		$gameStore.gameMode === 'daily' && $gameStore.modifier
			? modifierInfo($gameStore.modifier)
			: null;

	/** Start or resume the Cash Game (the persistent real-Cash Climb). */
	// ===== Cash Game V2 — tier select + run =====
	let showTierSelect = false;
	/** @type {any} */
	let cgMeta = null;
	let cgBusy = false;
	/** @type {any} */
	let cashoutResult = null; // { banked, buy_in, profit, multiple_x100, solves, tier }

	async function enterClimbGame() {
		hasInitialized = true;
		showMainMenu = false;
		showTierSelect = false;
		refreshClimbPups();
		await tick();
		playDailyIntroIfArmed();
	}
	async function handleMenuClimb() {
		const currentUser = get(user);
		if (!currentUser?.id) return;
		localStorage.setItem('gameMode', 'climb');
		const res = await fetchClimbGame();
		if (res === 'needs_tier') {
			cgMeta = await getCashgameMeta();
			showTierSelect = true;
		} else if (res) {
			await enterClimbGame();
		} else {
			initError = 'Cash Game failed to load.';
		}
	}
	/** @param {string} tier */
	async function pickTier(tier) {
		if (cgBusy) return;
		cgBusy = true;
		const res = await startCashGame(tier);
		cgBusy = false;
		if (res?.ok) {
			await enterClimbGame();
		} else if (res?.reason === 'insufficient') {
			await borrowToBuyIn(tier, res.buy_in ?? 0, res.bank ?? 0);
		} else if (res?.reason === 'locked') {
			fx('wrong');
		}
	}
	// 🦈 Buy-in wall → borrow exactly the shortfall (+25% fee), confirm with PIN, auto-start.
	/** @param {string} tier @param {number} buyIn @param {number} have */
	async function borrowToBuyIn(tier, buyIn, have) {
		const shortfall = Math.max(10, Math.ceil((buyIn - have) / 10) * 10);
		const info = await getBank().catch(() => null);
		if ((info?.loan ?? 0) > 0) {
			alert('Pay off your current loan first, then you can buy in.');
			return;
		}
		const cap = info?.loan_cap ?? 0;
		if (shortfall > cap) {
			alert(
				`You're $${(buyIn - have).toLocaleString()} short of the $${buyIn.toLocaleString()} buy-in and can only borrow up to $${cap.toLocaleString()}. Try a lower tier.`
			);
			return;
		}
		const fee = Math.round(shortfall * 0.25);
		try {
			await requirePin(`Borrow $${shortfall.toLocaleString()} to buy in`, [
				{ label: 'Buy-in', value: '$' + buyIn.toLocaleString() },
				{ label: 'You have', value: '$' + have.toLocaleString() },
				{
					label: 'Borrow (25% fee)',
					value: `$${shortfall.toLocaleString()} → owe $${(shortfall + fee).toLocaleString()}`
				}
			]);
		} catch {
			return; // cancelled at the pad
		}
		cgBusy = true;
		const loanRes = await takeLoan(shortfall);
		if (!loanRes?.ok) {
			cgBusy = false;
			fx('wrong');
			alert('Could not borrow right now.');
			return;
		}
		const retry = await startCashGame(tier);
		cgBusy = false;
		if (retry?.ok) {
			fx('win');
			await enterClimbGame();
		} else {
			fx('wrong');
		}
	}
	async function cashOut() {
		if (cgBusy) return;
		cgBusy = true;
		const res = await cashOutClimb();
		cgBusy = false;
		if (res?.ok) {
			cashoutResult = res;
			showResultModal = true;
			refreshBank();
		}
	}

	// ===== ⚡ Blitz — tier select + timed run =====
	let showBlitzTier = false;
	/** @type {any} */
	let bzMeta = null;
	let bzBusy = false;
	/** @type {any} */
	let blitzResult = null; // { solved, winnings, buy_in, net, best_combo, tier }
	async function handleMenuBlitz() {
		if (!get(user)?.id) return;
		localStorage.setItem('gameMode', 'blitz');
		bzMeta = await getBlitzMeta();
		showBlitzTier = true;
	}
	/** @param {string} tier */
	async function pickBlitzTier(tier) {
		if (bzBusy) return;
		bzBusy = true;
		const res = await startBlitz(tier);
		bzBusy = false;
		if (res?.ok) {
			hasInitialized = true;
			showMainMenu = false;
			showBlitzTier = false;
			blitzResult = null;
		} else if (res?.reason === 'insufficient') {
			if (
				confirm(
					`You need $${(res.buy_in ?? 0).toLocaleString()} to buy in (you have $${(res.bank ?? 0).toLocaleString()}). Borrow from the Bank?`
				)
			) {
				showBlitzTier = false;
				goto('/bank');
			}
		}
	}
	// When the run ends (clock → 0), surface the result modal.
	$: if (isBlitz && blitz && blitz.state === 'ended' && !blitzResult) {
		blitzResult = blitz;
		showResultModal = true;
		refreshBank();
	}

	// ===== Challenge Builder (configurable packs vs friends/groups) =====
	let showChallenges = false; // the New-Challenge builder modal
	/** Which Community hub tab is showing. */
	let communityTab = /** @type {'challenges'|'leaderboard'|'activity'|'people'} */ ('challenges');
	/** Which People sub-tab (when communityTab === 'people'). */
	let peopleTab = /** @type {'friends'|'groups'} */ ('friends');
	/** Start a challenge with a friend from the People list. @param {string} username */
	function challengeFriend(username) {
		newChallenge().then(() => {
			mbTarget = 'friend';
			mbOpponent = username;
		});
	}
	/** @type {any[]} */
	let myMatches = [];
	/** @type {any[]} */
	let myGroups = [];
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
	let mbWager = 500;
	let mbPayout = 'winner'; // derived from field size at settle; kept for the RPC signature
	// Challenge tier antes (ante = stake = pot size; payout is by field size at settle).
	const CHALLENGE_TIERS = [
		{ v: 0, label: '🤝 Friendly' },
		{ v: 500, label: '🥉 $500' },
		{ v: 2000, label: '🥈 $2K' },
		{ v: 10000, label: '🥇 $10K' }
	];
	let mbWindow = 172800; // seconds
	let mbItemsAllowed = false; // host toggle: allow power-ups in this challenge
	let mbMsg = '';
	let mbBusy = false;
	/** @type {{username:string,is_friend:boolean}[]} */
	let mbResults = [];
	/** @type {ReturnType<typeof setTimeout>|undefined} */
	let mbSearchTimer;
	const WINDOWS = [
		{ s: 3600, l: '1 hour' },
		{ s: 21600, l: '6 hours' },
		{ s: 86400, l: '24 hours' },
		{ s: 172800, l: '48 hours' },
		{ s: 604800, l: '1 week' }
	];

	/** Refresh the data behind the home act-now banner (matches + friend requests). */
	async function refreshChallengeCount() {
		if (!get(user)?.id) return;
		try {
			const [matches, reqs] = await Promise.all([getMyMatches(), listFriendRequests()]);
			myMatches = matches;
			friendRequests = reqs.incoming ?? [];
			friendReqCount = friendRequests.length;
		} catch {
			/* non-fatal */
		}
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
	/** @param {string} tab */
	async function openCommunity(tab) {
		if (!get(user)?.id) return;
		matchResults = null;
		peopleBackToHome = tab === 'people';
		communityTab = /** @type {any} */ (tab ?? 'challenges');
		menuView = 'community';
		showMainMenu = true;
		[myMatches, myGroups] = await Promise.all([getMyMatches(), getMyGroups()]);
	}
	/** Back-compat shim for existing callers (banner "+N more", toasts, result modal). */
	/** @param {string} [forceTab] */
	async function openChallenges(forceTab) {
		if (forceTab === 'new') return newChallenge();
		return openCommunity('challenges');
	}

	function onMbOppInput() {
		clearTimeout(mbSearchTimer);
		const q = mbOpponent.trim();
		if (q.length < 2) {
			mbResults = [];
			return;
		}
		mbSearchTimer = setTimeout(async () => {
			mbResults = await searchUsers(q);
		}, 220);
	}
	/** @param {string} username */
	function pickMbOpp(username) {
		mbOpponent = username;
		mbResults = [];
	}
	/** @param {string} c */
	function toggleCategory(c) {
		mbCategories = mbCategories.includes(c)
			? mbCategories.filter((x) => x !== c)
			: [...mbCategories, c];
	}

	async function submitNewMatch() {
		if (mbBusy) return;
		if (mbTarget === 'friend' && !mbOpponent.trim()) {
			mbMsg = 'Pick an opponent.';
			return;
		}
		if (mbTarget === 'group' && !mbGroupId) {
			mbMsg = 'Pick a group.';
			return;
		}
		const w = Math.floor(Number(mbWager) || 0);
		const createStakes = [
			{
				label: mbTarget === 'group' ? 'Group' : 'Opponent',
				value:
					mbTarget === 'group'
						? myGroups.find((g) => g.id === mbGroupId)?.name || 'Group'
						: '@' + mbOpponent.trim()
			},
			{ label: 'Puzzles', value: String(mbPackSize) },
			{ label: 'Buy-in', value: w > 0 ? '$' + w.toLocaleString() : 'Friendly' },
			{ label: 'Payout', value: mbPayout === 'podium' ? 'Podium 3·2·1' : 'Winner takes all' }
		];
		try {
			await requirePin(w > 0 ? 'Send & stake your buy-in' : 'Send this challenge', createStakes);
		} catch {
			return;
		}
		mbBusy = true;
		mbMsg = 'Creating…';
		const res = await startMatch({
			opponent: mbTarget === 'friend' ? mbOpponent.trim() : null,
			group_id: mbTarget === 'group' ? mbGroupId : null,
			categories: mbCategories,
			pack_size: mbPackSize,
			mode: mbMode,
			wager: Math.floor(Number(mbWager) || 0),
			payout: mbPayout,
			window_seconds: mbWindow,
			items_allowed: mbItemsAllowed
		});
		mbBusy = false;
		if (res?.ok) {
			launchMatchPlay();
		} else {
			mbMsg =
				res?.reason === 'no_opponent'
					? 'No player with that username.'
					: res?.reason === 'insufficient'
						? 'Not enough Cash for that wager.'
						: res?.reason === 'min_wager'
							? 'Minimum wager is $500 (or $0 for a friendly).'
							: res?.reason === 'self'
								? "You can't challenge yourself."
								: res?.reason === 'not_member'
									? "You're not in that group."
									: res?.reason === 'no_puzzles'
										? 'No puzzles in those categories.'
										: 'Could not create the challenge.';
		}
	}
	/** Stakes shown on the PIN confirm. @param {any} m */
	function matchStakes(m) {
		const s = [
			{
				label: m.is_host ? 'Players' : 'Opponent',
				value: m.is_host ? `${m.players}` : '@' + m.host
			},
			{ label: 'Puzzles', value: String(m.pack_size) },
			{
				label: 'Buy-in',
				value: Number(m.wager) > 0 ? '$' + Number(m.wager).toLocaleString() : 'Friendly'
			},
			{ label: 'Payout', value: m.payout === 'podium' ? 'Podium 3·2·1' : 'Winner takes all' }
		];
		if (Number(m.wager) > 0 && netWorth != null)
			s.push({ label: 'Your Cash', value: '$' + Math.round(netWorth).toLocaleString() });
		return s;
	}
	/** A challenge whose buy-in I can't fully afford — drives the play-or-decline sheet. */
	let shortMatch = /** @type {any|null} */ (null);
	/** @param {any} m */
	async function respondToMatch(m) {
		if (mbBusy) return;
		if (m.status === 'settled') {
			matchResults = { loading: true };
			matchResults = await getMatchDetail(m.id);
			return;
		}
		// Accepting an invite commits your buy-in → confirm with PIN (resuming doesn't).
		if (m.my_state === 'invited') {
			// Can't afford the full buy-in → offer "play with what you have" or decline.
			if (Number(m.wager) > 0 && netWorth != null && netWorth < Number(m.wager)) {
				shortMatch = m;
				return;
			}
			try {
				await requirePin(`Accept @${m.host}'s challenge`, matchStakes(m));
			} catch {
				return;
			}
		}
		mbBusy = true;
		const ok = m.my_state === 'invited' ? await acceptAndPlayMatch(m.id) : await resumeMatch(m.id);
		mbBusy = false;
		if (ok) {
			markChallengeNotifRead(m.id);
			launchMatchPlay();
		} else mbMsg = 'Could not open that challenge.';
	}
	/** Play a challenge with a budget capped at your current Cash. @param {any} m */
	async function playReduced(m) {
		shortMatch = null;
		const cap = Math.round(netWorth ?? 0);
		const stakes = matchStakes(m).map((s) =>
			s.label === 'Buy-in' ? { label: 'Buy-in (capped)', value: '$' + cap.toLocaleString() } : s
		);
		try {
			await requirePin(`Play with $${cap.toLocaleString()}`, stakes);
		} catch {
			return;
		}
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
		getDailyStatus(currentUser.id).then((s) => {
			dailyStatus = s;
			menuDailyPlayed = s.has_played_today;
		});
		refreshOpenGames();
		refreshBank();
		refreshChallengeCount();
		refreshNotifications();
	}

	let showMyAccount = false;
	let showAudio = false; // in-game quick audio panel (sound / haptics / music / track)
	let showStreakMessage = false;
	let maUsername = '';
	/** @type {any} */ let myAvatar = null;
	let _avatarLoaded = false;
	$: if (browser && loggedIn && hasInitialized && !_avatarLoaded) {
		_avatarLoaded = true;
		getMyAvatar().then((a) => {
			myAvatar = a.config;
		});
	}
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
		claimBusy = true;
		claimMsg = '';
		const res = await setUsername(name);
		claimBusy = false;
		if (res.ok) {
			maUsername = res.username ?? name;
			needsUsername = false;
			track('username_set', { at: 'signup' });
			fx('win');
		} else {
			claimMsg =
				res.reason === 'taken'
					? 'That username is taken — try another.'
					: res.reason === 'reserved'
						? 'That one’s reserved — try another.'
						: res.reason === 'invalid'
							? '3–15 characters: letters, numbers, or _.'
							: 'Could not set that username.';
		}
	}
	async function handleMenuMyAccount() {
		showMyAccount = true;
		maMsg = '';
		const u = get(user);
		if (u?.id) {
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
		if (res.ok) {
			maUsername = res.username ?? name;
			maEditing = false;
			maMsg = '';
			track('username_set');
		} else {
			maMsg =
				res.reason === 'taken'
					? 'That username is taken.'
					: res.reason === 'reserved'
						? 'That username is reserved.'
						: res.reason === 'invalid'
							? '3–15 letters, numbers or _ only.'
							: 'Could not save username.';
		}
	}
	/** @param {KeyboardEvent} e */
	function handleEscape(e) {
		if (e.key !== 'Escape') return;
		if (showMyAccount) showMyAccount = false;
		if (showStreakMessage) showStreakMessage = false;
	}

	// Daily result → go to the daily leaderboard.
	const goToDailyLeaderboard = () => {
		showResultModal = false;
		hasTriggeredModal = false;
		const currentUser = get(user);
		if (!currentUser?.id) return;
		clearSavedGame();
		gameWasRestored.set(false);
		goto('/leaderboard?mode=daily');
	};

	const onPhraseRevealComplete = () => {
		if (!hasTriggeredModal && ['won', 'lost'].includes($gameStore.gameState)) {
			hasTriggeredModal = true;
			const won = $gameStore.gameState === 'won';
			if ($gameStore.gameMode === 'daily' && won) {
				resultRank = null;
				getMyDailyRank()
					.then((r) => {
						resultRank = r;
					})
					.catch(() => {});
				const uid = get(user)?.id;
				if (uid)
					getDailyStatus(uid)
						.then((s) => {
							dailyStatus = s;
						})
						.catch(() => {});
			}
			setTimeout(() => {
				showResultModal = true;
				// 🏆 Win banner: count the profit up, then scroll Cash to the new total.
				if ($gameStore.gameMode === 'daily' && won) {
					const profit = $gameStore.dailyResult?.net ?? 0;
					const newBank = Math.round($gameStore.bankroll ?? 0);
					resultProfit.set(0, { duration: 0 });
					resultBankAnim.set(newBank - profit, { duration: 0 });
					setTimeout(() => {
						resultProfit.set(profit);
						fx('win');
					}, 350);
					setTimeout(() => {
						resultBankAnim.set(newBank);
					}, 1100);
				} else if ($gameStore.gameMode === 'climb' && won) {
					const c = $gameStore.climbInfo || {};
					const profit = Math.round((c.last_gain ?? 0) - (c.spent ?? 0));
					const newBank = Math.round($gameStore.bankroll ?? 0);
					resultProfit.set(0, { duration: 0 });
					resultBankAnim.set(newBank - profit, { duration: 0 });
					setTimeout(() => {
						resultProfit.set(profit);
						fx('win');
					}, 350);
					setTimeout(() => {
						resultBankAnim.set(newBank);
					}, 1100);
				}
			}, 1000);
		}
	};
</script>

<svelte:window on:keydown={handleEscape} />
<!-- ☰ Main menu (top-left) -->
{#if loggedIn && hasInitialized && !showMainMenu}
	<button class="menu-back-btn" title="Main menu" aria-label="Main menu" on:click={goToMainMenu}
		><span class="hamburger"></span></button
	>
{/if}
<!-- ❓ How to play THIS game type (top-center) -->
{#if loggedIn && hasInitialized && !showMainMenu && $gameStore.gameMode}
	<button
		class="help-btn"
		title="How to play"
		aria-label="How to play this game"
		on:click={() => showObjectiveFor($gameStore.gameMode, true)}>?</button
	>
{/if}
<!-- 🔊 In-game audio controls (sound / haptics / music) -->
{#if loggedIn && hasInitialized && !showMainMenu}
	<button
		class="audio-btn"
		title="Sound & music"
		aria-label="Sound and music settings"
		on:click={() => {
			fx('tap');
			showAudio = true;
		}}>{$soundEnabled || $musicEnabled ? '🔊' : '🔇'}</button
	>
{/if}
<!-- 🏳️ Give up (top-right) — Daily / Challenges -->
{#if loggedIn && hasInitialized && !showMainMenu && foldMode && gameActive}
	<button class="giveup-btn" title="Give up" aria-label="Give up" on:click={confirmFold}>↪</button>
{/if}
<!-- Skip retired in Cash Game V4 — Cash Out is the graceful bail. -->

<!-- 💬 Match chat (1v1 + group challenges) — only inside a live match, never on the menu -->
{#if isMatch && matchInfo && !showMainMenu}
	<button
		class="match-chat-btn"
		class:unread={matchChatUnread}
		title="Trash talk"
		on:click={openMatchChat}
	>
		💬 <span class="mcb-label">Chat</span>{#if matchChatUnread}<span class="mc-dot"></span>{/if}
	</button>
{/if}
{#if matchChatOpen && !showMainMenu}
	<div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Match chat">
		<button
			type="button"
			class="modal-backdrop"
			aria-label="Close"
			on:click={() => (matchChatOpen = false)}
		></button>
		<div class="modal-content chat-modal">
			<button class="close-btn" on:click={() => (matchChatOpen = false)}>❌</button>
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
				<input
					class="chat-input"
					placeholder="Message…"
					maxlength="500"
					bind:value={matchChatInput}
					on:keydown={(e) => {
						if (e.key === 'Enter') sendMatchChat();
					}}
				/>
				<button
					class="chat-send"
					on:click={sendMatchChat}
					disabled={matchChatBusy || !matchChatInput.trim()}>Send</button
				>
			</div>
		</div>
	</div>
{/if}

<!-- 🏳️ Give-up confirm layer -->
{#if showGiveUp}
	<div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Give up">
		<button type="button" class="modal-backdrop" aria-label="Cancel" on:click={cancelGiveUp}
		></button>
		<div class="modal-content giveup-modal">
			<h2 class="gu-title">
				{isClimb
					? 'Skip this puzzle?'
					: `Give up ${$gameStore.gameMode === 'match' ? 'this puzzle' : "today's Daily"}?`}
			</h2>
			<p class="gu-text">
				{isClimb
					? `Your heat resets to ×1.0${(climb?.spent ?? 0) > 0 ? ` and you forfeit the $${(climb?.spent ?? 0).toLocaleString()} spent on this one` : ''} — then a fresh puzzle.`
					: $gameStore.gameMode === 'match'
						? 'Skip this puzzle — you pay its full price and move on.'
						: 'It counts as a loss and reveals the answer.'}
			</p>
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
				Solve this puzzle and your payout <b>doubles</b> to
				<b class="don-win">${donTarget.toLocaleString()}</b>. But you're all in — you
				<b>can't skip</b>, and if you get stuck you walk away with
				<b class="don-loss">$0</b>{(climb?.spent ?? 0) > 0
					? ` and forfeit the $${(climb?.spent ?? 0).toLocaleString()} you've spent`
					: ''}.
			</p>
			<div class="gu-actions">
				<button class="gu-cancel" on:click={cancelDon}>Not now</button>
				<button class="gu-confirm don-confirm" on:click={armDon} disabled={donBusy}
					>💥 Double it</button
				>
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
	<button
		class="attendance-toast"
		on:click={() => gameStore.update((s) => ({ ...s, cashToast: null }))}
	>
		{#if $gameStore.cashToast.amount > 0}<strong
				>+${$gameStore.cashToast.amount.toLocaleString()}</strong
			> ·
		{/if}{$gameStore.cashToast.label}
	</button>
{/if}

<!-- 🎰 Pure-solve ×1.5 multiplier fly-in -->
<!-- 💰 In-game bank modal: same info as /bank, but closing returns to the game -->
{#if showBank}
	<div
		class="modal-overlay info-overlay"
		role="button"
		tabindex="0"
		aria-label="Close"
		on:click={() => (showBank = false)}
		on:keydown={(e) => {
			if (e.key === 'Escape' || e.key === 'Enter') showBank = false;
		}}
	>
		<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions a11y_no_noninteractive_element_interactions a11y_no_noninteractive_tabindex -->
		<div class="info-card bank-card" on:click|stopPropagation role="dialog" aria-modal="true">
			<button class="modal-x" on:click={() => (showBank = false)} aria-label="Close">✕</button>
			<p class="bm-label">💰 Available Balance</p>
			<div class="info-big">{fmtCash(bankData?.bank ?? netWorth ?? 0)}</div>
			<p class="info-sub">Your Available Balance — this is your score</p>
			<!-- 🦈 Borrow / Repay, inline -->
			<LoanPanel bank={bankData} on:changed={reloadBank} />
			{#if bankData}
				<div class="bm-hist-h">Recent activity</div>
				{#if (bankData.ledger ?? []).length === 0}
					<p class="info-note" style="text-align:center">
						No transactions yet. Win the Daily, show up for attendance, or climb the Cash Game to
						grow your Bank Account.
					</p>
				{:else}
					<div class="bm-ledger">
						{#each bankData.ledger.slice(0, 8) as e}
							<div class="bm-row">
								<span class="bm-reason">{bankReason(e.reason)}</span>
								<span class="bm-delta" class:pos={e.delta > 0} class:neg={e.delta < 0}
									>{e.delta > 0 ? '+' : '−'}{fmtCash(Math.abs(e.delta))}</span
								>
							</div>
						{/each}
					</div>
					<button class="bm-fullledger" on:click={() => goto('/bank')}>See full Statement →</button>
				{/if}
			{/if}
			<button class="info-close" on:click={() => (showBank = false)}>Back to game</button>
		</div>
	</div>
{/if}

<!-- 🔐 Vault door-open animation (from the main menu, after the PIN) → then items -->
{#if vaultVideo}
	<VaultReveal on:done={onVaultVideoEnd} />
{/if}

<!-- 🔐 My Vault: use power-ups in-game + view inventory + Store link -->
{#if showBag}
	<div
		class="modal-overlay info-overlay"
		role="button"
		tabindex="0"
		aria-label="Close"
		on:click={() => (showBag = false)}
		on:keydown={(e) => {
			if (e.key === 'Escape') showBag = false;
		}}
	>
		<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions a11y_no_noninteractive_element_interactions a11y_no_noninteractive_tabindex -->
		<div class="info-card bag-modal" on:click|stopPropagation role="dialog" aria-modal="true">
			<button class="modal-x" on:click={() => (showBag = false)} aria-label="Close">✕</button>
			<h3 class="info-title"><img src="/vault.png" alt="" class="vault-ic-xs" /> My Vault</h3>
			{#if showMainMenu}
				<div class="bag-inv"><InventoryList /></div>
				<button class="bag-store" on:click={() => goto('/shop')}>🛍️ Go to the Store →</button>
			{:else}
				<div class="bag-use-h">Your items</div>
				{#if vaultItems.length}
					<div class="bag-use-grid">
						{#each vaultItems as it}
							<button
								class="bag-use"
								class:locked={!it.usable}
								disabled={(dailyTwistBusy || dailyBoostBusy) && it.usable}
								on:click={() => tapVaultItem(it)}
								title={it.usable ? it.blurb : it.reason}
							>
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
			{/if}
			{#if vaultMsg}<div class="bag-msg">{vaultMsg}</div>{/if}
		</div>
	</div>
{/if}

<!-- ℹ️ Daily explainers: multiplier breakdown / Solve-to-Earn calculation -->
{#if dailyInfo}
	<div
		class="modal-overlay info-overlay"
		role="button"
		tabindex="0"
		aria-label="Close"
		on:click={() => (dailyInfo = null)}
		on:keydown={(e) => {
			if (e.key === 'Escape' || e.key === 'Enter') dailyInfo = null;
		}}
	>
		<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions a11y_no_noninteractive_element_interactions a11y_no_noninteractive_tabindex -->
		<div class="info-card" on:click|stopPropagation role="dialog" aria-modal="true">
			<button class="modal-x" on:click={() => (dailyInfo = null)} aria-label="Close">✕</button>
			{#if dailyInfo === 'mult'}
				<div class="info-big">{fmtMult(dlMult)}</div>
				<h3 class="info-title">Bounty Multiplier</h3>
				<p class="info-sub">Everything you can earn from this puzzle is multiplied by this.</p>
				<div class="info-rows">
					<div class="info-row"><span>Base</span><b>+0%</b></div>
					{#if dlStreakBonus > 0}<div class="info-row">
							<span>🏆 Win streak ({dlWinStreak} in a row)</span><b class="pos"
								>+{dlStreakBonus.toFixed(1)}</b
							>
						</div>{/if}
					{#if dlBoost > 0}<div class="info-row">
							<span>💥 Boosts</span><b class="pos">+{dlBoost.toFixed(1)}</b>
						</div>{/if}
					{#if dlWrong > 0}<div class="info-row">
							<span>❌ Wrong guesses ({dlWrong})</span><b class="neg">−{dlPenalty.toFixed(1)}</b>
						</div>{/if}
					<div class="info-row total"><span>Your multiplier</span><b>{fmtMult(dlMult)}</b></div>
				</div>
				<p class="info-note">
					Grows with your <button
						class="info-inline"
						on:click|stopPropagation={() => (dailyInfo = 'streak')}>deposit streak</button
					>
					(<b>+0.1×</b>/solve, up to <b>×1.5</b>). Each wrong guess costs <b>−0.2×</b> (never below ×1.0).
				</p>
			{:else if dailyInfo === 'twist'}
				<div class="info-big">{dailyMod?.emoji ?? '🎁'}</div>
				<h3 class="info-title">{dailyMod?.name ?? "Today's Twist"}</h3>
				<p class="info-sub">Today's special — applied automatically. ✓</p>
				<p class="info-twist-do">{dailyMod?.blurb ?? ''}</p>
				<p class="info-note">A different special each weekday — same for everyone.</p>
			{:else if dailyInfo === 'streak'}
				<div class="info-big">🏆 {dlWinStreak}</div>
				<h3 class="info-title">Deposit Streak</h3>
				<p class="info-sub">Daily puzzles you've solved in a row.</p>
				<div class="info-rows">
					<div class="info-row"><span>Solve today's Daily</span><b class="pos">+1</b></div>
					<div class="info-row"><span>Lose or give up</span><b class="neg">back to 0</b></div>
				</div>
				<p class="info-note">
					Also boosts your <button
						class="info-inline"
						on:click|stopPropagation={() => (dailyInfo = 'mult')}>multiplier</button
					>
					— <b>+0.1×</b> per win.
				</p>
			{:else}
				<div class="info-big green">${Math.max(0, dlWinnings).toLocaleString()}</div>
				<h3 class="info-title">You'll bank</h3>
				<p class="info-sub">
					What you'd bank if you solve right now. Your Cash never drops — playing only adds to it.
				</p>
				<div class="info-rows">
					<div class="info-row">
						<span>🏆 Prize left</span><b class="pos">${dlRemaining.toLocaleString()}</b>
					</div>
					{#if dlMult > 1}<div class="info-row">
							<span>× Streak bonus</span><b>{fmtMult(dlMult)}</b>
						</div>{/if}
					<div class="info-row total">
						<span>You bank</span><b class="green">${dlWinnings.toLocaleString()}</b>
					</div>
				</div>
				<p class="info-note">
					Deduce letters instead of buying them — keep more of the Prize. Grows your <button
						class="info-inline"
						on:click|stopPropagation={() => (dailyInfo = 'mult')}>multiplier</button
					> too.
				</p>
			{/if}
			<button class="info-close" on:click={() => (dailyInfo = null)}>Got it</button>
		</div>
	</div>
{/if}

<!-- ℹ️ Cash Game explainers: heat (= win streak) / Solve-to-Earn calculation -->
{#if climbInfo}
	<div
		class="modal-overlay info-overlay"
		role="button"
		tabindex="0"
		aria-label="Close"
		on:click={() => (climbInfo = null)}
		on:keydown={(e) => {
			if (e.key === 'Escape' || e.key === 'Enter') climbInfo = null;
		}}
	>
		<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions a11y_no_noninteractive_element_interactions a11y_no_noninteractive_tabindex -->
		<div class="info-card" on:click|stopPropagation role="dialog" aria-modal="true">
			<button class="modal-x" on:click={() => (climbInfo = null)} aria-label="Close">✕</button>
			{#if climbInfo === 'heat'}
				<div class="info-big">📈 +{climbYield}%</div>
				<h3 class="info-title">Yield — your return rate</h3>
				<p class="info-sub">Everything you earn from a puzzle is boosted by your Yield rate.</p>
				<div class="info-rows">
					<div class="info-row"><span>Base</span><b>+0%</b></div>
					<div class="info-row"><span>Each solve in a row</span><b class="pos">+10%</b></div>
					<div class="info-row">
						<span>Maxes out at</span><b>+{(climb?.heat_cap ?? 200) - 100}%</b>
					</div>
					<div class="info-row total"><span>Your Yield</span><b>+{climbYield}%</b></div>
				</div>
				<p class="info-note">
					Yield climbs with your <button
						class="info-inline"
						on:click|stopPropagation={() => (climbInfo = 'streak')}>deposit streak</button
					> and resets to +0% on a VOID.
				</p>
			{:else if climbInfo === 'streak'}
				<div class="info-big">🏆 {climbStreak}</div>
				<h3 class="info-title">Deposit Streak</h3>
				<p class="info-sub">Cash Game puzzles you've solved in a row.</p>
				<div class="info-rows">
					<div class="info-row"><span>Solve a puzzle</span><b class="pos">+1</b></div>
					<div class="info-row"><span>VOID</span><b class="neg">back to 0</b></div>
				</div>
				<p class="info-note">
					Powers your <button
						class="info-inline"
						on:click|stopPropagation={() => (climbInfo = 'heat')}>Yield</button
					>
					— <b>+10%</b> per solve.
				</p>
			{:else}
				<div class="info-big green">${Math.max(0, climbLive?.net ?? 0).toLocaleString()}</div>
				<h3 class="info-title">Potential Credit</h3>
				<p class="info-sub">What lands in your Pending Deposit if you solve right now.</p>
				<div class="info-rows">
					<div class="info-row">
						<span>Cash Advance left <small>(spend on letters)</small></span><b
							>${Math.round(climb?.budget_left ?? 0).toLocaleString()}</b
						>
					</div>
					<div class="info-row">
						<span>📈 Yield</span><b class="pos">+{climbYield}%</b>
					</div>
					<div class="info-row total">
						<span>Credit</span><b class="green">${(climbLive?.net ?? 0).toLocaleString()}</b>
					</div>
				</div>
				<p class="info-note">
					Each puzzle's <b>Cash Advance</b> shrinks as you buy letters — solve to keep what's left ×
					<button class="info-inline" on:click|stopPropagation={() => (climbInfo = 'heat')}
						>Yield</button
					>. Reveal less, keep more.
				</p>
			{/if}
			<button class="info-close" on:click={() => (climbInfo = null)}>Got it</button>
		</div>
	</div>
{/if}

<!-- ℹ️ Challenge "Left to Spend" explainer -->
{#if showAnteInfo}
	<div
		class="modal-overlay info-overlay"
		role="button"
		tabindex="0"
		aria-label="Close"
		on:click={() => (showAnteInfo = false)}
		on:keydown={(e) => {
			if (e.key === 'Escape' || e.key === 'Enter') showAnteInfo = false;
		}}
	>
		<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions a11y_no_noninteractive_element_interactions a11y_no_noninteractive_tabindex -->
		<div class="info-card" on:click|stopPropagation role="dialog" aria-modal="true">
			<button class="modal-x" on:click={() => (showAnteInfo = false)} aria-label="Close">✕</button>
			<div class="info-big green">${Math.max(0, matchLeft).toLocaleString()}</div>
			<h3 class="info-title">Left to Spend</h3>
			<p class="info-sub">
				Your buy-in — real Cash, all of it at stake. Buying letters spends it; your wallet up top is
				the rest of your Cash and it's safe.
			</p>
			<div class="info-rows">
				<div class="info-row">
					<span>Most Cash left at the end</span><b class="pos">takes the whole pot</b>
				</div>
				<div class="info-row"><span>Lose</span><b class="neg">forfeit your buy-in</b></div>
				<div class="info-row"><span>Skip a puzzle</span><b class="neg">pays full price</b></div>
			</div>
			<p class="info-note">
				Most Cash left wins the pot. Duel = winner-take-all (tie splits 50/50); groups pay a podium
				(3 → 70/30, 4+ → 60/30/10). Wrong guesses waste your ante, so guess only when you're sure.
			</p>
			<button class="info-close" on:click={() => (showAnteInfo = false)}>Got it</button>
		</div>
	</div>
{/if}

<!-- 💥 Sabotage debuff explainer: what it does + who hit you -->
{#if debuffModal}
	<div
		class="modal-overlay info-overlay"
		role="button"
		tabindex="0"
		aria-label="Close"
		on:click={() => (debuffModal = null)}
		on:keydown={(e) => {
			if (e.key === 'Escape' || e.key === 'Enter') debuffModal = null;
		}}
	>
		<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions a11y_no_noninteractive_element_interactions a11y_no_noninteractive_tabindex -->
		<div class="info-card" on:click|stopPropagation role="dialog" aria-modal="true">
			<button class="modal-x" on:click={() => (debuffModal = null)} aria-label="Close">✕</button>
			<div class="info-big">💥</div>
			<h3 class="info-title">You got hit</h3>
			{#if debuffModal.length}
				<div class="info-rows">
					{#each debuffModal as d}
						<div class="info-row debuff-row">
							<span
								>{DEBUFF_LABEL[d.effect] ?? d.effect}<small class="db-desc"
									>{DEBUFF_DESC[d.effect] ?? ''}</small
								></span
							>
							<b>{d.by ? 'by ' + d.by : ''}</b>
						</div>
					{/each}
				</div>
			{:else}
				<p class="info-sub">No active sabotage right now.</p>
			{/if}
			<button class="info-close" on:click={() => (debuffModal = null)}>Got it</button>
		</div>
	</div>
{/if}

<!-- 😈 Sabotage target picker (group play): each opponent's puzzle + ante left -->
{#if sabPicker}
	<div
		class="modal-overlay info-overlay"
		role="button"
		tabindex="0"
		aria-label="Cancel"
		on:click={() => (sabPicker = null)}
		on:keydown={(e) => {
			if (e.key === 'Escape') sabPicker = null;
		}}
	>
		<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions a11y_no_noninteractive_element_interactions a11y_no_noninteractive_tabindex -->
		<div class="info-card" on:click|stopPropagation role="dialog" aria-modal="true">
			<button class="modal-x" on:click={() => (sabPicker = null)} aria-label="Cancel">✕</button>
			<div class="info-big">{PUP_ICON[sabPicker.item.id] ?? '😈'}</div>
			<h3 class="info-title">{sabPicker.item.name} — hit who?</h3>
			<div class="sab-target-list">
				{#each sabPicker.opponents as o}
					<button class="sab-target-row" on:click={() => applySabotage(o.id)}>
						<span class="st-name">{o.name}</span>
						<span class="st-stat"
							>🧩 Puzzle {o.position} · ${Number(o.ante_left ?? 0).toLocaleString()}</span
						>
					</button>
				{/each}
			</div>
			<button class="info-close" on:click={() => (sabPicker = null)}>Cancel</button>
		</div>
	</div>
{/if}

<!-- ▶ Resume menu — pick which in-progress game to jump back into -->
{#if showResumeMenu}
	<div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Resume a game">
		<button
			type="button"
			class="modal-backdrop"
			aria-label="Close"
			on:click={() => (showResumeMenu = false)}
		></button>
		<div class="info-card resume-menu" role="document">
			<button class="modal-x" on:click={() => (showResumeMenu = false)} aria-label="Close">✕</button
			>
			<h3 class="info-title">Resume a game</h3>
			<div class="rm-list">
				{#each resumables as r (r.key)}
					<button
						class="rm-row"
						on:click={() => {
							showResumeMenu = false;
							r.go();
						}}
					>
						<span class="rm-ic">{r.icon}</span><span class="rm-label">{r.label}</span><span
							class="rm-arrow">▶</span
						>
					</button>
				{/each}
			</div>
		</div>
	</div>
{/if}

<!-- 🔊 In-game audio panel — sound / haptics / music + track, adjustable mid-puzzle -->
{#if showAudio}
	<div
		class="modal-overlay info-overlay"
		role="button"
		tabindex="0"
		aria-label="Close"
		on:click={() => (showAudio = false)}
		on:keydown={(e) => {
			if (e.key === 'Escape' || e.key === 'Enter') showAudio = false;
		}}
	>
		<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions a11y_no_noninteractive_element_interactions a11y_no_noninteractive_tabindex -->
		<div class="info-card audio-panel" on:click|stopPropagation role="dialog" aria-modal="true">
			<button class="modal-x" on:click={() => (showAudio = false)} aria-label="Close">✕</button>
			<h3 class="info-title">Sound &amp; Music</h3>
			<div class="ap-rows">
				<button
					class="ap-toggle"
					on:click={() => {
						toggleSound();
						if ($soundEnabled) fx('select');
					}}
				>
					<span>{$soundEnabled ? '🔊' : '🔇'} Sound</span><span
						class="ap-state"
						class:on={$soundEnabled}>{$soundEnabled ? 'On' : 'Off'}</span
					>
				</button>
				<button
					class="ap-toggle"
					on:click={() => {
						toggleHaptics();
						if ($hapticsEnabled) fx('tap');
					}}
				>
					<span>{$hapticsEnabled ? '📳' : '📴'} Haptics</span><span
						class="ap-state"
						class:on={$hapticsEnabled}>{$hapticsEnabled ? 'On' : 'Off'}</span
					>
				</button>
				<button class="ap-toggle" on:click={toggleMusic}>
					<span>{$musicEnabled ? '🎵' : '🔕'} Music</span><span
						class="ap-state"
						class:on={$musicEnabled}>{$musicEnabled ? 'On' : 'Off'}</span
					>
				</button>
			</div>
			{#if $musicEnabled}
				<div class="ma-music-ctl">
					<span class="mmc-ic">🔈</span>
					<input
						class="mmc-slider"
						type="range"
						min="0"
						max="100"
						step="1"
						value={Math.round($musicVolume * 100)}
						on:input={(e) => setMusicVolume(Number(e.currentTarget.value) / 100)}
					/>
					<span class="mmc-pct">{Math.round($musicVolume * 100)}%</span>
				</div>
				<div class="ma-tracks">
					{#each TRACKS as t, i}
						<button
							class="ma-track"
							class:on={$currentTrackId === t.id}
							on:click={() => selectTrack(t.id)}>Track {i + 1}</button
						>
					{/each}
				</div>
			{/if}
		</div>
	</div>
{/if}

<main>
	<!-- 👤 First-run: pick a username (required to play socially) -->
	{#if loggedIn && hasInitialized && needsUsername}
		<div
			class="modal-overlay username-gate"
			role="dialog"
			aria-modal="true"
			aria-label="Pick your username"
		>
			<div class="modal-content main-menu-modal claim-card">
				<img class="claim-coin" src="/logo-coin.png" alt="" width="84" height="84" />
				<h2>Pick your username</h2>
				<p class="claim-sub">
					This is your @handle — how friends find you and challenge you. You can change it later in
					My Account.
				</p>
				<div class="claim-row">
					<span class="claim-at">@</span>
					<input
						class="claim-input"
						placeholder="username"
						bind:value={claimInput}
						maxlength="15"
						autocomplete="off"
						on:keydown={(e) => {
							if (e.key === 'Enter') claimUsername();
						}}
					/>
				</div>
				{#if claimMsg}<p class="claim-msg">{claimMsg}</p>{/if}
				<button
					class="claim-btn"
					disabled={claimBusy || !claimInput.trim()}
					on:click={claimUsername}
				>
					{claimBusy ? 'Claiming…' : 'Claim username'}
				</button>
				<p class="claim-hint">3–15 characters · letters, numbers, or _</p>
			</div>
		</div>
	{/if}

	<!-- 🔐 PIN gate: unlock (returning) or set (new), full-screen over everything -->
	{#if showPinUnlock}
		<PinGate
			mode="unlock"
			uid={sessionUid}
			name={maUsername}
			balance={netWorth}
			on:unlocked={onPinUnlocked}
			on:logout={onPinLogout}
		/>
	{:else if showPinSetup}
		<PinGate
			mode="set"
			uid={sessionUid}
			name={maUsername}
			on:pinset={onPinSet}
			on:skip={onPinSkip}
			on:logout={onPinLogout}
		/>
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
					<button
						class="bell-ic"
						on:click={() => goto('/profile?tab=alerts')}
						title="Notifications"
						aria-label="Notifications"
					>
						🔔{#if $unreadCount > 0}<span class="account-count" title="{$unreadCount} new"
								>{$unreadCount > 99 ? '99+' : $unreadCount}</span
							>{/if}
					</button>
					<button
						class="bank-chip"
						class:in-debt={menuLoan > 0}
						on:click={openBankModal}
						title="Bank Account"
					>
						<span class="bc-coin">💰</span>{menuBank == null
							? '—'
							: '$' + Math.round(menuBank).toLocaleString()}
						{#if menuLoan > 0}<span class="bc-debt" title="You owe the Loan Shark"
								>🦈 −${Math.round(menuLoan).toLocaleString()}</span
							>{/if}
					</button>
					<button
						class="account-ic has-av"
						on:click={() => goto('/profile')}
						title="Profile"
						aria-label="Profile"
					>
						<Avatar config={myAvatar} mode="head" fx size={50} />
					</button>
				</div>
				<video
					class="menu-mark"
					src="/coin.mp4"
					poster="/coin-poster.jpg"
					autoplay
					loop
					muted
					playsinline
					disablepictureinpicture
				></video>
				<img
					class="menu-wordmark"
					src="/wordmark-slogan.png"
					alt="WordBank — Spend Less. Think More."
				/>
			</div>
			{#if menuView === 'home'}
				<div class="main-menu-buttons stagger">
					<!-- 🦈 Debt banner — you owe the Loan Shark; Store locked + payouts auto-skim. -->
					{#if menuLoan > 0}
						<button
							class="debt-banner"
							style="--i: 0"
							on:click={() => {
								fx('tap');
								goto('/bank');
							}}
						>
							🦈 <span class="db-text"
								>You owe <b>${Math.round(menuLoan).toLocaleString()}</b> — half of every payout auto-repays
								it</span
							>
							<span class="db-go">Repay ›</span>
						</button>
					{/if}
					<!-- ▶ Resume — any in-progress game (solo + started challenges). One → straight in; many → the Resume menu. -->
					{#if resumables.length}
						<button class="resume-strip" style="--i: 0" on:click={onResume}>
							<span class="rs-dot">▸</span>
							<span class="rs-label"
								>Resume{resumables.length === 1 ? ' — ' + resumables[0].label : ''}</span
							>
							{#if resumables.length > 1}<span class="rs-count">{resumables.length}</span>{/if}
							<span class="rs-go">›</span>
						</button>
					{/if}
					<button
						class="menu-card primary"
						style="--i: 0"
						on:click={() => {
							menuView = 'play';
							fx('tap');
						}}
					>
						<span class="mc-title">Play Now!</span>
					</button>
					<!-- ⚔️ Challenges hub (list + New). Incoming invites alert via the bell → tap routes here. -->
					<div class="vs-cta-group">
						<button
							class="vs-main"
							on:click={() => {
								fx('tap');
								openCommunity('challenges');
							}}
						>
							⚔️ Challenge Friends
						</button>
						<button
							class="vs-people"
							title="Friends &amp; Groups"
							aria-label="Friends and groups"
							on:click={() => {
								fx('tap');
								openCommunity('people');
							}}
						>
							<span class="vs-ppl">👥</span><span class="vs-ppl-plus">+</span>
						</button>
					</div>
					<button
						class="menu-card"
						style="--i: 1"
						on:click={() => {
							fx('tap');
							openCommunity('leaderboard');
						}}
					>
						<span class="mc-title">🏆 Leaderboard</span>
					</button>
					<button class="menu-card" style="--i: 2" on:click={() => goto('/shop')}>
						<span class="mc-title">Store</span>
					</button>
				</div>
			{:else if menuView === 'play'}
				<div class="sub-head">
					<button
						class="sub-back"
						on:click={() => {
							menuView = 'home';
							fx('tap');
						}}>← Back</button
					>
					<h2 class="sub-title">Play</h2>
				</div>
				<div class="main-menu-buttons stagger">
					<button
						class="menu-card"
						class:done={dailyDone}
						class:resumable={dailyInProgress}
						class:fresh={!dailyDone && !dailyInProgress}
						style="--i: 0"
						on:click={handleMenuDaily}
					>
						<span class="mc-streak left" title="Play streak — days in a row"
							>📅 {dailyStatus?.current_streak ?? 0}</span
						>
						<span class="mc-title">{dailyInProgress ? 'Resume Daily' : 'Daily'}</span>
						<span class="mc-streak right" title="Win streak — solves in a row"
							>🏆 {dailyStatus?.win_streak ?? 0}</span
						>
						{#if dailyDone}
							{#if dailyStatus?.last_daily_won}
								<span class="daily-chip won"
									>✅ +${(dailyStatus?.today_score ?? 0).toLocaleString()}</span
								>
							{:else}
								<span class="daily-chip lost"
									>❌{dailyStatus?.today_score
										? ' −$' + Math.abs(dailyStatus.today_score).toLocaleString()
										: ''}</span
								>
							{/if}
						{:else if dailyInProgress}
							<span class="daily-chip prog">▶ Resume</span>
						{/if}
					</button>
					<button
						class="menu-card"
						class:resumable={climbInProgress}
						style="--i: 1"
						on:click={handleMenuClimb}
					>
						<span class="mc-title">Cash Game</span>
						{#if climbInProgress}<span class="daily-chip prog">▶ Resume</span>{/if}
					</button>
					<button class="menu-card" style="--i: 2" on:click={handleMenuBlitz}>
						<span class="mc-title">⚡ Blitz</span><span class="mc-stat">Beat the clock</span>
					</button>
				</div>
			{:else if menuView === 'community'}
				<div class="sub-head">
					{#if communityTab === 'people'}
						{#if peopleBackToHome}
							<button
								class="sub-back"
								on:click={() => {
									menuView = 'home';
									fx('tap');
								}}>← Back</button
							>
						{:else}
							<button
								class="sub-back"
								on:click={() => {
									communityTab = 'challenges';
									fx('tap');
								}}>← Community</button
							>
						{/if}
						<h2 class="sub-title">People</h2>
					{:else}
						<button
							class="sub-back"
							on:click={() => {
								menuView = 'home';
								fx('tap');
							}}>← Back</button
						>
						<h2 class="sub-title">
							{communityTab === 'leaderboard' ? '🏆 Leaderboard' : '⚔️ Challenges'}
						</h2>
						{#if communityTab === 'challenges'}
							<button
								class="sub-people"
								title="Friends & Groups"
								aria-label="Friends & Groups"
								on:click={() => {
									communityTab = 'people';
									peopleBackToHome = false;
									fx('tap');
								}}><span class="vs-ppl">👥</span><span class="vs-ppl-plus">+</span></button
							>
						{/if}
					{/if}
				</div>
				{#if communityTab === 'people'}
					<div class="comm-tabs">
						<button
							class="comm-tab"
							class:active={peopleTab === 'friends'}
							on:click={() => {
								peopleTab = 'friends';
								fx('tap');
							}}
							>Friends{#if friendReqCount > 0}
								· {friendReqCount}{/if}</button
						>
						<button
							class="comm-tab"
							class:active={peopleTab === 'groups'}
							on:click={() => {
								peopleTab = 'groups';
								fx('tap');
							}}>Groups</button
						>
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
											<span class="ch-vs">{m.is_host ? 'You hosted' : m.host + ' invited you'}</span
											>
											<span class="ch-meta"
												>{m.pack_size} puzzle{m.pack_size === 1 ? '' : 's'} · {m.players} players{#if m.wager > 0}
													· ${m.wager?.toLocaleString()}{/if}</span
											>
										</div>
										{#if m.status === 'settled'}
											<button
												class="ch-play ghost"
												disabled={mbBusy}
												on:click={() => respondToMatch(m)}>Results</button
											>
										{:else if m.my_state !== 'done'}
											<button class="ch-play" disabled={mbBusy} on:click={() => respondToMatch(m)}
												>{m.my_state === 'invited' ? 'Play' : 'Resume'}</button
											>
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

		<!-- 🎰 Cash Game: tier select (buy-in run) -->
		{#if showTierSelect}
			<div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Pick a tier">
				<button
					type="button"
					class="modal-backdrop"
					aria-label="Close"
					on:click={() => (showTierSelect = false)}
				></button>
				<div class="modal-content main-menu-modal tier-modal">
					<button class="close-btn" on:click={() => (showTierSelect = false)}>❌</button>
					<h2>🎰 Cash Game</h2>
					<p class="cat-sub">
						Invest your Principal, grow it, Deposit — or VOID. Higher tiers put more on the table
						for a bigger Yield.
					</p>
					<div class="tier-grid">
						{#each cgMeta?.tiers ?? [] as t}
							<button
								class="tier-tile"
								class:locked={!t.unlocked}
								disabled={cgBusy || !t.unlocked || (cgMeta?.bank ?? 0) < t.buy_in}
								on:click={() => pickTier(t.tier)}
							>
								<span class="tt-label">{t.label}</span>
								<span class="tt-buyin">${t.buy_in.toLocaleString()} <small>principal</small></span>
								<span class="tt-meta">yield to +{Math.round(t.heat_cap - 100)}%</span>
								{#if !t.unlocked}<span class="tt-lock"
										>🔒 {t.tier === 'silver'
											? '3 Bronze deposits'
											: t.tier === 'gold'
												? '3 Silver deposits'
												: 'locked'}</span
									>
								{:else if (cgMeta?.bank ?? 0) < t.buy_in}<span class="tt-lock"
										>Need ${t.buy_in.toLocaleString()}</span
									>{/if}
							</button>
						{/each}
					</div>
					{#if (cgMeta?.best_run ?? 0) > 0}
						<p class="tier-stats">
							Best deposit <b>${cgMeta.best_run.toLocaleString()}</b> · best multiple
							<b>{((cgMeta.best_multiple_x100 ?? 0) / 100).toFixed(1)}×</b>
							· deposit streak <b>{cgMeta.run_streak ?? 0}</b>
						</p>
					{/if}
				</div>
			</div>
		{/if}

		<!-- ⚡ Blitz: tier select (timed run) -->
		{#if showBlitzTier}
			<div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Pick a Blitz tier">
				<button
					type="button"
					class="modal-backdrop"
					aria-label="Close"
					on:click={() => (showBlitzTier = false)}
				></button>
				<div class="modal-content main-menu-modal tier-modal">
					<button class="close-btn" on:click={() => (showBlitzTier = false)}>❌</button>
					<h2>⚡ Blitz</h2>
					<p class="cat-sub">
						Beat the clock. 45s to start — reveal costs 3s, a wrong guess costs 5s, each solve adds
						8s + a combo-boosted payout. Bank whatever you win.
					</p>
					<div class="tier-grid tier-grid-3">
						{#each bzMeta?.tiers ?? [] as t}
							<button
								class="tier-tile"
								disabled={bzBusy || !t.affordable}
								on:click={() => pickBlitzTier(t.tier)}
							>
								<span class="tt-label">{t.label}</span>
								<span class="tt-buyin">${t.buy_in.toLocaleString()} <small>buy-in</small></span>
								<span class="tt-meta">~${t.base}/solve × combo</span>
								{#if !t.affordable}<span class="tt-lock">Need ${t.buy_in.toLocaleString()}</span
									>{/if}
							</button>
						{/each}
					</div>
					{#if (bzMeta?.best_run ?? 0) > 0}
						<p class="tier-stats">
							Best run <b>{bzMeta.best_run}</b> solved · best combo
							<b>×{((bzMeta.best_combo_x100 ?? 100) / 100).toFixed(2)}</b>
							· biggest payout <b>${(bzMeta.best_payout ?? 0).toLocaleString()}</b>
						</p>
					{/if}
				</div>
			</div>
		{/if}

		<!-- Challenges: wager vs friends -->
		{#if showChallenges}
			<div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Challenge Friends">
				<button
					type="button"
					class="modal-backdrop"
					aria-label="Close"
					on:click={() => (showChallenges = false)}
				></button>
				<div class="modal-content main-menu-modal ch-modal">
					<button class="close-btn" on:click={() => (showChallenges = false)}>❌</button>

					<h2>⚔️ New Challenge</h2>
					<p class="cat-sub">
						Build a match — a pack of puzzles vs a friend or a group. Same puzzles for everyone.
					</p>

					<div class="ch-new">
						<!-- Opponent: friend or group -->
						<div class="ch-modes">
							<button
								type="button"
								class="ch-mode"
								class:active={mbTarget === 'friend'}
								on:click={() => (mbTarget = 'friend')}>👤 A friend<small>by username</small></button
							>
							<button
								type="button"
								class="ch-mode"
								class:active={mbTarget === 'group'}
								on:click={() => (mbTarget = 'group')}
								>👥 A group<small>everyone in it</small></button
							>
						</div>
						{#if mbTarget === 'friend'}
							<div class="ch-search-wrap">
								<input
									class="ch-input"
									placeholder="Opponent username"
									bind:value={mbOpponent}
									on:input={onMbOppInput}
									autocomplete="off"
								/>
								{#if mbResults.length}
									<div class="ch-results">
										{#each mbResults as r}
											<button
												type="button"
												class="ch-result-item"
												on:click={() => pickMbOpp(r.username)}
												>@{r.username}{#if r.is_friend}
													<span class="ch-friend-tag">friend</span>{/if}</button
											>
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
							<button
								type="button"
								class="ch-mode"
								class:active={mbMode === 'standard'}
								on:click={() => (mbMode = 'standard')}
								>🧠 Standard<small>efficiency · spend less</small></button
							>
							<button
								type="button"
								class="ch-mode"
								class:active={mbMode === 'blitz'}
								on:click={() => (mbMode = 'blitz')}
								>⚡ Blitz<small>timed · combo speed</small></button
							>
						</div>

						<!-- Categories (optional) -->
						<div class="ch-cats">
							{#each CATEGORIES as c}
								<button
									type="button"
									class="ch-cat"
									class:on={mbCategories.includes(c.value)}
									on:click={() => toggleCategory(c.value)}>{c.emoji}</button
								>
							{/each}
						</div>
						<p class="ch-hint">
							{mbCategories.length ? mbCategories.length + ' categories' : 'Any category'}
						</p>

						<!-- Pack size + payout + window -->
						<div class="ch-row">
							<label class="ch-field"
								><span>Puzzles</span>
								<select class="ch-input" bind:value={mbPackSize}
									>{#each [1, 3, 5, 10] as n}<option value={n}>{n}</option>{/each}</select
								>
							</label>
							<label class="ch-field"
								><span>Respond within</span>
								<select class="ch-input" bind:value={mbWindow}
									>{#each WINDOWS as w}<option value={w.s}>{w.l}</option>{/each}</select
								>
							</label>
						</div>
						<div class="ch-field ch-ante">
							<span>Ante — the stakes</span>
							<div class="ante-chips">
								{#each CHALLENGE_TIERS as t}
									<button
										class="ante-chip"
										class:on={mbWager === t.v}
										type="button"
										on:click={() => {
											mbWager = t.v;
											fx('tap');
										}}>{t.label}</button
									>
								{/each}
							</div>
							<p class="ch-hint">
								{mbWager > 0
									? 'Each player antes this → the pot. Duel: winner takes all. Group: podium (3 → 70/30 · 4+ → 60/30/10). Spend less to keep more — that’s your score.'
									: 'Friendly — no stakes, just bragging rights.'}
							</p>
						</div>
						<button
							class="ch-toggle"
							class:on={mbItemsAllowed}
							on:click={() => {
								mbItemsAllowed = !mbItemsAllowed;
								fx('tap');
							}}
						>
							<span class="ch-tog-box">{mbItemsAllowed ? '✓' : ''}</span>
							⚡ Allow power-ups
						</button>
						<p class="ch-objective"><strong>Spend the least — winner takes the pot.</strong></p>
						<button
							class="ch-create"
							disabled={mbBusy}
							on:click={submitNewMatch}
							style="width:100%;">Send challenge ⚔️</button
						>
						{#if mbMsg}<p class="add-msg">{mbMsg}</p>{/if}
					</div>
				</div>
			</div>
		{/if}

		<!-- Settled-challenge results (shared with /history) -->
		<MatchDetailModal detail={matchResults} on:close={() => (matchResults = null)} />

		<!-- 💸 Can't afford the full buy-in: play with what you have, or decline -->
		{#if shortMatch}
			<div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Not enough Cash">
				<button
					type="button"
					class="modal-backdrop"
					aria-label="Close"
					on:click={() => (shortMatch = null)}
				></button>
				<div class="modal-content sm-modal">
					<div class="sm-icon">💸</div>
					<h2>Not enough for the full buy-in</h2>
					<div class="sm-rows">
						<div class="sm-row">
							<span>This challenge</span><b>${Number(shortMatch.wager).toLocaleString()} buy-in</b>
						</div>
						<div class="sm-row">
							<span>You have</span><b>${Math.round(netWorth ?? 0).toLocaleString()}</b>
						</div>
					</div>
					<p class="sm-note">
						Your whole buy-in is at stake — winner takes the pot. Play with a smaller buy-in, or
						decline.
					</p>
					<button class="sm-play" disabled={mbBusy} on:click={() => playReduced(shortMatch)}
						>Play with ${Math.round(netWorth ?? 0).toLocaleString()}</button
					>
					<button class="sm-decline" disabled={mbBusy} on:click={() => declineChallenge(shortMatch)}
						>Decline challenge</button
					>
				</div>
			</div>
		{/if}

		<!-- Streak message (when Daily is disabled and user taps it) -->
		{#if showStreakMessage}
			<div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Come back tomorrow">
				<button
					type="button"
					class="modal-backdrop"
					aria-label="Close"
					on:click={() => (showStreakMessage = false)}
				></button>
				<div class="modal-content main-menu-modal">
					<button class="close-btn" on:click={() => (showStreakMessage = false)}>❌</button>
					<div class="cbt-medal">{dailyStatus?.last_daily_won ? '✅' : '🏁'}</div>
					<h2>{dailyStatus?.last_daily_won ? 'Daily Solved!' : "Today's Daily Done"}</h2>
					<p class="cbt-result">
						{dailyStatus?.last_daily_won
							? "Nice work — you've finished today's puzzle."
							: "You've already played today's puzzle."}
					</p>
					<div class="cbt-stats">
						<div class="cbt-stat">
							<span class="cbt-val">+${dailyStatus?.today_score?.toLocaleString() ?? 0}</span><span
								class="cbt-cap">Profit</span
							>
						</div>
						{#if (dailyStatus?.current_streak ?? 0) > 0}
							<div class="cbt-stat">
								<span class="cbt-val">🔥 {dailyStatus?.current_streak}</span><span class="cbt-cap"
									>Play streak</span
								>
							</div>
						{/if}
					</div>
					<p class="streak-message">
						{#if (dailyStatus?.current_streak ?? 0) > 0}Come back tomorrow for a new puzzle to keep
							your 🔥 {dailyStatus?.current_streak}-day streak alive!{:else}Come back tomorrow for a
							fresh puzzle and start a streak!{/if}
					</p>
					<button
						class="main-menu-btn"
						on:click={() => {
							showStreakMessage = false;
							goToDailyLeaderboard();
						}}>View Leaderboard</button
					>
					<button class="main-menu-btn ghost-btn" on:click={() => (showStreakMessage = false)}
						>Close</button
					>
				</div>
			</div>
		{/if}
		<!-- My Account modal -->
		{#if showMyAccount}
			<div class="modal-overlay" role="dialog" aria-modal="true" aria-label="My Account">
				<button
					type="button"
					class="modal-backdrop"
					aria-label="Close"
					on:click={() => (showMyAccount = false)}
				></button>
				<div class="modal-content main-menu-modal settings-modal">
					<button class="close-btn" on:click={() => (showMyAccount = false)}>❌</button>
					<h2>Settings</h2>

					<!-- Profile -->
					<div class="set-profile">
						<button
							class="set-av"
							on:click={() => {
								showMyAccount = false;
								goto('/avatar');
							}}
							aria-label="Edit avatar"
						>
							<Avatar config={myAvatar} fx size={68} />
							<span class="set-av-edit">Edit</span>
						</button>
						<div class="set-id">
							{#if maUsername && !maEditing}
								<div class="set-uname">
									@{maUsername}<button
										class="ma-edit"
										on:click={() => {
											maEditing = true;
											maInput = maUsername;
											maMsg = '';
										}}>edit</button
									>
								</div>
							{:else}
								<div class="set-uname-edit">
									<input
										class="ma-input"
										placeholder="pick a username"
										bind:value={maInput}
										maxlength="15"
										on:keydown={(e) => {
											if (e.key === 'Enter') saveMaUsername();
										}}
									/>
									<button class="ma-save" on:click={saveMaUsername}>Save</button>
								</div>
							{/if}
							{#if $user?.email}<div class="set-email">{$user.email}</div>{/if}
						</div>
					</div>
					{#if maMsg}<p class="ma-msg">{maMsg}</p>{/if}

					<!-- Preferences -->
					<div class="set-label">Preferences</div>
					<div class="set-group">
						<button
							class="set-row"
							on:click={() => {
								toggleSound();
								if ($soundEnabled) fx('select');
							}}
						>
							<span>🔊 Sound</span><span class="set-state" class:on={$soundEnabled}
								>{$soundEnabled ? 'On' : 'Off'}</span
							>
						</button>
						<button
							class="set-row"
							on:click={() => {
								toggleHaptics();
								if ($hapticsEnabled) fx('tap');
							}}
						>
							<span>📳 Haptics</span><span class="set-state" class:on={$hapticsEnabled}
								>{$hapticsEnabled ? 'On' : 'Off'}</span
							>
						</button>
						<button class="set-row" on:click={toggleMusic}>
							<span>🎵 Music</span><span class="set-state" class:on={$musicEnabled}
								>{$musicEnabled ? 'On' : 'Off'}</span
							>
						</button>
						{#if $musicEnabled}
							<div class="set-row sub">
								<span class="mmc-ic">🔈</span>
								<input
									class="mmc-slider"
									type="range"
									min="0"
									max="100"
									step="1"
									value={Math.round($musicVolume * 100)}
									on:input={(e) => setMusicVolume(Number(e.currentTarget.value) / 100)}
								/>
								<span class="mmc-pct">{Math.round($musicVolume * 100)}%</span>
							</div>
							{#if TRACKS.length > 1}
								<div class="set-row sub tracks">
									{#each TRACKS as t, i}<button
											class="ma-track"
											class:on={$currentTrackId === t.id}
											on:click={() => selectTrack(t.id)}>Track {i + 1}</button
										>{/each}
								</div>
							{/if}
						{/if}
					</div>

					<!-- Social -->
					<div class="set-label">Social</div>
					<div class="set-group">
						<button
							class="set-row nav"
							on:click={() => {
								showMyAccount = false;
								peopleTab = 'friends';
								openCommunity('people');
							}}><span>👋 Friends</span><span class="chev">›</span></button
						>
						<button
							class="set-row nav"
							on:click={() => {
								showMyAccount = false;
								peopleTab = 'groups';
								openCommunity('people');
							}}><span>👥 Groups</span><span class="chev">›</span></button
						>
					</div>

					<!-- Security -->
					{#if hasPin}
						<div class="set-label">Security</div>
						<div class="set-group">
							<button class="set-row nav" on:click={changePin}
								><span>🔑 Change PIN</span><span class="chev">›</span></button
							>
							<button class="set-row nav" on:click={forgotPin}
								><span>🔓 Forgot PIN?</span><span class="chev">›</span></button
							>
						</div>
					{/if}

					<!-- Help & Legal -->
					<div class="set-label">Help &amp; Legal</div>
					<div class="set-group">
						<button
							class="set-row nav"
							on:click={() => {
								showMyAccount = false;
								showTutorial = true;
							}}><span>❓ How to Play</span><span class="chev">›</span></button
						>
						<a class="set-row nav" href="/privacy" target="_blank" rel="noopener noreferrer"
							><span>🔒 Privacy Policy</span><span class="chev">↗</span></a
						>
						<a class="set-row nav" href="/terms" target="_blank" rel="noopener noreferrer"
							><span>📄 Terms of Service</span><span class="chev">↗</span></a
						>
						<a class="set-row nav" href={`mailto:${SUPPORT_EMAIL}`}
							><span>✉️ Contact Support</span><span class="chev">↗</span></a
						>
					</div>

					<!-- Account -->
					<div class="set-label">Account</div>
					<div class="set-group">
						<button
							class="set-row nav"
							on:click={() => {
								showMyAccount = false;
								handleLogout();
							}}><span>🚪 Log Out</span><span class="chev">›</span></button
						>
						<button
							class="set-row nav danger"
							on:click={() => {
								deleteInput = '';
								maMsg = '';
								showDeleteConfirm = true;
							}}><span>🗑️ Delete Account</span><span class="chev">›</span></button
						>
					</div>

					<p class="ma-version">WordBank v{APP_VERSION}</p>
				</div>
			</div>
		{/if}

		<!-- 🗑️ Delete-account confirmation — permanent, requires typing DELETE -->
		{#if showDeleteConfirm}
			<div
				class="modal-overlay danger-overlay"
				role="dialog"
				aria-modal="true"
				aria-label="Delete account"
			>
				<button
					type="button"
					class="modal-backdrop"
					aria-label="Cancel"
					on:click={() => {
						if (!deleteBusy) showDeleteConfirm = false;
					}}
				></button>
				<div class="info-card del-card" role="document">
					<div class="info-big">🗑️</div>
					<h3 class="info-title">Delete your account?</h3>
					<p class="del-body">
						This permanently erases your account, Cash, stats, streaks, badges and history. <b
							>It can't be undone.</b
						>
					</p>
					<input
						class="ma-input del-input"
						placeholder="Type DELETE to confirm"
						bind:value={deleteInput}
						autocomplete="off"
						autocapitalize="characters"
						spellcheck="false"
					/>
					<button
						class="main-menu-btn ma-danger"
						disabled={!deleteArmed || deleteBusy}
						on:click={confirmDeleteAccount}
					>
						{deleteBusy ? 'Deleting…' : 'Delete forever'}
					</button>
					<button
						class="main-menu-btn ghost-btn"
						disabled={deleteBusy}
						on:click={() => (showDeleteConfirm = false)}>Cancel</button
					>
				</div>
			</div>
		{/if}
	{:else}
		<!-- ✅ GAME UI (Visible only when logged in) -->

		<!-- 🧠 Game Logo -->
		<img class="game-logo" src="/wordmark.png" alt="WordBank" />

		<!-- 🏷️ Game-mode pill — same spot & style for every mode; tap to see the rules -->
		{#if $gameStore.currentPhrase && $gameStore.gameMode && modeLabel}
			<button
				class="mode-pill"
				title="How {modeLabel.name} works"
				on:click={() => {
					fx('tap');
					showObjectiveFor($gameStore.gameMode, true);
				}}
			>
				<span class="mp-emoji">{modeLabel.emoji}</span>{modeLabel.name}<span class="mp-info">ⓘ</span
				>
			</button>
		{/if}

		<!-- 💰 Bankroll — top of every mode. Challenge ante now lives in the bounty hero below. -->
		{#if $gameStore.currentPhrase && $gameStore.gameMode}
			{#if isBlitz && blitz && blitz.state !== 'ended'}
				<!-- ⚡ Blitz HUD: big countdown clock + combo + live winnings -->
				<div class="blitz-hud">
					<div class="bz-clock" class:danger={blitzSec <= 10}>
						⏱️ {blitzSec}<span class="bz-clock-s">s</span>
					</div>
					<div class="bz-row">
						<span class="bz-stat"
							><b class="bz-combo">×{((blitz.combo ?? 100) / 100).toFixed(2)}</b><small>combo</small
							></span
						>
						<span class="bz-stat"
							><b class="bz-win">${Math.round(blitz.winnings ?? 0).toLocaleString()}</b><small
								>winnings</small
							></span
						>
						<span class="bz-stat"><b>{blitz.solved ?? 0}</b><small>solved</small></span>
					</div>
					<button
						class="bz-skip"
						on:click={() => {
							fx('tap');
							blitzSkipPuzzle();
						}}>Skip (−3s, combo resets)</button
					>
				</div>
			{:else if !matchBlitz}
				{@const isDailyLike = $gameStore.gameMode === 'daily' || isMakeup}
				<button
					class="top-bank solo"
					class:pop-up={bankFlash === 'up'}
					class:pop-down={bankFlash === 'down'}
					title={isDailyLike ? 'Prize remaining — spend it, keep the rest' : 'Bank Account'}
					on:click={openBankModal}
				>
					{#if isMatch}<span class="tb-wallet-cap">👛 Wallet</span>{:else if isDailyLike}<span
							class="tb-wallet-cap">🏆 Prize</span
						>{:else if isClimb}<span class="tb-wallet-cap">Pending Deposit</span>{/if}
					<span class="tb-solo"
						>{#if isMatch}👛
						{:else if isClimb}{:else if !isDailyLike}💰
						{/if}${Math.round($tweenBank).toLocaleString()}</span
					>
				</button>
			{/if}
		{/if}

		<!-- 🔍 Diagnostic banner (shows when init failed) -->
		{#if initError}
			<div class="diagnostic-banner">
				<strong>⚠️ Diagnostic:</strong>
				{initError}
				<br />
				<small>Open DevTools (F12) → Console for details.</small>
				<button
					class="diagnostic-retry"
					on:click={() => {
						initError = null;
						location.reload();
					}}
				>
					Retry
				</button>
			</div>
		{:else if loggedIn && hasInitialized && !$gameStore.currentPhrase && !$gameWasRestored}
			<div class="diagnostic-banner info">
				Loading puzzle… If this persists, check Console (F12).
			</div>
		{/if}

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
				<span class="mb-text">{makeupLabel}</span>
			</div>
		{/if}

		<!-- 🎰 Cash Game (Climb) HUD — number-free so it feels random. Heat lives in the
         Solve-to-Earn box; power-ups live in the vault beside Solve. -->
		{#if isClimb && climb}
			{#if climb.must_guess && $gameStore.gameState !== 'won' && $gameStore.gameState !== 'lost'}
				<div class="climb-stuck">
					<span class="cs-text"
						>🎯 Cash Advance spent — guess now, or Deposit your Pending Deposit to bank it. A wrong
						guess VOIDs it.</span
					>
				</div>
			{/if}
			<!-- 🏦 Cash Out — bank the run bankroll anytime (the press-your-luck valve). -->
			{#if climb.state === 'active' && $gameStore.gameState !== 'won' && $gameStore.gameState !== 'lost'}
				{@const bankroll = Math.round(climb.bankroll ?? 0)}
				{@const profit = bankroll - Math.round(climb.buy_in ?? 0)}
				<button
					class="cashout-btn"
					class:up={profit > 0}
					disabled={cgBusy || bankroll <= 0}
					on:click={cashOut}
				>
					🏦 Deposit
				</button>
			{/if}
		{/if}

		<!-- ⚔️ Challenge match HUD -->
		{#if isMatch && matchInfo && !matchInfo.done}
			{#if matchBlitz}
				<div class="climb-hud">
					<div class="ch-cell">
						<span class="ch-val">{matchInfo.position}/{matchInfo.pack_size}</span><span
							class="ch-label">Puzzle</span
						>
					</div>
					<div class="ch-cell">
						<span class="ch-val ch-gold">{(matchInfo.total_score ?? 0).toLocaleString()}</span><span
							class="ch-label">Score</span
						>
					</div>
					<div class="ch-cell">
						<span class="ch-val">×{matchCombo}</span><span class="ch-label">Combo</span>
					</div>
					<div class="ch-cell" class:hot={matchRemaining <= 10}>
						<span class="ch-val">⏱️{matchRemaining}</span><span class="ch-label">Time</span>
					</div>
				</div>
			{:else}
				{#if matchInfo.pack_size > 1}<p class="match-pos">
						Puzzle {matchInfo.position}/{matchInfo.pack_size}
					</p>{/if}
				<StandingStrip standing={matchInfo.standing ?? null} />
			{/if}
			{#if (matchInfo.my_debuffs ?? []).length}
				<button
					type="button"
					class="debuff-banner"
					on:click={openDebuffInfo}
					title="Who hit you & what it does"
				>
					{(matchInfo.my_debuffs ?? [])
						.map((/** @type {string} */ d) => DEBUFF_LABEL[d] ?? d)
						.join(' · ')} <span class="db-info">ⓘ</span>
				</button>
			{/if}
			<!-- Power-ups & sabotage all live in the 🔐 vault beside Solve now. -->
		{/if}

		<!-- 🌍 Category + today's auto-applied Twist chip + witty clue -->
		<div class="puzzle-meta">
			{#if $gameStore.category}<span class="category-chip">{$gameStore.category}</span>{/if}
			{#if $gameStore.gameMode === 'daily' && dailyMod}
				<button
					class="twist-chip"
					title="Today's special — tap to see"
					on:click={() => {
						fx('tap');
						dailyInfo = 'twist';
					}}>{dailyMod.emoji}</button
				>
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
				<!-- Daily · Cash Game = the number you keep if you solve now. Challenge = ante left to spend (depletes). -->
				<div
					class="bounty-panel"
					class:loss={!isMatch && soloHero.net < 0}
					class:ante-empty={isMatch && matchLeft <= 0}
					class:count-pop={introCountPop}
				>
					<span class="bp-label"
						>{isMatch
							? matchLeft > 0
								? '👛 Wallet'
								: '👛 Wallet empty'
							: $gameStore.gameMode === 'daily'
								? "You'll bank"
								: soloHero.net >= 0
									? 'Potential Credit'
									: '⚠️ You’re losing money'}</span
					>
					<div class="bp-row">
						{#if $gameStore.gameMode === 'daily'}
							<button
								class="bp-mult-badge"
								title="How your multiplier works"
								on:click={() => {
									fx('tap');
									dailyInfo = 'mult';
								}}>×{Number($gameStore.bountyMult ?? 1).toFixed(1)}</button
							>
						{:else if isClimb}
							<button
								class="bp-mult-badge"
								title="Yield — your return rate, climbs with each solve"
								on:click={() => {
									fx('tap');
									climbInfo = 'heat';
								}}>📈 +{climbYield}%</button
							>
						{:else}
							<span class="bp-badge-spacer"></span>
						{/if}
						{#if $gameStore.gameMode === 'daily'}
							<button
								class="bp-amount bp-amount-btn"
								title="How this is calculated"
								on:click={() => {
									fx('tap');
									dailyInfo = 'bounty';
								}}
								>{$tweenNet >= 0 ? '$' : '−$'}{Math.abs(
									Math.round($tweenNet)
								).toLocaleString()}</button
							>
						{:else if isClimb}
							<button
								class="bp-amount bp-amount-btn"
								title="How this is calculated"
								on:click={() => {
									fx('tap');
									climbInfo = 'earn';
								}}
								>{$tweenNet >= 0 ? '$' : '−$'}{Math.abs(
									Math.round($tweenNet)
								).toLocaleString()}</button
							>
						{:else if isMatch}
							<button
								class="bp-amount bp-amount-btn"
								title="What is this?"
								on:click={() => {
									fx('tap');
									showAnteInfo = true;
								}}>${Math.max(0, Math.round($tweenNet)).toLocaleString()}</button
							>
						{:else}
							<span class="bp-amount"
								>{$tweenNet >= 0 ? '$' : '−$'}{Math.abs(
									Math.round($tweenNet)
								).toLocaleString()}</span
							>
						{/if}
						{#if $gameStore.gameMode === 'daily'}
							<button
								class="bp-winstreak"
								title="Win streak"
								on:click={() => {
									fx('tap');
									dailyInfo = 'streak';
								}}>🏆 {dailyStatus?.win_streak ?? 0}</button
							>
						{:else if isClimb}
							<button
								class="bp-winstreak"
								title="Deposit streak"
								on:click={() => {
									fx('tap');
									climbInfo = 'streak';
								}}>🏆 {climbStreak}</button
							>
						{:else}
							<span class="bp-badge-spacer"></span>
						{/if}
					</div>
					{#each spendFloaters as f (f.id)}<span class="spend-float">{f.text}</span>{/each}
				</div>
				{#if isMatch && matchLive}
					<div class="ante-bar">
						<span
							class="ante-fill"
							style="width:{(matchLive.budget ?? 0) > 0
								? Math.max(0, Math.min(100, (matchLeft / matchLive.budget) * 100))
								: 100}%"
						></span>
					</div>
				{/if}
				{#if isClimb && climbRun && climbRun.solves >= 2}
					<p class="climb-run-line" class:best={climbRunIsBest}>
						🔥 {climbRun.solves}-solve run ·
						<b class="run-profit" class:neg={climbRun.profit < 0}
							>{climbRun.profit >= 0 ? '+' : '−'}${Math.abs(climbRun.profit).toLocaleString()}</b
						>
						this run{#if climbRunIsBest}
							· 🏆 personal best{/if}
					</p>
				{/if}
			{/if}
		</section>

		<!-- 💥 Double or Nothing — Cash Game only, when heat ≥ ×1.5. Arm to double the payout. -->
		{#if isClimb && climb && $gameStore.gameState !== 'won'}
			{#if donAvailable}
				<button class="don-cta" on:click={openDon}>
					<span class="don-cta-title">💥 Double or Nothing</span>
					<span class="don-cta-sub">Solve for <b>${donTarget.toLocaleString()}</b> · all-in</span>
				</button>
			{:else if donArmed}
				<div class="don-armed" role="status">
					<span class="don-armed-title">💥 Doubled — all in</span>
					<span class="don-armed-sub">Solve for <b>${donTarget.toLocaleString()}</b></span>
				</div>
			{/if}
		{/if}

		<!-- 🎮 Solve / Cancel Buttons (Cash Game gets a vault to the left for power-ups) -->
		<section class="buttons-section">
			<GameButtons>
				<svelte:fragment slot="left">
					{#if isClimb && climb?.state === 'active'}
						<button
							class="solve-vault"
							on:click={openBag}
							title="Your power-ups"
							aria-label="Open your vault"
						>
							<img src="/vault.png" alt="" />
							{#if usableClimbPups > 0}<span class="solve-vault-badge">{usableClimbPups}</span>{/if}
						</button>
					{:else if isMatch && matchInfo?.items_allowed && !matchInfo?.done && gameActive}
						<button
							class="solve-vault"
							on:click={openBag}
							title="Your power-ups"
							aria-label="Open your vault"
						>
							<img src="/vault.png" alt="" />
							{#if usableMatchPups > 0}<span class="solve-vault-badge">{usableMatchPups}</span>{/if}
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
		{#if $gameStore.gameState === 'lost'}
			<div class="banner lose">{isClimb ? '⚠ VOID' : 'No luck'}</div>
		{/if}

		<!-- 🎯 Result Modal -->
		{#if showResultModal && ['won', 'lost'].includes($gameStore.gameState)}
			<div class="modal-overlay">
				<div class="modal-content result-modal">
					{#if isDailyResult && resultWon && dr}
						{@const mult = Number(dr.mult ?? $gameStore.bountyMult ?? 1)}
						{@const prize = Number(dr.base ?? 0)}
						{@const kept = Number(dr.kept ?? Math.max(0, prize - (dr.spent ?? 0)))}
						{@const banked = Number(
							dr.winnings ?? dr.banked ?? dr.reward ?? Math.round(kept * mult)
						)}
						<h2 class="win-h">🎉 Solved!</h2>
						<p class="result-sub">{todayLabel}</p>
						<!-- Prize − Spent = Kept ×mult = Banked -->
						<div class="win-math">
							<div class="wm-row"><span>🏆 Prize</span><b>${prize.toLocaleString()}</b></div>
							<div class="wm-row">
								<span>− Spent on letters</span><b class="neg"
									>−${(dr.spent ?? 0).toLocaleString()}</b
								>
							</div>
							<div class="wm-row"><span>= Kept</span><b>${kept.toLocaleString()}</b></div>
							{#if mult > 1}<div class="wm-row">
									<span>× Streak bonus</span><b>{fmtMult(mult)}</b>
								</div>{/if}
							<div class="wm-row total">
								<span>💰 Banked</span><b class="profit">+${banked.toLocaleString()}</b>
							</div>
						</div>
						{#if dailyMod}
							<p class="win-twist">
								{dailyMod.emoji} <b>{dailyMod.name}</b> — applied for everyone
							</p>
						{/if}
						<!-- bankroll scrolls to the new total -->
						<div class="win-bank">
							<span class="wb-label">💰 Your Cash</span>
							<span class="wb-amount">${Math.round($resultBankAnim).toLocaleString()}</span>
						</div>
						<p class="win-rank">
							{#if resultRank && resultRank.total > 0}<b>🏆 #{resultRank.rank}</b> of {resultRank.total.toLocaleString()}
								today{/if}
							{#if (dailyStatus?.win_streak ?? 0) > 0}
								· 🔥 {dailyStatus?.win_streak} win streak{/if}
						</p>
						<div class="result-actions">
							<button class="share-btn" on:click={handleShare}
								>{shareCopied ? '✓ Copied!' : 'Share'}</button
							>
							<button class="next-puzzle-button" on:click={goToDailyLeaderboard}>Leaderboard</button
							>
						</div>
						<button
							class="win-menu"
							on:click={() => {
								showResultModal = false;
								hasTriggeredModal = false;
								goToMainMenu();
							}}>Back to menu</button
						>
					{:else if isDailyResult}
						<div class="result-medal lose">😖</div>
						<h2>Busted</h2>
						<p class="result-sub">{todayLabel}</p>
						<div class="result-bankroll">
							<span class="rb-label">Your Cash</span>
							<span class="rb-amount">${resultBankroll.toLocaleString()}</span>
						</div>
						<p class="win-rank">
							No profit this time — your win streak resets. Come back tomorrow.
						</p>
						<div class="result-actions">
							<button class="share-btn" on:click={handleShare}
								>{shareCopied ? '✓ Copied!' : 'Share'}</button
							>
							<button class="next-puzzle-button" on:click={goToDailyLeaderboard}>Leaderboard</button
							>
						</div>
					{:else if isClimb && cashoutResult}
						<!-- 🧾 Cash-out receipt -->
						{@const co = cashoutResult}
						{@const prof = co.profit ?? 0}
						<div class="receipt">
							<div class="rcpt-brand">
								<img class="rcpt-coin" src="/logo-coin.png" alt="" width="40" height="40" />
								<img class="rcpt-mark" src="/wordmark.png" alt="WordBank" />
							</div>
							<div class="rcpt-title">DEPOSIT SLIP</div>
							<div class="rcpt-meta">
								{(co.tier ?? '').charAt(0).toUpperCase() + (co.tier ?? '').slice(1)} · {co.solves ??
									0} solve{co.solves === 1 ? '' : 's'}
							</div>
							<div class="rcpt-rule"></div>
							<div class="rcpt-line">
								<span>Pending Deposit</span><span>${(co.banked ?? 0).toLocaleString()}</span>
							</div>
							<div class="rcpt-line">
								<span>Principal</span><span class="neg">−${(co.buy_in ?? 0).toLocaleString()}</span>
							</div>
							<div class="rcpt-rule double"></div>
							<div class="rcpt-line total" class:profit={prof >= 0}>
								<span>NET {prof >= 0 ? 'PROFIT' : 'LOSS'}</span><span
									>{prof >= 0 ? '+' : '−'}${Math.abs(prof).toLocaleString()}</span
								>
							</div>
							<div class="rcpt-note">
								{((co.multiple_x100 ?? 0) / 100).toFixed(1)}× principal · peak yield +{Math.round(
									(co.heat ?? 100) - 100
								)}%
							</div>
							{#if co.phrase}
								<div class="rcpt-rule"></div>
								<div class="rcpt-line answer"><span>Answer</span><span>{co.phrase}</span></div>
							{/if}
							<div class="rcpt-foot">✓ Deposited to your Available Balance</div>
						</div>
						<div class="result-actions">
							<button
								class="share-btn"
								on:click={() => {
									cashoutResult = null;
									showResultModal = false;
									hasTriggeredModal = false;
									goToMainMenu();
								}}>Done</button
							>
							<button
								class="next-puzzle-button"
								on:click={() => {
									cashoutResult = null;
									showResultModal = false;
									hasTriggeredModal = false;
									handleMenuClimb();
								}}>New Run</button
							>
						</div>
					{:else if isClimb && resultWon}
						<!-- 🧾 Per-puzzle TRANSACTION slip -->
						{@const advance = Math.round(climb?.bounty ?? 0)}
						{@const letters = Math.round(climb?.spent ?? 0)}
						{@const subtotal = Math.max(0, advance - letters)}
						{@const payout = Math.round(climb?.last_gain ?? 0)}
						{@const yieldBonus = Math.max(0, payout - subtotal)}
						{@const yieldPct = Math.round((climb?.heat ?? 100) - 100)}
						{@const pendAfter = Math.round(climb?.bankroll ?? 0)}
						{@const pendBefore = pendAfter - payout}
						<div class="receipt">
							<div class="rcpt-brand">
								<img class="rcpt-coin" src="/logo-coin.png" alt="" width="40" height="40" />
								<img class="rcpt-mark" src="/wordmark.png" alt="WordBank" />
							</div>
							<div class="rcpt-title">TRANSACTION</div>
							<div class="rcpt-meta">
								{(climb?.tier ?? '').charAt(0).toUpperCase() + (climb?.tier ?? '').slice(1)} · Puzzle
								#{climb?.position ?? 1}
							</div>
							<div class="rcpt-rule"></div>
							<div class="rcpt-line">
								<span>Cash Advance</span><span>${advance.toLocaleString()}</span>
							</div>
							<div class="rcpt-line">
								<span>Letters (debit)</span><span class="neg">−${letters.toLocaleString()}</span>
							</div>
							<div class="rcpt-rule"></div>
							<div class="rcpt-line">
								<span>Subtotal</span><span>${subtotal.toLocaleString()}</span>
							</div>
							<div class="rcpt-line">
								<span>Yield +{yieldPct}%</span><span class="pos"
									>+${yieldBonus.toLocaleString()}</span
								>
							</div>
							<div class="rcpt-rule double"></div>
							<div class="rcpt-line total profit">
								<span>CREDIT</span><span>+${payout.toLocaleString()}</span>
							</div>
							<div class="rcpt-line">
								<span>Pending Deposit</span><span
									>${pendBefore.toLocaleString()} ▸ ${pendAfter.toLocaleString()}</span
								>
							</div>
						</div>
						<div class="result-actions">
							<button
								class="share-btn co-inline"
								disabled={cgBusy}
								on:click={() => {
									showResultModal = false;
									hasTriggeredModal = false;
									cashOut();
								}}>🏦 Deposit ${pendAfter.toLocaleString()}</button
							>
							<button
								class="next-puzzle-button"
								on:click={() => {
									showResultModal = false;
									hasTriggeredModal = false;
									climbAdvance().then(() => tick().then(playDailyIntroIfArmed));
								}}>Next →</button
							>
						</div>
					{:else if isClimb}
						<!-- 🧾 Wipe (VOID) receipt -->
						{@const wiped = Math.round(climb?.wiped ?? 0)}
						{@const ante = Math.round(climb?.buy_in ?? 0)}
						<div class="receipt void">
							<div class="rcpt-brand">
								<img class="rcpt-coin" src="/logo-coin.png" alt="" width="40" height="40" />
								<img class="rcpt-mark" src="/wordmark.png" alt="WordBank" />
							</div>
							<div class="rcpt-title void">⚠ VOID</div>
							<div class="rcpt-meta">Wrong guess</div>
							<div class="rcpt-rule"></div>
							{#if wiped > 0}
								<div class="rcpt-line">
									<span>Pending Deposit</span><span>${wiped.toLocaleString()}</span>
								</div>
								<div class="rcpt-line">
									<span>Wrong guess</span><span class="neg">−${wiped.toLocaleString()}</span>
								</div>
								<div class="rcpt-rule double"></div>
								<div class="rcpt-line total"><span>DEPOSIT VOIDED</span><span>$0</span></div>
							{/if}
							<div class="rcpt-line">
								<span>Principal lost</span><span class="neg">−${ante.toLocaleString()}</span>
							</div>
							<div class="rcpt-rule"></div>
							<div class="rcpt-line answer">
								<span>Answer</span><span>{$gameStore.currentPhrase}</span>
							</div>
							<div class="rcpt-foot">The Daily refills your Available Balance</div>
						</div>
						<div class="result-actions">
							<button
								class="share-btn"
								on:click={() => {
									showResultModal = false;
									hasTriggeredModal = false;
									goToMainMenu();
								}}>Leave</button
							>
							<button
								class="next-puzzle-button"
								on:click={() => {
									showResultModal = false;
									hasTriggeredModal = false;
									handleMenuClimb();
								}}>New Run</button
							>
						</div>
					{:else if isBlitz && blitzResult}
						<!-- ⚡ Blitz: time's up -->
						{@const br = blitzResult}
						<h2 class="win-h">⚡ Time!</h2>
						<p class="result-sub">
							{br.solved ?? 0} solved · best combo ×{((br.best_combo ?? 100) / 100).toFixed(2)}
						</p>
						<div class="win-math">
							<div class="wm-row">
								<span>Winnings</span><b>${(br.winnings ?? 0).toLocaleString()}</b>
							</div>
							<div class="wm-row">
								<span>− Buy-in</span><b class="neg">−${(br.buy_in ?? 0).toLocaleString()}</b>
							</div>
							<div class="wm-row total">
								<span>Net</span><b class="profit"
									>{(br.net ?? 0) >= 0 ? '+' : '−'}${Math.abs(br.net ?? 0).toLocaleString()}</b
								>
							</div>
						</div>
						<p class="win-twist">
							{(br.net ?? 0) >= 0
								? '🔥 You beat the clock — banked to your Cash.'
								: 'Whiffed the bet — the Daily always refills your Cash.'}
						</p>
						<div class="result-actions">
							<button
								class="share-btn"
								on:click={() => {
									blitzResult = null;
									showResultModal = false;
									hasTriggeredModal = false;
									goToMainMenu();
								}}>Done</button
							>
							<button
								class="next-puzzle-button"
								on:click={() => {
									blitzResult = null;
									showResultModal = false;
									hasTriggeredModal = false;
									handleMenuBlitz();
								}}>New Run</button
							>
						</div>
					{:else if isMatch}
						<!-- Challenge match: finished the whole pack -->
						<div class="result-medal">⚔️</div>
						<h2>Challenge complete!</h2>
						<p class="result-sub">
							{#if matchInfo?.mode === 'blitz'}You scored {(
									matchInfo?.total_score ?? 0
								).toLocaleString()} across {matchInfo?.pack_size} puzzle{matchInfo?.pack_size === 1
									? ''
									: 's'}{:else}You solved {matchInfo?.solved ?? 0}/{matchInfo?.pack_size} spending ${(
									matchInfo?.spent ?? 0
								).toLocaleString()}{/if}
						</p>
						<p class="arcade-gain">
							{matchInfo?.status === 'settled'
								? 'Settled — check the results.'
								: "Most Cash left wins — we'll settle once everyone plays."}
						</p>
						<div class="result-actions">
							{#if matchInfo?.status === 'settled'}
								<button
									class="share-btn"
									on:click={async () => {
										const id = matchInfo?.id;
										showResultModal = false;
										hasTriggeredModal = false;
										goToMainMenu();
										matchResults = { loading: true };
										matchResults = await getMatchDetail(id);
									}}>View Results</button
								>
							{:else}
								<button
									class="share-btn"
									on:click={() => {
										showResultModal = false;
										hasTriggeredModal = false;
										goToMainMenu();
										newChallenge();
									}}>Challenge Friends</button
								>
							{/if}
							<button
								class="next-puzzle-button"
								on:click={() => {
									showResultModal = false;
									hasTriggeredModal = false;
									goToMainMenu();
								}}>Menu</button
							>
						</div>
					{:else if isMakeup}
						<!-- Make-up daily result (calendar fill; no streak/Bank) -->
						{#if resultWon}
							<div class="result-medal">🗓️</div>
							<h2>Made it up!</h2>
							<p class="result-sub">
								{makeupLabel} is on your calendar · {$gameStore.currentPhrase}
							</p>
							<p class="arcade-gain">Counts toward 🗓️ Perfect Week / 📅 Perfect Month.</p>
						{:else}
							<div class="result-medal">💸</div>
							<h2>Out of Cash</h2>
							<p class="result-sub">The answer was {$gameStore.currentPhrase}</p>
						{/if}
						<div class="result-actions">
							<button
								class="share-btn"
								on:click={() => {
									showResultModal = false;
									hasTriggeredModal = false;
									goToMainMenu();
									goto('/streak');
								}}>Calendar</button
							>
							<button
								class="next-puzzle-button"
								on:click={() => {
									showResultModal = false;
									hasTriggeredModal = false;
									goToMainMenu();
								}}>Menu</button
							>
						</div>
					{:else if isChallenge}
						<!-- Challenge result (settles when the friend plays) -->
						<div class="result-medal">{resultWon ? (isPressure ? '⏱️' : '⚔️') : '⌛'}</div>
						<h2>{resultWon ? 'Challenge played!' : "Time's up!"}</h2>
						{#if resultWon}
							<p class="result-sub">
								You scored ${chScore.toLocaleString()} · {$gameStore.currentPhrase}
							</p>
							{#if isPressure}<p class="arcade-earn">
									Bankroll ${resultBankroll.toLocaleString()} + speed bonus
								</p>{/if}
						{:else}
							<p class="result-sub">Ran out of time — scored $0 · {$gameStore.currentPhrase}</p>
						{/if}
						<p class="arcade-gain">We'll settle the pot once your friend plays.</p>
						<div class="result-actions">
							<button
								class="share-btn"
								on:click={() => {
									showResultModal = false;
									hasTriggeredModal = false;
									goToMainMenu();
									newChallenge();
								}}>Challenge Friends</button
							>
							<button
								class="next-puzzle-button"
								on:click={() => {
									showResultModal = false;
									hasTriggeredModal = false;
									goToMainMenu();
								}}>Menu</button
							>
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
		position: fixed;
		top: 14px;
		left: 50%;
		transform: translateX(-50%);
		z-index: 2000;
		padding: 0.6rem 1.1rem;
		border-radius: 999px;
		cursor: pointer;
		font-family: var(--font-ui);
		font-size: 0.85rem;
		color: #3a2a00;
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
		border: none;
		box-shadow: var(--glow-brand, 0 8px 24px rgba(251, 191, 36, 0.4));
		animation: attDrop 0.4s var(--ease-spring, ease) both;
	}
	.attendance-toast strong {
		font-family: var(--font-display);
	}
	/* 🎰 Pure-solve ×1.5 multiplier fly-in */
	@keyframes attDrop {
		from {
			transform: translate(-50%, -60px);
			opacity: 0;
		}
		to {
			transform: translate(-50%, 0);
			opacity: 1;
		}
	}
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
		/* "safe center": center when content fits, but top-align when it's taller than the
       viewport (e.g. the menu) so the page doesn't load pre-scrolled and jump on nav. */
		justify-content: safe center;
	}

	.pressure-hud {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 2px;
		width: 100%;
		max-width: 360px;
		margin: 0 auto 14px;
		padding: 0.5rem 1rem;
		border: 1px solid rgba(251, 191, 36, 0.4);
		border-radius: 14px;
		background: linear-gradient(135deg, rgba(251, 191, 36, 0.12), rgba(251, 191, 36, 0.03));
	}
	.pressure-hud .ph-clock {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1.5rem;
		color: #fbbf24;
		line-height: 1;
		font-variant-numeric: tabular-nums;
	}
	.pressure-hud .ph-label {
		font-size: 0.72rem;
		color: var(--text-muted);
	}
	.pressure-hud.danger {
		border-color: rgba(248, 113, 113, 0.6);
		background: linear-gradient(135deg, rgba(248, 113, 113, 0.16), rgba(248, 113, 113, 0.04));
		animation: pressurePulse 1s ease-in-out infinite;
	}
	.pressure-hud.danger .ph-clock {
		color: #f87171;
	}
	@keyframes pressurePulse {
		0%,
		100% {
			box-shadow: 0 0 0 rgba(248, 113, 113, 0);
		}
		50% {
			box-shadow: 0 0 16px rgba(248, 113, 113, 0.35);
		}
	}
	.makeup-banner {
		display: flex;
		align-items: center;
		gap: 8px;
		justify-content: center;
		width: 100%;
		max-width: 360px;
		margin: 0 auto 12px;
		padding: 0.5rem 0.9rem;
		border: 1px solid rgba(56, 189, 248, 0.4);
		border-radius: 12px;
		background: linear-gradient(135deg, rgba(56, 189, 248, 0.12), rgba(56, 189, 248, 0.03));
	}
	.makeup-banner .mb-tag {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 0.8rem;
		color: #38bdf8;
		white-space: nowrap;
	}
	.makeup-banner .mb-text {
		font-size: 0.74rem;
		color: var(--text-muted);
	}
	/* Cash Game (Climb) HUD */
	.climb-hud {
		display: flex;
		gap: 8px;
		width: 100%;
		max-width: 360px;
		margin: 0 auto 12px;
	}
	.match-pos {
		text-align: center;
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.8rem;
		color: var(--text-muted);
		margin: 0 0 8px;
	}
	.ch-cell {
		flex: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 2px;
		padding: 10px 6px;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--r-md, 12px);
	}
	.ch-cell.hot {
		border-color: rgba(251, 191, 36, 0.5);
		background: linear-gradient(135deg, rgba(251, 191, 36, 0.14), rgba(251, 191, 36, 0.04));
	}
	.ch-val {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1.15rem;
		color: var(--text);
		font-variant-numeric: tabular-nums;
	}
	.ch-cell.hot .ch-val {
		color: #fbbf24;
	}
	.ch-gold {
		color: #fcd34d;
	}
	.ch-label {
		font-size: 0.55rem;
		letter-spacing: 0.14em;
		text-transform: uppercase;
		color: var(--text-faint);
		font-weight: 600;
	}

	.debuff-banner {
		display: block;
		text-align: center;
		font-size: 0.76rem;
		font-weight: 700;
		color: #fb7185;
		margin: 0 auto 8px;
		max-width: 340px;
		padding: 5px 10px;
		border-radius: 999px;
		cursor: pointer;
		background: rgba(251, 113, 133, 0.1);
		border: 1px solid rgba(251, 113, 133, 0.3);
	}
	.debuff-banner:active {
		transform: scale(0.97);
	}
	.db-info {
		opacity: 0.7;
		font-size: 0.7rem;
	}
	.debuff-row {
		align-items: flex-start;
	}
	.db-desc {
		display: block;
		font-size: 0.72rem;
		font-weight: 500;
		color: var(--text-muted);
		margin-top: 2px;
	}
	/* 😈 Sabotage target picker (in the bag flow) */
	.sab-target-list {
		display: flex;
		flex-direction: column;
		gap: 8px;
		margin: 4px 0 12px;
	}
	.sab-target-row {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: 10px;
		padding: 11px 14px;
		border-radius: 12px;
		cursor: pointer;
		background: rgba(244, 114, 182, 0.1);
		border: 1px solid rgba(244, 114, 182, 0.4);
		color: var(--text);
	}
	.sab-target-row:active {
		transform: scale(0.98);
	}
	.st-name {
		font-weight: 800;
		font-size: 0.95rem;
	}
	.st-stat {
		font-size: 0.82rem;
		color: #f9a8d4;
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}

	.climb-stuck {
		display: flex;
		flex-direction: column;
		gap: 8px;
		width: 100%;
		max-width: 360px;
		margin: 0 auto 12px;
		padding: 0.8rem;
		border: 1px solid rgba(248, 113, 113, 0.45);
		border-radius: 14px;
		background: rgba(248, 113, 113, 0.08);
		text-align: center;
	}
	.cs-text {
		font-size: 0.82rem;
		color: #fca5a5;
	}

	/* 🏦 Cash Out button (during a run) */
	.cashout-btn {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 8px;
		width: 100%;
		max-width: 360px;
		margin: 0 auto 12px;
		padding: 0.7rem 1rem;
		border-radius: 14px;
		cursor: pointer;
		border: 1px solid rgba(110, 231, 183, 0.5);
		background: linear-gradient(135deg, rgba(110, 231, 183, 0.14), rgba(52, 211, 153, 0.05));
		color: #6ee7b7;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1rem;
	}
	.cashout-btn.up {
		border-color: rgba(110, 231, 183, 0.8);
		box-shadow: 0 0 16px rgba(52, 211, 153, 0.25);
	}
	.cashout-btn:disabled {
		opacity: 0.45;
		cursor: default;
	}
	.co-inline {
		background: linear-gradient(135deg, #6ee7b7, #34d399) !important;
		color: #06281d !important;
	}
	/* 🎰 Cash Game tier select */
	.tier-modal {
		max-width: 460px;
	}
	.tier-grid {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 10px;
		margin: 4px 0 12px;
	}
	.tier-tile {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 3px;
		padding: 14px 10px;
		border-radius: 16px;
		background: var(--surface);
		border: 1px solid var(--border);
		color: var(--text);
		cursor: pointer;
		transition:
			transform 0.15s,
			border-color 0.2s;
	}
	.tier-tile:hover:not(:disabled) {
		transform: translateY(-2px);
		border-color: var(--brand-2);
	}
	.tier-tile:disabled {
		opacity: 0.5;
		cursor: default;
	}
	.tier-tile.locked {
		border-style: dashed;
	}
	.tt-label {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1.05rem;
	}
	.tt-buyin {
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		color: var(--brand-2);
		font-size: 1.1rem;
	}
	.tt-buyin small {
		font-family: var(--font-ui);
		font-weight: 500;
		font-size: 0.62rem;
		color: var(--text-faint);
	}
	.tt-meta {
		font-size: 0.66rem;
		color: var(--text-faint);
	}
	.tt-lock {
		font-size: 0.66rem;
		color: #fca5a5;
		margin-top: 2px;
	}
	.tier-stats {
		text-align: center;
		font-size: 0.78rem;
		color: var(--text-muted);
		margin: 0;
	}
	.tier-stats b {
		color: var(--brand-2);
	}
	.tier-grid-3 {
		grid-template-columns: repeat(3, 1fr);
	}
	/* ⚡ Blitz HUD */
	.blitz-hud {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 6px;
		width: 100%;
		max-width: 360px;
		margin: 0 auto 12px;
	}
	.bz-clock {
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		font-size: 2.6rem;
		line-height: 1;
		color: #fde047;
		font-variant-numeric: tabular-nums;
	}
	.bz-clock-s {
		font-size: 1.1rem;
		color: var(--text-faint);
		margin-left: 2px;
	}
	.bz-clock.danger {
		color: #fb7185;
		animation: pressurePulse 1s ease-in-out infinite;
	}
	.bz-row {
		display: flex;
		gap: 10px;
	}
	.bz-stat {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 0;
		padding: 5px 14px;
		border-radius: 12px;
		border: 1px solid var(--border);
		background: var(--surface);
	}
	.bz-stat b {
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		font-size: 1.05rem;
		color: var(--text);
	}
	.bz-stat small {
		font-size: 0.58rem;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--text-faint);
	}
	.bz-combo {
		color: #fbbf24 !important;
	}
	.bz-win {
		color: #6ee7b7 !important;
	}
	.bz-skip {
		padding: 0.4rem 0.9rem;
		border-radius: 999px;
		border: 1px solid var(--border);
		background: transparent;
		color: var(--text-muted);
		font-weight: 700;
		font-size: 0.74rem;
		cursor: pointer;
	}
	.bz-skip:hover {
		border-color: #fb7185;
		color: #fca5a5;
	}
	.arcade-gain {
		font-family: var(--font-display);
		font-weight: 700;
		color: var(--brand-2);
		margin: -8px 0 14px;
		font-size: 1rem;
	}
	.arcade-earn {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.95rem;
		color: #fcd34d;
		margin: 10px auto 0;
		padding: 7px 14px;
		background: rgba(251, 191, 36, 0.12);
		border: 1px solid rgba(251, 191, 36, 0.4);
		border-radius: 999px;
		display: inline-block;
	}
	.arcade-earn {
		font-family: var(--font-display);
		font-weight: 700;
		color: #fcd34d;
		margin: -6px 0 14px;
		font-size: 0.95rem;
		text-shadow: 0 0 14px rgba(251, 191, 36, 0.35);
	}

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
		background: rgba(253, 224, 71, 0.1);
		border: 1px solid rgba(253, 224, 71, 0.28);
		padding: 6px 13px;
		border-radius: var(--r-pill);
	}
	/* 🎁 today's auto-applied Twist chip (tap to see what it does) */
	.twist-chip {
		display: inline-grid;
		place-items: center;
		width: 32px;
		height: 32px;
		border-radius: 999px;
		cursor: pointer;
		border: 1px solid rgba(253, 224, 71, 0.55);
		background: rgba(251, 191, 36, 0.16);
		font-size: 1.1rem;
		line-height: 1;
		box-shadow: 0 0 10px rgba(251, 191, 36, 0.25);
	}
	.twist-chip:active {
		transform: scale(0.92);
	}
	/* ⓘ re-open the "How to win" card */
	.fold-bar {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 10px;
		flex-wrap: wrap;
		margin: 6px auto 2px;
	}
	.fold-bar.broke {
		padding: 8px 14px;
		border-radius: 12px;
		max-width: 340px;
		background: rgba(248, 113, 113, 0.12);
		border: 1px solid rgba(248, 113, 113, 0.5);
		animation: pressurePulse 1s ease-in-out infinite;
	}
	.fold-timer {
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		font-size: 1.25rem;
		color: #f87171;
	}
	.fold-warn {
		font-size: 0.76rem;
		color: #fca5a5;
		flex: 1 1 140px;
		text-align: left;
	}
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
		width: 100%;
		display: grid;
		grid-template-columns: 1fr auto 1fr;
		align-items: center;
		gap: 0.6rem;
		margin-bottom: 0.2rem;
	}
	.sub-head .sub-back {
		justify-self: start;
	}
	.sub-back {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		padding: 0.5rem 0.9rem;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: 12px;
		color: var(--text);
		font-weight: 700;
		font-size: 0.9rem;
		cursor: pointer;
		transition:
			transform 0.15s,
			border-color 0.2s,
			background 0.2s;
	}
	.sub-back:hover {
		transform: translateX(-2px);
		border-color: var(--border-strong);
		background: var(--surface-2);
	}
	.sub-title {
		font-family: var(--font-display);
		font-size: 1.15rem;
		font-weight: 800;
		text-align: center;
		grid-column: 2;
	}
	.sub-people {
		position: relative;
		justify-self: end;
		width: 40px;
		height: 40px;
		display: grid;
		place-items: center;
		font-size: 1.1rem;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: 12px;
		cursor: pointer;
	}
	.sub-people:hover {
		border-color: var(--brand-2);
	}
	/* Community hub tabs + body */
	.comm-tabs {
		display: flex;
		gap: 8px;
		width: 100%;
		margin: 12px 0 14px;
	}
	.comm-tab {
		flex: 1;
		padding: 9px 0;
		border-radius: 12px;
		border: 1px solid var(--border);
		background: var(--surface);
		color: var(--text-muted);
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.86rem;
		cursor: pointer;
	}
	.comm-tab.active {
		background: linear-gradient(135deg, #fde047, #f59e0b);
		color: #3a2a00;
		border-color: transparent;
	}
	/* Unread-count badges (Activity tab + Community card) */

	.comm-body {
		width: 100%;
	}

	/* Subtle "play with friends" nudge under the solo modes */
	/* Challenge A Friend — one on-brand gold pill, split by a divider into CTA + friends */
	.vs-cta-group {
		display: flex;
		width: 100%;
		margin-top: 8px;
		border-radius: 12px;
		overflow: hidden;
		box-shadow:
			0 3px 10px rgba(245, 158, 11, 0.3),
			inset 0 1px 0 rgba(255, 255, 255, 0.4);
	}
	.vs-main,
	.vs-people {
		border: none;
		cursor: pointer;
		color: #3a2a00;
		background: linear-gradient(135deg, #fde047, #f59e0b);
	}
	.vs-main {
		flex: 1;
		padding: 12px 14px 12px 72px;
		text-align: center; /* left pad offsets the people button so the label centers over the whole group */
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 0.94rem;
		letter-spacing: 0.01em;
	}
	.vs-main:hover {
		filter: brightness(1.05);
	}
	.vs-main:active {
		transform: scale(0.99);
	}

	.vs-people {
		position: relative;
		width: 58px;
		flex: none;
		display: grid;
		place-items: center;
		border-left: 1.5px solid rgba(120, 80, 0, 0.45);
	} /* just the vertical divider line */
	.vs-people:hover {
		filter: brightness(1.06);
	}
	.vs-people:active {
		transform: scale(0.97);
	}
	.vs-ppl {
		font-size: 1.35rem;
		line-height: 1;
	}
	.vs-ppl-plus {
		position: absolute;
		top: 7px;
		right: 9px;
		width: 14px;
		height: 14px;
		border-radius: 50%;
		background: #3a2a00;
		color: #fde047;
		font-weight: 900;
		font-size: 0.6rem;
		line-height: 1;
		display: grid;
		place-items: center;
		box-shadow: 0 1px 2px rgba(0, 0, 0, 0.4);
	}
	.ch-new-btn {
		width: 100%;
		margin-bottom: 12px;
		padding: 12px;
		border-radius: 14px;
		border: none;
		cursor: pointer;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 0.95rem;
		color: #3a2a00;
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
		box-shadow: 0 6px 18px rgba(251, 191, 36, 0.25);
	}
	.ch-new-btn:hover {
		filter: brightness(1.05);
	}
	/* Short-on-Cash sheet */
	.sm-modal {
		max-width: 360px;
		text-align: center;
	}
	.sm-icon {
		font-size: 2.4rem;
		margin-bottom: 6px;
	}
	.sm-modal h2 {
		font-family: var(--font-display);
		font-size: 1.2rem;
		margin: 0 0 14px;
	}
	.sm-rows {
		display: flex;
		flex-direction: column;
		gap: 6px;
		margin: 0 0 12px;
		padding: 12px 14px;
		border-radius: 14px;
		border: 1px solid var(--border);
		background: var(--surface);
	}
	.sm-row {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: 12px;
		font-size: 0.88rem;
		color: var(--text-muted);
	}
	.sm-row b {
		font-family: var(--font-display);
		color: var(--text);
	}
	.sm-note {
		font-size: 0.8rem;
		color: var(--text-faint);
		margin: 0 0 16px;
	}
	.sm-play {
		width: 100%;
		padding: 13px;
		border: none;
		border-radius: 14px;
		cursor: pointer;
		margin-bottom: 8px;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 0.98rem;
		color: #3a2a00;
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
		box-shadow: 0 6px 18px rgba(251, 191, 36, 0.25);
	}
	.sm-play:disabled {
		opacity: 0.5;
	}
	.sm-decline {
		width: 100%;
		padding: 11px;
		border-radius: 14px;
		cursor: pointer;
		border: 1px solid rgba(251, 113, 133, 0.4);
		background: transparent;
		color: #fb7185;
		font-weight: 700;
		font-size: 0.9rem;
	}
	.sm-decline:disabled {
		opacity: 0.5;
	}
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

	.hero-top .bank-chip {
		justify-self: center;
	}
	.hero-top .bell-ic {
		justify-self: start;
	}
	.bell-ic {
		position: relative;
		width: 42px;
		height: 42px;
		border-radius: 50%;
		display: grid;
		place-items: center;
		cursor: pointer;
		background: var(--surface, rgba(255, 255, 255, 0.05));
		border: 1px solid var(--border);
		font-size: 1.15rem;
		transition:
			transform 0.15s,
			border-color 0.2s;
	}
	.bell-ic:hover {
		transform: translateY(-1px);
		border-color: rgba(251, 191, 36, 0.5);
	}
	.bell-ic:active {
		transform: scale(0.94);
	}
	.account-ic {
		position: relative;
		justify-self: end;
		display: inline-grid;
		place-items: center;
		width: 54px;
		height: 54px;
		border-radius: 50%;
		background: var(--surface, rgba(255, 255, 255, 0.05));
		border: 1px solid var(--border);
		cursor: pointer;
		font-size: 1.7rem;
		transition:
			transform 0.15s,
			border-color 0.2s;
	}
	.account-ic:hover {
		transform: translateY(-1px);
		border-color: rgba(251, 191, 36, 0.5);
	}
	.account-ic.has-av {
		overflow: visible;
		padding: 0;
	}
	.account-ic.has-av :global(.wb-avatar) {
		width: 100%;
		height: 100%;
		border: none;
		border-radius: 50%;
		overflow: hidden;
	}
	/* My Account → avatar / edit-avatar entry */

	.account-ic:active {
		transform: scale(0.94);
	}
	/* unread notification count, off the top-right of the avatar */
	.account-count {
		position: absolute;
		top: -4px;
		right: -4px;
		display: grid;
		place-items: center;
		min-width: 19px;
		height: 19px;
		padding: 0 5px;
		border-radius: 999px;
		background: #f43f5e;
		color: #fff;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 0.68rem;
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
		text-shadow:
			0 0 10px rgba(251, 191, 36, 0.65),
			0 0 22px rgba(251, 191, 36, 0.35);
		box-shadow: inset 0 0 14px rgba(251, 191, 36, 0.1);
		cursor: pointer;
		transition:
			transform 0.15s,
			box-shadow 0.2s;
	}
	.bank-chip.in-debt {
		border-color: rgba(248, 113, 113, 0.55);
	}
	.bc-debt {
		font-family: var(--font-display);
		font-size: 0.72rem;
		font-weight: 800;
		letter-spacing: 0;
		color: #fb7185;
		text-shadow: none;
		padding-left: 6px;
		border-left: 1px solid rgba(248, 113, 113, 0.4);
	}
	.bank-chip:hover {
		transform: translateY(-1px);
	}
	.bank-chip:active {
		transform: scale(0.96);
	}
	.bank-chip .bc-coin {
		font-size: 1.1rem;
		text-shadow: none;
	}

	.menu-mark {
		width: min(46vw, 172px);
		aspect-ratio: 1;
		height: auto;
		object-fit: cover;
		border-radius: 50%;
		margin-bottom: 4px;
		box-shadow:
			0 0 26px rgba(251, 191, 36, 0.55),
			0 10px 44px rgba(251, 191, 36, 0.4);
	}
	/* Mario-style coin spin: flat horizontal flip (edge-on at 90°/270°) + a gentle bob */

	@keyframes coinSpin {
		0% {
			transform: translateY(0) rotateY(0deg);
		}
		25% {
			transform: translateY(-5px) rotateY(90deg);
		}
		50% {
			transform: translateY(-7px) rotateY(180deg);
		}
		75% {
			transform: translateY(-5px) rotateY(270deg);
		}
		100% {
			transform: translateY(0) rotateY(360deg);
		}
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
		background: linear-gradient(
			180deg,
			#fdfefe 0%,
			#e7ecf1 10%,
			#c4cdd7 50%,
			#9ba7b4 78%,
			#c1cad4 100%
		);
		border: 1px solid #8794a2;
		color: #b8860b;
		cursor: pointer;
		overflow: hidden;
		box-shadow:
			inset 0 0 0 1.5px rgba(255, 255, 255, 0.85),
			/* bright chrome inner edge */ inset 0 0 0 3.5px rgba(92, 106, 122, 0.28),
			/* groove → recessed brushed panel */ inset 0 2px 2px rgba(255, 255, 255, 0.9),
			/* top catch-light */ inset 0 -3px 6px rgba(70, 85, 100, 0.45),
			/* bottom depth */ 0 5px 12px rgba(0, 0, 0, 0.55),
			/* drop shadow */ 0 0 16px rgba(205, 222, 240, 0.25); /* soft glow */
		transition:
			transform 0.16s var(--ease-spring),
			box-shadow 0.2s,
			filter 0.2s;
	}
	/* glossy chrome sheen */
	.menu-card::before {
		content: '';
		position: absolute;
		inset: 0;
		border-radius: inherit;
		z-index: 0;
		pointer-events: none;
		background:
			linear-gradient(
				180deg,
				rgba(255, 255, 255, 0.7) 0%,
				rgba(255, 255, 255, 0.15) 14%,
				rgba(255, 255, 255, 0) 42%,
				rgba(255, 255, 255, 0.1) 100%
			),
			radial-gradient(130% 60% at 50% -10%, rgba(255, 255, 255, 0.55), rgba(255, 255, 255, 0) 60%);
		mix-blend-mode: screen;
	}
	/* moving shine streak */
	.menu-card::after {
		content: '';
		position: absolute;
		top: 0;
		bottom: 0;
		left: 0;
		width: 55%;
		background: linear-gradient(
			105deg,
			transparent 25%,
			rgba(255, 255, 255, 0.25) 42%,
			rgba(255, 255, 255, 0.95) 50%,
			rgba(255, 255, 255, 0.25) 58%,
			transparent 75%
		);
		transform: translateX(-180%) skewX(-12deg);
		animation: barShine 5s ease-in-out infinite;
		animation-delay: calc(var(--i, 0) * 0.45s);
		pointer-events: none;
	}
	@keyframes barShine {
		0%,
		58% {
			transform: translateX(-180%) skewX(-12deg);
		}
		78%,
		100% {
			transform: translateX(330%) skewX(-12deg);
		}
	}
	@media (hover: hover) and (pointer: fine) {
		.menu-card:hover:not(.disabled) {
			transform: translateY(-2px);
			filter: brightness(1.05);
			box-shadow:
				inset 0 0 0 1.5px rgba(255, 255, 255, 0.9),
				inset 0 0 0 3.5px rgba(92, 106, 122, 0.28),
				inset 0 -3px 6px rgba(70, 85, 100, 0.45),
				0 7px 16px rgba(0, 0, 0, 0.55),
				0 0 24px rgba(210, 225, 240, 0.4);
		}
	}

	.menu-card:focus-visible:not(.disabled) {
		outline: none;
		box-shadow:
			inset 0 0 0 1.5px rgba(255, 255, 255, 0.85),
			0 0 0 2px rgba(255, 240, 190, 0.9),
			0 0 22px rgba(255, 220, 110, 0.7),
			0 6px 14px rgba(0, 0, 0, 0.5);
	}
	.menu-card.primary {
		filter: brightness(1.04);
		box-shadow:
			inset 0 0 0 1.5px rgba(255, 255, 255, 0.9),
			inset 0 0 0 3.5px rgba(92, 106, 122, 0.28),
			inset 0 2px 2px rgba(255, 255, 255, 0.9),
			inset 0 -3px 6px rgba(70, 85, 100, 0.45),
			0 6px 14px rgba(0, 0, 0, 0.55),
			0 0 22px rgba(210, 225, 240, 0.4);
	}

	.mc-title {
		position: relative;
		z-index: 1;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1.2rem;
		letter-spacing: 0.02em;
		/* embossed gold to match the reference button */
		background: linear-gradient(180deg, #fff1a8 0%, #f6cd4d 38%, #dd9c1b 66%, #b3760b 100%);
		-webkit-background-clip: text;
		background-clip: text;
		-webkit-text-fill-color: transparent;
		color: transparent;
		text-shadow:
			0 1px 1px rgba(70, 44, 0, 0.45),
			0 0 1px rgba(120, 80, 0, 0.4);
	}
	.mc-stat {
		position: relative;
		z-index: 1;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 0.9rem;
		color: #b8860b;
	}
	/* notification badge — top-right corner of the bar */

	/* home "you've been challenged" banner */
	/* Home act-now banner: most-urgent item + optional "+N more" chip */

	@keyframes invitePulse {
		0%,
		100% {
			box-shadow: 0 0 16px rgba(251, 191, 36, 0.18);
		}
		50% {
			box-shadow: 0 0 30px rgba(251, 191, 36, 0.42);
		}
	}

	/* Empty state = subtle CTA, no pulse/glow */
	/* Daily status chip on the Play Now card */
	.daily-chip {
		font-size: 0.68rem;
		font-weight: 800;
		padding: 3px 9px;
		border-radius: 999px;
		white-space: nowrap;
		border: 1px solid var(--border);
		background: rgba(0, 0, 0, 0.25);
		color: var(--text);
	}
	/* 📅 / 🏆 streak chips on the Daily card */
	.mc-streak {
		position: absolute;
		top: 50%;
		transform: translateY(-50%);
		z-index: 1;
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		font-size: 0.82rem;
		color: #463413;
		text-shadow: 0 1px 0 rgba(255, 255, 255, 0.35);
	}
	.mc-streak.left {
		left: 13px;
	}
	.mc-streak.right {
		right: 13px;
	}
	.menu-card.done .mc-streak,
	.menu-card.resumable .mc-streak {
		color: rgba(255, 255, 255, 0.85);
		text-shadow: none;
	}
	/* solid fills so chips read clearly */
	.daily-chip.won {
		color: #052e16;
		border-color: rgba(22, 163, 74, 0.85);
		background: linear-gradient(135deg, #4ade80, #16a34a);
		box-shadow: 0 1px 6px rgba(22, 163, 74, 0.5);
	}
	.daily-chip.lost {
		color: #fff;
		border-color: rgba(225, 80, 100, 0.85);
		background: linear-gradient(135deg, #fb7185, #e11d48);
		box-shadow: 0 1px 6px rgba(225, 29, 72, 0.45);
		text-shadow: 0 1px 1px rgba(0, 0, 0, 0.25);
	}
	.daily-chip.prog {
		color: #fff;
		border-color: rgba(5, 150, 105, 0.85);
		background: linear-gradient(135deg, #34d399, #059669);
		box-shadow: 0 1px 6px rgba(5, 150, 105, 0.5);
		text-shadow: 0 1px 1px rgba(0, 0, 0, 0.25);
	}

	/* ✅ Completed Daily — grayed-out plate (no chrome shine), result chip shows the score */
	.menu-card.done {
		background: linear-gradient(180deg, #39414c 0%, #2b323b 100%);
		border-color: #49525e;
		box-shadow:
			inset 0 1px 0 rgba(255, 255, 255, 0.06),
			inset 0 -2px 4px rgba(0, 0, 0, 0.4),
			0 3px 8px rgba(0, 0, 0, 0.45);
	}
	.menu-card.done::before,
	.menu-card.done::after {
		display: none;
	} /* kill chrome sheen + shine streak */
	.menu-card.done .mc-title {
		background: linear-gradient(180deg, #aeb7c2, #7f8893);
		-webkit-background-clip: text;
		background-clip: text;
		-webkit-text-fill-color: transparent;
		color: transparent;
		text-shadow: none;
	}
	/* ▶ Resumable mode — clean green accent instead of the gold chrome */
	.menu-card.resumable {
		background: linear-gradient(180deg, #16352b 0%, #0f2a22 100%);
		border-color: rgba(16, 185, 129, 0.55);
		box-shadow:
			inset 0 1px 0 rgba(110, 231, 183, 0.18),
			inset 0 0 0 1px rgba(16, 185, 129, 0.25),
			0 4px 12px rgba(0, 0, 0, 0.5),
			0 0 16px rgba(16, 185, 129, 0.18);
	}
	.menu-card.resumable::before,
	.menu-card.resumable::after {
		display: none;
	}
	.menu-card.resumable .mc-title {
		background: linear-gradient(180deg, #d1fae5, #6ee7b7);
		-webkit-background-clip: text;
		background-clip: text;
		-webkit-text-fill-color: transparent;
		color: transparent;
		text-shadow: none;
	}
	/* 📅 Fresh Daily (not started today) — solid gold, "play me" */
	.menu-card.fresh {
		background: linear-gradient(135deg, #fde047, #f59e0b);
		border-color: transparent;
		box-shadow:
			0 4px 16px rgba(245, 158, 11, 0.45),
			0 0 24px rgba(251, 191, 36, 0.3);
	}
	.menu-card.fresh::before,
	.menu-card.fresh::after {
		display: none;
	}
	.menu-card.fresh .mc-title {
		color: #3a2a00;
		-webkit-text-fill-color: #3a2a00;
		background: none;
		text-shadow: none;
	}
	.menu-card.fresh .mc-streak {
		color: #5a4200;
		text-shadow: none;
	}
	/* ▶ Resume shortcut card (home menu) — green, mirrors the in-progress accent */
	/* ▸ slim "Continue" strip — lighter than the Play button, so it reads as a resume
     prompt rather than a second primary action. */
	.resume-strip {
		display: flex;
		align-items: center;
		gap: 9px;
		width: 100%;
		margin-bottom: 2px;
		padding: 9px 14px;
		border-radius: 12px;
		cursor: pointer;
		background: linear-gradient(180deg, rgba(16, 53, 43, 0.65), rgba(15, 42, 34, 0.65));
		border: 1px solid rgba(16, 185, 129, 0.4);
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.85rem;
		box-shadow: 0 2px 8px rgba(0, 0, 0, 0.3);
	}
	.resume-strip:hover {
		border-color: rgba(16, 185, 129, 0.65);
	}
	.resume-strip:active {
		transform: scale(0.99);
	}
	.debt-banner {
		display: flex;
		align-items: center;
		gap: 9px;
		width: 100%;
		margin-bottom: 2px;
		padding: 9px 14px;
		border-radius: 12px;
		cursor: pointer;
		background: linear-gradient(180deg, rgba(53, 16, 16, 0.7), rgba(42, 15, 15, 0.7));
		border: 1px solid rgba(248, 113, 113, 0.5);
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.82rem;
		box-shadow: 0 2px 8px rgba(0, 0, 0, 0.3);
	}
	.debt-banner:hover {
		border-color: rgba(248, 113, 113, 0.75);
	}
	.debt-banner:active {
		transform: scale(0.99);
	}
	.db-text {
		flex: 1;
		text-align: left;
		color: #fecaca;
		font-weight: 600;
	}
	.db-text b {
		color: #fb7185;
	}
	.db-go {
		color: rgba(251, 113, 133, 0.85);
	}
	.rs-dot {
		color: #34d399;
		font-size: 0.8rem;
	}
	.rs-label {
		flex: 1;
		text-align: left;
		color: #d1fae5;
	}
	.rs-go {
		color: rgba(110, 231, 183, 0.7);
	}
	.rs-count {
		min-width: 20px;
		height: 20px;
		padding: 0 6px;
		border-radius: 999px;
		display: grid;
		place-items: center;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 0.72rem;
		color: #0f2a22;
		background: #6ee7b7;
	}

	/* ▶ Resume menu modal */
	.resume-menu {
		text-align: left;
	}
	.rm-list {
		display: flex;
		flex-direction: column;
		gap: 8px;
		margin: 10px 0 4px;
	}
	.rm-row {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 12px 14px;
		border-radius: 12px;
		cursor: pointer;
		background: rgba(16, 185, 129, 0.1);
		border: 1px solid rgba(16, 185, 129, 0.4);
		color: var(--text);
	}
	.rm-row:active {
		transform: scale(0.98);
	}
	.rm-ic {
		font-size: 1.2rem;
	}
	.rm-label {
		flex: 1;
		font-weight: 800;
		font-size: 0.98rem;
	}
	.rm-arrow {
		color: #6ee7b7;
		font-size: 0.85rem;
	}

	/* Play accordion */

	/* per-mode accent so they pop on the dark background */

	/* utility footer (replaces the old floating icon cluster) */

	/* back-to-menu button on game/sub screens */
	/* ☰ hamburger main-menu (top-left) */
	.menu-back-btn {
		position: fixed;
		top: 14px;
		left: 14px;
		z-index: 1000;
		width: 38px;
		height: 38px;
		border-radius: 999px;
		cursor: pointer;
		display: grid;
		place-items: center;
		color: var(--text);
		background: var(--surface-strong, rgba(20, 28, 40, 0.85));
		border: 1px solid var(--border-strong, var(--border));
		backdrop-filter: blur(10px);
	}
	.menu-back-btn:hover {
		border-color: var(--brand-2);
		color: var(--brand-2);
	}
	.hamburger,
	.hamburger::before,
	.hamburger::after {
		content: '';
		display: block;
		width: 18px;
		height: 2px;
		border-radius: 2px;
		background: currentColor;
	}
	.hamburger {
		position: relative;
	}
	.hamburger::before {
		position: absolute;
		top: -6px;
		left: 0;
	}
	.hamburger::after {
		position: absolute;
		top: 6px;
		left: 0;
	}
	/* how-to-play (top-center) */
	.help-btn {
		position: fixed;
		top: 14px;
		left: 50%;
		transform: translateX(-50%);
		z-index: 1000;
		width: 38px;
		height: 38px;
		border-radius: 999px;
		cursor: pointer;
		font-weight: 800;
		font-size: 1.1rem;
		line-height: 1;
		display: grid;
		place-items: center;
		color: var(--text);
		background: var(--surface-strong, rgba(20, 28, 40, 0.85));
		border: 1px solid var(--border-strong, var(--border));
		backdrop-filter: blur(10px);
	}
	.help-btn:hover {
		border-color: var(--brand-2);
		color: var(--brand-2);
	}
	/* 🔊 in-game audio button — sits just right of the help button */
	.audio-btn {
		position: fixed;
		top: 14px;
		left: calc(50% + 46px);
		transform: translateX(-50%);
		z-index: 1000;
		width: 38px;
		height: 38px;
		border-radius: 999px;
		cursor: pointer;
		font-size: 1.05rem;
		line-height: 1;
		display: grid;
		place-items: center;
		color: var(--text);
		background: var(--surface-strong, rgba(20, 28, 40, 0.85));
		border: 1px solid var(--border-strong, var(--border));
		backdrop-filter: blur(10px);
	}
	.audio-btn:hover {
		border-color: var(--brand-2);
	}
	.audio-btn:active {
		transform: translateX(-50%) scale(0.92);
	}
	/* audio panel */
	.audio-panel {
		text-align: left;
	}
	.ap-rows {
		display: flex;
		flex-direction: column;
		gap: 8px;
		margin: 10px 0;
	}
	.ap-toggle {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: 10px;
		padding: 11px 14px;
		border-radius: 12px;
		cursor: pointer;
		font-weight: 700;
		font-size: 0.95rem;
		color: var(--text);
		background: var(--surface-2, rgba(255, 255, 255, 0.05));
		border: 1px solid var(--border);
	}
	.ap-toggle:active {
		transform: scale(0.98);
	}
	.ap-state {
		font-size: 0.8rem;
		font-weight: 800;
		color: var(--text-faint);
	}
	.ap-state.on {
		color: #4ade80;
	}
	.ma-tracks {
		display: flex;
		gap: 6px;
		margin-top: 8px;
	}
	.ma-track {
		flex: 1;
		padding: 8px 4px;
		border-radius: 10px;
		cursor: pointer;
		font-weight: 800;
		font-size: 0.8rem;
		color: var(--text-muted);
		background: var(--surface-2, rgba(255, 255, 255, 0.05));
		border: 1px solid var(--border);
	}
	.ma-track.on {
		color: #3a2a00;
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
		border-color: transparent;
	}
	/* 🏳️ give up (top-right) — red exit arrow */
	.giveup-btn {
		position: fixed;
		top: 14px;
		right: 14px;
		z-index: 1000;
		width: 38px;
		height: 38px;
		border-radius: 999px;
		cursor: pointer;
		font-size: 1.25rem;
		line-height: 1;
		font-weight: 800;
		display: grid;
		place-items: center;
		color: #f87171;
		background: var(--surface-strong, rgba(20, 28, 40, 0.85));
		border: 1px solid rgba(248, 113, 113, 0.5);
		backdrop-filter: blur(10px);
	}
	.giveup-btn:hover {
		border-color: #f87171;
		background: rgba(248, 113, 113, 0.16);
	}
	.giveup-btn:active {
		transform: scale(0.93);
	}
	/* match chat — sits just below the help button so they never overlap */
	.match-chat-btn {
		position: fixed;
		top: 60px;
		right: 14px;
		z-index: 1000;
		display: flex;
		align-items: center;
		gap: 5px;
		padding: 9px 14px;
		border-radius: 999px;
		cursor: pointer;
		font-size: 1.02rem;
		font-weight: 700;
		color: var(--text);
		background: var(--surface-strong, rgba(20, 28, 40, 0.9));
		border: 1px solid rgba(251, 191, 36, 0.5);
		backdrop-filter: blur(10px);
		box-shadow:
			0 2px 12px rgba(0, 0, 0, 0.4),
			0 0 12px rgba(251, 191, 36, 0.15);
	}
	.match-chat-btn:hover {
		border-color: var(--brand-2);
	}
	.match-chat-btn.unread {
		border-color: #f43f5e;
		animation: chatPulse 1.6s ease-in-out infinite;
	}
	@keyframes chatPulse {
		0%,
		100% {
			box-shadow:
				0 2px 12px rgba(0, 0, 0, 0.4),
				0 0 0 0 rgba(244, 63, 94, 0.5);
		}
		50% {
			box-shadow:
				0 2px 12px rgba(0, 0, 0, 0.4),
				0 0 0 6px rgba(244, 63, 94, 0);
		}
	}
	.mcb-label {
		font-family: var(--font-display);
		font-size: 0.84rem;
	}
	.mc-dot {
		position: absolute;
		top: 3px;
		right: 3px;
		width: 10px;
		height: 10px;
		border-radius: 999px;
		background: #f43f5e;
		box-shadow: 0 0 0 2px var(--bg, #0a0e14);
	}
	.welcome-modal {
		max-width: 380px;
		text-align: center;
	}
	.wc-coin {
		display: block;
		margin: 0 auto 0.5rem;
	}
	.wc-title {
		font-family: var(--font-display);
		font-size: 1.4rem;
		margin: 0 0 0.35rem;
	}
	.wc-sub {
		font-size: 0.92rem;
		color: var(--text-muted);
		margin: 0 0 1rem;
	}
	.wc-list {
		list-style: none;
		padding: 0;
		margin: 0 0 1.2rem;
		display: flex;
		flex-direction: column;
		gap: 0.55rem;
		text-align: left;
	}
	.wc-list li {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		font-size: 0.9rem;
		color: var(--text);
		background: var(--surface-2, rgba(255, 255, 255, 0.04));
		border: 1px solid var(--border);
		border-radius: 12px;
		padding: 0.6rem 0.8rem;
	}
	.wc-list li span {
		font-size: 1.15rem;
	}
	.wc-list b {
		color: #fde047;
	}
	.wc-btn {
		width: 100%;
		padding: 0.85rem;
		border-radius: 13px;
		border: none;
		cursor: pointer;
		font-weight: 800;
		font-size: 1rem;
		color: #3a2a00;
		background: linear-gradient(135deg, #fde047, #f59e0b);
	}
	.giveup-modal {
		max-width: 360px;
		text-align: center;
	}
	.gu-title {
		font-family: var(--font-display);
		font-size: 1.2rem;
		margin: 0 0 0.5rem;
	}
	.gu-text {
		font-size: 0.88rem;
		color: var(--text-muted);
		margin: 0 0 1.2rem;
		line-height: 1.4;
	}
	.gu-actions {
		display: flex;
		gap: 0.6rem;
	}
	.gu-actions button {
		flex: 1;
		padding: 0.75rem 0.7rem;
		border-radius: 12px;
		cursor: pointer;
		font-weight: 800;
		font-size: 0.9rem;
	}
	.gu-cancel {
		border: 1px solid var(--border-strong, var(--border));
		background: var(--surface-2, rgba(255, 255, 255, 0.05));
		color: var(--text);
	}
	.gu-confirm {
		border: none;
		background: rgba(248, 113, 113, 0.18);
		border: 1px solid rgba(248, 113, 113, 0.5);
		color: #fca5a5;
	}
	.gu-confirm:hover {
		background: rgba(248, 113, 113, 0.28);
	}
	/* 💥 Double or Nothing — high-stakes gold/amber accent (distinct from the red Skip/Give-up) */
	.don-modal .don-win {
		color: #fbbf24;
	}
	.don-modal .don-loss {
		color: #fca5a5;
	}
	.don-confirm {
		background: rgba(251, 191, 36, 0.16) !important;
		border: 1px solid rgba(251, 191, 36, 0.6) !important;
		color: #fcd34d !important;
	}
	.don-confirm:hover {
		background: rgba(251, 191, 36, 0.28) !important;
	}
	.don-confirm:disabled {
		opacity: 0.55;
		cursor: default;
	}
	/* CTA shown in the Cash Game when heat ≥ ×1.5 */
	.don-cta {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 2px;
		width: 100%;
		margin: 0 auto 0.5rem;
		padding: 0.6rem 0.9rem;
		border-radius: 14px;
		cursor: pointer;
		background: linear-gradient(180deg, rgba(251, 191, 36, 0.16), rgba(245, 158, 11, 0.1));
		border: 1px solid rgba(251, 191, 36, 0.55);
		color: #fcd34d;
		box-shadow: 0 0 18px rgba(251, 191, 36, 0.18);
		animation: donPulse 1.8s ease-in-out infinite;
	}
	.don-cta:active {
		transform: scale(0.98);
	}
	.don-cta-title {
		font-family: var(--font-display);
		font-weight: 900;
		font-size: 1rem;
		letter-spacing: 0.02em;
	}
	.don-cta-sub {
		font-size: 0.74rem;
		color: var(--text-muted);
	}
	.don-cta-sub b,
	.don-armed-sub b {
		color: #fbbf24;
	}
	/* 🔥 Cash Game run line — momentum under the money hero */
	.climb-run-line {
		margin: 0.35rem auto 0;
		text-align: center;
		font-size: 0.8rem;
		color: var(--text-muted);
	}
	.climb-run-line .run-profit {
		color: #4ade80;
	}
	.climb-run-line .run-profit.neg {
		color: #fca5a5;
	}
	.climb-run-line.best {
		color: #fcd34d;
	}
	@keyframes donPulse {
		0%,
		100% {
			box-shadow: 0 0 14px rgba(251, 191, 36, 0.16);
		}
		50% {
			box-shadow: 0 0 26px rgba(251, 191, 36, 0.36);
		}
	}
	/* Armed (committed) indicator */
	.don-armed {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 2px;
		width: 100%;
		margin: 0 auto 0.5rem;
		padding: 0.55rem 0.9rem;
		border-radius: 14px;
		background: rgba(251, 191, 36, 0.12);
		border: 1px solid rgba(251, 191, 36, 0.7);
	}
	.don-armed-title {
		font-family: var(--font-display);
		font-weight: 900;
		font-size: 0.95rem;
		color: #fcd34d;
	}
	.don-armed-sub {
		font-size: 0.74rem;
		color: var(--text-muted);
	}
	.chat-modal {
		max-width: 440px;
	}
	.chat-h {
		font-family: var(--font-display);
		font-size: 1.15rem;
		margin: 0 0 0.8rem;
	}
	.chat-msgs {
		display: flex;
		flex-direction: column;
		gap: 6px;
		height: 300px;
		overflow-y: auto;
		padding: 0.8rem;
		border-radius: 14px;
		border: 1px solid var(--border);
		background: var(--surface);
		text-align: left;
	}
	.chat-empty {
		color: var(--text-faint);
		font-size: 0.85rem;
		text-align: center;
		margin: auto;
	}
	.cmsg {
		max-width: 80%;
		align-self: flex-start;
		display: flex;
		flex-direction: column;
		gap: 1px;
		padding: 0.45rem 0.7rem;
		border-radius: 12px;
		background: var(--surface-2, rgba(255, 255, 255, 0.05));
		border: 1px solid var(--border);
	}
	.cmsg.mine {
		align-self: flex-end;
		background: rgba(253, 224, 71, 0.12);
		border-color: rgba(253, 224, 71, 0.3);
	}
	.cm-name {
		font-size: 0.66rem;
		font-weight: 700;
		color: var(--brand-2);
	}
	.cmsg.mine .cm-name {
		align-self: flex-end;
		color: var(--text-faint);
	}
	.cm-body {
		font-size: 0.88rem;
		color: var(--text);
		word-break: break-word;
	}
	.chat-input-row {
		display: flex;
		gap: 0.5rem;
		margin-top: 0.7rem;
	}
	.chat-input {
		flex: 1;
		min-width: 0;
		padding: 0.6rem 0.9rem;
		border-radius: 12px;
		border: 1px solid var(--border);
		background: var(--surface);
		color: var(--text);
		font-size: 0.95rem;
	}
	.chat-send {
		padding: 0.6rem 1.1rem;
		border: none;
		border-radius: 12px;
		cursor: pointer;
		font-weight: 700;
		color: #3a2a00;
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
	}
	.chat-send:disabled {
		opacity: 0.5;
	}
	/* notification bell */

	/* notifications panel */

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
		transition:
			transform 0.15s var(--ease-spring),
			filter 0.2s;
	}
	.main-menu-btn:hover {
		transform: translateY(-2px);
		filter: brightness(1.05);
	}
	.main-menu-btn.ghost-btn {
		background: var(--surface-2, rgba(255, 255, 255, 0.06));
		color: var(--text);
		border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.16));
		box-shadow: none;
	}
	.main-menu-modal {
		text-align: center;
	}
	.main-menu-modal .main-menu-btn {
		margin-top: 1rem;
	}

	.cat-sub {
		font-size: 0.85rem;
		color: var(--text-muted);
		margin: 0 0 16px;
	}

	/* Challenges modal */
	.ch-modal {
		max-width: 440px;
	}

	.ch-empty {
		color: var(--text-muted);
		font-size: 0.92rem;
		padding: 2rem 1rem;
	}
	.ch-empty b {
		color: var(--brand-2);
	}
	.ch-new {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		margin-bottom: 1rem;
	}
	.ch-modes {
		display: flex;
		gap: 0.5rem;
	}
	.ch-mode {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		align-items: flex-start;
		padding: 0.55rem 0.7rem;
		border-radius: 10px;
		cursor: pointer;
		text-align: left;
		border: 1px solid var(--border);
		background: var(--surface);
		color: var(--text);
		font-weight: 700;
		font-size: 0.9rem;
		transition:
			border-color 0.15s,
			background 0.15s;
	}
	.ch-mode small {
		font-weight: 500;
		font-size: 0.68rem;
		color: var(--text-muted);
	}
	.ch-mode.active {
		border-color: rgba(251, 191, 36, 0.6);
		background: linear-gradient(135deg, rgba(251, 191, 36, 0.14), rgba(251, 191, 36, 0.04));
		box-shadow: 0 0 12px rgba(251, 191, 36, 0.15);
	}
	.ch-search-wrap {
		position: relative;
		display: flex;
		flex-direction: column;
	}
	.ch-search-wrap .ch-input {
		width: 100%;
	}
	.ch-results {
		display: flex;
		flex-direction: column;
		gap: 2px;
		margin-top: 4px;
		border: 1px solid var(--border);
		border-radius: 10px;
		padding: 4px;
		background: var(--surface);
	}
	.ch-result-item {
		text-align: left;
		padding: 0.45rem 0.6rem;
		border: none;
		border-radius: 8px;
		cursor: pointer;
		background: none;
		color: var(--text);
		font-weight: 600;
		font-size: 0.9rem;
	}
	.ch-result-item:hover {
		background: rgba(255, 255, 255, 0.06);
	}
	.ch-friend-tag {
		font-size: 0.7rem;
		color: var(--brand-2);
		font-weight: 700;
	}
	.ch-row {
		display: flex;
		gap: 0.5rem;
	}
	.ch-input {
		flex: 1;
		min-width: 0;
		padding: 0.6rem 0.8rem;
		border-radius: 10px;
		border: 1px solid var(--border);
		background: var(--surface);
		color: var(--text);
		font-size: 0.9rem;
	}
	.ch-create {
		padding: 0.6rem 1rem;
		border: none;
		border-radius: 10px;
		cursor: pointer;
		font-weight: 700;
		color: #3a2a00;
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
	}
	.ch-create:disabled {
		opacity: 0.6;
	}
	.ch-objective {
		font-size: 0.74rem;
		line-height: 1.4;
		color: var(--text-muted);
		margin: 0 0 10px;
	}
	.ch-objective strong {
		color: var(--brand-2);
	}
	.ch-toggle {
		display: flex;
		align-items: center;
		gap: 8px;
		width: 100%;
		margin: 2px 0 10px;
		padding: 0;
		background: none;
		border: none;
		cursor: pointer;
		color: var(--text-muted);
		font-size: 0.8rem;
		text-align: left;
		font-weight: 600;
	}
	.ch-toggle.on {
		color: var(--brand-2);
	}
	.ch-tog-box {
		width: 20px;
		height: 20px;
		flex-shrink: 0;
		border-radius: 6px;
		display: grid;
		place-items: center;
		border: 1px solid var(--border);
		background: var(--surface-2, rgba(255, 255, 255, 0.04));
		color: #3a2a00;
		font-size: 0.75rem;
		font-weight: 800;
	}
	.ch-toggle.on .ch-tog-box {
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
		border-color: transparent;
	}
	.ch-cats {
		display: flex;
		flex-wrap: wrap;
		gap: 4px;
		justify-content: center;
	}
	.ch-cat {
		width: 34px;
		height: 34px;
		border-radius: 9px;
		cursor: pointer;
		font-size: 1rem;
		border: 1px solid var(--border);
		background: var(--surface);
		opacity: 0.5;
		transition:
			opacity 0.15s,
			border-color 0.15s;
	}
	.ch-cat.on {
		opacity: 1;
		border-color: rgba(253, 224, 71, 0.55);
		background: rgba(253, 224, 71, 0.08);
	}
	.ch-hint {
		font-size: 0.72rem;
		color: var(--text-faint);
		text-align: center;
		margin: 0;
	}
	.ch-field {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 3px;
		text-align: left;
		min-width: 0;
	}
	.ch-field > span {
		font-size: 0.72rem;
		color: var(--text-faint);
		font-weight: 700;
	}
	.ch-ante {
		margin-top: 0.2rem;
	}
	.ante-chips {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: 6px;
		margin: 4px 0 2px;
	}
	.ante-chip {
		padding: 0.55rem 0.3rem;
		border-radius: 11px;
		border: 1px solid var(--border);
		background: var(--surface);
		color: var(--text);
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.82rem;
		cursor: pointer;
		white-space: nowrap;
	}
	.ante-chip:hover {
		border-color: var(--brand-2);
	}
	.ante-chip.on {
		border-color: var(--brand-2);
		background: linear-gradient(135deg, rgba(251, 191, 36, 0.16), rgba(253, 224, 71, 0.05));
		color: var(--brand-2);
	}
	.ch-ante .ch-hint {
		text-align: left;
		margin-top: 4px;
		line-height: 1.4;
	}
	.ch-field > span {
		font-size: 0.62rem;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--text-faint);
		font-weight: 600;
	}
	.ch-play.ghost {
		color: var(--brand-2);
		background: transparent;
		border: 1px solid rgba(253, 224, 71, 0.4);
	}
	.ch-list {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		max-height: 280px;
		overflow-y: auto;
	}
	.ch-item {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.6rem;
		padding: 0.7rem 0.8rem;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: 12px;
	}
	.ch-info {
		display: flex;
		flex-direction: column;
		gap: 2px;
		text-align: left;
		min-width: 0;
	}
	.ch-vs {
		font-weight: 600;
		font-size: 0.9rem;
	}
	.ch-meta {
		font-size: 0.75rem;
		color: var(--text-faint);
	}
	.ch-play {
		padding: 0.45rem 0.9rem;
		border: none;
		border-radius: 999px;
		cursor: pointer;
		font-weight: 700;
		font-size: 0.85rem;
		color: #3a2a00;
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
	}
	.ch-play:disabled {
		opacity: 0.6;
	}
	.ch-waiting {
		font-size: 0.8rem;
		color: var(--text-faint);
	}

	/* Streak + freeze chips (My Account) */

	.streak-message {
		margin: 1rem 0 0 0;
		font-size: 1.05rem;
		color: var(--text-muted);
	}
	.cbt-medal {
		font-size: 2.6rem;
		line-height: 1;
		margin-bottom: 0.3rem;
	}
	.cbt-result {
		font-size: 0.95rem;
		color: var(--text-muted);
		margin: 0.2rem 0 0;
	}
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
	.cbt-val {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1.15rem;
		color: var(--brand-2);
	}
	.cbt-cap {
		font-size: 0.68rem;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--text-faint);
	}

	/* About: legal links + version + delete */

	.ma-version {
		text-align: center;
		font-size: 0.72rem;
		color: var(--text-faint);
		margin: 14px 0 2px;
	}
	/* ── Sectioned settings layout ── */
	.settings-modal {
		text-align: left;
	}
	.settings-modal > h2 {
		text-align: center;
	}
	.set-profile {
		display: flex;
		align-items: center;
		gap: 13px;
		margin: 6px 0 4px;
	}
	.set-av {
		position: relative;
		background: none;
		border: none;
		cursor: pointer;
		padding: 0;
		flex: none;
	}
	.set-av-edit {
		position: absolute;
		bottom: -4px;
		left: 50%;
		transform: translateX(-50%);
		font-size: 0.62rem;
		font-weight: 800;
		color: #3a2a00;
		background: var(--brand-2, #fde047);
		padding: 1px 7px;
		border-radius: 999px;
	}
	.set-id {
		display: flex;
		flex-direction: column;
		gap: 3px;
		min-width: 0;
		flex: 1;
	}
	.set-uname {
		display: flex;
		align-items: center;
		gap: 8px;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1.05rem;
		color: var(--text);
	}
	.set-uname-edit {
		display: flex;
		gap: 6px;
	}
	.set-email {
		font-size: 0.78rem;
		color: var(--text-faint);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.set-label {
		text-align: left;
		font-size: 0.7rem;
		font-weight: 800;
		letter-spacing: 0.09em;
		text-transform: uppercase;
		color: var(--text-faint);
		margin: 16px 0 7px;
		padding-left: 0.3rem;
	}
	.set-group {
		display: flex;
		flex-direction: column;
		border-radius: 14px;
		overflow: hidden;
		border: 1px solid var(--border);
		background: var(--surface);
	}
	.set-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 10px;
		width: 100%;
		padding: 13px 15px;
		background: none;
		border: none;
		border-bottom: 1px solid var(--border);
		cursor: pointer;
		color: var(--text);
		font-weight: 600;
		font-size: 0.95rem;
		text-align: left;
		text-decoration: none;
	}
	.set-group > :last-child {
		border-bottom: none;
	}
	.set-row:hover {
		background: rgba(255, 255, 255, 0.04);
	}
	.set-row.sub {
		cursor: default;
		padding: 11px 15px;
	}
	.set-row.sub:hover {
		background: none;
	}
	.set-row.sub.tracks {
		gap: 6px;
	}
	.set-row.sub .mmc-slider {
		flex: 1;
	}
	.set-row.danger {
		color: #f87171;
	}
	.set-state {
		font-size: 0.82rem;
		font-weight: 800;
		color: var(--text-faint);
	}
	.set-state.on {
		color: #4ade80;
	}
	.chev {
		color: var(--text-faint);
		font-weight: 700;
	}
	.main-menu-btn.ma-danger {
		background: rgba(248, 113, 113, 0.12);
		color: #f87171;
		border: 1px solid rgba(248, 113, 113, 0.5);
	}
	.main-menu-btn.ma-danger:hover {
		background: rgba(248, 113, 113, 0.2);
	}
	.main-menu-btn.ma-danger:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}
	.del-card {
		text-align: center;
		max-width: 360px;
	}
	.del-body {
		font-size: 0.9rem;
		line-height: 1.5;
		color: var(--text-muted);
		margin: 6px 0 14px;
	}
	.del-input {
		width: 100%;
		text-align: center;
		margin-bottom: 12px;
	}
	.danger-overlay {
		z-index: 4000;
	}

	.ma-music-ctl {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		margin: 0.4rem 0.2rem 0;
		padding: 0.3rem 0.2rem;
	}
	.mmc-ic {
		font-size: 0.95rem;
	}
	.mmc-slider {
		flex: 1;
		accent-color: #fbbf24;
		height: 4px;
		cursor: pointer;
	}
	.mmc-pct {
		font-size: 0.72rem;
		font-weight: 800;
		color: var(--text-muted);
		min-width: 34px;
		text-align: right;
	}

	.ma-edit {
		background: none;
		border: none;
		color: var(--text-faint);
		font-size: 0.8rem;
		cursor: pointer;
		text-decoration: underline;
	}
	.ma-input {
		padding: 0.5rem 0.8rem;
		border-radius: 10px;
		border: 1px solid var(--border);
		background: var(--surface);
		color: var(--text);
		font-size: 0.95rem;
		max-width: 180px;
	}
	.ma-save {
		padding: 0.5rem 1rem;
		border: none;
		border-radius: 10px;
		cursor: pointer;
		font-weight: 700;
		color: #3a2a00;
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
	}
	.ma-msg {
		text-align: center;
		font-size: 0.82rem;
		color: #f87171;
		margin: 0.2rem 0 0;
	}

	/* First-run username gate */
	.username-gate {
		z-index: 3000;
	}
	.claim-card {
		text-align: center;
		max-width: 360px;
	}
	.claim-coin {
		display: block;
		margin: 0 auto 0.4rem;
		filter: drop-shadow(0 6px 20px rgba(251, 191, 36, 0.4));
	}
	.claim-sub {
		color: var(--text-muted);
		font-size: 0.88rem;
		line-height: 1.45;
		margin: 0.4rem 0 1.1rem;
	}
	.claim-row {
		display: flex;
		align-items: center;
		gap: 4px;
		padding: 0 0.9rem;
		background: var(--surface);
		border: 1px solid rgba(251, 191, 36, 0.4);
		border-radius: 12px;
	}
	.claim-row:focus-within {
		border-color: #fde047;
	}
	.claim-at {
		font-family: var(--font-display);
		font-weight: 800;
		color: #fbbf24;
		font-size: 1.15rem;
	}
	.claim-input {
		flex: 1;
		min-width: 0;
		padding: 0.8rem 0.2rem;
		border: none;
		background: transparent;
		color: var(--text);
		font-size: 1.1rem;
		font-family: var(--font-display);
		font-weight: 700;
	}
	.claim-input:focus {
		outline: none;
	}
	.claim-msg {
		color: #f87171;
		font-size: 0.82rem;
		margin: 0.6rem 0 0;
	}
	.claim-btn {
		width: 100%;
		margin-top: 1rem;
		padding: 0.85rem;
		border: none;
		border-radius: 12px;
		cursor: pointer;
		font-weight: 800;
		font-size: 1rem;
		color: #3a2a00;
		background: linear-gradient(135deg, #fde047, #f59e0b);
	}
	.claim-btn:disabled {
		opacity: 0.5;
		cursor: default;
	}
	.claim-hint {
		color: var(--text-faint);
		font-size: 0.74rem;
		margin: 0.7rem 0 0;
	}

	@keyframes bankPulseUp {
		0%,
		100% {
			transform: scale(1);
			box-shadow:
				var(--shadow-md),
				inset 0 1px 0 rgba(255, 255, 255, 0.06);
		}
		40% {
			transform: scale(1.07);
			box-shadow:
				var(--shadow-md),
				0 0 30px rgba(253, 224, 71, 0.55);
		}
	}
	@keyframes bankPulseDown {
		0%,
		100% {
			transform: scale(1);
		}
		35% {
			transform: scale(0.96);
		}
	}

	@keyframes deltaFloatUp {
		0% {
			opacity: 0;
			transform: translateY(8px);
		}
		25% {
			opacity: 1;
		}
		100% {
			opacity: 0;
			transform: translateY(-28px);
		}
	}
	@keyframes deltaFloatDown {
		0% {
			opacity: 0;
			transform: translateY(-8px);
		}
		25% {
			opacity: 1;
		}
		100% {
			opacity: 0;
			transform: translateY(24px);
		}
	}

	@keyframes hotHandPop {
		0% {
			opacity: 0;
			transform: translateX(-50%) translateY(8px) scale(0.8);
		}
		18% {
			opacity: 1;
			transform: translateX(-50%) translateY(0) scale(1.05);
		}
		32% {
			transform: translateX(-50%) translateY(0) scale(1);
		}
		80% {
			opacity: 1;
		}
		100% {
			opacity: 0;
			transform: translateX(-50%) translateY(-22px) scale(1);
		}
	}

	/* Live "spent · profit" line (all modes) */

	/* Cash Game bounty panel: one hero number (what you keep) that ticks down as you spend */
	.bounty-panel {
		position: relative;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 2px;
		width: 100%;
		max-width: 340px;
		margin: 0 auto;
		padding: 14px 18px;
		border-radius: var(--r-lg, 18px);
		border: 1px solid rgba(253, 224, 71, 0.4);
		background: linear-gradient(135deg, rgba(251, 191, 36, 0.14), rgba(251, 191, 36, 0.04));
		box-shadow: 0 0 22px rgba(251, 191, 36, 0.16);
	}
	.bounty-panel.loss {
		border-color: rgba(251, 113, 133, 0.5);
		background: linear-gradient(135deg, rgba(251, 113, 133, 0.13), rgba(251, 113, 133, 0.03));
		box-shadow: none;
	}
	.bp-label {
		font-size: 0.7rem;
		font-weight: 700;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--brand-2);
	}
	.bounty-panel.loss .bp-label {
		color: #fb7185;
	}
	.bp-amount {
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		font-size: 2.3rem;
		line-height: 1.05;
		color: #4ade80;
		text-shadow: 0 0 18px rgba(52, 211, 153, 0.5);
		font-variant-numeric: tabular-nums;
		transition: color 0.2s;
	}
	.bp-amount-btn {
		background: none;
		border: none;
		padding: 0;
		cursor: pointer;
	}
	.bounty-panel.loss .bp-amount {
		color: #fb7185;
		text-shadow: none;
	}
	/* 🪙 Challenge ante: the bounty hero depletes as you spend; empties to a calm "out of ante" look */
	.bounty-panel.ante-empty {
		border-color: rgba(148, 163, 184, 0.4);
		background: linear-gradient(135deg, rgba(148, 163, 184, 0.12), rgba(148, 163, 184, 0.03));
		box-shadow: none;
	}
	.bounty-panel.ante-empty .bp-label,
	.bounty-panel.ante-empty .bp-amount {
		color: #cbd5e1;
		text-shadow: none;
	}
	.ante-bar {
		width: 100%;
		max-width: 240px;
		height: 7px;
		margin: 6px auto 0;
		border-radius: 999px;
		background: rgba(255, 255, 255, 0.1);
		overflow: hidden;
	}
	.ante-fill {
		display: block;
		height: 100%;
		border-radius: 999px;
		background: linear-gradient(90deg, #fbbf24, #fde047);
		transition: width 0.35s ease;
	}

	/* lit gold bounty multiplier badge (left of the bounty) — ×1.0 today, boostable later */
	/* badge · amount · badge row — a 3-col grid keeps the amount dead-centered and clear */
	.bp-row {
		display: grid;
		grid-template-columns: 1fr auto 1fr;
		align-items: center;
		width: 100%;
		gap: 8px;
		margin-top: 2px;
	}
	.bp-badge-spacer {
		display: block;
	}
	.bp-mult-badge {
		justify-self: start;
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		font-size: 0.9rem;
		line-height: 1;
		padding: 5px 9px;
		border-radius: 9px;
		color: #3a2a00;
		background: linear-gradient(135deg, #fff1a8, #f6cd4d 45%, #e0a312);
		border: 1px solid rgba(180, 130, 15, 0.95);
		cursor: pointer;
		box-shadow:
			0 0 14px rgba(251, 191, 36, 0.65),
			inset 0 1px 0 rgba(255, 255, 255, 0.6),
			inset 0 -2px 3px rgba(120, 80, 0, 0.35);
	}
	.bp-mult-badge:active {
		transform: scale(0.94);
	}
	/* 🏆 win streak — mirror of the multiplier badge, on the right of the bounty (boosts mult) */
	.bp-winstreak {
		justify-self: end;
		cursor: pointer;
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		font-size: 0.9rem;
		line-height: 1;
		padding: 5px 9px;
		border-radius: 9px;
		color: #3a2a00;
		background: linear-gradient(135deg, #fff1a8, #f6cd4d 45%, #e0a312);
		border: 1px solid rgba(180, 130, 15, 0.95);
		box-shadow:
			0 0 12px rgba(251, 191, 36, 0.5),
			inset 0 1px 0 rgba(255, 255, 255, 0.5);
	}
	.bp-winstreak:active {
		transform: scale(0.94);
	}
	/* ℹ️ Daily explainer modal (multiplier / Solve-to-Earn breakdown) */
	.info-overlay {
		border: none;
		cursor: pointer;
	}
	.info-card {
		position: relative;
		width: 100%;
		max-width: 330px;
		cursor: default;
		text-align: center;
		background: var(--surface-strong, #141c28);
		border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.14));
		border-radius: 18px;
		padding: 22px 20px;
		box-shadow: 0 20px 60px rgba(0, 0, 0, 0.6);
	}
	/* reusable red close ✕ (top-right) — returns to the game */
	.modal-x {
		position: absolute;
		top: 10px;
		right: 10px;
		z-index: 2;
		width: 30px;
		height: 30px;
		border-radius: 50%;
		display: grid;
		place-items: center;
		cursor: pointer;
		font-size: 0.8rem;
		font-weight: 900;
		color: #fff;
		background: linear-gradient(135deg, #fb5a5a, #c81e1e);
		border: 1px solid rgba(0, 0, 0, 0.25);
		box-shadow: 0 2px 6px rgba(200, 30, 30, 0.4);
	}
	.modal-x:hover {
		filter: brightness(1.08);
	}
	.modal-x:active {
		transform: scale(0.92);
	}
	/* 🎒 Bag button left of Solve (in-game) */

	/* 🔐 Cash Game vault — sits to the left of Solve; absolute so Solve stays centered */
	.solve-vault {
		position: absolute;
		right: 100%;
		margin-right: 12px;
		top: 50%;
		transform: translateY(-50%);
		width: 50px;
		height: 50px;
		border-radius: 14px;
		display: grid;
		place-items: center;
		cursor: pointer;
		background: var(--surface-strong, rgba(20, 28, 40, 0.9));
		border: 1px solid rgba(253, 224, 71, 0.5);
		backdrop-filter: blur(10px);
		box-shadow: 0 4px 12px rgba(0, 0, 0, 0.4);
		transition: transform 0.16s var(--ease-spring);
	}
	.solve-vault:active {
		transform: translateY(-50%) scale(0.93);
	}
	.solve-vault img {
		width: 34px;
		height: 34px;
		object-fit: contain;
	}
	.solve-vault-badge {
		position: absolute;
		top: -6px;
		right: -6px;
		min-width: 18px;
		height: 18px;
		padding: 0 4px;
		border-radius: 999px;
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
		color: #3a2a00;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 0.66rem;
		display: grid;
		place-items: center;
	}

	.vault-ic-xs {
		width: 22px;
		height: 22px;
		object-fit: contain;
		vertical-align: -5px;
	}
	/* 🎒 Bag modal */
	.bag-modal {
		max-width: 360px;
		max-height: 84vh;
		overflow-y: auto;
	}
	.bag-use-h {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.78rem;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--brand-2);
		margin: 6px 0 8px;
		text-align: left;
	}
	.bag-use-grid {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 8px;
		margin-bottom: 16px;
	}
	.bag-use {
		position: relative;
		display: flex;
		flex-direction: column;
		align-items: center;
		text-align: center;
		gap: 3px;
		cursor: pointer;
		padding: 0.9rem 0.5rem;
		border-radius: 14px;
		color: var(--text);
		background: linear-gradient(135deg, rgba(251, 191, 36, 0.2), rgba(251, 191, 36, 0.05));
		border: 1px solid rgba(253, 224, 71, 0.55);
	}
	.bag-use:active {
		transform: scale(0.96);
	}
	.bag-use:disabled {
		opacity: 0.5;
		cursor: default;
	}
	.bag-use.locked {
		background: var(--surface);
		border: 1px solid var(--border);
		filter: grayscale(0.7);
	}
	.bag-use.locked .bag-use-e {
		opacity: 0.55;
	}
	.bag-use.locked .bag-use-d {
		color: var(--text-faint);
	}
	.bag-msg {
		margin-top: 12px;
		padding: 10px 12px;
		border-radius: 11px;
		text-align: center;
		font-size: 0.82rem;
		line-height: 1.35;
		color: var(--text);
		background: rgba(251, 191, 36, 0.14);
		border: 1px solid rgba(253, 224, 71, 0.45);
	}
	.bag-use-e {
		font-size: 1.7rem;
		line-height: 1;
	}
	.bag-use-n {
		position: absolute;
		top: 7px;
		right: 9px;
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		font-size: 0.78rem;
		color: #fde047;
	}
	.bag-use-name {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.86rem;
	}
	.bag-use-d {
		font-size: 0.72rem;
		color: var(--text-muted);
		line-height: 1.3;
	}
	.bag-inv {
		margin-bottom: 14px;
	}
	.bag-store {
		width: 100%;
		padding: 11px;
		border-radius: 12px;
		border: none;
		cursor: pointer;
		font-family: var(--font-display);
		font-weight: 800;
		color: #3a2a00;
		background: linear-gradient(135deg, #fde047, #f59e0b);
	}
	/* in-game bank modal */
	.bm-label {
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--text-faint);
		margin: 0 0 2px;
	}
	.bm-hist-h {
		font-family: var(--font-display);
		font-size: 0.78rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--brand-2);
		text-align: left;
		margin: 16px 0 6px;
	}
	.bm-ledger {
		display: flex;
		flex-direction: column;
		gap: 1px;
		background: var(--border);
		border-radius: 12px;
		overflow: hidden;
		max-height: 40vh;
		overflow-y: auto;
		margin-bottom: 14px;
	}
	.bm-row {
		display: flex;
		justify-content: space-between;
		gap: 10px;
		padding: 9px 11px;
		background: var(--surface);
	}
	.bm-fullledger {
		display: block;
		width: 100%;
		margin: -6px 0 12px;
		padding: 4px;
		background: none;
		border: none;
		color: var(--brand-2);
		font-size: 0.82rem;
		font-weight: 700;
		cursor: pointer;
		text-align: center;
	}
	.bm-reason {
		color: var(--text-muted);
		font-size: 0.84rem;
		text-align: left;
	}
	.bm-delta {
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		font-size: 0.84rem;
		font-variant-numeric: tabular-nums;
	}
	.bm-delta.pos {
		color: #4ade80;
	}
	.bm-delta.neg {
		color: #fb7185;
	}
	.info-big {
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		font-size: 2.6rem;
		line-height: 1;
		color: #fde047;
		text-shadow: 0 0 22px rgba(251, 191, 36, 0.5);
	}
	.info-big.green {
		color: #4ade80;
		text-shadow: 0 0 22px rgba(74, 222, 128, 0.45);
	}
	.info-title {
		font-family: var(--font-display);
		font-size: 1.15rem;
		margin: 8px 0 2px;
	}
	.info-sub {
		font-size: 0.84rem;
		color: var(--text-muted);
		margin: 0 0 14px;
	}
	.info-rows {
		display: flex;
		flex-direction: column;
		gap: 7px;
		text-align: left;
		margin-bottom: 14px;
	}
	.info-row {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: 10px;
		font-size: 0.88rem;
		color: var(--text);
	}
	.info-row b {
		font-family: 'Orbitron', var(--font-display);
		font-variant-numeric: tabular-nums;
	}
	.info-row .pos {
		color: #4ade80;
	}
	.info-row .neg {
		color: #fb7185;
	}
	.info-row .green {
		color: #4ade80;
	}
	.info-row.total {
		border-top: 1px solid var(--border);
		padding-top: 8px;
		margin-top: 2px;
		font-weight: 700;
	}
	.info-note {
		font-size: 0.76rem;
		color: var(--text-faint);
		line-height: 1.45;
		margin: 0 0 16px;
	}
	.info-twist-do {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1.02rem;
		color: #4ade80;
		margin: 0 0 14px;
	}
	/* 🎁 Twist announcement during the opening reveal */
	.twist-announce {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 3px;
		text-align: center;
		margin: 2px auto 6px;
		animation: twistAnnounceIn 0.5s cubic-bezier(0.34, 1.56, 0.64, 1);
	}
	.ta-label {
		font-size: 0.66rem;
		letter-spacing: 0.14em;
		text-transform: uppercase;
		color: var(--brand-2);
	}
	.ta-name {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1.35rem;
		color: #fde047;
		text-shadow: 0 0 16px rgba(251, 191, 36, 0.5);
	}
	.ta-blurb {
		font-size: 0.78rem;
		color: var(--text-muted);
	}
	@keyframes twistAnnounceIn {
		0% {
			opacity: 0;
			transform: translateY(-10px) scale(0.9);
		}
		100% {
			opacity: 1;
			transform: none;
		}
	}
	.info-note b {
		color: var(--brand-2);
	}
	.info-inline {
		background: none;
		border: none;
		padding: 0;
		color: var(--brand-2);
		font: inherit;
		font-weight: 700;
		text-decoration: underline;
		cursor: pointer;
	}
	.info-close {
		width: 100%;
		padding: 11px;
		border-radius: 12px;
		border: none;
		cursor: pointer;
		font-family: var(--font-display);
		font-weight: 800;
		color: #3a2a00;
		background: linear-gradient(135deg, #fde047, #f59e0b);
	}
	/* 🎰 Opening-reveal climax: bounty number pops + glows as it counts up */
	.bounty-panel.count-pop {
		animation: bountyGlow 1.1s ease-out;
	}
	.bounty-panel.count-pop .bp-amount {
		animation: bountyCount 1.1s cubic-bezier(0.34, 1.56, 0.64, 1);
	}
	@keyframes bountyGlow {
		0% {
			box-shadow: 0 0 22px rgba(251, 191, 36, 0.16);
		}
		35% {
			box-shadow:
				0 0 16px 4px rgba(74, 222, 128, 0.6),
				0 0 40px rgba(74, 222, 128, 0.4);
			border-color: rgba(74, 222, 128, 0.7);
		}
		100% {
			box-shadow: 0 0 22px rgba(251, 191, 36, 0.16);
		}
	}
	@keyframes bountyCount {
		0% {
			transform: scale(0.7);
			opacity: 0.5;
		}
		45% {
			transform: scale(1.32);
			text-shadow: 0 0 30px rgba(74, 222, 128, 0.95);
		}
		100% {
			transform: scale(1);
		}
	}
	/* floating -$X spend feedback by the green number */
	.spend-float {
		position: absolute;
		right: 16px;
		top: 8px;
		pointer-events: none;
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		font-size: 1.05rem;
		color: #fb7185;
		text-shadow: 0 0 8px rgba(248, 113, 133, 0.55);
		animation: spendFloat 1.1s ease-out forwards;
	}
	@keyframes spendFloat {
		0% {
			opacity: 0;
			transform: translateY(8px) scale(0.9);
		}
		16% {
			opacity: 1;
			transform: translateY(0) scale(1.06);
		}
		100% {
			opacity: 0;
			transform: translateY(-28px) scale(1);
		}
	}
	/* 💰 Top bankroll bar (very top, all modes) */
	.top-bank {
		width: 100%;
		max-width: 340px;
		margin: 0 auto 12px;
		padding: 9px 16px;
		border-radius: 14px;
		border: 1px solid rgba(253, 224, 71, 0.4);
		background: linear-gradient(135deg, rgba(251, 191, 36, 0.12), rgba(251, 191, 36, 0.03));
	}
	/* solo bankroll = a centered gold chip below WordBank (matches the menu) — tap → /bank */
	.top-bank.solo {
		width: fit-content;
		max-width: none;
		margin: 0 auto 12px;
		padding: 7px 18px;
		text-align: center;
		cursor: pointer;
	}
	.top-bank.solo:active {
		transform: scale(0.97);
	}
	/* 💥 dramatic pop when the bankroll swings big (win payout / loss) */
	.top-bank.solo.pop-up {
		animation: bankPopUp 1.1s cubic-bezier(0.34, 1.56, 0.64, 1);
	}
	.top-bank.solo.pop-down {
		animation: bankPopDown 1.1s cubic-bezier(0.34, 1.56, 0.64, 1);
	}
	@keyframes bankPopUp {
		0% {
			transform: scale(1);
			border-color: rgba(253, 224, 71, 0.4);
		}
		22% {
			transform: scale(1.4);
			border-color: rgba(74, 222, 128, 0.9);
			box-shadow: 0 0 30px rgba(74, 222, 128, 0.7);
		}
		55% {
			transform: scale(0.96);
		}
		100% {
			transform: scale(1);
		}
	}
	@keyframes bankPopDown {
		0% {
			transform: scale(1);
		}
		18% {
			transform: scale(0.8) translateX(-3px);
			border-color: rgba(251, 113, 133, 0.9);
			box-shadow: 0 0 22px rgba(251, 113, 133, 0.6);
		}
		36% {
			transform: scale(0.86) translateX(3px);
		}
		100% {
			transform: scale(1);
		}
	}
	.top-bank.solo.pop-up .tb-solo {
		animation: bankColorUp 1.1s ease-out;
	}
	.top-bank.solo.pop-down .tb-solo {
		animation: bankColorDown 1.1s ease-out;
	}
	@keyframes bankColorUp {
		0%,
		100% {
			color: #fcd34d;
		}
		25% {
			color: #4ade80;
			text-shadow: 0 0 24px rgba(74, 222, 128, 0.95);
		}
	}
	@keyframes bankColorDown {
		0%,
		100% {
			color: #fcd34d;
		}
		25% {
			color: #fb7185;
			text-shadow: 0 0 20px rgba(251, 113, 133, 0.9);
		}
	}
	.tb-solo {
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		font-size: 1.55rem;
		color: #fcd34d;
		font-variant-numeric: tabular-nums;
	}
	.tb-wallet-cap {
		display: block;
		font-size: 0.62rem;
		font-weight: 700;
		letter-spacing: 0.05em;
		text-transform: uppercase;
		color: var(--text-faint);
	}
	/* 🏷️ Game-mode pill — centered under the wordmark, same for every mode */
	.mode-pill {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		margin: -2px auto 10px;
		padding: 4px 14px;
		border-radius: 999px;
		white-space: nowrap;
		cursor: pointer;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.1em;
		color: var(--brand-2);
		background: rgba(253, 224, 71, 0.08);
		border: 1px solid rgba(253, 224, 71, 0.3);
		transition:
			transform 0.16s var(--ease-spring),
			background 0.2s,
			border-color 0.2s;
	}
	.mode-pill:hover {
		background: rgba(253, 224, 71, 0.14);
		border-color: rgba(253, 224, 71, 0.5);
	}
	.mode-pill:active {
		transform: scale(0.95);
	}
	.mp-emoji {
		font-size: 0.9rem;
		letter-spacing: 0;
	}
	.mp-info {
		font-size: 0.72rem;
		opacity: 0.6;
		letter-spacing: 0;
	}

	.game-logo {
		display: block;
		width: min(52vw, 180px);
		height: auto;
		margin: 2px auto 10px;
		filter: drop-shadow(0 2px 12px rgba(0, 0, 0, 0.5));
	}

	:global(html, body) {
		overflow-x: hidden;
		touch-action: manipulation;
	}

	@keyframes winPulse {
		0%,
		100% {
			transform: scale(1) rotate(0deg);
			text-shadow: 0px 0px 10px green;
		}
		25% {
			transform: scale(1.2) rotate(3deg);
			text-shadow: 0px 0px 20px limegreen;
		}
		50% {
			transform: scale(1.5) rotate(-3deg);
			text-shadow: 0px 0px 30px limegreen;
		}
		75% {
			transform: scale(1.2) rotate(3deg);
			text-shadow: 0px 0px 20px green;
		}
	}

	@keyframes winFlash {
		0% {
			opacity: 1;
		}
		50% {
			opacity: 0.2;
		}
		100% {
			opacity: 1;
		}
	}

	@keyframes bannerPop {
		from {
			transform: scale(0.8);
			opacity: 0;
		}
		to {
			transform: scale(1);
			opacity: 1;
		}
	}

	@keyframes gameOverPulse {
		0%,
		100% {
			transform: scale(1) rotate(0deg);
			text-shadow: 0px 0px 10px red;
		}
		25% {
			transform: scale(1.2) rotate(3deg);
			text-shadow: 0px 0px 20px red;
		}
		50% {
			transform: scale(1.5) rotate(-3deg);
			text-shadow: 0px 0px 30px red;
		}
		75% {
			transform: scale(1.2) rotate(3deg);
			text-shadow: 0px 0px 20px red;
		}
	}

	@keyframes gameOverFlash {
		0% {
			opacity: 1;
		}
		50% {
			opacity: 0.2;
		}
		100% {
			opacity: 1;
		}
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
	.modal-content :global(h2) {
		font-family: var(--font-display);
	}

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
		transition:
			background 0.2s,
			border-color 0.2s;
	}
	.close-btn:hover {
		background: rgba(251, 90, 90, 0.16);
		border-color: rgba(251, 90, 90, 0.4);
	}

	@keyframes fadeIn {
		from {
			opacity: 0;
		}
		to {
			opacity: 1;
		}
	}

	@keyframes slideIn {
		from {
			transform: translateY(-20px);
		}
		to {
			transform: translateY(0);
		}
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
		transition:
			transform 0.16s var(--ease-spring),
			filter 0.2s;
	}
	.next-puzzle-button:hover {
		transform: translateY(-2px);
		filter: brightness(1.05);
	}
	.next-puzzle-button:active {
		transform: scale(0.97);
	}

	/* Result modal */
	.result-modal h2 {
		font-size: 1.7rem;
		margin: 4px 0 2px;
	}
	.result-medal {
		font-size: 3.4rem;
		line-height: 1;
		margin-bottom: 6px;
		animation: wb-pop-in 0.6s var(--ease-spring) both;
		filter: drop-shadow(0 6px 18px rgba(0, 0, 0, 0.5));
	}

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
	.win-h {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1.7rem;
		margin: 0 0 2px;
		animation: winPunch 0.5s cubic-bezier(0.34, 1.56, 0.64, 1);
	}
	@keyframes winPunch {
		0% {
			opacity: 0;
			transform: scale(0.6);
		}
		60% {
			transform: scale(1.12);
		}
		100% {
			opacity: 1;
			transform: scale(1);
		}
	}
	/* 🧾 Receipt-style Cash Game results */
	.receipt {
		font-family: 'Courier New', 'Courier', ui-monospace, monospace;
		width: 100%;
		max-width: 290px;
		margin: 0.4rem auto 1.1rem;
		padding: 18px 20px 20px;
		background: #f6f1e6;
		color: #23201a;
		border-radius: 3px;
		box-shadow: 0 12px 34px rgba(0, 0, 0, 0.55);
		text-align: left;
		/* torn thermal-paper bottom edge */
		-webkit-mask:
			linear-gradient(#000 0 0) top / 100% calc(100% - 7px) no-repeat,
			radial-gradient(6px 7px at 6px 0, #0000 98%, #000) bottom left / 12px 7px repeat-x;
		mask:
			linear-gradient(#000 0 0) top / 100% calc(100% - 7px) no-repeat,
			radial-gradient(6px 7px at 6px 0, #0000 98%, #000) bottom left / 12px 7px repeat-x;
	}
	.rcpt-brand {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 5px;
		margin-bottom: 2px;
	}
	.rcpt-coin {
		width: 40px;
		height: 40px;
		object-fit: contain;
		filter: drop-shadow(0 2px 3px rgba(0, 0, 0, 0.35));
	}
	.rcpt-mark {
		width: 150px;
		max-width: 72%;
		height: auto;
		/* the wordmark's silver half can wash out on cream — a hair of contrast/shadow keeps it crisp */
		filter: drop-shadow(0 1px 1px rgba(0, 0, 0, 0.28)) saturate(1.05) contrast(1.05);
	}
	.rcpt-title {
		text-align: center;
		font-weight: 700;
		font-size: 0.76rem;
		letter-spacing: 0.28em;
		margin-top: 3px;
	}
	.rcpt-title.void {
		color: #b91c1c;
	}
	.rcpt-meta {
		text-align: center;
		font-size: 0.72rem;
		color: #6b6455;
		margin: 3px 0 6px;
	}
	.rcpt-rule {
		border-top: 1px dashed #b3a88f;
		margin: 8px 0;
	}
	.rcpt-rule.double {
		border-top: 2px solid #23201a;
	}
	.rcpt-line {
		display: flex;
		justify-content: space-between;
		gap: 12px;
		font-size: 0.82rem;
		padding: 2px 0;
		font-variant-numeric: tabular-nums;
	}
	.rcpt-line .neg {
		color: #b91c1c;
	}
	.rcpt-line .pos {
		color: #157a3a;
	}
	.rcpt-line.total {
		font-weight: 800;
		font-size: 0.94rem;
	}
	.rcpt-line.total.profit {
		color: #157a3a;
	}
	.rcpt-line.answer {
		font-weight: 700;
		letter-spacing: 0.02em;
	}
	.rcpt-note {
		text-align: center;
		font-size: 0.72rem;
		color: #6b6455;
		margin: 6px 0 2px;
	}
	.rcpt-foot {
		text-align: center;
		font-size: 0.7rem;
		color: #6b6455;
		margin-top: 12px;
		letter-spacing: 0.03em;
	}

	.win-math {
		display: flex;
		flex-direction: column;
		gap: 7px;
		text-align: left;
		margin: 14px auto 12px;
		max-width: 300px;
		padding: 14px 16px;
		border-radius: 16px;
		border: 1px solid rgba(253, 224, 71, 0.4);
		background: linear-gradient(135deg, rgba(251, 191, 36, 0.12), rgba(251, 191, 36, 0.04));
	}
	.wm-row {
		display: flex;
		justify-content: space-between;
		align-items: baseline;
		gap: 10px;
		font-size: 0.92rem;
		color: var(--text);
	}
	.wm-row b {
		font-family: 'Orbitron', var(--font-display);
		font-variant-numeric: tabular-nums;
	}
	.wm-row .neg {
		color: #fb7185;
	}
	.wm-row.total {
		border-top: 1px solid rgba(253, 224, 71, 0.3);
		padding-top: 9px;
		margin-top: 2px;
		font-weight: 700;
		font-size: 1rem;
	}
	.wm-row .profit {
		font-size: 1.8rem;
		color: #4ade80;
		text-shadow: 0 0 18px rgba(74, 222, 128, 0.5);
	}
	.win-twist {
		font-size: 0.82rem;
		color: var(--text-muted);
		margin: 0 0 12px;
	}
	.win-twist b {
		color: var(--brand-2);
	}
	.win-bank {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 2px;
		margin: 0 0 10px;
	}
	.wb-label {
		font-size: 0.66rem;
		letter-spacing: 0.12em;
		text-transform: uppercase;
		color: var(--text-faint);
	}
	.wb-amount {
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		font-size: 1.9rem;
		color: #fde047;
		text-shadow: 0 0 18px rgba(251, 191, 36, 0.45);
		font-variant-numeric: tabular-nums;
	}
	.win-rank {
		font-size: 0.86rem;
		color: var(--text-muted);
		margin: 0 0 14px;
	}
	.win-rank b {
		color: #fde047;
		font-family: var(--font-display);
	}
	.win-menu {
		margin-top: 10px;
		background: none;
		border: none;
		color: var(--text-faint);
		font-size: 0.84rem;
		text-decoration: underline;
		cursor: pointer;
	}
	.result-actions {
		display: flex;
		gap: 10px;
	}
	.result-actions > * {
		flex: 1;
		margin-top: 0;
	}
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
		transition:
			transform 0.15s var(--ease-spring),
			background 0.2s,
			border-color 0.2s;
	}
	.share-btn:hover {
		transform: translateY(-2px);
		background: rgba(56, 189, 248, 0.14);
		border-color: rgba(56, 189, 248, 0.4);
	}
	.share-btn:active {
		transform: scale(0.97);
	}
</style>
