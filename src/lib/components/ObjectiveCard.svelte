<script>
	// Pre-game "How to win" card. Shown the moment a mode starts so a first-time
	// player always knows the objective. The parent gates on localStorage so it shows
	// once — per-mode for solo modes, per-match for challenges (first entry, not resume).
	import { createEventDispatcher } from 'svelte';
	import { MODIFIERS } from '$lib/powerups.js';
	import ModeIcon from '$lib/components/ModeIcon.svelte';
	import Icon from '$lib/components/Icon.svelte';
	const dispatch = createEventDispatcher();

	let page = 0; // 0 = how to win, 1 = power-ups (daily only)
	// Power-ups a player can use in the Daily: the weekday Twists + the Interest Boosts.
	const DAILY_PUPS = [
		{ group: 'Daily Twist — one free helper each weekday', items: Object.values(MODIFIERS) },
		{
			group: 'Interest Boosts — buy in the Store, stack your rate',
			items: [
				{ emoji: 'boost', name: 'Interest Boost', blurb: 'Adds +50% Interest to your deposit' },
				{ emoji: 'gem', name: 'Jackpot', blurb: 'Adds +100% Interest to your deposit' }
			]
		}
	];

	/** @type {string} */ export let mode;
	/** @type {{ opponent?: string, wager?: number, packSize?: number, fieldSize?: number }} */
	export let ctx = {};

	/** @param {string} m @param {any} c */
	function content(m, c) {
		const pk = (c.packSize ?? 1) > 1 ? `${c.packSize} puzzles` : 'the puzzle';
		switch (m) {
			case 'daily':
				return {
					icon: 'calendar',
					title: "Today's Daily",
					goal: "Solve today's hidden phrase.",
					win: 'Spend as little as you can — whatever you don’t spend is deposited to your account.',
					bar: 'Every deposit earns Interest, bigger with your streak, credit, and boosts.'
				};
			case 'climb':
				return {
					icon: 'coin',
					title: 'Cash Game',
					goal: 'Buy in, then grow it by solving puzzles cheaply.',
					win: 'Winnings grow with each solve, boosted by Interest. Cash out between puzzles — once you start one, it’s solve or bust.',
					bar: 'A wrong guess drains your budget — run out and you bust.'
				};
			case 'makeup':
				return {
					icon: 'calendar',
					title: 'Make-up Daily',
					goal: 'Play a Daily you missed.',
					win: 'Same rules — solve it as cheaply as you can.',
					bar: 'Fills your calendar; won’t change your streak.'
				};
			case 'freeplay':
				return {
					icon: 'star',
					title: 'Free Play',
					goal: 'Solve as many phrases as you want.',
					win: 'No stakes — just ★ points. The less you spend, the higher you score.',
					bar: ''
				};
			case 'match': {
				if ((c.fieldSize ?? 2) > 2)
					return {
						icon: 'users',
						title: 'Group Challenge',
						goal: `Solve ${pk}, keeping as much of each Bounty as you can.`,
						win: 'Top Score takes the pot; your buy-in is the stake.',
						bar: 'A wrong guess drains your Bounty — run out and you fold.'
					};
				return {
					icon: 'swords',
					title: c.opponent ? `Duel vs @${c.opponent}` : 'Challenge',
					goal: `Solve ${pk}, keeping as much of each Bounty as you can.`,
					win: 'Top Score takes the pot; your buy-in is the stake.',
					bar: 'A wrong guess drains your Bounty — run out and you fold.'
				};
			}
			default:
				return {
					icon: 'target',
					title: 'WordBank',
					goal: 'Solve the hidden phrase.',
					win: 'Spend as little as you can.',
					bar: ''
				};
		}
	}

	$: c = content(mode, ctx);
	// Use the mode line-icon for every mode except a group challenge (keeps its 👥)
	// and the unknown-mode fallback (keeps 🎯).
	$: useModeIcon =
		['daily', 'makeup', 'climb', 'challenge'].includes(mode) ||
		(mode === 'match' && (ctx.fieldSize ?? 2) <= 2);
	function go() {
		dispatch('close');
	}
