<script>
	import { goto } from '$app/navigation';
	import PageNav from '$lib/components/PageNav.svelte';
	import { renderAvatarSvg, renderHoloAvatar } from '$lib/avatar.js';

	const base = {
		skinColor: 'edb98a',
		top: 'shortFlat',
		hairColor: '4a312c',
		eyes: 'happy',
		eyebrows: 'default',
		mouth: 'smile',
		clothing: 'blazerAndShirt',
		clothesColor: '5199e4',
		accessories: 'sunglasses',
		facialHair: 'none'
	};

	let holo = true,
		frame = true,
		crown = true,
		aura = true;
	$: svg = holo ? renderHoloAvatar(base) : renderAvatarSvg(base);
</script>

<svelte:head><title>WordBank — Premium FX</title></svelte:head>

<main class="fxp">
	<header class="fxp-head">
		<PageNav />
		<span class="fxp-tag">Premium FX demo</span>
	</header>

	<p class="fxp-note">
		These effects layer on the avatar you already have — no new character art. This is the top tier
		of the cosmetic store.
	</p>

	<div class="fxp-stage-wrap">
		<div class="fxp-stage" style="--sz:230px">
			{#if aura}<div class="fx-aura"></div>{/if}
			{#if frame}<div class="fx-ring"></div>{/if}
			<div class="fx-inner" class:framed={frame}>{@html svg}</div>
			{#if crown}<img class="fx-crown" src="/avatar/fx/crown.svg" alt="" />{/if}
		</div>
	</div>

	<div class="fxp-toggles">
		<button class="fxp-t" class:on={holo} on:click={() => (holo = !holo)}
			>✨ Holographic Shirt</button
		>
		<button class="fxp-t" class:on={frame} on:click={() => (frame = !frame)}>🌀 Neon Frame</button>
		<button class="fxp-t" class:on={crown} on:click={() => (crown = !crown)}>👑 Crown</button>
		<button class="fxp-t" class:on={aura} on:click={() => (aura = !aura)}>🔆 Glow Aura</button>
	</div>
</main>

<style>
	.fxp {
		max-width: 480px;
		margin: 0 auto;
		padding: 1rem 1rem 4rem;
	}
	.fxp-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
	}

	.fxp-tag {
		font-size: 0.75rem;
		font-weight: 700;
		color: var(--text-faint);
	}
	.fxp-note {
		font-size: 0.82rem;
		line-height: 1.5;
		color: var(--text-muted);
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: 12px;
		padding: 0.7rem 0.9rem;
	}
	.fxp-stage-wrap {
		display: grid;
		place-items: center;
		min-height: 320px;
		margin: 1rem 0;
	}

	.fxp-stage {
		position: relative;
		width: var(--sz);
		height: var(--sz);
	}
	.fx-aura {
		position: absolute;
		inset: -22%;
		border-radius: 50%;
		z-index: 0;
		filter: blur(14px);
		background: radial-gradient(
			circle,
			rgba(124, 255, 107, 0.5),
			rgba(92, 208, 255, 0.35) 45%,
			transparent 70%
		);
		animation: fxpulse 2.6s ease-in-out infinite;
	}
	.fx-ring {
		position: absolute;
		inset: -8px;
		border-radius: 50%;
		z-index: 1;
		background: conic-gradient(from 0deg, #ff5cf0, #5cd0ff, #7cff6b, #ffe45c, #ff5cf0);
		box-shadow:
			0 0 26px rgba(124, 255, 107, 0.55),
			0 0 14px rgba(255, 92, 240, 0.5);
		animation: fxspin 4s linear infinite;
	}
	.fx-inner {
		position: absolute;
		inset: 0;
		z-index: 2;
		border-radius: 50%;
		overflow: hidden;
		background: #0b0f1a;
	}
	.fx-inner.framed {
		box-shadow: inset 0 0 0 2px rgba(0, 0, 0, 0.4);
	}
	.fx-inner :global(svg) {
		width: 100%;
		height: 100%;
		display: block;
	}
	.fx-crown {
		position: absolute;
		z-index: 3;
		top: -7%;
		left: 50%;
		transform: translateX(-50%);
		width: 52%;
		filter: drop-shadow(0 3px 5px rgba(0, 0, 0, 0.5));
		animation: fxfloat 2.4s ease-in-out infinite;
	}

	@keyframes fxspin {
		to {
			transform: rotate(360deg);
		}
	}
	@keyframes fxpulse {
		0%,
		100% {
			opacity: 0.65;
			transform: scale(0.96);
		}
		50% {
			opacity: 1;
			transform: scale(1.04);
		}
	}
	@keyframes fxfloat {
		0%,
		100% {
			transform: translateX(-50%) translateY(0);
		}
		50% {
			transform: translateX(-50%) translateY(-4px);
		}
	}

	.fxp-toggles {
		display: flex;
		flex-wrap: wrap;
		gap: 9px;
		justify-content: center;
	}
	.fxp-t {
		padding: 10px 16px;
		border-radius: 999px;
		cursor: pointer;
		font-weight: 800;
		font-size: 0.9rem;
		color: var(--text-muted);
		background: var(--surface);
		border: 1px solid var(--border);
	}
	.fxp-t.on {
		color: #3a2a00;
		background: linear-gradient(135deg, #fde047, #f59e0b);
		border-color: transparent;
	}
</style>
