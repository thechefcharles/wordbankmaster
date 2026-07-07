<script>
	// 🔐 Vault door-open flourish (same feel as the login balance reveal), but it
	// opens the safe and then hands you off to your items. Auto-advances; tap to skip.
	import { createEventDispatcher, onMount } from 'svelte';
	import { fx } from '$lib/sound.js';
	const dispatch = createEventDispatcher();

	let doorOpen = false;
	onMount(() => {
		const t1 = setTimeout(() => {
			doorOpen = true;
			fx('vault');
		}, 480);
		const t2 = setTimeout(() => dispatch('done'), 1850); // hand off to the items
		return () => {
			clearTimeout(t1);
			clearTimeout(t2);
		};
	});
	function skip() {
		dispatch('done');
	}
</script>

<div
	class="vault"
	class:open={doorOpen}
	on:click={skip}
	role="button"
	tabindex="0"
	on:keydown={(e) => {
		if (e.key === 'Enter' || e.key === 'Escape') skip();
	}}
>
	<div class="vault-stage">
		<div class="reveal">
			<span class="reveal-amount">Unlocked</span>
		</div>
		<div class="door-hinge">
			<div class="door">
				<div class="door-ring"></div>
				<div class="door-dial">
					<span class="spoke"></span><span class="spoke"></span><span class="spoke"></span>
				</div>
				<img class="door-coin" src="/logo-coin.png" alt="" />
			</div>
		</div>
	</div>
	<div class="flash"></div>
</div>

<style>
	.vault {
		position: fixed;
		inset: 0;
		z-index: 6500;
		display: grid;
		place-items: center;
		cursor: pointer;
		background: radial-gradient(60% 50% at 50% 50%, #14110a, #050505 70%);
		overflow: hidden;
	}
	.vault-stage {
		position: relative;
		width: 300px;
		height: 300px;
		display: grid;
		place-items: center;
		perspective: 1100px;
	}
	.flash {
		position: fixed;
		inset: 0;
		z-index: 50;
		pointer-events: none;
		opacity: 0;
		background: radial-gradient(
			circle at 50% 50%,
			rgba(255, 255, 255, 0.95),
			rgba(253, 224, 71, 0.85) 22%,
			rgba(251, 191, 36, 0.5) 42%,
			rgba(251, 191, 36, 0) 70%
		);
	}
	.vault.open .flash {
		animation: flash 0.9s ease-out 0.15s;
	}
	@keyframes flash {
		0% {
			opacity: 0;
		}
		18% {
			opacity: 1;
		}
		100% {
			opacity: 0;
		}
	}

	.reveal {
		position: absolute;
		inset: 0;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 6px;
		opacity: 0;
		transform: scale(0.9);
		transition:
			opacity 0.6s 0.4s,
			transform 0.6s 0.4s;
	}
	.vault.open .reveal {
		opacity: 1;
		transform: scale(1);
	}

	.reveal-amount {
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		font-size: 2.2rem;
		color: #fde047;
		text-shadow:
			0 0 18px rgba(251, 191, 36, 0.7),
			0 0 40px rgba(251, 191, 36, 0.4);
	}

	@keyframes pulse {
		0%,
		100% {
			opacity: 0.5;
		}
		50% {
			opacity: 1;
		}
	}

	.door-hinge {
		position: absolute;
		inset: 0;
		transform-style: preserve-3d;
	}
	.door {
		position: absolute;
		inset: 0;
		display: grid;
		place-items: center;
		border-radius: 50%;
		background: radial-gradient(circle at 38% 32%, #3a2f12, #1a1407 70%);
		box-shadow:
			inset 0 0 0 10px rgba(251, 191, 36, 0.18),
			inset 0 0 60px rgba(0, 0, 0, 0.7),
			0 18px 50px rgba(0, 0, 0, 0.7);
		transform-origin: left center;
		transition: transform 1.15s cubic-bezier(0.55, 0.06, 0.2, 1);
	}
	.door-ring {
		position: absolute;
		inset: 20px;
		border-radius: 50%;
		border: 6px solid rgba(251, 191, 36, 0.45);
		box-shadow: inset 0 0 24px rgba(251, 191, 36, 0.2);
	}
	.door-dial {
		position: absolute;
		width: 96px;
		height: 96px;
		border-radius: 50%;
		background: radial-gradient(circle at 40% 35%, #fbcf4b, #9a6f12);
		box-shadow:
			0 0 0 8px rgba(0, 0, 0, 0.35),
			0 6px 14px rgba(0, 0, 0, 0.6);
		transition: transform 0.85s cubic-bezier(0.5, 0, 0.2, 1);
	}
	.spoke {
		position: absolute;
		top: 50%;
		left: 50%;
		width: 54px;
		height: 6px;
		border-radius: 3px;
		background: linear-gradient(90deg, #7a5a0e, #fde047, #7a5a0e);
		transform-origin: 0 50%;
	}
	.spoke:nth-child(1) {
		transform: translate(-50%, -50%) rotate(0deg);
	}
	.spoke:nth-child(2) {
		transform: translate(-50%, -50%) rotate(60deg);
	}
	.spoke:nth-child(3) {
		transform: translate(-50%, -50%) rotate(120deg);
	}
	.door-coin {
		position: absolute;
		width: 70px;
		height: auto;
		opacity: 0.9;
	}
	.vault.open .door-dial {
		transform: rotate(540deg);
	}
	.vault.open .door {
		transform: rotateY(-115deg);
		box-shadow: 0 18px 60px rgba(0, 0, 0, 0.8);
	}
</style>
