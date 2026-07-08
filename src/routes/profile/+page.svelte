<script>
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/stores';
	import { getProfileDetail, getMyAvatar, getUserBadges } from '$lib/stores/statsStore.js';
	import { badgeInfo } from '$lib/badges.js';
	import Avatar from '$lib/components/Avatar.svelte';
	import AccountCard from '$lib/components/AccountCard.svelte';
	import NotificationsPanel from '$lib/components/NotificationsPanel.svelte';
	import { unreadCount, requestInbox } from '$lib/stores/notificationStore.js';
	import { track } from '$lib/analytics.js';

	/** @type {'overview'|'stats'|'alerts'} */
	let tab = $state('overview');
	/** @type {any|null} */
	let d = $state(null);
	let loading = $state(true);
	let avatar = $state(null);
	/** @type {string[]} */
	let earned = $state([]);
	let earnedBadges = $derived(earned.map((id) => badgeInfo(id)).filter(Boolean));
	/** @type {{title:string, desc:string, link?:string, linkLabel?:string}|null} */
	let statInfo = $state(null);

	// True when we deep-linked straight into a sub-view (e.g. the menu bell → ?tab=alerts).
	// Back then returns to the menu instead of the Overview the user never saw.
	let deepLinked = $state(false);

	onMount(async () => {
		track('profile_view');
		const t = $page.url.searchParams.get('tab');
		if (t === 'stats' || t === 'alerts') {
			tab = /** @type {any} */ (t);
			deepLinked = true;
		}
		getMyAvatar().then((a) => {
			avatar = a.config;
		});
		getUserBadges().then((b) => {
			earned = b;
		});
		try {
			d = await getProfileDetail();
		} finally {
			loading = false;
		}
	});

	// Note: the unread count only drops when a notification is acted on or dismissed —
	// NOT just from viewing the list. (No mark-all-read on open.)
	/** @param {any} n */
	function notifNav(n) {
		// Challenge invites/results → open the Challenges hub on the menu.
		if (n?.type === 'challenge_incoming' || n?.data?.match_id || n?.data?.challenge_id) {
			requestInbox('challenges');
			goto('/');
		}
	}

	// Back: deep-linked sub-view → menu; sub-view reached from Overview → Overview; Overview → menu.
	function back() {
		if (tab !== 'overview' && !deepLinked) tab = 'overview';
		else goto('/');
	}

	const fmt = (/** @type {any} */ n) => '$' + Math.round(Number(n ?? 0)).toLocaleString();
	const mult = (/** @type {any} */ x) => (x ? (Number(x) / 100).toFixed(1) + '×' : '—');
	const time = (/** @type {any} */ ms) =>
		!ms
			? '—'
			: Number(ms) < 60000
				? Math.round(Number(ms) / 1000) + 's'
				: (Number(ms) / 60000).toFixed(1) + 'm';
	const pct = (/** @type {number} */ w, /** @type {number} */ n) =>
		n > 0 ? Math.round((w / n) * 100) + '%' : '—';
</script>

<svelte:head><title>WordBank — Profile</title></svelte:head>

{#snippet chip(/** @type {string|number} */ value, /** @type {string} */ label)}
	<div class="stat"><span class="sv">{value}</span><span class="sc">{label}</span></div>
{/snippet}
{#snippet chipLink(
	/** @type {any} */ value,
	/** @type {string} */ label,
	/** @type {string} */ href
)}
	<button class="stat stat-link" onclick={() => goto(href)}
		><span class="sv">{value}</span><span class="sc">{label} ›</span></button
	>
{/snippet}
{#snippet chipAct(
	/** @type {any} */ value,
	/** @type {string} */ label,
	/** @type {() => void} */ action
)}
	<button class="stat stat-link" onclick={action}
		><span class="sv">{value}</span><span class="sc">{label} ⓘ</span></button
	>
{/snippet}

