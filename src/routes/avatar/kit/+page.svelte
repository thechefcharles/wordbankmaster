<script>
	import PageNav from '$lib/components/PageNav.svelte';
	import KitAvatar from '$lib/components/KitAvatar.svelte';
	import Icon from '$lib/components/Icon.svelte';
	import { SLOTS, PARTS, DEFAULT_KIT, KIT_READY } from '$lib/avatarKit.js';

	/** @type {any} */ let config = { ...DEFAULT_KIT };
	/** @param {string} slot @param {string} id */
	function pick(slot, id) {
		config = { ...config, [slot]: id };
	}
	const fmt = (/** @type {number} */ n) => '$' + n.toLocaleString();
</script>

<svelte:head><title>WordBank — Avatar Kit (preview)</title></svelte:head>

<main class="kp">
	<header class="kp-head">
		<PageNav />
		<span class="kp-tag">{KIT_READY ? 'Kit: LIVE' : 'Kit: scaffold preview'}</span>
	</header>

	<p class="kp-note">
		Full-body kit — real <b>Humaaans</b> art. Mix & match below. Not yet live in the builder.
	</p>

	<div class="kp-stage"><KitAvatar {config} size={220} /></div>

	{#each SLOTS as s (s.key)}
		<div class="kp-slot">
			<div class="kp-slot-label">{s.label}</div>
			<div class="kp-opts">
				{#each PARTS[s.key] as o (o.id)}
					<button
						class="kp-opt"
						class:on={config[s.key] === o.id}
						on:click={() => pick(s.key, o.id)}
					>
						{o.label}{#if o.price}<span class="kp-price"
								><Icon name="lock" size={12} /> {fmt(o.price)}</span
							>{/if}
					</button>
				{/each}
			</div>
		</div>
	{/each}
</main>

<style>
	.kp {
		max-width: 480px;
		margin: 0 auto;
		padding: 1rem 1rem 4rem;
	}
	.kp-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
	}

	.kp-tag {
		font-size: 0.75rem;
		font-weight: 700;
		color: var(--text-faint);
	}
	.kp-note {
		font-size: 0.82rem;
		line-height: 1.5;
		color: var(--text-muted);
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: 12px;
		padding: 0.7rem 0.9rem;
	}
	.kp-note code {
		color: var(--brand-2);
	}
	.kp-stage {
		display: grid;
		place-items: center;
		margin: 1rem 0 1.4rem;
	}
	.kp-stage :global(.kit) {
		background: radial-gradient(circle at 50% 38%, rgba(255, 255, 255, 0.06), transparent 60%);
	}
	.kp-slot {
		margin-bottom: 12px;
	}
	.kp-slot-label {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.85rem;
		color: var(--text-muted);
		margin-bottom: 6px;
	}
	.kp-opts {
		display: flex;
		flex-wrap: wrap;
		gap: 7px;
	}
	.kp-opt {
		display: flex;
		align-items: center;
		gap: 6px;
		padding: 8px 12px;
		border-radius: 999px;
		cursor: pointer;
		font-weight: 700;
		font-size: 0.82rem;
		color: var(--text);
		background: var(--surface);
		border: 1px solid var(--border);
	}
	.kp-opt.on {
		color: #3a2a00;
		background: linear-gradient(135deg, #fde047, #f59e0b);
		border-color: transparent;
	}
	.kp-price {
		font-size: 0.72rem;
		font-weight: 800;
		color: var(--brand-2);
	}
	.kp-opt.on .kp-price {
		color: #3a2a00;
	}
</style>
