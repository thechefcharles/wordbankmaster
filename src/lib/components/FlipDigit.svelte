<script>
	export let digit = 0;

	const digitHeight = 40;
	let currentDigit = digit;
	let reelStyle = `transform: translateY(-${digit * digitHeight}px);`;

	// 🔄 Trigger animation when digit changes
	$: if (digit !== currentDigit) {
		const fullReelHeight = 10 * digitHeight;
		const animatedOffset = 2 * fullReelHeight + digit * digitHeight;

		// 🎞️ Animate to simulate spinning reel
		reelStyle = `
      transform: translateY(-${animatedOffset}px);
      transition: transform 0.8s cubic-bezier(0.68, -0.55, 0.265, 1.55);
    `;

		// 🧼 Reset style for looped look after animation
		setTimeout(() => {
			currentDigit = digit;
			reelStyle = `transform: translateY(-${digit * digitHeight}px); transition: none;`;
		}, 800);
	}
</script>

<!-- 🎰 Slot Reel Display -->
<div class="slot-container">
	<div class="reel" style={reelStyle}>
		{#each Array(20) as _, i}
			<div class="slot-digit">{i % 10}</div>
		{/each}
	</div>
</div>

<style>
	.slot-container {
		overflow: hidden;
		width: 22px;
		height: 40px;
	}

	.reel {
		display: flex;
		flex-direction: column;
	}

	.slot-digit {
		height: 40px;
		line-height: 40px;
		text-align: center;
		font-size: 1.9rem;
		font-family: 'Space Grotesk', system-ui, sans-serif;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
		color: #fcd34d;
		text-shadow: 0 0 14px rgba(251, 191, 36, 0.45);
	}
</style>
