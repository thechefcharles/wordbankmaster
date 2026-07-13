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
		fetchMakeupGame,
		fetchClimbGame,
		startCashGame,
		cashOutClimb,
		climbAdvance,
		climbFreeSkip,
		climbForfeitRun,
		climbLeaveGame,
		climbArmDoubleOrNothing,
		climbPowerup,
		startMatch,
		acceptAndPlayMatch,
		resumeMatch,
		refreshMatchMeta,
		matchPowerup,
		matchSabotageOpponent,
		dailyFold,
		matchFold,
		startFreePlay,
		freePlayNext,
		freePlayPoints
	} from '$lib/stores/GameStore.js';
	import {
		getPowerups,
		getDailyAvailBoosts,
		getDailyInterest,
		getMyMatches,
		getMyGroups,
		getMatchDetail,
		getMatchDebuffs,
		getMatchOpponents,
		declineMatch
	} from '$lib/stores/statsStore.js';
	import { CATEGORIES, categoryLabel } from '$lib/categories.js';
	import CategoryIcon from '$lib/components/CategoryIcon.svelte';
	import ModeIcon from '$lib/components/ModeIcon.svelte';
	import Icon from '$lib/components/Icon.svelte';
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
		listFriends,
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
		getCashgameMeta
	} from '$lib/stores/statsStore.js';
	import Avatar from '$lib/components/Avatar.svelte';
	import {
		unreadCount,
		refreshNotifications,
		inboxRequest,
		inboxTarget,
		inboxMatch,
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
	import { goto, replaceState } from '$app/navigation';

	import PhraseDisplay from '$lib/components/PhraseDisplay.svelte';
	import SolveTimer from '$lib/components/SolveTimer.svelte';
	import InventoryList from '$lib/components/InventoryList.svelte';
	import VaultReveal from '$lib/components/VaultReveal.svelte';
	import Keyboard from '$lib/components/Keyboard.svelte';
	import GameButtons from '$lib/components/GameButtons.svelte';
	import Auth from '$lib/components/Auth.svelte';
	import Tutorial from '$lib/components/Tutorial.svelte';
	import ObjectiveCard from '$lib/components/ObjectiveCard.svelte';
	import AccountCard from '$lib/components/AccountCard.svelte';
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
	// Set once the client confirms it has no usable session — stops the SSR data.user
	// reactive from re-asserting loggedIn (see the reactive below).
	let noClientSession = false;
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
			modeKey: g.mode,
			go: () => resumeSolo(g.mode)
		})),
		...(myMatches ?? [])
			.filter((/** @type {any} */ m) => m.status === 'open' && m.my_state === 'active')
			.map((/** @type {any} */ m) => ({
				key: 'match-' + m.id,
				label: m.group_name || (m.opponent ? '@' + m.opponent : 'Challenge'),
				modeKey: 'match',
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
	let menuCreditTier = /** @type {string} */ ('Good'); // skins the menu account card
	async function refreshBank() {
		try {
			const gb = await getBank();
			netWorth = gb.net_worth;
			menuBank = gb.bank ?? 0;
			menuLoan = gb.loan ?? 0;
			menuCreditTier = gb.credit_tier ?? 'Good';
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
				// No usable client session. This can happen when an SSR cookie (or a hydrated
				// $user) marks us logged-in while the client's token is expired/invalid — which
				// would otherwise strand the user on "Loading…" forever (loggedIn=true but init
				// never completes). Purge the stale auth and fall through to the login screen.
				console.warn('⛔ No client session — clearing stale auth, showing login.', error?.message);
				noClientSession = true; // suppress the SSR data.user reactive so login actually shows
				// Mismatch: SSR read a user from the cookie but the browser has no usable session.
				// That means a stale server-side cookie (e.g. a legacy httpOnly one the client
				// can't read or overwrite) — only the server can delete it, so bounce through the
				// /signout route to purge it, then land on a clean login. Guard with a one-shot
				// query flag so we never loop once the cookie is gone.
				if (data?.user && !window.location.search.includes('signedout')) {
					window.location.href = '/signout';
					return;
				}
				try {
					await supabase.auth.signOut({ scope: 'local' });
				} catch {
					/* ignore — nothing to clear */
				}
				user.set(null);
				// Also show the menu (not just init): if the user then logs in / signs up on this
				// same page instance (Auth flips loggedIn before its window.location reload), a
				// false showMainMenu would let the game-restorer reactive fire and auto-start a
				// game from a leftover gameMode. showMainMenu=true keeps that guard closed; the
				// <Auth/> screen still shows because loggedIn is false.
				showMainMenu = true;
				hasInitialized = true;
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

			// Cold open → land on the menu. Drop any stale transient gameMode first: it's a
			// device-global key (not per-account), so a value left over from a previous session
			// or a different account on this device would otherwise let the game-restorer
			// auto-start/resume a game the user never chose — e.g. silently firing daily_start
			// on a brand-new account (burning the attendance bonus). Real starts re-set it;
			// Resume uses the per-user saved slot, not this.
			if (localStorage.getItem('gameMode')) localStorage.removeItem('gameMode');
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
					myUsername = u ?? '';
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
		!needsUsername &&
		$gameStore.currentPhrase === '' &&
		!$gameWasRestored
	) {
		// Restore an in-progress game when returning to this route (e.g. back from the Store).
		// Only act on an EXPLICITLY-set gameMode — never default to 'daily', or a brand-new
		// user mid-onboarding (showMainMenu still false, no gameMode yet) would silently
		// auto-start the Daily: burning the attendance bonus + a session before they chose to.
		const gameMode = localStorage.getItem('gameMode');
		if (gameMode === 'makeup') {
			fetchMakeupGame().then((ok) => {
				if (!ok) showMainMenu = true;
			});
		} else if (gameMode === 'climb') {
			fetchClimbGame().then((ok) => {
				if (!ok) showMainMenu = true;
			});
		} else if (gameMode === 'daily') {
			fetchDailyGame().then((ok) => {
				if (!ok) initError = 'Daily puzzle failed to load.';
			});
		} else {
			// 'match' isn't deep-link restorable, and no/unknown gameMode means nothing to
			// resume — show the menu instead of auto-starting anything.
			if (gameMode === 'match') localStorage.setItem('gameMode', 'daily');
			showMainMenu = true;
		}
	}

	// ✅ Set user from SSR if present (profile load happens once in onMount).
	// Suppressed once the client confirms it has NO usable session (noClientSession): the
	// SSR cookie can still decode server-side (esp. a legacy httpOnly cookie the browser
	// can't read) and would otherwise re-assert loggedIn=true, stranding the user in the
	// signed-in-but-every-call-401 game screen instead of the login screen.
	$: if (data?.user && !noClientSession) {
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
	$: isMakeup = $gameStore.gameMode === 'makeup';
	// Auto-dismiss the Cash-earned toast after a few seconds.
	/** @type {ReturnType<typeof setTimeout>|undefined} */
	let _attTimer;
	$: if ($gameStore.cashToast) {
		clearTimeout(_attTimer);
		_attTimer = setTimeout(() => gameStore.update((s) => ({ ...s, cashToast: null })), 4000);
	}
	$: isClimb = $gameStore.gameMode === 'climb';
	$: isDaily = $gameStore.gameMode === 'daily';
	$: climb = $gameStore.climbInfo; // { wallet, bounty, budget_left, solve_reward, spent, heat, must_guess, cheapest, last_gain, state, run_solves, wiped, pups_locked, equipped }
	$: overdriveArmed = isClimb && (climb?.equipped ?? []).includes('overdrive');
	// 🚨 Last-stand: out of budget, this guess decides it. Persistent while stuck
	// (drives the red screen treatment + keyboard lock). Overdrive lifts the lock.
	// Cash Game = your run is on the line; Daily = your one shot at today's win.
	$: dangerMode =
		((isClimb && !!climb?.must_guess) || (isDaily && !!$gameStore.dailyMustGuess)) &&
		gameActive &&
		$gameStore.gameState !== 'won' &&
		$gameStore.gameState !== 'lost';

	// 🧾 Bank-receipt meta — a stable masked account number derived from the user id
	// (deterministic, no DB), the account holder, and a timestamp captured when a
	// result slip opens so the printed DATE/TIME stays fixed while it's on screen.
	let myUsername = '';
	$: acctNo =
		($userProfile?.account_number ?? '').toString().slice(-4) ||
		(() => {
			const id = $user?.id ?? '';
			let h = 5381;
			for (let i = 0; i < id.length; i++) h = ((h << 5) + h + id.charCodeAt(i)) >>> 0;
			return String(h % 10000).padStart(4, '0');
		})();
	/** @type {Date|null} */
	let receiptStamp = null;
	$: if (showResultModal && !receiptStamp) receiptStamp = new Date();
	$: if (!showResultModal && receiptStamp) receiptStamp = null;
	$: rcptDate = receiptStamp
		? `${String(receiptStamp.getMonth() + 1).padStart(2, '0')}/${String(
				receiptStamp.getDate()
			).padStart(2, '0')}/${String(receiptStamp.getFullYear()).slice(2)}`
		: '';
	$: rcptTime = receiptStamp
		? (() => {
				let h = receiptStamp.getHours();
				const m = String(receiptStamp.getMinutes()).padStart(2, '0');
				const ap = h < 12 ? 'AM' : 'PM';
				h = h % 12 || 12;
				return `${h}:${m} ${ap}`;
			})()
		: '';
	// 🏷️ Which mode you're in — a consistent pill under the wordmark on every game screen.
	$: modeLabel =
		{
			daily: { name: 'Daily' },
			climb: { name: 'Cash Game' },
			makeup: { name: 'Make-up' },
			match: { name: 'Challenge' },
			challenge: { name: 'Challenge' }
		}[$gameStore.gameMode] ?? null;
	$: isMatch = $gameStore.gameMode === 'match';
	$: matchInfo = $gameStore.matchInfo; // { position, pack_size, total_score, last_score, done, mode, solved, spent, budget, wager, items_allowed, used_powerups, started_at, clock_seconds, combo }
	// 💥 Double or Nothing (Cash Game): server exposes don_armed + don_available (heat ≥ ×1.5).
	$: donArmed = !!climb?.don_armed;
	$: donAvailable = !!climb?.don_available;
	// The doubled target payout (matches server: bounty ×2, then × heat, rounded).
	$: donTarget =
		isClimb && climb ? Math.round(((climb.bounty ?? 0) * 2 * (climb.heat ?? 100)) / 100) : 0;
	// Climb live (Accumulator): "Solve to Earn" = leftover budget × heat, added to the
	// Payout on solve. Server-computed as solve_reward.
	$: climbLive =
		isClimb && climb && climb.state === 'active'
			? {
					spent: climb.spent ?? 0,
					payout: climb.solve_reward ?? 0,
					// One-number model: the hero shows the running Balance (secured pile + this puzzle's spend).
					net: climb.balance ?? (climb.bankroll ?? 0) + (climb.solve_reward ?? 0)
				}
			: null;
	// Challenge live: Spent of your ante budget — lowest spend wins (standard only).
	$: matchLive =
		isMatch && matchInfo && !matchInfo.done
			? { spent: matchInfo.spent ?? 0, budget: matchInfo.budget ?? 0 }
			: null;
	$: matchLeft = matchLive ? Math.max(0, (matchLive.budget ?? 0) - (matchLive.spent ?? 0)) : 0;
	// The hero number: the bounty you spend down THIS puzzle. Daily & Cash Game keep the
	// leftover; Challenge's resets each puzzle (fresh bounty) — the accumulated total is the
	// Score, shown up top. Cash Game's carries via climb.balance (secured pile + current budget).
	$: soloHero = climbLive
		? { net: climbLive.net }
		: dLive
			? { net: dLive.remaining }
			: matchLive
				? { net: matchLeft }
				: null;

	// Solve timer runs on the Daily board while unsolved and past the opening reveal.
	$: dailyTimerActive =
		$gameStore.gameMode === 'daily' &&
		!showMainMenu &&
		!introBuilding &&
		$gameStore.gameState !== 'won' &&
		$gameStore.gameState !== 'lost';

	// 🎰 Slot-machine money feel: count the hero number up/down; float a −$X off it on each spend.
	const tweenNet = tweened(0, { duration: 900, easing: cubicOut });
	// 🏆 Win-banner animations: profit counts up, then Cash scrolls to the new total.
	const resultProfit = tweened(0, { duration: 1100, easing: cubicOut });
	const resultBankAnim = tweened(0, { duration: 1300, easing: cubicOut });
	// 💸 "Deposit lands" beat (Daily): coins fly into the account card + the balance counts up,
	// played AFTER the SOLVED reveal and BEFORE the receipt.
	const depositBank = tweened(0, { duration: 1300, easing: cubicOut });
	/** @type {{ amount:number, from:number, to:number }|null} */
	let depositAnim = null;
	/** @type {{ id:number, dx:number, dy:number, delay:number, rot:number }[]} */
	let depositCoins = [];
	/** @type {ReturnType<typeof setTimeout>|null} */
	let _depTimer = null;
	/** @type {{rank:number,total:number,score:number}|null} */
	let resultRank = null;
	// While the opening reveal is landing boxes, hold the bounty at $0 so it can
	// dramatically count up at the climax (introDone). Cash Game stages the count-up manually
	// (puzzle value → + carried run pile), so pause this auto-driver while climbStaging is on.
	$: if (!climbStaging) tweenNet.set(introBuilding ? 0 : soloHero ? Math.round(soloHero.net) : 0);
	// The Pot you're playing for = every player's ante (server-computed over all
	// non-declined players, so it stays stable as opponents finish). Reduced-stake joins
	// can make the settled pot a bit lower; this is the headline "playing for" figure.
	$: matchPot = isMatch
		? Math.round(
				matchInfo?.pot ?? (matchInfo?.wager ?? 0) * ((matchInfo?.opponents?.length ?? 0) + 1)
			)
		: 0;

	// 🎰 Daily opening reveal coordination (boxes land → bounty counts up × multiplier).
	// fetchDailyGame ARMS it (dailyIntro token); we only PLAY it once the board is
	// actually on screen — i.e. the "How to win" card is dismissed — by bumping
	// dailyIntroGo, which PhraseDisplay watches.
	let introBuilding = false;
	let _introFired = 0;
	let introCountPop = false;
	// 🎰 Cash Game two-stage reveal: after the boxes land, the hero counts 0 → this puzzle's
	// value, then the carried run pile flies on (carryCue) and it ticks up to the new total.
	let climbStaging = false;
	let carryCue = 0;
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
		// 🎰 Cash Game with a carried run pile → stage it: count up to THIS puzzle's value first,
		// then fly the carried pile on and tick up to the new total.
		if (isClimb && climb && (climb.bankroll ?? 0) > 0) {
			const total = Math.round(soloHero?.net ?? 0);
			const carried = Math.round(climb.bankroll ?? 0);
			const bounty = Math.max(0, total - carried); // this puzzle's value (net − carried)
			climbStaging = true;
			tweenNet.set(0, { duration: 0 });
			tweenNet.set(bounty, { duration: 700 }); // 0 → puzzle value
			// hold the puzzle value for a beat, THEN fly the carried pile on
			setTimeout(() => {
				carryCue = carried; // flashy "+$X run pile" floats onto the number
				fx('multiplier');
				tweenNet.set(total, { duration: 950 }); // puzzle value → puzzle value + run pile
			}, 1500);
			setTimeout(() => {
				climbStaging = false; // count-up done → the reactive can drive again
			}, 2600);
			setTimeout(() => {
				carryCue = 0; // float lingers ~2s before clearing
			}, 3650);
		}
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
	// In-game, tapping the ambient balance chip shows a tiny explainer (not the full Bank hub —
	// no mid-puzzle loan repay / navigation). The Bank hub still opens from the menu (/bank).
	let showBalanceInfo = false;

	// 🔐 My Vault — owned inventory; use power-ups in-game (mode-eligible only).
	let showBag = false;
	let vaultVideo = false;
	/** @type {any[]} */ let vaultOwned = [];
	/** @type {Record<string,number>} */ let dailyAvailBoosts = {};
	let vaultMsg = '';
	/** @type {ReturnType<typeof setTimeout>|undefined} */ let _vaultMsgTimer;
	const BOOST_META = /** @type {Record<string,{emoji:string,blurb:string}>} */ ({
		bounty_boost: { emoji: 'boost', blurb: 'Adds +50% Interest to your deposit' },
		jackpot_boost: { emoji: 'gem', blurb: 'Adds +100% Interest to your deposit' }
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
								emoji: BOOST_META[it.id]?.emoji ?? 'boost',
								name: it.name,
								blurb: BOOST_META[it.id]?.blurb ?? '',
								count: it.owned,
								usable: avail,
								reason: avail ? '' : 'Bought after you started — usable on your next puzzle.'
							});
						} else if (it.kind === 'climb') {
							// Heat Shield is a PASSIVE safety net (auto-saves you from a bust while owned) —
							// it's not tap-to-use, so keep it out of the usable tray.
							if (it.id === 'heat_shield') continue;
							// Self-buffs work in BOTH the Cash Game and Challenges.
							const climbUsed = (climb?.equipped ?? []).includes(it.id);
							const matchUsed = (matchInfo?.used_powerups ?? []).includes(it.id);
							// 🏧 Overdrive is a Cash-Game lifeline: only usable when you're out of money.
							const isOverdrive = it.id === 'overdrive';
							// ⏭️ Free Skip swaps the run's puzzle — Cash Game only, not Challenges.
							const isFreeSkip = it.id === 'free_skip';
							const climbAvail =
								$gameStore.gameMode === 'climb' &&
								gameActive &&
								!climbUsed &&
								(it.owned ?? 0) > 0 &&
								(!isOverdrive || !!climb?.must_guess);
							const matchAvail =
								isMatch &&
								!!matchInfo?.items_allowed &&
								gameActive &&
								!matchUsed &&
								(it.owned ?? 0) > 0 &&
								!isOverdrive &&
								!isFreeSkip;
							const avail = climbAvail || matchAvail;
							out.push({
								id: it.id,
								emoji: PUP_ICON[it.id] ?? 'boost',
								name: it.name,
								blurb: avail
									? isOverdrive
										? 'Then buy any letter — free'
										: isFreeSkip
											? 'Fresh puzzle — keep your Interest'
											: 'Tap to use now'
									: '',
								count: it.owned,
								usable: avail,
								reason:
									climbUsed || matchUsed
										? 'Already used on this puzzle.'
										: isOverdrive && $gameStore.gameMode === 'climb' && !climb?.must_guess
											? 'Use it when you run out of money.'
											: isFreeSkip && isMatch
												? 'For the Cash Game — not Challenges.'
												: $gameStore.gameMode === 'climb' || isMatch
													? ''
													: 'For the Cash Game or Challenges — not this mode.'
							});
						} else if (it.kind === 'sabotage') {
							const sabAvail =
								isMatch && !!matchInfo?.items_allowed && gameActive && (it.owned ?? 0) > 0;
							out.push({
								id: it.id,
								emoji: PUP_ICON[it.id] ?? 'sabotage',
								name: it.name,
								blurb: sabAvail ? 'Tap to aim at an opponent' : '',
								count: it.owned,
								usable: sabAvail,
								kind: 'sabotage',
								reason: sabAvail ? '' : 'For Challenges — use it during a challenge.'
							});
						} else {
							out.push({
								id: it.id,
								emoji: PUP_ICON[it.id] ?? 'boost',
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
			if (item.id === 'free_skip') {
				// Fresh puzzle mid-run — replay the dramatic opening reveal.
				climbFreeSkip().then(() => {
					refreshClimbPups();
					loadVault();
					tick().then(playDailyIntroIfArmed);
				});
			} else {
				climbPowerup(item.id).then(() => {
					refreshClimbPups();
					loadVault();
				});
			}
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
	/** @type {{win_streak:number,tier:string,streak:number,credit:number,boost:number,total:number}|null} */
	let dailyInterest = null;
	// Open the Interest breakdown modal and pull the fresh streak/credit/boost split.
	async function openDailyMult() {
		fx('tap');
		dailyInfo = 'mult';
		dailyInterest = await getDailyInterest();
	}
	$: dlMult = Number($gameStore.dailyLive?.mult ?? $gameStore.bountyMult ?? 1);
	$: dlRemaining = $gameStore.dailyLive?.remaining ?? 0; // Prize budget left
	$: dlWinnings = $gameStore.dailyLive?.winnings ?? Math.round(dlRemaining * dlMult); // banked if you solve now
	$: dlWinStreak = dailyStatus?.win_streak ?? 0;
	// Daily Interest = earned (win streak + credit tier) + any 💥/💎 Interest Boosts you tap in.
	// Total lands in dlMult; the breakdown comes from getDailyInterest() (dailyInterest).
	let _prevNet = /** @type {number|null} */ (null);
	let _floatId = 0;
	let _prevWrongTick = 0;
	/** @type {{id:number,text:string,wrong?:boolean}[]} */
	let spendFloaters = [];
	// Float a −$X off the hero number whenever it drops from a letter buy — in ANY mode.
	// Watches the actual displayed value (soloHero.net) so it fires identically for Daily,
	// Cash Game and Challenge. Guards: only while the game is active (so a bust → $0 doesn't
	// float) and not during the opening reveal count-up (introBuilding) or on the menu.
	$: trackSpend(soloHero?.net, gameActive, showMainMenu, introBuilding, $gameStore.wrongTick);
	/** @param {number|null|undefined} v @param {boolean} active @param {boolean} onMenu @param {boolean} building @param {number|undefined} wtick */
	function trackSpend(v, active, onMenu, building, wtick) {
		// A Cash Game wrong guess bumps wrongTick in the SAME update as the budget drop, so this
		// reactive sees both together — label that one floater "✗ Wrong" instead of a plain −$X buy.
		const isWrong = wtick != null && wtick > _prevWrongTick;
		_prevWrongTick = wtick ?? _prevWrongTick;
		if (
			browser &&
			active &&
			!onMenu &&
			!building &&
			_prevNet != null &&
			v != null &&
			v < _prevNet
		) {
			const amt = _prevNet - v;
			if (amt > 0) {
				const id = ++_floatId;
				const text = (isWrong ? '✗ Wrong  −$' : '−$') + amt.toLocaleString();
				spendFloaters = [...spendFloaters, { id, text, wrong: isWrong }];
				setTimeout(() => {
					spendFloaters = spendFloaters.filter((f) => f.id !== id);
				}, 1100);
			}
		}
		_prevNet = v ?? null;
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

	// 🎁 Daily Twist "as it happens" toast. GameStore sets $gameStore.twistCue when a Twist
	// affects a buy (Insured free / pricing saving) or pre-reveals at open (head start / free
	// vowel). Hold it until the board is interactive (past the intro + How-to-win card), then
	// flash it for ~2.6s.
	let twistToast = /** @type {{ id:number, text:string }|null} */ (null);
	let _twistSeenId = 0;
	$: maybeTwistToast(
		$gameStore.twistCue,
		gameActive,
		showMainMenu,
		introBuilding,
		objective,
		$gameStore.cashToast
	);
	/** @param {{id:number,text:string}|null|undefined} cue @param {boolean} active @param {boolean} onMenu @param {boolean} building @param {any} obj @param {any} attendanceToast */
	function maybeTwistToast(cue, active, onMenu, building, obj, attendanceToast) {
		if (!browser || !cue || cue.id === _twistSeenId) return;
		// Wait until the board is playable AND the attendance toast has cleared (no stacking).
		if (!active || onMenu || building || obj || attendanceToast) return;
		_twistSeenId = cue.id;
		twistToast = cue;
		setTimeout(() => {
			if (twistToast?.id === cue.id) twistToast = null;
		}, 2600);
	}

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
			// Only Daily + Challenges reach this (brokeMode = match; Daily give-up = manual).
			// Cash Game never folds here — it busts via the guess flow or forfeits its run.
			if ($gameStore.gameMode === 'daily') await dailyFold();
			else if ($gameStore.gameMode === 'match') await matchFold();
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

	// Heat IS the Cash Game win streak: each solve +0.1× (cap ×2.0), reset to ×1.0 when stuck.
	$: climbStreak = Math.max(0, Math.round(((climb?.heat ?? 100) - 100) / 10));
	// 🔥 The run: solves + cumulative profit since heat last reset (run_profit can be negative early).
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
	// Icon.svelte names, rendered via <Icon>.
	const PUP_ICON = /** @type {Record<string,string>} */ ({
		free_reveal: 'search',
		half_off: 'tag',
		vowel_vision: 'eye',
		extra_hint: 'bulb',
		reveal_word: 'book',
		free_vowel: 'letter-a',
		last_letters: 'chevron-right',
		overdrive: 'coin',
		free_skip: 'skip',
		sabotage_tax: 'percent',
		sabotage_fog: 'fog',
		sabotage_toll: 'toll',
		sabotage_vowel_block: 'block',
		sabotage_lock: 'lock'
	});
	const DEBUFF_LABEL = /** @type {Record<string,string>} */ ({
		tax: 'Taxed (letters +50%)',
		fog: 'Fogged (clue hidden)',
		toll: 'Tolled (next letter 3×)',
		vowel_block: 'Vowel-blocked (vowels 3×)'
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
			// Live board meta: a sabotage debuff (my row) or an opponent's score (their row)
			// updates the banner + standing instantly — meta only, so it never disrupts typing.
			.on(
				'postgres_changes',
				{
					event: 'UPDATE',
					schema: 'public',
					table: 'challenge_participants',
					filter: `match_id=eq.${id}`
				},
				() => refreshMatchMeta()
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
	$: resultBankroll = Math.max(0, Math.floor($gameStore.bankroll || 0));
	$: resultMedal = medalFor(resultBankroll, resultWon);

	let shareCopied = false;
	function buildShareText() {
		const br = '$' + resultBankroll.toLocaleString();
		// Always share the production URL — never localhost/preview. Override with
		// VITE_SITE_URL if the domain ever changes; falls back to the prod alias.
		const link = import.meta.env.VITE_SITE_URL || 'https://wordbanksvelte.vercel.app';
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
	});
	onDestroy(() => {
		if (brokeTimer) clearInterval(brokeTimer);
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
			// Community-tab deep link / browser-back restore: ?c=<tab> (or legacy ?people=1).
			// openCommunity re-syncs the URL, so we skip the generic strip when it fires.
			const cTab = params.get('c') || (params.get('people') ? 'people' : '');
			if (['people', 'leaderboard', 'challenges', 'activity'].includes(cTab)) {
				openCommunity(cTab);
			} else {
				params.delete('people');
				params.delete('c');
				const qs = params.toString();
				replaceState(window.location.pathname + (qs ? '?' + qs : ''), {});
			}
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
		} else {
			const targetMatch = $inboxMatch;
			openCommunity('challenges').then(() => {
				// Deep-link: auto-open the specific match the notification pointed at.
				if (!targetMatch) return;
				const m = (myMatches ?? []).find((/** @type {any} */ x) => x.id === targetMatch);
				if (m) respondToMatch(m);
				inboxMatch.set(null);
			});
		}
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
			if ($gameStore.gameMode !== 'freeplay') refreshBank(); // keep the on-board "Cash" fresh (e.g. a challenge buy-in was just paid)
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

	/** Svelte action: play the printer buzz the moment a receipt mounts (feeds out). */
	function printSound(/** @type {HTMLElement} */ _node) {
		fx('print');
		return {};
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

	// Free Play: device-local points, refreshed whenever the mode is active.
	let fpPoints = { total: 0, best: 0 };
	$: if ($gameStore.gameMode === 'freeplay' && $gameStore.gameState) fpPoints = freePlayPoints();
	function handleFreePlay() {
		fx('tap');
		startFreePlay();
		showMainMenu = false;
		hasInitialized = true;
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
	// Can't afford ANY unlocked tier → we'll nudge them to a loan / the free Daily.
	$: cgMinBuyIn = Math.min(
		...(cgMeta?.tiers ?? [])
			.filter((/** @type {any} */ t) => t.unlocked)
			.map((/** @type {any} */ t) => t.buy_in),
		Infinity
	);
	$: cgBroke = !!cgMeta && (cgMeta.bank ?? 0) < cgMinBuyIn;
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
			// The tier-select modal lives inside the main-menu branch, so it only renders
			// when showMainMenu is true. Coming from a "New Run" button after a void/cash-out
			// we're still in the game view — flip to the menu so the picker actually shows.
			showMainMenu = true;
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
			refreshBank(); // buy-in was just debited server-side → keep the top-bar Available Balance fresh
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
			refreshBank(); // borrowed + bought in → refresh the top-bar Available Balance
			await enterClimbGame();
		} else {
			fx('wrong');
		}
	}
	let showDepositConfirm = false;
	let depositPend = 0;
	// Tapping Deposit opens a confirm + info layer (no PIN) that explains it banks your
	// winnings and ENDS the run. Covers every deposit point (in-run pill + per-puzzle receipt).
	function cashOut() {
		if (cgBusy) return;
		depositPend = Math.round(climb?.bankroll ?? 0);
		showDepositConfirm = true;
	}
	async function confirmDeposit() {
		if (cgBusy) return;
		showDepositConfirm = false;
		cgBusy = true;
		const preBank = Math.round(menuBank ?? netWorth ?? 0); // balance during the run (after buy-in)
		const res = await cashOutClimb();
		cgBusy = false;
		if (res?.ok) {
			await refreshBank(); // settle the account balance → exact count-up target
			const endBal = Math.round(menuBank ?? netWorth ?? 0);
			const buyIn = Math.round(res.buy_in ?? 0);
			// Stash the balance from BEFORE the run started (pre-buy-in) for the recap slip.
			cashoutResult = { ...res, run_start_bal: preBank + buyIn };
			// Dismiss the per-puzzle slip so the deposit beat plays clean (it was still showing
			// underneath), then the "deposit lands" beat → finishDepositAnim shows the recap.
			showResultModal = false;
			startDepositAnim(Math.max(0, endBal - preBank)); // exact account rise (skim-safe)
		}
	}
	// 🏳️ Give up: when you're stuck (can't afford letters, don't know it), forfeit
	// the run instead of typing wrong guesses. Same outcome as a bust — a forced-choice
	// confirm makes the loss deliberate.
	let showForfeitConfirm = false;
	let forfeitAmount = 0;
	function askForfeit() {
		if (cgBusy) return;
		forfeitAmount = Math.round(climb?.bankroll ?? 0);
		showForfeitConfirm = true;
	}
	async function confirmForfeit() {
		if (cgBusy) return;
		showForfeitConfirm = false;
		cgBusy = true;
		await climbForfeitRun();
		cgBusy = false;
	}

	// ===== Challenge Builder (configurable packs vs friends/groups) =====
	let showChallenges = false; // the New-Challenge builder modal
	/** Which Community hub tab is showing. */
	let communityTab = /** @type {'challenges'|'leaderboard'|'activity'|'people'} */ ('challenges');
	// ⚡ Quick-tiles horizontal scroll state — drives the "more to swipe" fade + chevron.
	let qtEl = /** @type {HTMLElement|null} */ (null);
	let qtAtEnd = false; // true once scrolled to the end (or when the row fits with no overflow)
	function updateQt() {
		if (!qtEl) return;
		qtAtEnd = qtEl.scrollLeft + qtEl.clientWidth >= qtEl.scrollWidth - 4;
	}
	/** Svelte action: capture the scroller, size the hint on mount + resize. */
	function qtInit(/** @type {HTMLElement} */ node) {
		qtEl = node;
		updateQt();
		const ro = typeof ResizeObserver !== 'undefined' ? new ResizeObserver(updateQt) : null;
		ro?.observe(node);
		return {
			destroy() {
				ro?.disconnect();
				if (qtEl === node) qtEl = null;
			}
		};
	}
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
	let mbStep = 1; // wizard step: 1 Who · 2 Match · 3 Stakes
	let mbOpponent = '';
	let mbGroupId = '';
	/** @type {string[]} */
	let mbCategories = [];
	let mbPackSize = 3;
	let mbWager = 500;
	let mbPayout = 'winner'; // derived from field size at settle; kept for the RPC signature
	// Challenge tier antes (ante = stake = pot size; payout is by field size at settle).
	const CHALLENGE_TIERS = [
		{ v: 0, label: 'Friendly' },
		{ v: 500, label: '$500' },
		{ v: 2000, label: '$2K' },
		{ v: 10000, label: '$10K' }
	];
	let mbWindow = 172800; // seconds
	let mbItemsAllowed = false; // host toggle: allow power-ups in this challenge
	let mbMsg = '';
	let mbBusy = false;
	// Wizard: step 1 (Who) needs an opponent before Continue is allowed.
	$: mbStep1Ok = mbTarget === 'friend' ? mbOpponent.trim().length > 0 : !!mbGroupId;
	$: potSummary =
		mbWager === 0
			? 'Friendly — no stakes, just bragging rights.'
			: mbTarget === 'group'
				? `Everyone antes $${mbWager.toLocaleString()} → the pot; top finishers split it. Spend less to keep more.`
				: `You both ante $${mbWager.toLocaleString()} → $${(mbWager * 2).toLocaleString()} pot · winner takes all.`;
	/** @type {{username:string,is_friend:boolean}[]} */
	let mbResults = [];
	let mbSearch = ''; // opponent search box (separate from the selected mbOpponent)
	/** @type {{username:string,name?:string}[]} */
	let mbFriends = []; // your friends, for the tap-to-pick list
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
		mbStep = 1;
		mbSearch = '';
		mbResults = [];
		showChallenges = true;
		[myGroups, mbFriends] = await Promise.all([getMyGroups(), listFriends()]);
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
		// Reflect the community tab in the URL (router-safe) so a profile opened from here
		// can be returned to via the browser Back button (history restores /?c=<tab>).
		if (typeof window !== 'undefined' && tab) {
			replaceState(`/?c=${tab}`, {});
		}
		[myMatches, myGroups] = await Promise.all([getMyMatches(), getMyGroups()]);
	}
	// Leave the community view → home, clearing the ?c=/?people= flag from the URL.
	function exitCommunity() {
		menuView = 'home';
		fx('tap');
		if (
			typeof window !== 'undefined' &&
			(window.location.search.includes('c=') || window.location.search.includes('people='))
		) {
			replaceState('/', {});
		}
	}
	/** Back-compat shim for existing callers (banner "+N more", toasts, result modal). */
	/** @param {string} [forceTab] */
	async function openChallenges(forceTab) {
		if (forceTab === 'new') return newChallenge();
		return openCommunity('challenges');
	}

	function onMbOppInput() {
		clearTimeout(mbSearchTimer);
		const q = mbSearch.trim();
		if (q.length < 2) {
			mbResults = [];
			return;
		}
		mbSearchTimer = setTimeout(async () => {
			mbResults = await searchUsers(q);
		}, 220);
	}
	/** Friends filtered by the search box (shown when not actively searching non-friends). */
	$: mbFriendsShown = mbSearch.trim()
		? mbFriends.filter((f) =>
				(f.username + ' ' + (f.name ?? '')).toLowerCase().includes(mbSearch.trim().toLowerCase())
			)
		: mbFriends;
	/** Search results that aren't already in your friends list (bundled: pick to challenge + friend). */
	$: mbNonFriends = mbResults.filter(
		(r) => !mbFriends.some((f) => f.username?.toLowerCase() === r.username?.toLowerCase())
	);
	/** @param {string} username */
	function pickMbOpp(username) {
		mbOpponent = username;
		mbSearch = '';
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
			{
				label: 'Payout',
				value: mbTarget === 'group' ? 'Top finishers split the pot' : 'Winner takes all'
			}
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
			mode: 'standard',
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
			// _match_settle: ≤2 paid → winner takes all; 3+ → top finishers split (70/30, 60/30/10).
			{
				label: 'Payout',
				value: Number(m.players) > 2 ? 'Top finishers split the pot' : 'Winner takes all'
			}
		];
		if (Number(m.wager) > 0 && netWorth != null)
			s.push({ label: 'Available Balance', value: '$' + Math.round(netWorth).toLocaleString() });
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
			myUsername = res.username ?? name;
			// Reflect the freshly-claimed name on the Account card without a reload.
			userProfile.update((p) => ({ ...p, username: res.username ?? name }));
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

	/** Build a little burst of coins that fly from the deposit amount up into the account card. */
	function makeDepositCoins(/** @type {number} */ amount) {
		const count = Math.max(6, Math.min(12, Math.round(amount / 40) + 6));
		const arr = [];
		for (let i = 0; i < count; i++) {
			arr.push({
				id: i,
				dx: Math.round((Math.random() - 0.5) * 130), // launch spread
				dy: 0,
				delay: Math.round(i * 45 + Math.random() * 70),
				rot: Math.round((Math.random() - 0.5) * 260)
			});
		}
		return arr;
	}

	// 💸 The "deposit lands" beat: coins fly into the account card and the balance counts up,
	// THEN we reveal the receipt. Assumes menuBank is already the settled (post-solve) balance.
	// Generic "deposit lands" beat: coins fly into the account card, balance counts up, then the
	// receipt shows. `netRise` = what actually landed in the account. Assumes menuBank is settled.
	function startDepositAnim(/** @type {number} */ netRise) {
		const to = Math.round(menuBank ?? netWorth ?? 0);
		const from = to - Math.max(0, netRise);
		if (netRise <= 0) {
			showResultModal = true; // nothing to animate → straight to the slip
			return;
		}
		depositBank.set(from, { duration: 0 });
		depositCoins = makeDepositCoins(netRise);
		depositAnim = { amount: netRise, from, to };
		setTimeout(() => {
			fx('multiplier'); // cash-register cue as the coins land
			depositBank.set(to); // count up old → new
		}, 500);
		_depTimer = setTimeout(finishDepositAnim, 2400); // auto-advance to the receipt
	}
	function playDailyDepositAnim() {
		const dr = $gameStore.dailyResult || {};
		const netRise = Math.max(0, Math.round(dr.net ?? 0) - Math.round(dr.loan_repaid ?? 0));
		startDepositAnim(netRise);
	}
	function finishDepositAnim() {
		if (_depTimer) {
			clearTimeout(_depTimer);
			_depTimer = null;
		}
		if (!depositAnim) return;
		depositAnim = null;
		depositCoins = [];
		showResultModal = true;
	}

	const onPhraseRevealComplete = async () => {
		// Free Play has its own in-game HUD "Next puzzle →" button and never uses the
		// result modal — fx('win') already played in the reconcile, so there's nothing
		// left for this handler to do. Bail before the modal-trigger bookkeeping below.
		if ($gameStore.gameMode === 'freeplay') return;
		if (hasTriggeredModal || !['won', 'lost'].includes($gameStore.gameState)) return;
		hasTriggeredModal = true;
		const won = $gameStore.gameState === 'won';

		// Daily WIN → play the "deposit lands" beat first, then the receipt.
		if ($gameStore.gameMode === 'daily' && won) {
			await refreshBank(); // account balance now settled → exact count-up target
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
			playDailyDepositAnim();
			return;
		}

		// Everything else (loss, Cash Game, etc.) → straight to the receipt.
		setTimeout(() => {
			showResultModal = true;
			// 🏆 Cash Game win banner: count the profit up, then scroll Cash to the new total.
			if ($gameStore.gameMode === 'climb' && won) {
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
		}}><Icon name={$soundEnabled || $musicEnabled ? 'volume' : 'mute'} size={18} /></button
	>
{/if}
<!-- 🏳️ Give up (top-right) — Daily / Challenges / Cash Game (forfeit) -->
{#if loggedIn && hasInitialized && !showMainMenu && gameActive && (foldMode || (isClimb && climb?.state === 'active'))}
	<button
		class="giveup-btn"
		title="Give up"
		aria-label="Give up"
		on:click={isClimb ? askForfeit : confirmFold}><Icon name="flag" size={18} /></button
	>
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
		<Icon name="chat" size={18} /> <span class="mcb-label">Chat</span>{#if matchChatUnread}<span
				class="mc-dot"
			></span>{/if}
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
			<button class="close-btn" on:click={() => (matchChatOpen = false)}
				><Icon name="close" size={16} /></button
			>
			<h2 class="chat-h"><Icon name="chat" size={18} /> Trash talk</h2>
			<div class="chat-msgs" bind:this={matchChatScroll}>
				{#if matchMessages.length}
					{#each matchMessages as m}
						<div class="cmsg" class:mine={m.is_me}>
							<span class="cm-name">{m.is_me ? 'You' : m.name}</span>
							<span class="cm-body">{m.body}</span>
						</div>
					{/each}
				{:else}
					<p class="chat-empty">No messages yet — start the smack talk</p>
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
				Give up {$gameStore.gameMode === 'match' ? 'this puzzle' : "today's Daily"}?
			</h2>
			<p class="gu-text">
				{$gameStore.gameMode === 'match'
					? 'Skip this puzzle — you pay its full price and move on.'
					: 'It counts as a loss — you deposit nothing and the answer is revealed.'}
			</p>
			<div class="gu-actions">
				<button class="gu-cancel" on:click={cancelGiveUp}>Keep playing</button>
				<button class="gu-confirm" on:click={doGiveUp}
					><Icon name="flag" size={15} /> Give up</button
				>
			</div>
		</div>
	</div>
{/if}

<!-- 💥 Double or Nothing confirm layer (Cash Game) -->
{#if showDon}
	<div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Double or Nothing">
		<button type="button" class="modal-backdrop" aria-label="Cancel" on:click={cancelDon}></button>
		<div class="modal-content giveup-modal don-modal">
			<h2 class="gu-title"><Icon name="boost" size={18} /> Double or Nothing?</h2>
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
					><Icon name="boost" size={15} /> Double it</button
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
			<h2 class="wc-title">Welcome to WordBank</h2>
			<p class="wc-sub">We’ve officially launched — and everyone’s starting fresh.</p>
			<ul class="wc-list">
				<li><span><Icon name="cash" size={16} /></span> <b>$2,000</b> in the bank to play with</li>
				<li><span><Icon name="calendar" size={16} /></span> Today is <b>Day 1</b> of the Daily</li>
				<li><span><Icon name="star" size={16} /></span> Fresh puzzles waiting in the Cash Game</li>
				<li>
					<span><Icon name="trophy" size={16} /></span> Leaderboards are wide open — go claim a spot
				</li>
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

<!-- 🎁 Daily Twist "as it happens" explainer toast -->
{#if twistToast}
	<div class="twist-toast" role="status">{twistToast.text}</div>
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
			<button class="modal-x" on:click={() => (showBag = false)} aria-label="Close"
				><Icon name="close" size={16} /></button
			>
			<h3 class="info-title">
				{#if showMainMenu}Items{:else}<img src="/vault.png" alt="" class="vault-ic-xs" /> My Vault{/if}
			</h3>
			{#if showMainMenu}
				<div class="bag-inv"><InventoryList /></div>
				<button class="bag-store" on:click={() => goto('/shop')}
					><Icon name="bag" size={15} /> Go to the Store →</button
				>
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
								<span class="bag-use-e"><Icon name={it.emoji} size={20} /></span>
								{#if (it.count ?? 1) > 1}<span class="bag-use-n">×{it.count}</span>{/if}
								<span class="bag-use-name">{it.name}</span>
								<span class="bag-use-d"
									>{#if it.usable}{it.blurb}{:else}<Icon name="lock" size={12} /> tap for why{/if}</span
								>
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

<!-- ℹ️ In-game account-balance explainer (tapping the ambient bankroll chip) -->
{#if showBalanceInfo}
	<div
		class="modal-overlay info-overlay"
		role="button"
		tabindex="0"
		aria-label="Close"
		on:click={() => (showBalanceInfo = false)}
		on:keydown={(e) => {
			if (e.key === 'Escape' || e.key === 'Enter') showBalanceInfo = false;
		}}
	>
		<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions a11y_no_noninteractive_element_interactions a11y_no_noninteractive_tabindex -->
		<div class="info-card" on:click|stopPropagation role="dialog" aria-modal="true">
			<button class="modal-x" on:click={() => (showBalanceInfo = false)} aria-label="Close"
				><Icon name="close" size={16} /></button
			>
			<div class="info-big green">
				${Math.round(menuBank ?? netWorth ?? 0).toLocaleString()}
			</div>
			<h3 class="info-title">Account Balance</h3>
			<p class="info-sub">
				Your Cash — banked winnings you keep between games. It doesn’t change mid-puzzle; solve to
				add to it.
			</p>
			<button class="info-close" on:click={() => (showBalanceInfo = false)}>Got it</button>
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
			<button class="modal-x" on:click={() => (dailyInfo = null)} aria-label="Close"
				><Icon name="close" size={16} /></button
			>
			{#if dailyInfo === 'mult'}
				<div class="info-big">+{Math.round((dlMult - 1) * 100)}%</div>
				<h3 class="info-title">Interest</h3>
				<p class="info-sub">Extra Interest on everything you Deposit from this puzzle.</p>
				<div class="info-rows">
					<div class="info-row">
						<span
							><Icon name="trophy" size={14} /> Win streak{dailyInterest
								? ` (${dailyInterest.win_streak})`
								: ''}</span
						><b class:pos={(dailyInterest?.streak ?? 0) > 0}
							>+{Math.round((dailyInterest?.streak ?? 0) * 100)}%</b
						>
					</div>
					<div class="info-row">
						<span
							><Icon name="card" size={14} /> Credit{dailyInterest
								? ` (${dailyInterest.tier})`
								: ''}</span
						><b class:pos={(dailyInterest?.credit ?? 0) > 0}
							>+{Math.round((dailyInterest?.credit ?? 0) * 100)}%</b
						>
					</div>
					{#if (dailyInterest?.boost ?? 0) > 0}<div class="info-row">
							<span><Icon name="boost" size={14} /> Boosts</span><b class="pos"
								>+{Math.round((dailyInterest?.boost ?? 0) * 100)}%</b
							>
						</div>{/if}
					<div class="info-row total">
						<span>Your Interest</span><b>+{Math.round((dlMult - 1) * 100)}%</b>
					</div>
				</div>
				<p class="info-note">
					Interest is earned — solve day after day to grow your <Icon name="trophy" size={13} /> streak
					(up to +15%) and keep good
					<Icon name="card" size={13} /> credit (up to +10%). Tap in <Icon
						name="boost"
						size={13}
					/>/<Icon name="gem" size={13} /> Interest Boosts from the Store for more on top.
				</p>
			{:else if dailyInfo === 'twist'}
				<div class="info-big"><Icon name={dailyMod?.emoji ?? 'boost'} size={40} /></div>
				<h3 class="info-title">{dailyMod?.name ?? "Today's Twist"}</h3>
				<p class="info-twist-do">{dailyMod?.blurb ?? ''}</p>
			{:else if dailyInfo === 'streak'}
				<div class="info-big"><Icon name="trophy" size={34} /> {dlWinStreak}</div>
				<h3 class="info-title">Daily Win Streak</h3>
				<p class="info-sub">Daily puzzles you've solved in a row.</p>
				<div class="info-rows">
					<div class="info-row"><span>Solve today's Daily</span><b class="pos">+1</b></div>
					<div class="info-row"><span>Lose or give up</span><b class="neg">back to 0</b></div>
				</div>
			{:else}
				<div class="info-big green">${Math.max(0, dlWinnings).toLocaleString()}</div>
				<h3 class="info-title">You'll deposit</h3>
				<p class="info-sub">
					What you'd Deposit if you solve right now. Your Available Balance never drops — solving
					only adds to it.
				</p>
				<div class="info-rows">
					<div class="info-row">
						<span>Balance Remaining</span><b class="pos">${dlRemaining.toLocaleString()}</b>
					</div>
					{#if dlMult > 1}<div class="info-row">
							<span>Interest</span><b class="pos">+{Math.round((dlMult - 1) * 100)}%</b>
						</div>{/if}
					<div class="info-row total">
						<span>You deposit</span><b class="green">${dlWinnings.toLocaleString()}</b>
					</div>
				</div>
				<p class="info-note">
					Deduce letters instead of buying them — keep more of your balance. Grows your <button
						class="info-inline"
						on:click|stopPropagation={openDailyMult}>Interest</button
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
			<button class="modal-x" on:click={() => (climbInfo = null)} aria-label="Close"
				><Icon name="close" size={16} /></button
			>
			{#if climbInfo === 'heat'}
				<div class="info-big">
					<Icon name="fire" size={34} /> +{Math.round((climb?.heat ?? 100) - 100)}%
				</div>
				<h3 class="info-title">Interest — grows your payouts</h3>
				<p class="info-sub">
					Every puzzle you solve adds its value to your Payout — boosted by your Interest.
				</p>
				<div class="info-rows">
					<div class="info-row"><span>Each solve</span><b class="pos">+5%</b></div>
					<div class="info-row">
						<span><Icon name="bolt" size={14} /> Solved cheaply</span><b class="pos">up to +10%</b>
					</div>
					<div class="info-row">
						<span><Icon name="card" size={14} /> Credit standing</span><b class="pos">up to +4%</b>
					</div>
					<div class="info-row">
						<span>Maxes out at</span><b>+{Math.round((climb?.heat_cap ?? 200) - 100)}%</b>
					</div>
					<div class="info-row total">
						<span>Your Interest</span><b>+{Math.round((climb?.heat ?? 100) - 100)}%</b>
					</div>
				</div>
				<p class="info-note">
					Interest grows every <button
						class="info-inline"
						on:click|stopPropagation={() => (climbInfo = 'streak')}>solve</button
					>
					— more when you solve cheaply and keep good credit. It resets to +0% on a bust, unless a
					<Icon name="shield" size={14} /> Heat Shield saves you.
				</p>
			{:else if climbInfo === 'streak'}
				<div class="info-big"><Icon name="fire" size={34} /> {climbStreak}</div>
				<h3 class="info-title">Solve Streak</h3>
				<p class="info-sub">Cash Game puzzles you've solved in a row.</p>
				<div class="info-rows">
					<div class="info-row"><span>Solve a puzzle</span><b class="pos">+1</b></div>
					<div class="info-row"><span>Bust</span><b class="neg">back to 0</b></div>
				</div>
				<p class="info-note">
					Powers your <button
						class="info-inline"
						on:click|stopPropagation={() => (climbInfo = 'heat')}>Interest</button
					>
					— <b>+10%</b> per solve.
				</p>
			{:else}
				<div class="info-big green">${Math.max(0, climbLive?.net ?? 0).toLocaleString()}</div>
				<h3 class="info-title">Payout</h3>
				<p class="info-sub">
					Your running cash this run — solve to keep it, one wrong guess loses it all.
				</p>
				<div class="info-rows">
					<div class="info-row">
						<span>Secured so far</span><b>${Math.round(climb?.bankroll ?? 0).toLocaleString()}</b>
					</div>
					<div class="info-row">
						<span>This puzzle's budget <small>(spend on letters)</small></span><b
							>${Math.round(climb?.budget_left ?? 0).toLocaleString()}</b
						>
					</div>
					<div class="info-row total">
						<span>Payout</span><b class="green">${(climbLive?.net ?? 0).toLocaleString()}</b>
					</div>
				</div>
				<p class="info-note">
					Each puzzle's <b>budget</b> shrinks as you buy letters — solve to lock it into your
					Payout. Reveal less, keep more; the next puzzle's value lands ×
					<button class="info-inline" on:click|stopPropagation={() => (climbInfo = 'heat')}
						>Interest</button
					>.
				</p>
			{/if}
			<button class="info-close" on:click={() => (climbInfo = null)}>Got it</button>
		</div>
	</div>
{/if}

<!-- ℹ️ Challenge "Left to Spend" explainer -->
{#if showDepositConfirm}
	<!-- No ✕ / no click-outside: this is a forced choice — Keep Playing or Deposit. -->
	<div class="modal-overlay info-overlay dep-confirm-overlay">
		<div class="info-card" role="dialog" aria-modal="true">
			<div class="info-big dep-amt">${depositPend.toLocaleString()}</div>
			<h3 class="info-title">Deposit & end your run?</h3>
			<p class="info-sub">
				Cash out now or keep playing, but <b class="neg">risk losing it all</b>!
			</p>
			<div class="dep-actions">
				<button class="dep-keep" on:click={() => (showDepositConfirm = false)}>Keep Playing</button>
				<button class="dep-go" disabled={cgBusy} on:click={confirmDeposit}
					>Deposit ${depositPend.toLocaleString()}</button
				>
			</div>
		</div>
	</div>
{/if}

{#if showForfeitConfirm}
	<!-- Forced choice — Keep Playing or Give Up. -->
	<div class="modal-overlay info-overlay dep-confirm-overlay">
		<div class="info-card" role="dialog" aria-modal="true">
			{#if forfeitAmount > 0}
				<div class="info-big neg">−${forfeitAmount.toLocaleString()}</div>
			{/if}
			<h3 class="info-title">Give up your whole run?</h3>
			<p class="info-sub">
				{#if forfeitAmount > 0}
					This <b class="neg">ends your Cash Game run</b> — not just this puzzle — and wipes the
					<b class="neg">${forfeitAmount.toLocaleString()}</b> you've banked so far. You'll see the answer,
					and it can't be undone.
				{:else}
					This <b class="neg">ends your Cash Game run</b> — not just this puzzle. You'll see the answer
					and walk away with nothing, and it can't be undone.
				{/if}
			</p>
			<div class="dep-actions">
				<button class="dep-keep" on:click={() => (showForfeitConfirm = false)}>Keep Playing</button>
				<button class="dep-go forfeit" disabled={cgBusy} on:click={confirmForfeit}>End Run</button>
			</div>
		</div>
	</div>
{/if}

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
			<button class="modal-x" on:click={() => (showAnteInfo = false)} aria-label="Close"
				><Icon name="close" size={16} /></button
			>
			<div class="info-big green">${Math.max(0, matchLeft).toLocaleString()}</div>
			<h3 class="info-title">Bounty kept</h3>
			<p class="info-sub">
				Each puzzle gives you a <b>fresh bounty</b> to spend on letters — it's <b>not</b> your
				money. Whatever you don't spend adds to your <b>Score</b>. Highest Score across the pack
				takes the pot.
			</p>
			<div class="info-rows">
				<div class="info-row">
					<span>This puzzle's bounty left</span><b>${Math.max(0, matchLeft).toLocaleString()}</b>
				</div>
				<div class="info-row">
					<span>Your Score so far</span><b class="pos"
						>${Math.round(matchInfo?.total_score ?? 0).toLocaleString()}</b
					>
				</div>
				<div class="info-row">
					<span>Your ante</span><b>${(matchInfo?.wager ?? 0).toLocaleString()}</b>
				</div>
				<div class="info-row">
					<span>Playing for</span><b class="pos">${matchPot.toLocaleString()} pot</b>
				</div>
				<div class="info-row"><span>Lose the duel</span><b class="neg">forfeit your ante</b></div>
			</div>
			<p class="info-note">
				Highest Score wins the pot. Duel = winner-take-all (tie splits 50/50); groups pay a podium
				(3 → 70/30, 4+ → 60/30/10). A wrong guess busts the puzzle, so guess only when you're sure.
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
			<button class="modal-x" on:click={() => (debuffModal = null)} aria-label="Close"
				><Icon name="close" size={16} /></button
			>
			<div class="info-big"><Icon name="sabotage" size={38} /></div>
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
			<button class="modal-x" on:click={() => (sabPicker = null)} aria-label="Cancel"
				><Icon name="close" size={16} /></button
			>
			<div class="info-big">
				<Icon name={PUP_ICON[sabPicker.item.id] ?? 'sabotage'} size={40} />
			</div>
			<h3 class="info-title">{sabPicker.item.name} — hit who?</h3>
			<div class="sab-target-list">
				{#each sabPicker.opponents as o}
					<button class="sab-target-row" on:click={() => applySabotage(o.id)}>
						<span class="st-name">{o.name}</span>
						<span class="st-stat"
							><Icon name="puzzle" size={14} /> Puzzle {o.position} · ${Number(
								o.ante_left ?? 0
							).toLocaleString()}</span
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
			<button class="modal-x" on:click={() => (showResumeMenu = false)} aria-label="Close"
				><Icon name="close" size={16} /></button
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
						<span class="rm-ic"><ModeIcon mode={r.modeKey} size={20} /></span><span class="rm-label"
							>{r.label}</span
						><span class="rm-arrow"><Icon name="play" size={11} /></span>
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
			<button class="modal-x" on:click={() => (showAudio = false)} aria-label="Close"
				><Icon name="close" size={16} /></button
			>
			<h3 class="info-title">Sound &amp; Music</h3>
			<div class="ap-rows">
				<button
					class="ap-toggle"
					on:click={() => {
						toggleSound();
						if ($soundEnabled) fx('select');
					}}
				>
					<span><Icon name={$soundEnabled ? 'volume' : 'mute'} size={16} /> Sound</span><span
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
					<span><Icon name={$hapticsEnabled ? 'vibrate' : 'vibrate-off'} size={16} /> Haptics</span
					><span class="ap-state" class:on={$hapticsEnabled}>{$hapticsEnabled ? 'On' : 'Off'}</span>
				</button>
				<button class="ap-toggle" on:click={toggleMusic}>
					<span>Music</span><span class="ap-state" class:on={$musicEnabled}
						>{$musicEnabled ? 'On' : 'Off'}</span
					>
				</button>
			</div>
			{#if $musicEnabled}
				<div class="ma-music-ctl">
					<span class="mmc-ic"><Icon name="volume-low" size={16} /></span>
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

<main class:danger-active={dangerMode && !overdriveArmed && $gameStore.gameState !== 'guess_mode'}>
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
			<!-- 🏦 Bank-app header: greeting + notifications + profile monogram -->
			<div class="menu-hero">
				<div class="hero-greet">
					Hi, <span class="hg-name">{$userProfile?.username ?? myUsername ?? 'wordbanker'}</span>
				</div>
				<div class="hero-actions">
					<button
						class="hero-ic"
						on:click={() => goto('/profile?tab=alerts')}
						title="Notifications"
						aria-label="Notifications"
					>
						<svg class="hero-bell-ic" viewBox="0 0 24 24" aria-hidden="true">
							<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9" />
							<path d="M10.3 21a1.94 1.94 0 0 0 3.4 0" />
						</svg>{#if $unreadCount > 0}<span class="account-count" title="{$unreadCount} new"
								>{$unreadCount > 99 ? '99+' : $unreadCount}</span
							>{/if}
					</button>
					<button
						class="hero-mono"
						on:click={() => goto('/profile')}
						title="Profile"
						aria-label="Profile"
					>
						{(String($userProfile?.username ?? myUsername ?? 'W').charAt(0) || 'W').toUpperCase()}
					</button>
				</div>
			</div>
			{#if menuView === 'home'}
				<!-- 💳 Account card — tap to open the Bank hub -->
				<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
				<div
					class="menu-card-wrap"
					role="button"
					tabindex="0"
					on:click={() => goto('/bank')}
					on:keydown={(e) => {
						if (e.key === 'Enter' || e.key === ' ') {
							e.preventDefault();
							goto('/bank');
						}
					}}
					aria-label="Open My Account"
				>
					<AccountCard
						holder={$userProfile?.username ?? myUsername}
						account={$userProfile?.account_number ?? ''}
						member={$userProfile?.member_no ?? null}
						balance={menuBank ?? $userProfile?.bank ?? 0}
						tier={menuCreditTier ?? 'Good'}
						loan={menuLoan}
					/>
				</div>
				<!-- ⚡ Bank-app quick actions — horizontally swipeable (flat line icons) -->
				<div class="qt-wrap" class:qt-end={qtAtEnd}>
					<div class="quick-tiles" use:qtInit on:scroll={updateQt}>
						<button class="qt" on:click={() => openCommunity('people')}>
							<span class="qt-plus" aria-hidden="true">+</span>
							<svg class="qt-svg" viewBox="0 0 24 24" aria-hidden="true">
								<circle cx="9" cy="7" r="3" />
								<path d="M3 20a6 6 0 0 1 12 0" />
								<path d="M16 4.5a3 3 0 0 1 0 5.5" />
								<path d="M18 13.5a6 6 0 0 1 3 5.5" />
							</svg><span class="qt-l">Friends</span>
						</button>
						<button class="qt" class:qt-locked={menuLoan > 0} on:click={() => goto('/shop')}>
							<svg class="qt-svg" viewBox="0 0 24 24" aria-hidden="true">
								<path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
								<path d="M3 6h18" />
								<path d="M16 10a4 4 0 0 1-8 0" />
							</svg><span class="qt-l"
								>{#if menuLoan > 0}<Icon name="lock" size={13} /> Store{:else}Store{/if}</span
							>
						</button>
						<button class="qt" on:click={() => openCommunity('leaderboard')}>
							<svg class="qt-svg" viewBox="0 0 24 24" aria-hidden="true">
								<path d="M8 4h8v5a4 4 0 0 1-8 0V4Z" />
								<path d="M8 5.5H5.2A1.2 1.2 0 0 0 4 6.7C4 8.8 5.8 10 8 10" />
								<path d="M16 5.5h2.8A1.2 1.2 0 0 1 20 6.7C20 8.8 18.2 10 16 10" />
								<path d="M12 13v3" /><path d="M9.5 20h5" /><path d="M10 20a2 2 0 0 1 4 0" />
							</svg><span class="qt-l">Ranks</span>
						</button>
						<button class="qt" on:click={() => goto('/loans')}>
							<svg class="qt-svg" viewBox="0 0 24 24" aria-hidden="true">
								<rect x="3" y="6.5" width="18" height="11" rx="2" />
								<circle cx="12" cy="12" r="2.3" />
								<path d="M6 10.5v3M18 10.5v3" />
							</svg><span class="qt-l">Loans</span>
						</button>
						<button class="qt" on:click={openBag}>
							<svg class="qt-svg" viewBox="0 0 24 24" aria-hidden="true">
								<rect x="3.5" y="3.5" width="7" height="7" rx="1.5" />
								<rect x="13.5" y="3.5" width="7" height="7" rx="1.5" />
								<rect x="3.5" y="13.5" width="7" height="7" rx="1.5" />
								<rect x="13.5" y="13.5" width="7" height="7" rx="1.5" />
							</svg><span class="qt-l">Items</span>
						</button>
						<button class="qt" on:click={() => goto('/streak')}>
							<svg class="qt-svg" viewBox="0 0 24 24" aria-hidden="true">
								<path d="M12 3s5 3.8 5 9a5 5 0 0 1-10 0c0-2 .9-3.5 2.4-4.6C10.2 8.7 12 7 12 3Z" />
							</svg><span class="qt-l">Streak</span>
						</button>
						<button class="qt" on:click={() => goto('/badges')}>
							<svg class="qt-svg" viewBox="0 0 24 24" aria-hidden="true">
								<circle cx="12" cy="9" r="5" />
								<path d="M8.5 13 7 21l5-2.7L17 21l-1.5-8" />
								<path
									d="m12 6.9.85 1.7 1.9.28-1.37 1.32.32 1.9L12 11.4l-1.7.9.32-1.9L9.25 8.88l1.9-.28Z"
								/>
							</svg><span class="qt-l">Badges</span>
						</button>
						<button class="qt" on:click={() => goto('/activity')}>
							<svg class="qt-svg" viewBox="0 0 24 24" aria-hidden="true">
								<path d="M3 12h3.5l2-6 4 13 2.5-7H21" />
							</svg><span class="qt-l">Activity</span>
						</button>
					</div>
					<span class="qt-more" aria-hidden="true">›</span>
				</div>
				<div class="main-menu-buttons stagger">
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
						class="play-cta"
						style="--i: 0"
						on:click={() => {
							menuView = 'play';
							fx('tap');
						}}
					>
						<span class="pc-ic"><Icon name="play" size={12} /></span>
						<span class="pc-label">Play Now</span>
					</button>
					<!-- ⚔️ Challenges hub (list + New). Incoming invites alert via the bell → tap routes here. -->
					<button
						class="challenge-cta"
						style="--i: 1"
						on:click={() => {
							fx('tap');
							openCommunity('challenges');
						}}
					>
						<span class="cc-ic"><ModeIcon mode="challenge" size={20} /></span> Challenge Friends
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
						class="menu-card has-streaks"
						class:done={dailyDone}
						class:resumable={dailyInProgress}
						class:fresh={!dailyDone && !dailyInProgress}
						style="--i: 0"
						on:click={handleMenuDaily}
					>
						<span class="mc-streak left" title="Play streak — days in a row"
							><ModeIcon mode="daily" size={14} /> {dailyStatus?.current_streak ?? 0}</span
						>
						<span class="mc-title">{dailyInProgress ? 'Resume Daily' : 'Daily'}</span>
						<span class="mc-right">
							{#if dailyDone}
								{#if dailyStatus?.last_daily_won}
									<span class="daily-chip won"
										><Icon name="check" size={13} /> +${(
											dailyStatus?.today_score ?? 0
										).toLocaleString()}</span
									>
								{:else}
									<span class="daily-chip lost"
										><Icon name="close" size={13} />{dailyStatus?.today_score
											? ' −$' + Math.abs(dailyStatus.today_score).toLocaleString()
											: ''}</span
									>
								{/if}
							{:else if dailyInProgress}
								<span class="daily-chip prog"><Icon name="play" size={11} /> Resume</span>
							{/if}
							<span class="mc-streak win" title="Win streak — solves in a row"
								><svg class="mc-fire" viewBox="0 0 24 24" aria-hidden="true"
									><path
										d="M12 3s5 3.8 5 9a5 5 0 0 1-10 0c0-2 .9-3.5 2.4-4.6C10.2 8.7 12 7 12 3Z"
									/></svg
								>
								{dailyStatus?.win_streak ?? 0}</span
							>
						</span>
					</button>
					<button class="menu-card fp-card" style="--i: 1" on:click={handleFreePlay}>
						<Icon name="puzzle" size={20} /><span class="mc-title">Free Play</span>
						<span class="mc-right"
							><span class="daily-chip">Best {freePlayPoints().best} pts</span></span
						>
					</button>
					<button
						class="menu-card"
						class:resumable={climbInProgress}
						style="--i: 2"
						on:click={handleMenuClimb}
					>
						<ModeIcon mode="climb" size={22} /><span class="mc-title">Cash Game</span>
						{#if climbInProgress}<span class="daily-chip prog"
								><Icon name="play" size={11} /> Resume</span
							>{/if}
					</button>
				</div>
			{:else if menuView === 'community'}
				<div class="sub-head">
					{#if communityTab === 'people'}
						{#if peopleBackToHome}
							<button class="sub-back" on:click={exitCommunity}>← Back</button>
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
						<button class="sub-back" on:click={exitCommunity}>← Back</button>
						<h2 class="sub-title">
							{#if communityTab === 'leaderboard'}<Icon name="trophy" size={16} /> Leaderboard{:else}<ModeIcon
									mode="challenge"
									size={17}
								/> Challenges{/if}
						</h2>
						{#if communityTab === 'challenges'}
							<button
								class="sub-people"
								title="Add Friends"
								aria-label="Add Friends"
								on:click={() => {
									communityTab = 'people';
									peopleBackToHome = false;
									fx('tap');
								}}><span class="sp-plus">+</span> Add Friends</button
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
					<button class="close-btn" on:click={() => (showTierSelect = false)}
						><Icon name="close" size={16} /></button
					>
					<h2>Cash Game</h2>
					<div class="cg-tagline"><Icon name="fire" size={16} /> Solve to Earn</div>
					<p class="cat-sub">
						Spend to solve each puzzle cheaply, keep what's left, and grow your Payout across
						puzzles. Cash out anytime — but run out of budget and you bust. Higher tiers, bigger
						payouts.
					</p>
					<div class="tier-balance">
						Your Cash <b class:neg={cgBroke}>${(cgMeta?.bank ?? 0).toLocaleString()}</b>
					</div>
					<div class="tier-grid">
						{#each cgMeta?.tiers ?? [] as t}
							<button
								class="tier-tile"
								class:locked={!t.unlocked}
								disabled={cgBusy || !t.unlocked || (cgMeta?.bank ?? 0) < t.buy_in}
								on:click={() => pickTier(t.tier)}
							>
								<span class="tt-label">{t.label}</span>
								<span class="tt-buyin">${t.buy_in.toLocaleString()} <small>buy-in</small></span>
								<span class="tt-meta">interest to +{Math.round(t.heat_cap - 100)}%</span>
								{#if !t.unlocked}<span class="tt-lock"
										><Icon name="lock" size={13} />
										{t.tier === 'silver'
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
					{#if cgBroke}
						<div class="tier-broke">
							<p class="tb-text">Not enough Cash to buy in — grab some first:</p>
							<div class="tb-actions">
								<button
									class="tb-btn loan"
									on:click={() => {
										showTierSelect = false;
										goto('/loans');
									}}>Take out a loan</button
								>
								<button
									class="tb-btn daily"
									on:click={() => {
										showTierSelect = false;
										handleMenuDaily();
									}}>Play the Daily</button
								>
							</div>
							<p class="tb-hint">The Daily is free — wins pay Cash, and a streak pays even more.</p>
						</div>
					{/if}
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
					<button class="close-btn" on:click={() => (showChallenges = false)}
						><Icon name="close" size={16} /></button
					>

					<h2><ModeIcon mode="challenge" size={20} /> New Challenge</h2>
					<div class="ch-steps" aria-hidden="true">
						<span class="ch-dot" class:on={mbStep >= 1}></span>
						<span class="ch-dot" class:on={mbStep >= 2}></span>
						<span class="ch-dot" class:on={mbStep >= 3}></span>
					</div>

					<div class="ch-new">
						{#if mbStep === 1}
							<!-- Step 1 · Who -->
							<div class="ch-step-title">Who are you challenging?</div>
							<div class="ch-modes">
								<button
									type="button"
									class="ch-mode"
									class:active={mbTarget === 'friend'}
									on:click={() => (mbTarget = 'friend')}
									><Icon name="user" size={16} /> A friend<small>by username</small></button
								>
								<button
									type="button"
									class="ch-mode"
									class:active={mbTarget === 'group'}
									on:click={() => (mbTarget = 'group')}
									><Icon name="users" size={16} /> A group<small>everyone in it</small></button
								>
							</div>
							{#if mbTarget === 'friend'}
								{#if mbOpponent}
									<div class="ch-opp-picked">
										<span>vs <b>@{mbOpponent}</b></span>
										<button type="button" class="ch-opp-change" on:click={() => (mbOpponent = '')}
											>Change</button
										>
									</div>
								{:else}
									<input
										class="ch-input"
										placeholder="Search friends or players"
										bind:value={mbSearch}
										on:input={onMbOppInput}
										autocomplete="off"
									/>
									<div class="ch-picklist">
										{#each mbFriendsShown as f}
											<button
												type="button"
												class="ch-pickrow"
												on:click={() => pickMbOpp(f.username)}
											>
												<span class="ch-pickname">@{f.username}</span>
												<span class="ch-picktag friend">friend</span>
											</button>
										{/each}
										{#each mbNonFriends as r}
											<button
												type="button"
												class="ch-pickrow"
												on:click={() => pickMbOpp(r.username)}
											>
												<span class="ch-pickname">@{r.username}</span>
												<span class="ch-picktag">+ add</span>
											</button>
										{/each}
										{#if !mbFriendsShown.length && !mbNonFriends.length}
											<p class="ch-hint" style="margin:8px 0 0">
												{mbSearch.trim()
													? 'No players found.'
													: 'No friends yet — search a username to challenge anyone.'}
											</p>
										{/if}
									</div>
								{/if}
							{:else}
								<select class="ch-input" bind:value={mbGroupId}>
									<option value="" disabled selected>Pick a group</option>
									{#each myGroups as g}<option value={g.id}>{g.name} ({g.members})</option>{/each}
								</select>
							{/if}
						{:else if mbStep === 2}
							<!-- Step 2 · Match -->
							<div class="ch-step-title">The match</div>

							<div class="ch-field">
								<span>Categories <em class="ch-opt">(optional)</em></span>
								<div class="ch-catlist">
									{#each CATEGORIES as c}
										<button
											type="button"
											class="ch-catrow"
											class:on={mbCategories.includes(c.value)}
											on:click={() => toggleCategory(c.value)}
										>
											<span class="ch-catemoji"><CategoryIcon category={c.value} size={19} /></span>
											<span class="ch-catname">{c.label}</span>
											<span class="ch-catcheck"
												>{#if mbCategories.includes(c.value)}<Icon
														name="check"
														size={13}
													/>{/if}</span
											>
										</button>
									{/each}
								</div>
								<p class="ch-hint">
									{mbCategories.length ? mbCategories.length + ' selected' : 'Any category'}
								</p>
							</div>

							<div class="ch-field">
								<span>Puzzles</span>
								<div class="ch-seg">
									{#each [1, 3, 5, 10] as n}<button
											type="button"
											class="ch-seg-btn"
											class:on={mbPackSize === n}
											on:click={() => (mbPackSize = n)}>{n}</button
										>{/each}
								</div>
							</div>
						{:else}
							<!-- Step 3 · Stakes -->
							<div class="ch-step-title">The stakes</div>
							<div class="ch-field ch-ante">
								<span>Ante</span>
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
							</div>
							<label class="ch-field"
								><span>Respond within</span>
								<select class="ch-input" bind:value={mbWindow}
									>{#each WINDOWS as w}<option value={w.s}>{w.l}</option>{/each}</select
								>
							</label>
							<button
								class="ch-toggle"
								class:on={mbItemsAllowed}
								on:click={() => {
									mbItemsAllowed = !mbItemsAllowed;
									fx('tap');
								}}
							>
								<span class="ch-tog-box"
									>{#if mbItemsAllowed}<Icon name="check" size={13} />{/if}</span
								>
								<Icon name="bolt" size={14} /> Allow power-ups
							</button>
							<p class="ch-objective">{potSummary}</p>
						{/if}

						{#if mbMsg}<p class="add-msg">{mbMsg}</p>{/if}

						<div class="ch-nav">
							{#if mbStep > 1}
								<button type="button" class="ch-back" on:click={() => (mbStep -= 1)}>Back</button>
							{/if}
							{#if mbStep < 3}
								<button
									type="button"
									class="ch-create ch-grow"
									disabled={mbStep === 1 && !mbStep1Ok}
									on:click={() => (mbStep += 1)}>Continue</button
								>
							{:else}
								<button class="ch-create ch-grow" disabled={mbBusy} on:click={submitNewMatch}
									>Send challenge <ModeIcon mode="challenge" size={17} /></button
								>
							{/if}
						</div>
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
					<div class="sm-icon"><Icon name="broke" size={34} /></div>
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
					<button class="close-btn" on:click={() => (showStreakMessage = false)}
						><Icon name="close" size={16} /></button
					>
					<div class="cbt-medal">
						{#if dailyStatus?.last_daily_won}<Icon name="check" size={30} />{:else}<Icon
								name="flag"
								size={30}
							/>{/if}
					</div>
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
								<span class="cbt-val"
									><Icon name="fire" size={15} /> {dailyStatus?.current_streak}</span
								><span class="cbt-cap">Play streak</span>
							</div>
						{/if}
					</div>
					<p class="streak-message">
						{#if (dailyStatus?.current_streak ?? 0) > 0}Come back tomorrow for a new puzzle to keep
							your <Icon name="fire" size={13} />
							{dailyStatus?.current_streak}-day streak alive!{:else}Come back tomorrow for a fresh
							puzzle and start a streak!{/if}
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
					<button class="close-btn" on:click={() => (showMyAccount = false)}
						><Icon name="close" size={16} /></button
					>
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
							<span><Icon name={$soundEnabled ? 'volume' : 'mute'} size={16} /> Sound</span><span
								class="set-state"
								class:on={$soundEnabled}>{$soundEnabled ? 'On' : 'Off'}</span
							>
						</button>
						<button
							class="set-row"
							on:click={() => {
								toggleHaptics();
								if ($hapticsEnabled) fx('tap');
							}}
						>
							<span
								><Icon name={$hapticsEnabled ? 'vibrate' : 'vibrate-off'} size={16} /> Haptics</span
							><span class="set-state" class:on={$hapticsEnabled}
								>{$hapticsEnabled ? 'On' : 'Off'}</span
							>
						</button>
						<button class="set-row" on:click={toggleMusic}>
							<span>Music</span><span class="set-state" class:on={$musicEnabled}
								>{$musicEnabled ? 'On' : 'Off'}</span
							>
						</button>
						{#if $musicEnabled}
							<div class="set-row sub">
								<span class="mmc-ic"><Icon name="volume-low" size={16} /></span>
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
							}}
							><span><Icon name="hand" size={15} /> Friends</span><span class="chev">›</span
							></button
						>
						<button
							class="set-row nav"
							on:click={() => {
								showMyAccount = false;
								peopleTab = 'groups';
								openCommunity('people');
							}}
							><span><Icon name="users" size={15} /> Groups</span><span class="chev">›</span
							></button
						>
					</div>

					<!-- Security -->
					{#if hasPin}
						<div class="set-label">Security</div>
						<div class="set-group">
							<button class="set-row nav" on:click={changePin}
								><span><Icon name="key" size={15} /> Change PIN</span><span class="chev">›</span
								></button
							>
							<button class="set-row nav" on:click={forgotPin}
								><span><Icon name="unlock" size={15} /> Forgot PIN?</span><span class="chev">›</span
								></button
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
							}}
							><span><Icon name="help" size={15} /> How to Play</span><span class="chev">›</span
							></button
						>
						<a class="set-row nav" href="/privacy" target="_blank" rel="noopener noreferrer"
							><span><Icon name="lock" size={15} /> Privacy Policy</span><span class="chev">↗</span
							></a
						>
						<a class="set-row nav" href="/terms" target="_blank" rel="noopener noreferrer"
							><span><Icon name="doc" size={15} /> Terms of Service</span><span class="chev"
								>↗</span
							></a
						>
						<a class="set-row nav" href={`mailto:${SUPPORT_EMAIL}`}
							><span><Icon name="mail" size={15} /> Contact Support</span><span class="chev"
								>↗</span
							></a
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
							}}
							><span><Icon name="door" size={15} /> Log Out</span><span class="chev">›</span
							></button
						>
						<button
							class="set-row nav danger"
							on:click={() => {
								deleteInput = '';
								maMsg = '';
								showDeleteConfirm = true;
							}}
							><span><Icon name="trash" size={15} /> Delete Account</span><span class="chev">›</span
							></button
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
					<div class="info-big"><Icon name="trash" size={38} /></div>
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

		<!-- 🚨 Last-stand red vignette — frames the whole screen when you're out of money. -->
		{#if dangerMode}
			<div class="danger-vignette" class:daily={isDaily} aria-hidden="true"></div>
		{/if}

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
				<span class="mp-emoji"><ModeIcon mode={$gameStore.gameMode} size={15} /></span
				>{modeLabel.name}{#if isClimb && climb?.buy_in}<span class="mp-sub"
						>· {(climb.tier ?? '').charAt(0).toUpperCase() + (climb.tier ?? '').slice(1)} · ${Math.round(
							climb.buy_in ?? 0
						).toLocaleString()}</span
					>{/if}<span class="mp-info"><Icon name="info" size={13} /></span>
			</button>
		{/if}

		<!-- ★ Free Play HUD — points earned this device + Next/Skip (freeplay only, no money). -->
		{#if $gameStore.gameMode === 'freeplay'}
			<div class="fp-hud">
				<span class="fp-pts">★ {fpPoints.total} pts</span>
				<span class="fp-budget">Budget: {$gameStore.dailyLive?.remaining ?? 0}</span>
				<button
					class="fp-next"
					on:click={() => {
						fx('tap');
						freePlayNext();
					}}>{$gameStore.gameState === 'won' ? 'Next puzzle →' : 'Skip →'}</button
				>
			</div>
		{/if}

		<!-- Daily solve timer — subtle server-anchored count-up (Daily only). -->
		{#if $gameStore.gameMode === 'daily' && $gameStore.currentPhrase}
			<div class="daily-timer-wrap">
				<SolveTimer
					openedAt={$gameStore.dailyOpenedAt}
					bestSeconds={$gameStore.dailyBestSeconds}
					active={dailyTimerActive}
					solved={$gameStore.gameState === 'won'}
				/>
			</div>
		{/if}

		<!-- 💰 Bankroll — top of every mode. Challenge ante now lives in the bounty hero below. -->
		{#if $gameStore.currentPhrase && $gameStore.gameMode}
			<!-- 🪙 Small ambient bankroll chip — your account, shown quietly; the hero number
             below is the game money. Static during play; tap → bank. -->
			<button
				class="bankroll-chip"
				title="Your account balance"
				on:click={() => {
					fx('tap');
					showBalanceInfo = true;
				}}
			>
				<img class="brc-coin" src="/logo-coin.png" alt="" width="16" height="16" />
				<span class="brc-amt">${Math.round(menuBank ?? netWorth ?? 0).toLocaleString()}</span>
			</button>
		{/if}

		<!-- 🔍 Diagnostic banner (shows when init failed) -->
		{#if initError}
			<div class="diagnostic-banner">
				<strong><Icon name="warning" size={14} /> Diagnostic:</strong>
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

		<!-- 🗓️ Make-up daily banner -->
		{#if isMakeup}
			<div class="makeup-banner">
				<span class="mb-tag"><Icon name="calendar" size={13} /> Make-up</span>
				<span class="mb-text">{makeupLabel}</span>
			</div>
		{/if}

		<!-- 🎰 Cash Game (Climb) HUD — account strip up top; Interest badge + Payout in the
         hero. Must-guess banner shows when this puzzle's budget is spent. -->
		{#if isClimb && climb}
			{#if overdriveArmed && $gameStore.gameState !== 'won' && $gameStore.gameState !== 'lost'}
				<!-- 🏧 Overdrive armed → guide the player to spend the free letter (danger lifts). -->
				<div class="danger-cue armed" role="status">
					<span class="dc-title"><Icon name="card" size={16} /> OVERDRIVE ARMED</span>
					<span class="dc-sub">Pick any letter — it's free</span>
				</div>
			{:else if dangerMode}
				<!-- 🚨 Last stand: out of money, this guess decides the run. -->
				<div class="danger-cue" role="alert">
					<span class="dc-title"><Icon name="broke" size={16} /> OUT OF MONEY</span>
					<span class="dc-sub">Last guess — solve now, or lose your run</span>
					<button class="dc-freeplay" on:click={handleFreePlay}>Keep playing free →</button>
					<button class="bn-forfeit" on:click={askForfeit}>Give up?</button>
				</div>
			{/if}
		{/if}

		<!-- 🚨 Daily out-of-budget wall — softer than Cash Game (no run to lose, just
		     today's win on the line). Same red screen + keyboard lock structure. -->
		{#if isDaily && dangerMode}
			<div class="danger-cue daily" role="alert">
				<span class="dc-title"><Icon name="broke" size={16} /> OUT OF BUDGET</span>
				<span class="dc-sub">Last guess — get it right to win today</span>
				<button class="bn-forfeit" on:click={confirmFold}>Give up?</button>
			</div>
		{/if}

		<!-- ⚔️ Challenge match HUD -->
		{#if isMatch && matchInfo && !matchInfo.done}
			<!-- 🏆 Your Score — the accumulated bounty-kept you win the pot on. The center hero
             below is just this puzzle's fresh bounty; this is the number that matters. -->
			<div class="match-score">
				<span class="ms-cap">Your Score</span>
				<span class="ms-val">${Math.round(matchInfo.total_score ?? 0).toLocaleString()}</span>
			</div>
			<div class="match-meta">
				{#if matchPot > 0}<span class="pot-chip">Pot ${matchPot.toLocaleString()}</span>{/if}
				{#if matchInfo.target != null}<span class="beat-chip"
						>Beat ${Number(
							matchInfo.target
						).toLocaleString()}{#if matchInfo.target_kind === 'place'}
							to place{/if}</span
					>{/if}
				{#if matchInfo.pack_size > 1}<span class="match-pos"
						>Puzzle {matchInfo.position}/{matchInfo.pack_size}</span
					>{/if}
			</div>
			<StandingStrip standing={matchInfo.standing ?? null} />
			{#if (matchInfo.my_debuffs ?? []).length}
				<button
					type="button"
					class="debuff-banner"
					on:click={openDebuffInfo}
					title="Who hit you & what it does"
				>
					{(matchInfo.my_debuffs ?? [])
						.map((/** @type {string} */ d) => DEBUFF_LABEL[d] ?? d)
						.join(' · ')} <span class="db-info"><Icon name="info" size={13} /></span>
				</button>
			{/if}
			<!-- Power-ups & sabotage all live in the 🔐 vault beside Solve now. -->
		{/if}

		<!-- 🌍 Category + today's auto-applied Twist chip + witty clue -->
		<div class="puzzle-meta">
			{#if $gameStore.category}<span class="category-chip"
					><CategoryIcon category={$gameStore.category} size={14} />{categoryLabel(
						$gameStore.category
					)}</span
				>{/if}
			{#if $gameStore.gameMode === 'daily' && dailyMod}
				<button
					class="twist-chip"
					title="Today's special — tap to see"
					on:click={() => {
						fx('tap');
						dailyInfo = 'twist';
					}}><Icon name={dailyMod.emoji} size={18} /></button
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
				<span class="ta-name"><Icon name={dailyMod.emoji} size={20} /> {dailyMod.name}</span>
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
				<span class="fold-timer"
					><Icon name="timer" size={13} /> 0:{String(brokeLeft).padStart(2, '0')}</span
				>
				<span class="fold-warn">Out of Cash — guess in time or you give up this one</span>
			</div>
		{/if}

		<!-- 💰 Money hero -->
		<section class="stats-section">
			{#if soloHero}
				<!-- Daily · Cash Game hero = Payout (bounty − spent, the cash you keep by solving efficiently). -->
				<div
					class="bounty-panel"
					class:loss={!isMatch && soloHero.net < 0}
					class:ante-empty={isMatch && matchLeft <= 0}
					class:count-pop={introCountPop}
				>
					<div class="bp-row">
						{#if $gameStore.gameMode === 'daily' && Number($gameStore.bountyMult ?? 1) > 1}
							<!-- Daily badge only appears when a 💥/💎 boost is active (no streak interest). -->
							<button
								class="bp-mult-badge"
								title="Interest — earned from your streak + credit, plus boosts"
								on:click={openDailyMult}
								>+{Math.round((Number($gameStore.bountyMult ?? 1) - 1) * 100)}%</button
							>
						{:else if isClimb}
							<button
								class="bp-mult-badge"
								title="Interest — boosts each puzzle's value as it lands in your Payout"
								on:click={() => {
									fx('tap');
									climbInfo = 'heat';
								}}>+{Math.round((climb?.heat ?? 100) - 100)}%</button
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
								}}
								><svg class="bp-fire" viewBox="0 0 24 24" aria-hidden="true"
									><path
										d="M12 3s5 3.8 5 9a5 5 0 0 1-10 0c0-2 .9-3.5 2.4-4.6C10.2 8.7 12 7 12 3Z"
									/></svg
								>{dailyStatus?.win_streak ?? 0}</button
							>
						{:else if isClimb}
							<button
								class="bp-winstreak"
								title="Deposit streak"
								on:click={() => {
									fx('tap');
									climbInfo = 'streak';
								}}
								><svg class="bp-fire" viewBox="0 0 24 24" aria-hidden="true"
									><path
										d="M12 3s5 3.8 5 9a5 5 0 0 1-10 0c0-2 .9-3.5 2.4-4.6C10.2 8.7 12 7 12 3Z"
									/></svg
								>{climbStreak}</button
							>
						{:else}
							<span class="bp-badge-spacer"></span>
						{/if}
					</div>
					{#each spendFloaters as f (f.id)}<span class="spend-float" class:wrong={f.wrong}
							>{f.text}</span
						>{/each}
					{#if carryCue > 0}
						<span class="carry-float">+${carryCue.toLocaleString()}</span>
					{/if}
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
			{/if}
		</section>

		<!-- 💥 Double or Nothing — Cash Game only, when heat ≥ ×1.5. Arm to double the payout. -->
		{#if isClimb && climb && $gameStore.gameState !== 'won'}
			{#if donAvailable}
				<button class="don-cta" on:click={openDon}>
					<span class="don-cta-title"><Icon name="boost" size={15} /> Double or Nothing</span>
					<span class="don-cta-sub">Solve for <b>${donTarget.toLocaleString()}</b> · all-in</span>
				</button>
			{:else if donArmed}
				<div class="don-armed" role="status">
					<span class="don-armed-title"><Icon name="boost" size={15} /> Doubled — all in</span>
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
							<svg class="qt-svg" viewBox="0 0 24 24" aria-hidden="true">
								<rect x="3.5" y="3.5" width="7" height="7" rx="1.5" />
								<rect x="13.5" y="3.5" width="7" height="7" rx="1.5" />
								<rect x="3.5" y="13.5" width="7" height="7" rx="1.5" />
								<rect x="13.5" y="13.5" width="7" height="7" rx="1.5" />
							</svg>
							{#if usableClimbPups > 0}<span class="solve-vault-badge">{usableClimbPups}</span>{/if}
						</button>
					{:else if isMatch && matchInfo?.items_allowed && !matchInfo?.done && gameActive}
						<button
							class="solve-vault"
							on:click={openBag}
							title="Your power-ups"
							aria-label="Open your vault"
						>
							<svg class="qt-svg" viewBox="0 0 24 24" aria-hidden="true">
								<rect x="3.5" y="3.5" width="7" height="7" rx="1.5" />
								<rect x="13.5" y="3.5" width="7" height="7" rx="1.5" />
								<rect x="3.5" y="13.5" width="7" height="7" rx="1.5" />
								<rect x="13.5" y="13.5" width="7" height="7" rx="1.5" />
							</svg>
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
			<div class="banner lose">
				{#if isClimb}<Icon name="warning" size={16} /> BUST{:else}No luck{/if}
			</div>
		{/if}

		<!-- 💸 Deposit-lands beat: coins fly into the account card + balance counts up, before the slip -->
		{#if depositAnim}
			<div
				class="deposit-anim"
				role="button"
				tabindex="0"
				aria-label="Continue to receipt"
				on:click={finishDepositAnim}
				on:keydown={(e) => {
					if (e.key === 'Enter' || e.key === ' ' || e.key === 'Escape') finishDepositAnim();
				}}
			>
				<div class="da-title">Depositing…</div>
				<div class="da-stage">
					<div class="da-card">
						<AccountCard
							holder={$userProfile?.username ?? myUsername}
							account={$userProfile?.account_number ?? ''}
							member={$userProfile?.member_no ?? null}
							balance={Math.round($depositBank)}
							tier={menuCreditTier ?? 'Good'}
						/>
					</div>
					<div class="da-amount">+${depositAnim.amount.toLocaleString()}</div>
					<div class="da-coins">
						{#each depositCoins as c (c.id)}
							<img
								class="da-coin"
								src="/logo-coin.png"
								alt=""
								style="--dx:{c.dx}px; --delay:{c.delay}ms; --rot:{c.rot}deg"
							/>
						{/each}
					</div>
				</div>
				<div class="da-hint">tap to continue</div>
			</div>
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
						{@const interestPct = Math.round((mult - 1) * 100)}
						{@const interestBonus = Math.max(0, banked - kept)}
						{@const attendance = Number(dr.attendance ?? 0)}
						{@const loanRepaid = Number(dr.loan_repaid ?? 0)}
						{@const acctNow = Math.round(menuBank ?? netWorth ?? 0)}
						<!-- Account before today: back out the show-up bonus + this deposit (net of the skim). -->
						{@const startBal = acctNow - attendance - banked + loanRepaid}
						<!-- 🧾 Daily DEPOSIT slip: Budget − Letters = Subtotal ×Interest = Deposit -->
						<div class="rcpt-slot" aria-hidden="true"></div>
						<div class="receipt" use:printSound>
							<div class="rcpt-brand">
								<img class="rcpt-coin" src="/logo-coin.png" alt="" width="40" height="40" />
								<img class="rcpt-mark" src="/wordmark.png" alt="WordBank" />
							</div>
							<div class="rcpt-title">DEPOSIT SLIP</div>
							<div class="rcpt-acct">WORDBANK CHECKING</div>
							<div class="rcpt-sub">
								ACCT ·········{acctNo}{#if myUsername}
									· @{myUsername}{/if}
							</div>
							<div class="rcpt-rule"></div>
							<div class="rcpt-info">
								<div class="ri-row"><span>{rcptDate}</span><span>{rcptTime}</span></div>
								<div class="ri-row">
									<span>DAILY</span><span
										>{dlWinStreak > 0 ? `${dlWinStreak} DAY STREAK` : 'FIRST WIN'}</span
									>
								</div>
							</div>
							<div class="rcpt-rule"></div>
							<div class="rcpt-line">
								<span>Starting Balance</span><span>${startBal.toLocaleString()}</span>
							</div>
							{#if attendance > 0}
								<div class="rcpt-line">
									<span>Show-up bonus</span><span class="pos">+${attendance.toLocaleString()}</span>
								</div>
							{/if}
							<div class="rcpt-rule"></div>
							<div class="rcpt-line">
								<span>Budget</span><span>${prize.toLocaleString()}</span>
							</div>
							<div class="rcpt-line">
								<span>Letters (debit)</span><span class="neg"
									>−${(dr.spent ?? 0).toLocaleString()}</span
								>
							</div>
							<div class="rcpt-rule"></div>
							<div class="rcpt-line">
								<span>Subtotal</span><span>${kept.toLocaleString()}</span>
							</div>
							{#if interestPct > 0}
								<div class="rcpt-line">
									<span>Boost +{interestPct}%</span><span class="pos"
										>+${interestBonus.toLocaleString()}</span
									>
								</div>
							{/if}
							<div class="rcpt-rule double"></div>
							<div class="rcpt-line total profit">
								<span>DEPOSIT</span><span>+${banked.toLocaleString()}</span>
							</div>
							{#if Number(dr.loan_repaid ?? 0) > 0}
								<!-- 🦈 50% of the deposit auto-skims to your loan — show why the balance rose less. -->
								<div class="rcpt-line">
									<span>Loan repayment <small>(50%)</small></span><span class="neg"
										>−${Number(dr.loan_repaid).toLocaleString()}</span
									>
								</div>
							{/if}
							<div class="rcpt-line balance">
								<span>AVAILABLE BALANCE</span><span
									>${Math.round(menuBank ?? netWorth ?? 0).toLocaleString()}</span
								>
							</div>
							{#if dailyMod}
								<div class="rcpt-rule"></div>
								<div class="rcpt-line">
									<span><Icon name={dailyMod.emoji} size={15} /> {dailyMod.name}</span><span
										>applied</span
									>
								</div>
							{/if}
							{#if resultRank && resultRank.total > 0}
								<div class="rcpt-foot">
									<Icon name="trophy" size={14} /> #{resultRank.rank} of {resultRank.total.toLocaleString()}
									today
								</div>
							{/if}
							<div class="rcpt-thanks">Thank you for banking with WordBank</div>
						</div>
						<div class="result-actions">
							<button class="share-btn" on:click={handleShare}
								>{#if shareCopied}<Icon name="check" size={13} /> Copied!{:else}Share{/if}</button
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
						<!-- 🧾 Daily VOID slip: didn't solve → no deposit, balance untouched -->
						<div class="rcpt-slot" aria-hidden="true"></div>
						<div class="receipt void" use:printSound>
							<div class="rcpt-brand">
								<img class="rcpt-coin" src="/logo-coin.png" alt="" width="40" height="40" />
								<img class="rcpt-mark" src="/wordmark.png" alt="WordBank" />
							</div>
							<div class="rcpt-title void"><Icon name="warning" size={18} /> BUST</div>
							<div class="rcpt-acct">WORDBANK CHECKING</div>
							<div class="rcpt-sub">
								ACCT ·········{acctNo}{#if myUsername}
									· @{myUsername}{/if}
							</div>
							<div class="rcpt-rule"></div>
							<div class="rcpt-info">
								<div class="ri-row"><span>{rcptDate}</span><span>{rcptTime}</span></div>
								<div class="ri-row"><span>DAILY</span><span>NO DEPOSIT</span></div>
							</div>
							<div class="rcpt-rule"></div>
							<div class="rcpt-line total"><span>DEPOSIT</span><span>$0</span></div>
							<div class="rcpt-rule"></div>
							<div class="rcpt-line answer">
								<span>Answer</span><span>{$gameStore.currentPhrase}</span>
							</div>
							<div class="rcpt-rule"></div>
							<div class="rcpt-line balance">
								<span>AVAILABLE BALANCE</span><span>${resultBankroll.toLocaleString()}</span>
							</div>
							<div class="rcpt-foot">No deposit today · win streak reset. Back tomorrow.</div>
							<div class="rcpt-thanks">Thank you for banking with WordBank</div>
						</div>
						<div class="result-actions">
							<button class="share-btn" on:click={handleShare}
								>{#if shareCopied}<Icon name="check" size={13} /> Copied!{:else}Share{/if}</button
							>
							<button class="next-puzzle-button" on:click={goToDailyLeaderboard}>Leaderboard</button
							>
						</div>
					{:else if isClimb && cashoutResult}
						<!-- 🧾 Cash-out slip: a full-run recap — starting balance → run → ending balance. -->
						{@const co = cashoutResult}
						{@const prof = co.profit ?? 0}
						{@const skim = Math.round(co.loan_repaid ?? 0)}
						{@const endBal = Math.round(menuBank ?? 0)}
						{@const startBal = Math.round(co.run_start_bal ?? endBal - prof + skim)}
						<div class="rcpt-slot" aria-hidden="true"></div>
						<div class="receipt" use:printSound>
							<div class="rcpt-brand">
								<img class="rcpt-coin" src="/logo-coin.png" alt="" width="40" height="40" />
								<img class="rcpt-mark" src="/wordmark.png" alt="WordBank" />
							</div>
							<div class="rcpt-title">DEPOSIT SLIP</div>
							<div class="rcpt-acct">WORDBANK CHECKING</div>
							<div class="rcpt-sub">
								ACCT ·········{acctNo}{#if myUsername}
									· @{myUsername}{/if}
							</div>
							<div class="rcpt-rule"></div>
							<div class="rcpt-info">
								<div class="ri-row"><span>{rcptDate}</span><span>{rcptTime}</span></div>
								<div class="ri-row">
									<span
										>{(co.tier ?? '').charAt(0).toUpperCase() + (co.tier ?? '').slice(1)} run</span
									><span>{co.solves ?? 0} solve{co.solves === 1 ? '' : 's'}</span>
								</div>
							</div>
							<div class="rcpt-rule"></div>
							<div class="rcpt-cap">Your run</div>
							<div class="rcpt-line">
								<span>Starting balance</span><span>${startBal.toLocaleString()}</span>
							</div>
							<div class="rcpt-line">
								<span>Buy-in</span><span class="neg">−${(co.buy_in ?? 0).toLocaleString()}</span>
							</div>
							<div class="rcpt-line">
								<span>Payout banked</span><span class="pos"
									>+${(co.banked ?? 0).toLocaleString()}</span
								>
							</div>
							{#if skim > 0}
								<div class="rcpt-line">
									<span>Loan repayment <small>(50%)</small></span><span class="neg"
										>−${skim.toLocaleString()}</span
									>
								</div>
							{/if}
							<div class="rcpt-rule double"></div>
							<div class="rcpt-line balance">
								<span>AVAILABLE BALANCE</span><span>${endBal.toLocaleString()}</span>
							</div>
							<div class="rcpt-rule"></div>
							<div class="rcpt-line total" class:profit={prof >= 0}>
								<span>NET {prof >= 0 ? 'PROFIT' : 'LOSS'}</span><span
									>{prof >= 0 ? '+' : '−'}${Math.abs(prof).toLocaleString()}</span
								>
							</div>
							<div class="rcpt-note">
								{((co.multiple_x100 ?? 0) / 100).toFixed(1)}× buy-in · peak interest +{Math.round(
									(co.heat ?? 100) - 100
								)}%
							</div>
							{#if co.phrase}
								<div class="rcpt-rule"></div>
								<div class="rcpt-line answer"><span>Last answer</span><span>{co.phrase}</span></div>
							{/if}
							<div class="rcpt-thanks">Thank you for banking with WordBank</div>
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
						<!-- 🧾 Per-puzzle RUN scorecard — mid-run, nothing hits the account until you Deposit. -->
						{@const letters = Math.round(climb?.spent ?? 0)}
						{@const payout = Math.round(climb?.last_gain ?? 0)}
						{@const advance = payout + letters}
						{@const pendAfter = Math.round(climb?.bankroll ?? 0)}
						{@const solves = Math.round(climb?.run_solves ?? 0)}
						{@const runInt = Math.max(0, Math.round((climb?.heat ?? 100) - 100))}
						{@const tierName =
							(climb?.tier ?? '').charAt(0).toUpperCase() + (climb?.tier ?? '').slice(1)}
						<div class="rcpt-slot" aria-hidden="true"></div>
						<div class="receipt" use:printSound>
							<div class="rcpt-brand">
								<img class="rcpt-coin" src="/logo-coin.png" alt="" width="40" height="40" />
								<img class="rcpt-mark" src="/wordmark.png" alt="WordBank" />
							</div>
							<div class="rcpt-title">CASH GAME</div>
							<div class="rcpt-acct">
								{tierName} RUN{#if solves > 0}
									· SOLVE #{solves}{/if}
							</div>
							<div class="rcpt-rule"></div>
							<div class="rcpt-info">
								<div class="ri-row"><span>{rcptDate}</span><span>{rcptTime}</span></div>
							</div>
							<div class="rcpt-rule"></div>
							<div class="rcpt-cap">This solve</div>
							<div class="rcpt-line">
								<span>Puzzle value</span><span>${advance.toLocaleString()}</span>
							</div>
							<div class="rcpt-line">
								<span>Letters (debit)</span><span class="neg">−${letters.toLocaleString()}</span>
							</div>
							<div class="rcpt-rule double"></div>
							<div class="rcpt-line total profit">
								<span>Kept this solve</span><span>+${payout.toLocaleString()}</span>
							</div>
							<div class="rcpt-rule"></div>
							<div class="rcpt-cap">Your run</div>
							<div class="rcpt-line balance">
								<span>RUNNING PAYOUT</span><span>${pendAfter.toLocaleString()}</span>
							</div>
							<div class="rcpt-line">
								<span>Interest · Solves</span><span>+{runInt}% · {solves}</span>
							</div>
							<div class="rcpt-rule"></div>
							<!-- Ambient reference: your account (untouched until you Deposit the run). -->
							<div class="rcpt-line rcpt-faint">
								<span>Available balance</span><span
									>${Math.round(menuBank ?? 0).toLocaleString()}</span
								>
							</div>
						</div>
						{#if climb?.next_category}
							<div class="cg-peek">
								<span class="cg-peek-cap">Next puzzle</span>
								<span class="cg-peek-val"
									><CategoryIcon category={climb.next_category} size={15} />{categoryLabel(
										climb.next_category
									)} for <b>${(climb.next_bounty ?? 0).toLocaleString()}</b></span
								>
							</div>
						{/if}
						<div class="result-actions">
							<button
								class="share-btn co-inline"
								disabled={cgBusy}
								on:click={() => {
									// Between-puzzle bank: opens the deposit confirm, then swaps this slip for
									// the cash-out slip on success. Cancelling keeps this slip (no soft-lock).
									hasTriggeredModal = false;
									cashOut();
								}}
								><svg class="dep-ic" viewBox="0 0 24 24" fill="none" aria-hidden="true">
									<path d="M12 4v10" />
									<path d="M8 11l4 4 4-4" />
									<path d="M5 17v2a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-2" />
								</svg>Deposit ${pendAfter.toLocaleString()}</button
							>
							<button
								class="next-puzzle-button"
								on:click={() => {
									showResultModal = false;
									hasTriggeredModal = false;
									climbAdvance().then(() => tick().then(playDailyIntroIfArmed));
								}}>Play On →</button
							>
						</div>
					{:else if isClimb}
						<!-- 🧾 Bust slip: a full-run recap — starting balance → buy-in lost → ending balance. -->
						{@const wiped = Math.round(climb?.wiped ?? 0)}
						{@const ante = Math.round(climb?.buy_in ?? 0)}
						{@const endBal = Math.round(menuBank ?? 0)}
						{@const startBal = endBal + ante}
						<div class="rcpt-slot" aria-hidden="true"></div>
						<div class="receipt void" use:printSound>
							<div class="rcpt-brand">
								<img class="rcpt-coin" src="/logo-coin.png" alt="" width="40" height="40" />
								<img class="rcpt-mark" src="/wordmark.png" alt="WordBank" />
							</div>
							<div class="rcpt-title void"><Icon name="warning" size={18} /> BUST</div>
							<div class="rcpt-acct">WORDBANK CHECKING</div>
							<div class="rcpt-sub">
								ACCT ·········{acctNo}{#if myUsername}
									· @{myUsername}{/if}
							</div>
							<div class="rcpt-rule"></div>
							<div class="rcpt-info">
								<div class="ri-row"><span>{rcptDate}</span><span>{rcptTime}</span></div>
								<div class="ri-row">
									<span
										>{(climb?.tier ?? '').charAt(0).toUpperCase() + (climb?.tier ?? '').slice(1)} run</span
									><span>WRONG GUESS</span>
								</div>
							</div>
							<div class="rcpt-rule"></div>
							<div class="rcpt-cap">Your run</div>
							<div class="rcpt-line">
								<span>Starting balance</span><span>${startBal.toLocaleString()}</span>
							</div>
							<div class="rcpt-line">
								<span>Buy-in lost</span><span class="neg">−${ante.toLocaleString()}</span>
							</div>
							<div class="rcpt-rule double"></div>
							<div class="rcpt-line balance">
								<span>AVAILABLE BALANCE</span><span>${endBal.toLocaleString()}</span>
							</div>
							{#if wiped > 0}
								<div class="rcpt-note">
									Also forfeited a ${wiped.toLocaleString()} run pile.
								</div>
							{/if}
							<div class="rcpt-rule"></div>
							<div class="rcpt-line answer">
								<span>Answer</span><span>{$gameStore.currentPhrase}</span>
							</div>
							<div class="rcpt-thanks">Thank you for banking with WordBank</div>
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
					{:else if isMatch}
						<!-- Challenge match: finished the whole pack -->
						<div class="result-medal"><Icon name="swords" size={40} /></div>
						<h2>Challenge complete!</h2>
						<p class="result-sub">
							You solved {matchInfo?.solved ?? 0}/{matchInfo?.pack_size} spending ${(
								matchInfo?.spent ?? 0
							).toLocaleString()}
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
							<div class="result-medal"><Icon name="calendar" size={40} /></div>
							<h2>Made it up!</h2>
							<p class="result-sub">
								{makeupLabel} is on your calendar · {$gameStore.currentPhrase}
							</p>
							<p class="arcade-gain">
								Counts toward <Icon name="calendar" size={13} /> Perfect Week / <Icon
									name="calendar"
									size={13}
								/> Perfect Month.
							</p>
						{:else}
							<div class="result-medal"><Icon name="broke" size={40} /></div>
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
					{/if}
				</div>
			</div>
		{/if}
	{/if}
</main>

<style>
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
	/* 🎁 Daily Twist explainer toast — sits just below the attendance toast, distinct
	   neon-indigo look so it reads as "your Twist did this". */
	.twist-toast {
		position: fixed;
		top: 58px;
		left: 50%;
		transform: translateX(-50%);
		z-index: 2000;
		max-width: min(90vw, 340px);
		padding: 0.5rem 0.95rem;
		border-radius: 999px;
		text-align: center;
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.82rem;
		line-height: 1.25;
		color: #e9f2ff;
		background: rgba(20, 24, 40, 0.94);
		border: 1px solid rgba(129, 140, 248, 0.6);
		box-shadow: 0 8px 24px rgba(99, 102, 241, 0.3);
		pointer-events: none;
		animation:
			twistDrop 0.35s var(--ease-spring, ease) both,
			twistOut 0.4s ease 2.2s forwards;
	}
	@keyframes twistDrop {
		from {
			transform: translate(-50%, -40px);
			opacity: 0;
		}
		to {
			transform: translate(-50%, 0);
			opacity: 1;
		}
	}
	@keyframes twistOut {
		to {
			opacity: 0;
			transform: translate(-50%, -12px);
		}
	}
	/* 💸 Deposit-lands beat */
	.deposit-anim {
		position: fixed;
		inset: 0;
		z-index: 3000;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 18px;
		padding: 24px;
		cursor: pointer;
		background: radial-gradient(circle at 50% 38%, rgba(18, 22, 38, 0.97), rgba(0, 0, 0, 0.99));
		animation: daFade 0.3s ease both;
	}
	.da-title {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.9rem;
		letter-spacing: 0.14em;
		text-transform: uppercase;
		color: var(--text-faint);
	}
	.da-stage {
		position: relative;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 22px;
		width: min(90vw, 360px);
	}
	.da-card {
		width: 100%;
		animation: daPulse 1.2s ease 0.5s;
	}
	.da-amount {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 2rem;
		color: #4ade80;
		text-shadow: 0 0 20px rgba(74, 222, 128, 0.6);
		font-variant-numeric: tabular-nums;
		animation: daAmt 1.9s ease both;
	}
	/* coins launch from the amount (bottom of the stage) and fly up into the card */
	.da-coins {
		position: absolute;
		left: 50%;
		bottom: 6px;
		width: 0;
		height: 0;
		pointer-events: none;
	}
	.da-coin {
		position: absolute;
		left: -14px;
		bottom: 0;
		width: 28px;
		height: 28px;
		opacity: 0;
		filter: drop-shadow(0 2px 6px rgba(0, 0, 0, 0.5));
		animation: daCoin 0.95s cubic-bezier(0.3, 0.7, 0.4, 1) var(--delay, 0ms) forwards;
	}
	@keyframes daCoin {
		0% {
			transform: translate(var(--dx, 0), 0) scale(0.5) rotate(0deg);
			opacity: 0;
		}
		15% {
			opacity: 1;
		}
		70% {
			opacity: 1;
		}
		100% {
			transform: translate(0, -210px) scale(1) rotate(var(--rot, 180deg));
			opacity: 0;
		}
	}
	@keyframes daPulse {
		0%,
		100% {
			transform: scale(1);
			filter: brightness(1);
		}
		45% {
			transform: scale(1.035);
			filter: brightness(1.18);
		}
	}
	@keyframes daAmt {
		0% {
			transform: translateY(10px);
			opacity: 0;
		}
		18% {
			opacity: 1;
		}
		80% {
			opacity: 1;
		}
		100% {
			transform: translateY(-6px);
			opacity: 0.85;
		}
	}
	@keyframes daFade {
		from {
			opacity: 0;
		}
		to {
			opacity: 1;
		}
	}
	.da-hint {
		font-size: 0.8rem;
		color: var(--text-faint);
		animation: daHintPulse 1.5s ease-in-out infinite;
	}
	@keyframes daHintPulse {
		0%,
		100% {
			opacity: 0.35;
		}
		50% {
			opacity: 0.8;
		}
	}
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
	/* 🏆 Challenge Score — the accumulated number you win the pot on (the hero below is
	   just this puzzle's fresh bounty). */
	.match-score {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 1px;
		margin: 2px 0 6px;
	}
	.ms-cap {
		font-size: 0.6rem;
		font-weight: 700;
		letter-spacing: 0.1em;
		text-transform: uppercase;
		color: var(--text-faint);
	}
	.ms-val {
		font-family: var(--font-display, sans-serif);
		font-weight: 800;
		font-size: 1.7rem;
		color: #fcd34d;
		font-variant-numeric: tabular-nums;
		line-height: 1.05;
	}
	.match-meta {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 8px;
		margin: 0 0 8px;
	}
	.match-pos {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.8rem;
		color: var(--text-muted);
	}
	/* 🏆 Pot you're playing for — the prize, off the Score headline */
	.pot-chip {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 0.8rem;
		color: #fcd34d;
		background: rgba(252, 211, 77, 0.12);
		border: 1px solid rgba(252, 211, 77, 0.3);
		padding: 3px 11px;
		border-radius: 999px;
		font-variant-numeric: tabular-nums;
	}
	/* 🎯 The score to beat (opponent has played) — the async duel's live target */
	.beat-chip {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 0.8rem;
		color: #fb7185;
		background: rgba(251, 113, 133, 0.12);
		border: 1px solid rgba(251, 113, 133, 0.35);
		padding: 3px 11px;
		border-radius: 999px;
		font-variant-numeric: tabular-nums;
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

	/* 🔔 Bank-app style push notification (out-of-Cash-Advance alert) */
	/* 🚨 Last-stand "out of money": bold red danger headline (Overdrive turns it green). */
	.danger-cue {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 3px;
		width: 100%;
		max-width: 360px;
		margin: 0 auto 12px;
		padding: 12px 16px 13px;
		text-align: center;
		border-radius: 16px;
		border: 1px solid rgba(248, 113, 113, 0.5);
		background: linear-gradient(180deg, rgba(48, 14, 18, 0.95), rgba(30, 10, 12, 0.95));
		animation: dangerPulse 1.1s ease-in-out infinite;
	}
	.dc-title {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1.15rem;
		letter-spacing: 0.06em;
		color: #fca5a5;
		text-shadow: 0 0 14px rgba(248, 113, 113, 0.55);
	}
	.dc-sub {
		font-size: 0.82rem;
		font-weight: 600;
		color: #f0cccc;
		letter-spacing: 0.01em;
	}
	@keyframes dangerPulse {
		0%,
		100% {
			box-shadow:
				0 0 0 1px rgba(248, 113, 113, 0.15),
				0 10px 30px rgba(190, 30, 40, 0.3);
		}
		50% {
			box-shadow:
				0 0 0 1px rgba(248, 113, 113, 0.42),
				0 12px 42px rgba(220, 40, 50, 0.55);
		}
	}
	.danger-cue.armed {
		border-color: rgba(74, 222, 128, 0.5);
		background: linear-gradient(180deg, rgba(16, 40, 26, 0.95), rgba(12, 28, 18, 0.95));
		animation: none;
		box-shadow: 0 10px 30px rgba(34, 160, 90, 0.28);
	}
	.danger-cue.armed .dc-title {
		color: #4ade80;
		text-shadow: 0 0 14px rgba(74, 222, 128, 0.55);
	}
	/* Daily wall: same danger language, a notch calmer — no run on the line. */
	.danger-cue.daily {
		animation-duration: 1.5s;
	}
	.danger-cue.daily .dc-title {
		font-size: 1.05rem;
	}
	.danger-vignette.daily {
		opacity: 0.62;
	}
	/* full-screen red vignette framing the moment */
	.danger-vignette {
		position: fixed;
		inset: 0;
		z-index: 400;
		pointer-events: none;
		animation: vignettePulse 1.5s ease-in-out infinite;
	}
	@keyframes vignettePulse {
		0%,
		100% {
			box-shadow:
				inset 0 0 80px 10px rgba(190, 30, 40, 0.26),
				inset 0 0 22px 2px rgba(248, 113, 113, 0.2);
		}
		50% {
			box-shadow:
				inset 0 0 120px 18px rgba(210, 35, 45, 0.5),
				inset 0 0 30px 3px rgba(248, 113, 113, 0.36);
		}
	}
	/* keyboard lock — you can't buy letters when you're broke, so darken + disable it */
	main.danger-active :global(.keyboard-container) {
		filter: grayscale(0.85) brightness(0.32);
		pointer-events: none;
		transition:
			filter 0.35s ease,
			opacity 0.35s ease;
	}
	/* 🏳️ give-up link inside the must-guess banner */
	.bn-forfeit {
		margin-top: 8px;
		background: none;
		border: none;
		padding: 2px 0;
		font-family: var(--font-ui);
		font-weight: 700;
		font-size: 0.76rem;
		color: #fb7185;
		cursor: pointer;
		text-decoration: underline;
		text-underline-offset: 2px;
	}
	/* ★ escape hatch on the out-of-money banner — keep playing with no money on the line */
	.dc-freeplay {
		margin-top: 8px;
		background: none;
		border: none;
		color: var(--brand-2, #fde047);
		font-weight: 700;
		font-size: 0.85rem;
		cursor: pointer;
		text-decoration: underline;
	}

	.dep-ic {
		width: 26px;
		height: 26px;
		stroke: #fff;
		stroke-width: 2;
		stroke-linecap: round;
		stroke-linejoin: round;
	}
	.co-inline {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 7px;
		white-space: nowrap;
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
		font-family: var(--font-display, sans-serif);
		font-weight: 800;
		color: var(--brand-2);
		font-size: 1.1rem;
		font-variant-numeric: tabular-nums;
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
	.tier-balance {
		text-align: center;
		font-size: 0.82rem;
		color: var(--text-muted);
		margin: -4px 0 12px;
		letter-spacing: 0.02em;
	}
	.tier-balance b {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1rem;
		color: var(--brand-2);
		margin-left: 4px;
		font-variant-numeric: tabular-nums;
	}
	.tier-balance b.neg {
		color: #fb7185;
	}
	/* 🚫 Too broke to buy in → nudge to a loan / the free Daily */
	.tier-broke {
		text-align: center;
		margin: 4px 0 10px;
		padding: 12px;
		border-radius: 14px;
		background: rgba(251, 113, 133, 0.08);
		border: 1px solid rgba(251, 113, 133, 0.25);
	}
	.tb-text {
		margin: 0 0 10px;
		font-size: 0.86rem;
		font-weight: 700;
		color: var(--text);
	}
	.tb-actions {
		display: flex;
		gap: 8px;
		justify-content: center;
	}
	.tb-btn {
		flex: 1;
		padding: 0.6rem 0.5rem;
		border-radius: 11px;
		font-weight: 800;
		font-size: 0.84rem;
		cursor: pointer;
		border: none;
	}
	.tb-btn.loan {
		background: linear-gradient(135deg, #fbbf24, #fde047);
		color: #3a2a00;
	}
	.tb-btn.daily {
		background: var(--surface);
		color: var(--text);
		border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.16));
	}
	.tb-hint {
		margin: 10px 0 0;
		font-size: 0.74rem;
		color: var(--text-faint);
	}
	.arcade-gain {
		font-family: var(--font-display);
		font-weight: 700;
		color: var(--brand-2);
		margin: -8px 0 14px;
		font-size: 1rem;
	}
	.puzzle-meta {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
		justify-content: center;
		margin: 0 0 12px;
	}
	.category-chip {
		display: inline-flex;
		align-items: center;
		gap: 6px;
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
		justify-self: end;
		display: inline-flex;
		align-items: center;
		gap: 5px;
		padding: 0.5rem 0.8rem;
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.84rem;
		white-space: nowrap;
		color: var(--text);
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: 12px;
		cursor: pointer;
		transition:
			transform 0.15s,
			border-color 0.2s,
			background 0.2s;
	}
	.sub-people:hover {
		transform: translateY(-1px);
		border-color: var(--brand-2);
		background: var(--surface-2);
	}
	.sp-plus {
		font-size: 1.05rem;
		font-weight: 800;
		line-height: 1;
		color: var(--brand-2, #fcd34d);
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
	/* ▶ Play — primary gold CTA (bank-app style, replaces the arcade bullion bar) */
	.play-cta {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 10px;
		width: 100%;
		height: 62px;
		border: none;
		border-radius: 18px;
		cursor: pointer;
		color: #2a1e00;
		background: linear-gradient(135deg, #fbbf24, #f59e0b);
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1.2rem;
		letter-spacing: 0.01em;
		box-shadow: 0 10px 26px rgba(245, 158, 11, 0.32);
		transition:
			transform 0.15s var(--ease-spring, ease),
			filter 0.2s;
	}
	.play-cta:hover {
		transform: translateY(-2px);
		filter: brightness(1.05);
	}
	.play-cta:active {
		transform: scale(0.98);
	}
	.pc-ic {
		font-size: 0.9rem;
	}
	/* ⚔️ Challenge — secondary dark button */
	.challenge-cta {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 9px;
		width: 100%;
		height: 56px;
		border-radius: 16px;
		cursor: pointer;
		background: var(--surface, rgba(255, 255, 255, 0.06));
		border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.14));
		color: var(--text, #f4f6fb);
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1.02rem;
		transition:
			transform 0.15s,
			border-color 0.2s,
			background 0.2s;
	}
	.challenge-cta:hover {
		transform: translateY(-2px);
		border-color: rgba(251, 191, 36, 0.4);
	}
	.challenge-cta:active {
		transform: scale(0.98);
	}
	.cc-ic {
		display: inline-flex;
		align-items: center;
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
	/* 🏦 Bank-app menu header */
	.menu-hero {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 12px;
		width: 100%;
		max-width: 360px;
		margin: 2px auto 1.1rem;
	}
	.hero-greet {
		font-family: var(--font-display);
		font-size: 1.5rem;
		font-weight: 800;
		color: var(--text, #f4f6fb);
		letter-spacing: 0.01em;
	}
	.hero-greet .hg-name {
		color: #fbbf24;
	}
	.hero-actions {
		display: flex;
		align-items: center;
		gap: 10px;
	}
	.hero-ic {
		position: relative;
		width: 42px;
		height: 42px;
		border-radius: 14px;
		display: grid;
		place-items: center;
		cursor: pointer;
		background: var(--surface, rgba(255, 255, 255, 0.05));
		border: 1px solid var(--border);
		font-size: 1.1rem;
		transition:
			transform 0.15s,
			border-color 0.2s;
	}
	.hero-bell-ic {
		width: 21px;
		height: 21px;
		fill: none;
		stroke: #fff;
		stroke-width: 1.8;
		stroke-linecap: round;
		stroke-linejoin: round;
	}
	.hero-ic:hover {
		transform: translateY(-1px);
		border-color: rgba(251, 191, 36, 0.5);
	}
	.hero-ic:active {
		transform: scale(0.94);
	}
	.hero-mono {
		width: 42px;
		height: 42px;
		border-radius: 50%;
		display: grid;
		place-items: center;
		cursor: pointer;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1.05rem;
		color: #fbbf24;
		background: linear-gradient(135deg, #3a2a40, #2a2140);
		border: 1px solid rgba(251, 191, 36, 0.4);
		transition:
			transform 0.15s,
			border-color 0.2s;
	}
	.hero-mono:hover {
		transform: translateY(-1px);
		border-color: rgba(251, 191, 36, 0.7);
	}
	.hero-mono:active {
		transform: scale(0.94);
	}
	.account-count {
		position: absolute;
		top: -5px;
		right: -5px;
		display: grid;
		place-items: center;
		min-width: 18px;
		height: 18px;
		padding: 0 5px;
		border-radius: 999px;
		background: #f43f5e;
		color: #fff;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 0.64rem;
		box-shadow: 0 0 0 2px var(--bg, #0a0e14);
	}
	/* 💳 Account card wrapper — tappable → Bank hub */
	.menu-card-wrap {
		position: relative;
		display: block;
		width: 100%;
		max-width: 360px;
		margin: 0 auto 1rem;
		padding: 0;
		border: none;
		background: none;
		cursor: pointer;
		transition: transform 0.15s;
	}
	.menu-card-wrap:active {
		transform: scale(0.985);
	}
	/* ⚡ Quick-action tiles — horizontally swipeable */
	.qt-wrap {
		position: relative;
		width: 100%;
		max-width: 360px;
		margin: 0 auto 1.4rem;
	}
	.quick-tiles {
		display: flex;
		gap: 9px;
		width: 100%;
		overflow-x: auto;
		scroll-snap-type: x proximity;
		-webkit-overflow-scrolling: touch;
		scrollbar-width: none;
		padding-bottom: 2px;
	}
	/* Fade the right edge only while there's more to swipe — clears fully at the end
	   so the last tile (Activity) is never cut off. */
	.qt-wrap:not(.qt-end) .quick-tiles {
		-webkit-mask: linear-gradient(90deg, #000 86%, transparent);
		mask: linear-gradient(90deg, #000 86%, transparent);
	}
	/* "+" badge on the Friends tile — hints you can add friends. */
	.qt-plus {
		position: absolute;
		top: 4px;
		right: 6px;
		color: #fff;
		font-family: var(--font-display, sans-serif);
		font-size: 0.85rem;
		font-weight: 700;
		line-height: 1;
	}
	/* Animated "swipe for more" chevron; hidden once scrolled to the end. */
	.qt-more {
		position: absolute;
		top: 50%;
		right: 4px;
		transform: translateY(-50%);
		display: grid;
		place-items: center;
		width: 22px;
		height: 22px;
		border-radius: 999px;
		background: rgba(0, 0, 0, 0.35);
		color: #fff;
		font-size: 1.2rem;
		font-weight: 700;
		line-height: 1;
		pointer-events: none;
		opacity: 0.9;
		transition: opacity 0.25s;
		animation: qtNudge 1.5s ease-in-out infinite;
	}
	.qt-wrap.qt-end .qt-more {
		opacity: 0;
	}
	@keyframes qtNudge {
		0%,
		100% {
			transform: translate(0, -50%);
		}
		50% {
			transform: translate(3px, -50%);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.qt-more {
			animation: none;
		}
	}
	.quick-tiles::-webkit-scrollbar {
		display: none;
	}
	.qt {
		position: relative;
		flex: 0 0 auto;
		width: 76px;
		scroll-snap-align: start;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 5px;
		padding: 13px 4px 11px;
		border-radius: 14px;
		cursor: pointer;
		background: var(--surface, rgba(255, 255, 255, 0.05));
		border: 1px solid var(--border, rgba(255, 255, 255, 0.08));
		color: var(--text, #dfe4ee);
		transition:
			transform 0.15s,
			border-color 0.2s,
			background 0.2s;
	}
	.qt:hover {
		transform: translateY(-2px);
		border-color: rgba(251, 191, 36, 0.4);
	}
	.qt:active {
		transform: scale(0.96);
	}
	/* 🔒 Store tile while you owe — dimmed with a red-tinted edge (page hard-locks buys). */
	.qt-locked {
		opacity: 0.72;
		border-color: rgba(248, 113, 113, 0.4);
	}
	.qt-svg {
		width: 25px;
		height: 25px;
		fill: none;
		stroke: #dfe4ee;
		stroke-width: 1.8;
		stroke-linecap: round;
		stroke-linejoin: round;
	}
	.qt-l {
		font-size: 0.66rem;
		font-weight: 600;
		color: var(--text-muted, #aeb8c6);
	}
	.main-menu-buttons {
		display: flex;
		flex-direction: column;
		gap: 0.85rem;
		width: 100%;
		max-width: 360px;
		margin: 0 auto;
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
		position: relative;
		z-index: 1;
		flex-shrink: 0;
		display: inline-flex;
		align-items: center;
		gap: 3px;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 0.82rem;
		color: #463413;
		text-shadow: 0 1px 0 rgba(255, 255, 255, 0.35);
	}
	.mc-fire {
		width: 1em;
		height: 1em;
		fill: none;
		stroke: currentColor;
		stroke-width: 1.7;
		stroke-linejoin: round;
	}
	/* Daily card: three zones (play-streak · title · status+win-streak) laid out with
	   space-between + gap, so nothing can overlap regardless of label or chip width. */
	.menu-card.has-streaks {
		justify-content: space-between;
	}
	.menu-card.has-streaks .mc-title {
		flex: 1 1 auto;
		min-width: 0;
	}
	.mc-right {
		position: relative;
		z-index: 1;
		flex-shrink: 0;
		display: inline-flex;
		align-items: center;
		gap: 8px;
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
	.rs-dot {
		color: #34d399;
		font-size: 0.8rem;
	}
	.rs-label {
		flex: 1;
		text-align: center;
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
		display: inline-flex;
		align-items: center;
		justify-content: center;
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
		white-space: nowrap;
	}
	.ch-mode.active {
		border-color: rgba(251, 191, 36, 0.6);
		background: linear-gradient(135deg, rgba(251, 191, 36, 0.14), rgba(251, 191, 36, 0.04));
		box-shadow: 0 0 12px rgba(251, 191, 36, 0.15);
	}
	.ch-opp-picked {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 10px;
		padding: 12px 14px;
		border-radius: 12px;
		border: 1px solid var(--brand-2);
		background: rgba(251, 191, 36, 0.1);
		font-size: 0.95rem;
	}
	.ch-opp-picked b {
		color: var(--brand-2);
	}
	.ch-opp-change {
		background: none;
		border: none;
		color: var(--text-muted);
		font-weight: 700;
		font-size: 0.82rem;
		cursor: pointer;
		text-decoration: underline;
	}
	.ch-picklist {
		display: flex;
		flex-direction: column;
		gap: 6px;
		max-height: 240px;
		overflow-y: auto;
		margin-top: 8px;
	}
	.ch-pickrow {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 10px;
		width: 100%;
		padding: 10px 12px;
		border-radius: 12px;
		border: 1px solid var(--border);
		background: var(--surface);
		color: var(--text);
		cursor: pointer;
		text-align: left;
	}
	.ch-pickrow:hover {
		border-color: var(--brand-2);
	}
	.ch-pickname {
		font-weight: 600;
		font-size: 0.9rem;
	}
	.ch-picktag {
		font-size: 0.7rem;
		font-weight: 700;
		color: var(--text-faint);
	}
	.ch-picktag.friend {
		color: var(--brand-2);
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
	/* 🧭 Challenge wizard */
	.ch-steps {
		display: flex;
		justify-content: center;
		gap: 7px;
		margin: 2px 0 14px;
	}
	.ch-dot {
		width: 7px;
		height: 7px;
		border-radius: 50%;
		background: var(--border-strong, rgba(255, 255, 255, 0.18));
		transition:
			background 0.2s,
			transform 0.2s;
	}
	.ch-dot.on {
		background: var(--brand-2, #fde047);
		transform: scale(1.15);
	}
	.ch-step-title {
		font-family: var(--font-display, sans-serif);
		font-weight: 700;
		font-size: 1.05rem;
		text-align: center;
		margin: 0 0 12px;
	}
	.ch-opt {
		font-style: normal;
		font-weight: 400;
		font-size: 0.72rem;
		color: var(--text-faint);
	}
	.ch-catlist {
		display: flex;
		flex-direction: column;
		gap: 6px;
		max-height: 244px;
		overflow-y: auto;
		margin-top: 6px;
	}
	.ch-catrow {
		display: flex;
		align-items: center;
		gap: 10px;
		width: 100%;
		padding: 10px 12px;
		border-radius: 12px;
		border: 1px solid var(--border);
		background: var(--surface);
		color: var(--text);
		cursor: pointer;
		font-size: 0.9rem;
		text-align: left;
	}
	.ch-catrow.on {
		border-color: var(--brand-2);
		background: rgba(251, 191, 36, 0.1);
	}
	.ch-catemoji {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 22px;
	}
	.ch-catname {
		flex: 1;
		font-weight: 600;
	}
	.ch-catcheck {
		width: 14px;
		color: var(--brand-2, #fde047);
		font-weight: 800;
	}
	.ch-seg {
		display: flex;
		gap: 6px;
		margin-top: 6px;
	}
	.ch-seg-btn {
		flex: 1;
		padding: 10px 0;
		border-radius: 10px;
		border: 1px solid var(--border);
		background: var(--surface);
		color: var(--text);
		cursor: pointer;
		font-weight: 700;
	}
	.ch-seg-btn.on {
		border-color: var(--brand-2);
		background: rgba(251, 191, 36, 0.12);
		color: var(--brand-2);
	}
	.ch-nav {
		display: flex;
		gap: 10px;
		margin-top: 14px;
	}
	.ch-back {
		padding: 0.6rem 1.1rem;
		border-radius: 10px;
		border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.16));
		background: var(--surface);
		color: var(--text);
		cursor: pointer;
		font-weight: 700;
	}
	.ch-grow {
		flex: 1;
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
	.ch-hint {
		font-size: 0.72rem;
		color: var(--text-faint);
		text-align: center;
		margin: 10px 0 0;
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
	.bp-amount {
		font-family: var(--font-display, sans-serif);
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
		font-family: var(--font-display, sans-serif);
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
		font-family: var(--font-display, sans-serif);
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
	.bp-fire {
		width: 0.98em;
		height: 0.98em;
		fill: none;
		stroke: #1a1a1a;
		stroke-width: 1.7;
		stroke-linejoin: round;
		vertical-align: -0.16em;
		margin-right: 2px;
	}
	/* ℹ️ Daily explainer modal (multiplier / Solve-to-Earn breakdown) */
	.info-overlay {
		border: none;
		cursor: pointer;
	}
	/* Deposit confirm is opened FROM the win receipt (also a .modal-overlay), so it
	   must sit above it — otherwise it renders behind and the tap looks like a no-op.
	   Two-class selector so it beats `.modal-overlay` regardless of source order. */
	.modal-overlay.dep-confirm-overlay {
		z-index: 10000;
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
	.solve-vault .qt-svg {
		width: 26px;
		height: 26px;
		stroke: #fff;
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
	.info-big {
		font-family: var(--font-display, sans-serif);
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
	.info-big.neg {
		font-family: var(--font-display, sans-serif);
		font-variant-numeric: tabular-nums;
		color: #fb7185;
		text-shadow: 0 0 22px rgba(251, 113, 133, 0.4);
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
	/* 🏦 Deposit confirm — amount uses the clean money font (not Orbitron) and the
	   same gold as its source (the Payout number in the HUD). */
	.info-big.dep-amt {
		font-family: var(--font-display, sans-serif);
		font-variant-numeric: tabular-nums;
		color: #fcd34d;
		text-shadow: 0 0 22px rgba(251, 191, 36, 0.5);
	}
	.dep-actions {
		display: flex;
		gap: 10px;
		margin-top: 4px;
	}
	.dep-keep {
		flex: 1;
		padding: 0.7rem 0.5rem;
		border-radius: 12px;
		border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.16));
		background: var(--surface);
		color: var(--text);
		font-weight: 700;
		cursor: pointer;
	}
	.dep-go {
		flex: 1.5;
		padding: 0.7rem 0.5rem;
		border-radius: 12px;
		border: none;
		background: linear-gradient(135deg, #34d399, #10b981);
		color: #06281c;
		font-weight: 800;
		cursor: pointer;
	}
	.dep-go:disabled {
		opacity: 0.6;
		cursor: default;
	}
	/* destructive variant — Give Up (forfeit) */
	.dep-go.forfeit {
		background: linear-gradient(135deg, #fb7185, #e11d48);
		color: #fff;
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
		font-family: var(--font-display, sans-serif);
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
	/* 💸 −$X spend feedback — pops at the hero number and flies up-and-off it, so the
	   letter's cost is visibly what just came off the number. Clean font, punchy. */
	.spend-float {
		position: absolute;
		left: 50%;
		top: 46%;
		pointer-events: none;
		font-family: var(--font-display, sans-serif);
		font-weight: 800;
		font-size: 1.55rem;
		color: #fb7185;
		text-shadow: 0 0 12px rgba(248, 113, 133, 0.65);
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
		animation: spendFloat 1.05s cubic-bezier(0.2, 0.75, 0.3, 1) forwards;
	}
	/* 🎰 Cash Game reveal: the carried run pile flying onto the puzzle-value number. */
	.carry-float {
		position: absolute;
		left: 50%;
		top: 120%;
		pointer-events: none;
		font-family: var(--font-display, sans-serif);
		font-weight: 800;
		font-size: 2rem;
		letter-spacing: 0.01em;
		color: #4ade80;
		text-shadow:
			0 0 20px rgba(74, 222, 128, 0.9),
			0 0 40px rgba(74, 222, 128, 0.5);
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
		animation:
			carryFloat 2s cubic-bezier(0.2, 0.7, 0.3, 1) forwards,
			carryGlow 0.5s ease-in-out 3 alternate;
	}
	@keyframes carryFloat {
		0% {
			opacity: 0;
			transform: translate(-50%, 34px) scale(0.6);
		}
		12% {
			opacity: 1;
			transform: translate(-50%, -6px) scale(1.3);
		}
		22% {
			transform: translate(-50%, 0) scale(1.12);
		}
		72% {
			opacity: 1;
			transform: translate(-50%, -6px) scale(1.12);
		}
		100% {
			opacity: 0;
			transform: translate(-50%, -58px) scale(0.95);
		}
	}
	@keyframes carryGlow {
		from {
			text-shadow: 0 0 14px rgba(74, 222, 128, 0.6);
		}
		to {
			text-shadow:
				0 0 30px rgba(74, 222, 128, 1),
				0 0 55px rgba(74, 222, 128, 0.65);
		}
	}
	/* A wrong whole-phrase guess (Cash Game): same red, but bigger + a hard shake so it
	   reads as a penalty, not a routine letter buy. */
	.spend-float.wrong {
		font-size: 1.85rem;
		letter-spacing: 0.02em;
		text-shadow: 0 0 16px rgba(248, 113, 133, 0.85);
		animation:
			spendFloat 1.15s cubic-bezier(0.2, 0.75, 0.3, 1) forwards,
			wrongShake 0.42s ease-in-out;
	}
	@keyframes wrongShake {
		0%,
		100% {
			margin-left: 0;
		}
		20% {
			margin-left: -7px;
		}
		40% {
			margin-left: 6px;
		}
		60% {
			margin-left: -4px;
		}
		80% {
			margin-left: 3px;
		}
	}
	@keyframes spendFloat {
		0% {
			opacity: 0;
			transform: translate(-50%, 6px) scale(0.8);
		}
		20% {
			opacity: 1;
			transform: translate(-50%, -6px) scale(1.15);
		}
		100% {
			opacity: 0;
			transform: translate(-50%, -46px) scale(1);
		}
	}
	/* 🪙 Small ambient bankroll chip (in-game top, all modes) — quiet status, not a game number. */
	.bankroll-chip {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		width: fit-content;
		margin: 0 auto 12px;
		padding: 4px 12px;
		border-radius: 999px;
		border: 1px solid var(--border);
		background: rgba(255, 255, 255, 0.03);
		cursor: pointer;
		transition: transform 0.12s ease;
	}
	.bankroll-chip:active {
		transform: scale(0.97);
	}
	.brc-coin {
		width: 16px;
		height: 16px;
		object-fit: contain;
		opacity: 0.9;
	}
	.brc-amt {
		font-family: var(--font-display, sans-serif);
		font-weight: 700;
		font-size: 0.82rem;
		color: var(--text-muted);
		font-variant-numeric: tabular-nums;
	}
	/* 🔥 Cash Game tagline under the title in the tier picker. */
	.cg-tagline {
		text-align: center;
		font-family: var(--font-display, sans-serif);
		font-weight: 800;
		font-size: 0.72rem;
		letter-spacing: 0.16em;
		text-transform: uppercase;
		color: #fcd34d;
		margin: -4px 0 8px;
	}
	/* 🏷️ Game-mode pill — centered under the wordmark, same for every mode */
	.daily-timer-wrap {
		display: flex;
		justify-content: center;
		margin-top: 3px;
	}
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
		display: inline-flex;
		align-items: center;
	}
	.mp-info {
		font-size: 0.72rem;
		opacity: 0.6;
		letter-spacing: 0;
	}
	/* subtle tier · principal appended to the Cash Game pill */
	.mp-sub {
		font-weight: 600;
		font-size: 0.66rem;
		letter-spacing: 0.02em;
		text-transform: none;
		opacity: 0.62;
		color: var(--text-muted, #cbd5e1);
	}
	/* ★ Free Play in-game HUD — points + Next/Skip, no money involved */
	.fp-hud {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 10px;
		margin: 6px auto 4px;
		max-width: 340px;
	}
	.fp-pts {
		font-family: var(--font-display, sans-serif);
		font-weight: 800;
		color: var(--brand-2, #fde047);
	}
	.fp-budget {
		font-weight: 700;
		color: var(--text-muted);
	}
	.fp-next {
		background: none;
		border: 1px solid var(--border);
		border-radius: 999px;
		padding: 4px 12px;
		color: var(--text);
		font-weight: 700;
		cursor: pointer;
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
	/* 🏆 Win banner */
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
	/* 🖨️ Printer slot the receipt feeds out of — a dark housing bar just above the slip,
	   with a black paper-exit gap. Sits above the paper (z-index) so the slip emerges from
	   behind it. It's a sibling of .receipt (not a child) so the slip's clip-path reveal
	   doesn't clip it. */
	.rcpt-slot {
		width: 100%;
		max-width: 306px;
		height: 13px;
		margin: 0.4rem auto -7px;
		position: relative;
		z-index: 2;
		border-radius: 7px 7px 4px 4px;
		background: linear-gradient(#45454f, #17171d 62%, #0b0b0f);
		box-shadow:
			inset 0 1px 0 rgba(255, 255, 255, 0.09),
			inset 0 -3px 5px rgba(0, 0, 0, 0.7),
			0 3px 8px rgba(0, 0, 0, 0.5);
	}
	.rcpt-slot::after {
		content: '';
		position: absolute;
		left: 9px;
		right: 9px;
		bottom: 2px;
		height: 3px;
		border-radius: 2px;
		background: #05050a;
		box-shadow: inset 0 1px 2px rgba(0, 0, 0, 0.9);
	}
	@media (prefers-reduced-motion: reduce) {
		.rcpt-slot {
			display: none;
		}
	}
	.receipt {
		font-family: 'Courier New', 'Courier', ui-monospace, monospace;
		width: 100%;
		max-width: 290px;
		margin: 0 auto 1.1rem;
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
		/* 🧾 Feed out of the printer: reveal top→bottom in mechanical steps (paper emerging
		   from behind the slot, torn edge last) with a faint side-to-side jitter like a
		   thermal head. Slow (~3s) so you can watch it print. */
		position: relative;
		z-index: 1;
		transform-origin: top center;
		will-change: clip-path, transform;
		animation:
			receipt-print 3s steps(60, end) both,
			receipt-jitter 0.14s steps(2, end) 21 both;
	}
	@keyframes receipt-print {
		from {
			clip-path: inset(0 0 100% 0);
		}
		to {
			clip-path: inset(0 0 -2% 0);
		}
	}
	@keyframes receipt-jitter {
		0%,
		100% {
			transform: translateX(0);
		}
		50% {
			transform: translateX(0.6px);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.receipt {
			animation: none;
		}
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
	/* 🏦 ATM-slip account header + meta rows */
	.rcpt-acct {
		text-align: center;
		font-size: 0.74rem;
		font-weight: 700;
		letter-spacing: 0.12em;
		color: #23201a;
		margin: 5px 0 1px;
	}
	.rcpt-sub {
		text-align: center;
		font-size: 0.68rem;
		letter-spacing: 0.04em;
		color: #6b6455;
	}
	/* Left-aligned section caption inside a receipt ("This solve" / "Your run"). */
	.rcpt-cap {
		font-size: 0.6rem;
		text-transform: uppercase;
		letter-spacing: 0.11em;
		font-weight: 700;
		color: #8a8172;
		margin: 4px 0 1px;
	}
	.rcpt-info {
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.rcpt-info .ri-row {
		display: flex;
		justify-content: space-between;
		gap: 12px;
		font-size: 0.7rem;
		letter-spacing: 0.03em;
		color: #6b6455;
		font-variant-numeric: tabular-nums;
	}
	.rcpt-line.balance {
		font-weight: 800;
		letter-spacing: 0.02em;
	}
	/* Ambient account reference on a run slip — de-emphasized so it doesn't read as run math. */
	.rcpt-line.rcpt-faint {
		font-size: 0.72rem;
		color: #8a8172;
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
	.rcpt-thanks {
		text-align: center;
		font-family: 'Courier New', 'Courier', ui-monospace, monospace;
		font-size: 0.72rem;
		font-style: italic;
		color: #4a4636;
		margin-top: 12px;
		letter-spacing: 0.02em;
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
	/* 🔮 Between-puzzle peek — what you'd be pushing into (Cash Game) */
	.cg-peek {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 10px;
		margin: 0 0 12px;
		padding: 9px 13px;
		border-radius: 12px;
		background: rgba(255, 255, 255, 0.05);
		border: 1px solid var(--border, rgba(255, 255, 255, 0.12));
	}
	.cg-peek-cap {
		font-size: 0.68rem;
		letter-spacing: 0.1em;
		text-transform: uppercase;
		color: var(--text-faint);
	}
	.cg-peek-val {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.86rem;
		color: var(--text);
	}
	.cg-peek-val b {
		color: #fcd34d;
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
