<script>
	import { createEventDispatcher } from 'svelte';
	import { fx } from '$lib/sound.js';
	import Icon from '$lib/components/Icon.svelte';

	const dispatch = createEventDispatcher();

	// icon = Icon.svelte name (rendered via <Icon>).
	const steps = [
		{
			icon: 'puzzle',
			title: 'Welcome to WordBank',
			body: 'Every puzzle is a hidden phrase. Crack it, and keep as much Cash as you can.'
		},
		{
			icon: 'letter-a',
			title: 'Buy letters, or guess',
			body: 'Buy a letter and every copy of it appears — each costs Cash. Or guess the full phrase — a wrong guess can cost you.'
		},
		{
			icon: 'cash',
			title: 'Spend less, keep more',
			body: 'Whatever you don’t spend, you keep. The cheaper you solve, the more you pocket.'
		},
		{
			icon: 'calendar',
			title: 'The free Daily',
			body: 'One free puzzle a day, the same for everyone. Keep a streak going to earn more.'
		},
		{
			icon: 'growth',
			title: 'Cash Game',
			body: 'Buy in and solve a run of puzzles. Your winnings grow with each solve — cash out to keep them, or bust and lose the run.'
		},
		{
			icon: 'swords',
			title: 'Challenge your friends',
			body: 'Buy in against a friend or a group. Everyone solves the same puzzles — the cheapest solver takes the pot.'
		},
		{
			icon: 'trophy',
			title: 'More to play',
			body: 'Your Cash earns Interest, the Store has power-ups and looks, and leaderboards rank every mode. Tap Play to start with the Daily.'
		}
	];

	let i = 0;
	$: step = steps[i];
	$: last = i === steps.length - 1;

	function next() {
		fx('tap');
		if (last) dispatch('close');
		else i += 1;
	}
	function back() {
		fx('tap');
		if (i > 0) i -= 1;
	}
	function skip() {
		dispatch('close');
	}
</script>

<div class="tut-overlay" role="dialog" aria-modal="true" aria-label="How to play WordBank">
	<div class="tut-card">
		<button class="tut-skip" on:click={skip}>Skip</button>

		{#key i}
			{#if step.isNew}<span class="tut-new">NEW</span>{/if}
			<div class="tut-icon"><Icon name={step.icon} size={40} /></div>
			<h2 class="tut-title">{step.title}</h2>
			<p class="tut-body">{step.body}</p>
		{/key}

		<div class="tut-dots">
			{#each steps as _, d}
				<span class="tut-dot" class:active={d === i}></span>
			{/each}
		</div>

		<div class="tut-actions">
			{#if i > 0}
				<button class="tut-btn ghost" on:click={back}>Back</button>
			{/if}
			<button class="tut-btn primary" on:click={next}>{last ? 'Play →' : 'Next'}</button>
		</div>
	</div>
</div>

<style>
	.tut-overlay {
		position: fixed;
		inset: 0;
		z-index: 3000;
		display: grid;
		place-items: center;
		padding: 20px;
		background: rgba(4, 8, 14, 0.72);
		backdrop-filter: blur(8px);
		animation: tutFade 0.25s ease;
	}
	@keyframes tutFade {
		from {
			opacity: 0;
		}
		to {
			opacity: 1;
		}
	}

	.tut-card {
		position: relative;
		width: 100%;
		max-width: 380px;
		padding: 30px 24px 22px;
		border-radius: var(--r-lg, 20px);
		background: var(--surface-strong, rgba(20, 26, 38, 0.9));
		border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.16));
		box-shadow:
			var(--shadow-lg, 0 24px 60px rgba(0, 0, 0, 0.5)),
			var(--glow-brand, 0 0 30px rgba(251, 191, 36, 0.25));
		text-align: center;
		animation: tutPop 0.3s var(--ease-spring, cubic-bezier(0.34, 1.56, 0.64, 1));
	}
	@keyframes tutPop {
		from {
			transform: translateY(14px) scale(0.96);
			opacity: 0;
		}
		to {
			transform: translateY(0) scale(1);
			opacity: 1;
		}
	}

	.tut-skip {
		position: absolute;
		top: 12px;
		right: 14px;
		background: none;
		border: none;
		color: var(--text-muted, #9aa6b8);
		font-family: var(--font-ui, sans-serif);
		font-size: 0.78rem;
		font-weight: 600;
		cursor: pointer;
		padding: 4px 6px;
	}
	.tut-skip:hover {
		color: var(--text, #fff);
	}

	.tut-new {
		display: inline-block;
		margin-bottom: 8px;
		padding: 3px 10px;
		border-radius: 999px;
		font-family: var(--font-display, sans-serif);
		font-size: 0.68rem;
		font-weight: 800;
		letter-spacing: 0.08em;
		color: #3a2a00;
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
	}
	.tut-icon {
		font-size: 3rem;
		line-height: 1;
		margin: 4px 0 14px;
		animation: tutIcon 0.4s var(--ease-spring, cubic-bezier(0.34, 1.56, 0.64, 1));
	}
	@keyframes tutIcon {
		from {
			transform: scale(0.4) rotate(-12deg);
			opacity: 0;
		}
		to {
			transform: scale(1) rotate(0);
			opacity: 1;
		}
	}

	.tut-title {
		font-family: var(--font-display, sans-serif);
		font-size: 1.4rem;
		font-weight: 700;
		margin: 0 0 10px;
		color: var(--text, #fff);
	}
	.tut-body {
		font-family: var(--font-ui, sans-serif);
		font-size: 0.95rem;
		line-height: 1.5;
		color: var(--text-muted, #c2cbd8);
		margin: 0 auto 20px;
		max-width: 320px;
		min-height: 4em;
	}

	.tut-dots {
		display: flex;
		justify-content: center;
		gap: 7px;
		margin-bottom: 20px;
	}
	.tut-dot {
		width: 7px;
		height: 7px;
		border-radius: 999px;
		background: var(--border-strong, rgba(255, 255, 255, 0.2));
		transition: all 0.2s ease;
	}
	.tut-dot.active {
		width: 22px;
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
	}

	.tut-actions {
		display: flex;
		gap: 10px;
		justify-content: center;
	}
	.tut-btn {
		flex: 1;
		max-width: 160px;
		height: 46px;
		border-radius: 14px;
		font-family: var(--font-display, sans-serif);
		font-size: 1rem;
		font-weight: 700;
		cursor: pointer;
		transition:
			transform 0.16s var(--ease-spring, ease),
			filter 0.2s;
	}
	.tut-btn.primary {
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
		color: #3a2a00;
		border: none;
		box-shadow: var(--glow-brand, 0 8px 24px rgba(251, 191, 36, 0.35));
	}
	.tut-btn.primary:hover {
		transform: translateY(-2px);
		filter: brightness(1.05);
	}
	.tut-btn.primary:active {
		transform: scale(0.97);
	}
	.tut-btn.ghost {
		background: var(--surface-2, rgba(255, 255, 255, 0.06));
		color: var(--text, #fff);
		border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.16));
	}
	.tut-btn.ghost:hover {
		transform: translateY(-1px);
	}
	.tut-btn.ghost:active {
		transform: scale(0.97);
	}
</style>