<main class="you-page">
	<div class="topbar">
		<button class="back-btn" onclick={back}>← Back</button>
		<h1 class="page-title">
			{tab === 'overview' ? 'Profile' : tab === 'stats' ? 'Full Stats' : 'Notifications'}
		</h1>
		<button class="gear" onclick={() => goto('/?account=1')} title="Settings" aria-label="Settings"
			>⚙️</button
		>
	</div>

	{#if loading}
		<p class="muted">Loading…</p>
	{:else if d}
		{#if tab === 'overview'}
			<div class="ov-hero">
				<button class="prof-avatar" onclick={() => goto('/avatar')}>
					<Avatar config={avatar} fx size={120} />
					<span class="prof-avatar-edit">🎨 Edit Avatar</span>
				</button>
				<div class="ov-id">
					<div class="uname-row">
						<span class="uname">{d.username ? '@' + d.username : 'You'}</span>
						<button
							class="bell-btn"
							onclick={() => (tab = 'alerts')}
							aria-label="Notifications"
							title="Notifications"
						>
							🔔{#if $unreadCount > 0}<span class="bell-count"
									>{$unreadCount > 99 ? '99+' : $unreadCount}</span
								>{/if}
						</button>
					</div>
					<button class="nw nw-btn" onclick={() => goto('/bank')}
						>{fmt(d.net_worth)}<span class="nw-go"> ›</span></button
					>
					<div class="ov-social">
						<button class="ov-social-btn" onclick={() => goto('/my-friends')}
							>👋 My Friends ›</button
						>
						<button class="ov-social-btn" onclick={() => goto('/my-groups')}>👥 My Groups ›</button>
					</div>
				</div>
			</div>

			<!-- 💳 Account card -->
			<div class="prof-card-wrap">
				<AccountCard
					holder={d.username}
					account={d.account_number}
					member={d.member_no}
					balance={d.net_worth}
				/>
			</div>

			<div class="grid ov-summary">
				{@render chipAct(
					(d.overall.puzzles_solved ?? 0).toLocaleString(),
					'Total Solves',
					() =>
						(statInfo = {
							title: 'Total solves',
							desc: 'Every puzzle you’ve solved across all modes — Daily, Cash Game, and challenges.'
						})
				)}
				{@render chipAct(
					d.overall.games_played ?? 0,
					'Games Played',
					() =>
						(statInfo = {
							title: 'Games played',
							desc: 'How many games you’ve started across every mode — whether you solved them or not.'
						})
				)}
				{@render chipAct(
					'🔥 ' + (d.daily.current_streak ?? 0),
					'Play Streak',
					() =>
						(statInfo = {
							title: '🔥 Play streak',
							desc: 'Days in a row you’ve shown up for the Daily. Miss a day and it resets (a freeze can save it).',
							link: '/streak',
							linkLabel: 'View Daily Calendar'
						})
				)}
				{@render chipAct(
					'🏆 ' + (d.daily.win_streak ?? 0),
					'Win Streak',
					() =>
						(statInfo = {
							title: '🏆 Win streak',
							desc: 'Daily puzzles you’ve solved in a row. Powers your bounty multiplier — the longer it runs, the more you earn.',
							link: '/streak',
							linkLabel: 'View Daily Calendar'
						})
				)}
				{@render chipAct(
					pct(d.daily.won ?? 0, d.daily.played ?? 0),
					'Daily Win %',
					() =>
						(statInfo = {
							title: 'Daily win rate',
							desc: 'The share of Dailies you’ve played that you actually solved.'
						})
				)}
				{@render chipAct(
					d.overall.clean_solves ?? 0,
					'Clean Solves',
					() =>
						(statInfo = {
							title: 'Clean solves',
							desc: 'Puzzles you solved with zero wrong letters — pure deduction, no misses.'
						})
				)}
			</div>

			<button class="ov-badges-card" onclick={() => goto('/badges')}>
				<span class="ov-badges-h">🏅 Badges <span class="arrow">›</span></span>
				<span class="ov-badges">
					{#if earnedBadges.length}
						{#each earnedBadges.slice(0, 14) as bdg}<span class="ov-badge" title={bdg.name}
								>{bdg.emoji}</span
							>{/each}
					{:else}<span class="ov-badges-empty">None yet — play to earn them</span>{/if}
				</span>
			</button>

			<div class="ov-nav">
				<button class="ov-link" onclick={() => (tab = 'stats')}
					>📊 Full stats <span class="arrow">›</span></button
				>
				<button class="ov-link" onclick={() => goto('/history')}
					>📜 Play history <span class="arrow">›</span></button
				>
				<button class="ov-link" onclick={() => goto('/streak')}
					>📅 Daily Calendar <span class="arrow">›</span></button
				>
			</div>
		{:else if tab === 'stats'}
			<div class="sec-title">📊 Overall</div>
			<div class="grid">
				{@render chip((d.overall.puzzles_solved ?? 0).toLocaleString(), 'Puzzles solved')}
				{@render chip(d.overall.games_played ?? 0, 'Games played')}
				{@render chip(d.overall.clean_solves ?? 0, 'Clean solves')}
				{@render chip(fmt(d.overall.earned), 'Lifetime earned')}
				{@render chip(fmt(d.overall.spent), 'Lifetime spent')}
			</div>

			<div class="sec-title">📅 Daily</div>
			<div class="grid">
				{@render chipLink('🔥 ' + (d.daily.current_streak ?? 0), 'Play streak', '/streak')}
				{@render chip(d.daily.best_streak ?? 0, 'Best play')}
				{@render chipLink('🏆 ' + (d.daily.win_streak ?? 0), 'Win streak', '/streak')}
				{@render chip(d.daily.best_win_streak ?? 0, 'Best win')}
				{@render chip(pct(d.daily.won ?? 0, d.daily.played ?? 0), 'Win rate')}
				{@render chip(d.daily.won ?? 0, 'Dailies won')}
				{@render chip(fmt(d.daily.best_bounty), 'Best bounty')}
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
				{@render chip(
					`${d.challenges_1v1.wins ?? 0}-${d.challenges_1v1.losses ?? 0}-${d.challenges_1v1.ties ?? 0}`,
					'W-L-T'
				)}
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
				<div class="sec-title">
					🤺 Rivals <span class="sec-hint">(tap for the full head-to-head)</span>
				</div>
				<div class="cats">
					{#each d.rivals as r}
						<button
							class="cat-row rival"
							onclick={() => goto('/u/' + encodeURIComponent(r.name || ''))}
						>
							<span class="cat-name">@{r.name}</span>
							<span class="rival-rec">
								<b class="w">{r.wins}W</b> <b class="l">{r.losses}L</b>{#if r.ties}<b class="t"
										>{r.ties}T</b
									>{/if}
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
							<span class="cat-meta"
								>{c.solves} solved{#if c.best_multiple}
									· best {mult(c.best_multiple)}{/if}</span
							>
						</div>
					{/each}
				</div>
			{/if}
		{:else}
			<NotificationsPanel onNavigate={notifNav} />
		{/if}
	{/if}

	{#if statInfo}
		<div
			class="si-overlay"
			role="button"
			tabindex="0"
			onclick={() => (statInfo = null)}
			onkeydown={(e) => {
				if (e.key === 'Escape' || e.key === 'Enter') statInfo = null;
			}}
		>
			<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions a11y_no_noninteractive_element_interactions a11y_no_noninteractive_tabindex -->
			<div class="si-card" role="document" onclick={(e) => e.stopPropagation()}>
				<h3 class="si-title">{statInfo.title}</h3>
				<p class="si-desc">{statInfo.desc}</p>
				{#if statInfo.link}<button
						class="si-link"
						onclick={() => goto(/** @type {string} */ (statInfo?.link))}
						>{statInfo.linkLabel} →</button
					>{/if}
				<button class="si-close" onclick={() => (statInfo = null)}>Got it</button>
			</div>
		</div>
	{/if}
</main>

<style>
	.you-page {
		max-width: 520px;
		margin: 0 auto;
		padding: 16px 14px 60px;
	}
	/* stat explanation popup */
	.si-overlay {
		position: fixed;
		inset: 0;
		z-index: 4000;
		display: grid;
		place-items: center;
		padding: 24px;
		background: rgba(4, 8, 14, 0.72);
		backdrop-filter: blur(6px);
		border: none;
	}
	.si-card {
		width: 100%;
		max-width: 320px;
		padding: 22px;
		border-radius: 18px;
		text-align: center;
		background: var(--surface-strong, rgba(20, 26, 38, 0.96));
		border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.16));
		box-shadow: 0 20px 50px rgba(0, 0, 0, 0.5);
		display: flex;
		flex-direction: column;
		gap: 10px;
	}
	.si-title {
		font-family: var(--font-display);
		font-size: 1.15rem;
		margin: 0;
	}
	.si-desc {
		font-size: 0.92rem;
		line-height: 1.5;
		color: var(--text-muted);
		margin: 0;
	}
	.si-link {
		background: none;
		border: none;
		color: var(--brand-2);
		font-weight: 700;
		cursor: pointer;
		padding: 4px;
		font-size: 0.92rem;
	}
	.si-close {
		margin-top: 4px;
		height: 44px;
		border-radius: 12px;
		border: none;
		cursor: pointer;
		font-weight: 800;
		color: #3a2a00;
		background: linear-gradient(135deg, #fde047, #f59e0b);
	}
	.topbar {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 8px;
	}
	.back-btn {
		background: none;
		border: none;
		color: var(--text-muted);
		font-size: 0.92rem;
		cursor: pointer;
		padding: 6px 0;
	}

	.page-title {
		font-family: var(--font-display);
		font-size: 1.2rem;
		margin: 0;
	}
	.gear {
		background: none;
		border: none;
		font-size: 1.1rem;
		cursor: pointer;
		padding: 6px;
		opacity: 0.85;
	}
	.gear:hover {
		opacity: 1;
	}
	.muted {
		color: var(--text-muted);
		text-align: center;
		padding: 2rem 0;
	}

	.uname {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1.3rem;
	}
	.nw {
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		font-size: 2.1rem;
		color: #fde047;
		margin-top: 10px;
		text-shadow: 0 0 18px rgba(251, 191, 36, 0.5);
	}

	.sec-title {
		font-family: var(--font-display);
		font-size: 0.78rem;
		font-weight: 700;
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--gold);
		text-align: left;
		margin: 18px 2px 8px;
	}
	.grid {
		display: grid;
		grid-template-columns: 1fr 1fr 1fr;
		gap: 8px;
	}
	.prof-avatar {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 6px;
		margin: 0 auto 14px;
		background: none;
		border: none;
		cursor: pointer;
	}
	.prof-avatar-edit {
		font-size: 0.82rem;
		font-weight: 700;
		color: var(--brand-2);
	}
	/* Overview tab */
	.ov-hero {
		display: flex;
		align-items: center;
		gap: 16px;
		margin: 6px 0 16px;
	}
	.ov-hero .prof-avatar {
		margin: 0;
	}
	.ov-id {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 2px;
		min-width: 0;
	}
	.uname-row {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.bell-btn {
		position: relative;
		background: none;
		border: none;
		cursor: pointer;
		font-size: 1.3rem;
		line-height: 1;
		padding: 2px;
	}
	.bell-count {
		position: absolute;
		top: -4px;
		right: -7px;
		min-width: 17px;
		height: 17px;
		display: grid;
		place-items: center;
		padding: 0 4px;
		border-radius: 999px;
		background: #dc2626;
		color: #fff;
		font-size: 0.62rem;
		font-weight: 800;
	}
	.ov-id .uname {
		font-size: 1.15rem;
	}
	.ov-social {
		display: flex;
		flex-direction: column;
		gap: 5px;
		margin-top: 8px;
		align-items: flex-start;
	}
	.ov-social-btn {
		background: var(--surface);
		border: 1px solid var(--border);
		color: var(--text);
		cursor: pointer;
		padding: 6px 12px;
		border-radius: 999px;
		font-weight: 700;
		font-size: 0.82rem;
	}
	.ov-social-btn:hover {
		border-color: var(--brand-2);
	}
	.ov-id .nw {
		font-size: 1.7rem;
	}

	.prof-card-wrap {
		margin: 4px auto 16px;
		max-width: 360px;
	}
	.ov-summary {
		margin-bottom: 4px;
	}

	.nw-btn {
		background: none;
		border: none;
		padding: 0;
		cursor: pointer;
		display: inline-flex;
		align-items: baseline;
	}
	.nw-go {
		font-size: 1rem;
		color: var(--text-faint);
		font-family: var(--font-display);
	}
	.ov-badges-card {
		display: block;
		width: 100%;
		text-align: left;
		cursor: pointer;
		margin-top: 16px;
		padding: 12px 14px;
		border-radius: 14px;
		background: var(--surface);
		border: 1px solid var(--border);
	}
	.ov-badges-card:hover {
		border-color: var(--brand-2);
	}
	.ov-badges-h {
		display: flex;
		justify-content: space-between;
		font-family: var(--font-display);
		font-size: 0.82rem;
		font-weight: 700;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--gold);
		margin-bottom: 8px;
	}
	.ov-badges-h .arrow {
		color: var(--text-faint);
	}
	.ov-badges {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
		padding: 4px 0;
	}
	.ov-badge {
		font-size: 1.5rem;
		line-height: 1;
	}
	.ov-badges-empty {
		font-size: 0.85rem;
		color: var(--text-muted);
	}
	.ov-nav {
		display: flex;
		flex-direction: column;
		gap: 8px;
		margin-top: 16px;
	}

	.ov-link {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: 13px 15px;
		border-radius: 14px;
		cursor: pointer;
		background: var(--surface);
		border: 1px solid var(--border);
		color: var(--text);
		font-weight: 700;
		font-size: 0.95rem;
		text-align: left;
	}
	.ov-link:hover {
		border-color: var(--brand-2);
	}
	.ov-link .arrow {
		color: var(--text-faint);
	}
	.stat {
		display: flex;
		flex-direction: column;
		gap: 3px;
		padding: 0.85rem 0.4rem;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: 14px;
		text-align: center;
	}
	.stat-link {
		cursor: pointer;
		color: var(--text);
		font: inherit;
	}
	.stat-link:hover {
		border-color: var(--brand-2);
	}
	.stat-link:active {
		transform: scale(0.97);
	}
	.stat-link .sc {
		color: var(--brand-2);
	}
	.sv {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1.02rem;
		color: var(--text);
	}
	.sc {
		font-size: 0.58rem;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--text-faint);
	}

	.cats {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.cat-row {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: 10px;
		padding: 9px 11px;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: 10px;
	}
	.cat-name {
		font-weight: 600;
		color: var(--text);
		font-size: 0.86rem;
	}
	.cat-meta {
		color: var(--text-faint);
		font-size: 0.74rem;
	}
	.sec-hint {
		font-family: var(--font-ui);
		font-weight: 500;
		font-size: 0.62rem;
		color: var(--text-faint);
		text-transform: none;
		letter-spacing: 0;
	}
	.rival {
		width: 100%;
		cursor: pointer;
	}
	.rival-rec {
		display: flex;
		align-items: center;
		gap: 7px;
		font-size: 0.8rem;
		font-variant-numeric: tabular-nums;
	}
	.rival-rec .w {
		color: #7ee0a8;
	}
	.rival-rec .l {
		color: #fb7185;
	}
	.rival-rec .t {
		color: var(--text-muted);
	}
	.rival-rec .arrow {
		color: var(--text-faint);
		font-size: 1rem;
		margin-left: 2px;
	}
</style>