</script>

<div class="obj-overlay" role="dialog" aria-modal="true" aria-label="How to win">
	<div class="obj-card">
		<button class="obj-x" on:click={go} aria-label="Close"><Icon name="close" size={16} /></button>
		{#if page === 0}
			<span class="obj-pill"><Icon name="target" size={14} /> How to win</span>
			<div class="obj-icon">
				{#if useModeIcon}<ModeIcon {mode} size={44} />{:else}<Icon name={c.icon} size={44} />{/if}
			</div>
			<h2 class="obj-title">{c.title}</h2>

			<p class="obj-goal">{c.goal}</p>
			<div class="obj-win"><span class="obj-win-key">WIN</span>{c.win}</div>
			{#if c.bar}<p class="obj-bar">{c.bar}</p>{/if}

			{#if mode === 'daily'}
				<button class="obj-link" on:click={() => (page = 1)}>Power-ups &amp; boosts →</button>
			{/if}
			<button class="obj-btn" on:click={go}>Let’s go →</button>
		{:else}
			<span class="obj-pill">Power-ups</span>
			<h2 class="obj-title">Daily Power-ups</h2>
			<div class="pup-list">
				{#each DAILY_PUPS as grp}
					<div class="pup-group-h">{grp.group}</div>
					{#each grp.items as it}
						<div class="pup-row">
							<span class="pup-e"><Icon name={it.emoji} size={22} /></span>
							<span class="pup-txt"
								><span class="pup-n">{it.name}</span><span class="pup-d">{it.blurb}</span></span
							>
						</div>
					{/each}
				{/each}
			</div>
			<button class="obj-btn ghost" on:click={() => (page = 0)}>← Back</button>
		{/if}
	</div>
</div>

<style>
	.obj-overlay {
		position: fixed;
		inset: 0;
		z-index: 3100;
		display: grid;
		place-items: center;
		padding: 20px;
		background: rgba(4, 8, 14, 0.72);
		backdrop-filter: blur(8px);
		animation: objFade 0.22s ease;
	}
	@keyframes objFade {
		from {
			opacity: 0;
		}
		to {
			opacity: 1;
		}
	}

	.obj-x {
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
	.obj-x:hover {
		filter: brightness(1.08);
	}
	.obj-x:active {
		transform: scale(0.92);
	}
	.obj-card {
		position: relative;
		width: 100%;
		max-width: 380px;
		padding: 26px 24px 22px;
		border-radius: var(--r-lg, 20px);
		background: var(--surface-strong, rgba(20, 26, 38, 0.92));
		border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.16));
		box-shadow:
			var(--shadow-lg, 0 24px 60px rgba(0, 0, 0, 0.5)),
			var(--glow-brand, 0 0 30px rgba(251, 191, 36, 0.25));
		text-align: center;
		animation: objPop 0.3s var(--ease-spring, cubic-bezier(0.34, 1.56, 0.64, 1));
	}
	@keyframes objPop {
		from {
			transform: translateY(14px) scale(0.96);
			opacity: 0;
		}
		to {
			transform: translateY(0) scale(1);
			opacity: 1;
		}
	}

	.obj-pill {
		display: inline-block;
		margin-bottom: 10px;
		padding: 4px 12px;
		border-radius: 999px;
		font-family: var(--font-display, sans-serif);
		font-size: 0.68rem;
		font-weight: 800;
		letter-spacing: 0.08em;
		color: #3a2a00;
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
	}
	.obj-icon {
		display: flex;
		align-items: center;
		justify-content: center;
		font-size: 2.8rem;
		line-height: 1;
		margin: 2px 0 10px;
		animation: objIcon 0.4s var(--ease-spring, cubic-bezier(0.34, 1.56, 0.64, 1));
	}
	@keyframes objIcon {
		from {
			transform: scale(0.4) rotate(-12deg);
			opacity: 0;
		}
		to {
			transform: scale(1) rotate(0);
			opacity: 1;
		}
	}
	.obj-title {
		font-family: var(--font-display, sans-serif);
		font-size: 1.35rem;
		font-weight: 700;
		margin: 0 0 12px;
		color: var(--text, #fff);
	}
	.obj-goal {
		font-family: var(--font-ui, sans-serif);
		font-size: 0.96rem;
		line-height: 1.45;
		color: var(--text, #f3f6fb);
		margin: 0 auto 12px;
		max-width: 320px;
	}
	.obj-win {
		display: flex;
		align-items: center;
		gap: 10px;
		text-align: left;
		margin: 0 auto 12px;
		max-width: 320px;
		padding: 11px 13px;
		border-radius: 13px;
		border: 1px solid rgba(253, 224, 71, 0.45);
		background: linear-gradient(135deg, rgba(251, 191, 36, 0.14), rgba(251, 191, 36, 0.05));
		font-family: var(--font-ui, sans-serif);
		font-size: 0.92rem;
		line-height: 1.4;
		color: var(--text, #fff);
		font-weight: 600;
	}
	.obj-win-key {
		flex: none;
		font-family: var(--font-display, sans-serif);
		font-size: 0.6rem;
		font-weight: 800;
		letter-spacing: 0.1em;
		color: #3a2a00;
		padding: 3px 7px;
		border-radius: 7px;
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
	}
	.obj-bar {
		font-family: var(--font-ui, sans-serif);
		font-size: 0.82rem;
		line-height: 1.4;
		color: var(--text-muted, #aeb8c6);
		margin: 0 auto 18px;
		max-width: 320px;
	}

	.obj-btn {
		width: 100%;
		max-width: 220px;
		height: 48px;
		border: none;
		border-radius: 14px;
		font-family: var(--font-display, sans-serif);
		font-size: 1.05rem;
		font-weight: 700;
		color: #3a2a00;
		cursor: pointer;
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
		box-shadow: var(--glow-brand, 0 8px 24px rgba(251, 191, 36, 0.35));
		transition:
			transform 0.16s var(--ease-spring, ease),
			filter 0.2s;
	}
	.obj-btn:hover {
		transform: translateY(-2px);
		filter: brightness(1.05);
	}
	.obj-btn:active {
		transform: scale(0.97);
	}
	.obj-btn.ghost {
		background: var(--surface-2, rgba(255, 255, 255, 0.08));
		color: var(--text, #fff);
		box-shadow: none;
	}
	.obj-link {
		display: inline-block;
		margin: 0 0 12px;
		padding: 8px 14px;
		border-radius: 999px;
		cursor: pointer;
		border: 1px solid rgba(110, 231, 183, 0.45);
		background: rgba(110, 231, 183, 0.1);
		font-family: var(--font-display, sans-serif);
		font-weight: 800;
		font-size: 0.82rem;
		color: #6ee7b7;
	}
	.obj-link:hover {
		background: rgba(110, 231, 183, 0.18);
	}
	/* power-ups page */
	.pup-list {
		text-align: left;
		max-height: 46vh;
		overflow-y: auto;
		margin: 4px 0 16px;
		border: 1px solid var(--border, rgba(255, 255, 255, 0.1));
		border-radius: 14px;
		padding: 4px 12px;
	}
	.pup-group-h {
		font-family: var(--font-display, sans-serif);
		font-size: 0.66rem;
		font-weight: 800;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--brand-2, #fcd34d);
		margin: 12px 0 4px;
	}
	.pup-row {
		display: flex;
		gap: 11px;
		align-items: flex-start;
		padding: 7px 0;
		border-bottom: 1px solid var(--border, rgba(255, 255, 255, 0.07));
	}
	.pup-row:last-child {
		border-bottom: none;
	}
	.pup-e {
		font-size: 1.25rem;
		flex: none;
		width: 26px;
		text-align: center;
		line-height: 1.3;
	}
	.pup-txt {
		display: flex;
		flex-direction: column;
		gap: 1px;
	}
	.pup-n {
		font-family: var(--font-display, sans-serif);
		font-weight: 700;
		font-size: 0.88rem;
		color: var(--text, #fff);
	}
	.pup-d {
		font-size: 0.78rem;
		line-height: 1.35;
		color: var(--text-muted, #aeb8c6);
	}
</style>
