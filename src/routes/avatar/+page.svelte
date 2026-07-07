<script>
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import Avatar from '$lib/components/Avatar.svelte';
	import { CATEGORIES, DEFAULT_AVATAR } from '$lib/avatar.js';
	import { getMyAvatar, setAvatar, buyCosmetic, getBank } from '$lib/stores/statsStore.js';
	import { fx } from '$lib/sound.js';
	import { track } from '$lib/analytics.js';
	import { requirePin } from '$lib/pinConfirm.js';

	/** @type {any} */ let config = { ...DEFAULT_AVATAR };
	/** @type {string[]} */ let owned = [];
	let bank = 0;
	let loading = true;
	let saving = false;
	let activeCat = CATEGORIES[0].key;
	let dirty = false;
	let toast = '';

	onMount(async () => {
		track('avatar_open');
		const [a, b] = await Promise.all([getMyAvatar(), getBank()]);
		if (a.config) config = { ...DEFAULT_AVATAR, ...a.config };
		owned = a.owned ?? [];
		bank = b?.bank ?? 0;
		loading = false;
	});

	$: cat = CATEGORIES.find((c) => c.key === activeCat) ?? CATEGORIES[0];
	const fmt = (/** @type {number} */ n) => '$' + Math.round(n ?? 0).toLocaleString();
	// Reactive on `owned` so a tile's 🔒 clears the instant a purchase lands.
	$: locked = (/** @type {any} */ o) => !!o.price && !owned.includes(o.cosmeticId);
	/** preview config with one category overridden @param {string} key @param {string} value */
	// a shirt design only shows on the Graphic Tee, so equipping a design auto-wears it
	const withDeps = (/** @type {string} */ key, /** @type {string} */ value) =>
		key === 'clothingGraphic'
			? { clothingGraphic: value, clothing: 'graphicShirt' }
			: { [key]: value };
	const preview = (/** @type {string} */ key, /** @type {string} */ value) => ({
		...config,
		...withDeps(key, value)
	});

	function flash(/** @type {string} */ m) {
		toast = m;
		setTimeout(() => {
			if (toast === m) toast = '';
		}, 1800);
	}

	// 🎲 Surprise look — only from free / already-owned options (never auto-buys).
	function randomize() {
		fx('select');
		const next = { ...config };
		for (const cat of CATEGORIES) {
			const avail = cat.options.filter((/** @type {any} */ o) => !locked(o));
			if (avail.length)
				Object.assign(
					next,
					withDeps(cat.key, avail[Math.floor(Math.random() * avail.length)].value)
				);
		}
		config = next;
		dirty = true;
	}

	/** Tap a tile face: equip if owned/free, otherwise buy. @param {string} key @param {any} o */
	function choose(key, o) {
		if (locked(o)) {
			buyNow(key, o);
			return;
		}
		fx('tap');
		config = { ...config, ...withDeps(key, o.value) };
		dirty = true;
	}

	/** Buy → PIN is the only confirmation (no separate sheet). @param {string} key @param {any} o */
	async function buyNow(key, o) {
		if (saving) return;
		if (bank < o.price) {
			flash('Not enough Cash');
			return;
		}
		// 🔐 Vault code IS the confirm step — no intermediate "Unlock for $X" sheet.
		try {
			await requirePin(`Unlock ${o.label}`, [{ label: o.label, value: fmt(o.price) }]);
		} catch {
			return; // cancelled at the pad
		}
		saving = true;
		const res = await buyCosmetic(o.cosmeticId);
		saving = false;
		if (!res.ok) {
			flash(
				res.reason === 'insufficient'
					? 'Not enough Cash'
					: res.reason === 'in_debt'
						? 'Pay off your loan first'
						: 'Could not buy'
			);
			return;
		}
		fx('win');
		owned = [...owned, o.cosmeticId];
		bank -= o.price;
		config = { ...config, ...withDeps(key, o.value) };
		dirty = true;
		flash('Unlocked!');
	}

	async function save() {
		saving = true;
		const res = await setAvatar(config);
		saving = false;
		if (res.ok) {
			fx('select');
			dirty = false;
			flash('Saved');
		} else flash('Could not save');
	}
</script>

<svelte:head><title>WordBank — Avatar</title></svelte:head>

<main class="av-page">
	<header class="av-head">
		<div class="av-nav">
			<button class="back-btn" on:click={() => (history.length > 1 ? history.back() : goto('/'))}
				>← Back</button
			>
			<button
				class="back-btn home"
				on:click={() => goto('/')}
				title="Main menu"
				aria-label="Main menu">🏠</button
			>
		</div>
		<div class="av-head-right">
			<button class="av-rand" on:click={randomize} title="Surprise me">🎲</button>
			<span class="av-cash">💰 {fmt(bank)}</span>
		</div>
	</header>

	{#if loading}
		<p class="loading">Loading…</p>
	{:else}
		<div class="av-hero"><Avatar {config} fx size={150} /></div>

		<div class="cat-row">
			{#each CATEGORIES as c}
				<button
					class="cat-chip"
					class:on={c.key === activeCat}
					on:click={() => {
						activeCat = c.key;
						fx('tap');
					}}>{c.label}</button
				>
			{/each}
		</div>

		<div class="opt-grid" class:colors={cat.type === 'color'}>
			{#each cat.options as o (o.value)}
				<div class="opt" class:sel={config[cat.key] === o.value} class:locked={locked(o)}>
					<button class="opt-face" on:click={() => choose(cat.key, o)} title={o.label}>
						{#if cat.type === 'color'}
							<span class="sw" style="background:#{o.value}"></span>
						{:else}
							<Avatar config={preview(cat.key, o.value)} fx={cat.type === 'fx'} size={62} />
						{/if}
						<span class="opt-label">{o.label}</span>
					</button>
					{#if locked(o)}
						<button class="opt-buy" on:click={() => buyNow(cat.key, o)}
							>🔒 Buy {fmt(o.price)}</button
						>
					{/if}
				</div>
			{/each}
		</div>
	{/if}

	{#if toast}<div class="av-toast">{toast}</div>{/if}

	<button class="av-save" class:dirty disabled={saving || !dirty} on:click={save}
		>{saving ? 'Saving…' : dirty ? 'Save' : 'Saved'}</button
	>
</main>

<style>
	.av-page {
		max-width: 480px;
		margin: 0 auto;
		padding: 1rem 1rem 6rem;
		min-height: 100vh;
	}
	.av-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-bottom: 0.5rem;
	}
	.av-nav {
		display: flex;
		gap: 8px;
	}
	.back-btn {
		padding: 0.5rem 1rem;
		background: var(--surface);
		color: var(--text);
		border: 1px solid var(--border);
		border-radius: 12px;
		cursor: pointer;
		font-weight: 600;
		font-size: 0.9rem;
	}
	.back-btn.home {
		padding: 0.5rem 0.7rem;
		font-size: 1.05rem;
	}
	.av-head-right {
		display: flex;
		align-items: center;
		gap: 10px;
	}
	.av-rand {
		width: 38px;
		height: 38px;
		border-radius: 50%;
		cursor: pointer;
		font-size: 1.1rem;
		line-height: 1;
		background: var(--surface);
		border: 1px solid var(--border);
	}
	.av-rand:active {
		transform: scale(0.92) rotate(20deg);
	}
	.av-cash {
		font-family: var(--font-display);
		font-weight: 800;
		color: var(--brand-2);
	}
	.loading {
		text-align: center;
		color: var(--text-muted);
		padding: 3rem;
	}
	.av-hero {
		display: grid;
		place-items: center;
		margin: 0.5rem 0 1rem;
	}
	.av-hero :global(.wb-avatar) {
		box-shadow: 0 8px 30px rgba(0, 0, 0, 0.5);
	}

	.cat-row {
		display: flex;
		gap: 7px;
		overflow-x: auto;
		padding: 4px 0 10px;
		-webkit-overflow-scrolling: touch;
		scrollbar-width: none;
	}
	.cat-row::-webkit-scrollbar {
		display: none;
	}
	.cat-chip {
		flex: none;
		padding: 7px 13px;
		border-radius: 999px;
		cursor: pointer;
		font-weight: 700;
		font-size: 0.82rem;
		white-space: nowrap;
		color: var(--text-muted);
		background: var(--surface);
		border: 1px solid var(--border);
	}
	.cat-chip.on {
		color: #3a2a00;
		background: linear-gradient(135deg, #fde047, #f59e0b);
		border-color: transparent;
	}

	.opt-grid {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: 9px;
	}
	.opt-grid.colors {
		grid-template-columns: repeat(5, 1fr);
	}
	.opt {
		position: relative;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 4px;
		padding: 8px 4px;
		border-radius: 14px;
		background: var(--surface);
		border: 1px solid var(--border);
		color: var(--text);
	}
	.opt-face {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 4px;
		width: 100%;
		padding: 0;
		background: none;
		border: 0;
		color: inherit;
		font: inherit;
		cursor: pointer;
	}
	.opt.sel {
		border-color: var(--brand-2);
		box-shadow: 0 0 0 1px var(--brand-2);
	}
	.opt.locked {
		opacity: 0.96;
	}
	.opt.locked :global(.wb-avatar) {
		filter: grayscale(0.5) brightness(0.8);
	}
	.opt-label {
		font-size: 0.68rem;
		color: var(--text-muted);
		text-align: center;
		line-height: 1.1;
	}
	.opt-buy {
		margin-top: 2px;
		padding: 4px 12px;
		border-radius: 999px;
		border: 1px solid var(--brand-2);
		background: rgba(251, 191, 36, 0.12);
		color: var(--brand-2);
		font-size: 0.68rem;
		font-weight: 800;
		white-space: nowrap;
		cursor: pointer;
	}
	.opt-buy:active {
		transform: scale(0.96);
	}
	.sw {
		width: 42px;
		height: 42px;
		border-radius: 50%;
		border: 2px solid rgba(255, 255, 255, 0.25);
	}
	.colors .opt-label {
		display: none;
	}

	.av-toast {
		position: fixed;
		left: 50%;
		bottom: 84px;
		transform: translateX(-50%);
		z-index: 1200;
		padding: 9px 18px;
		border-radius: 999px;
		background: rgba(20, 28, 40, 0.95);
		color: var(--text);
		border: 1px solid var(--border-strong, var(--border));
		font-weight: 700;
		font-size: 0.9rem;
	}
	.av-save {
		position: fixed;
		left: 50%;
		bottom: 18px;
		transform: translateX(-50%);
		z-index: 1100;
		width: calc(100% - 2rem);
		max-width: 448px;
		height: 52px;
		border-radius: 16px;
		cursor: pointer;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1.05rem;
		border: none;
		background: var(--surface-2, rgba(255, 255, 255, 0.08));
		color: var(--text-faint);
	}
	.av-save.dirty {
		background: linear-gradient(135deg, #fde047, #f59e0b);
		color: #3a2a00;
		box-shadow: 0 8px 24px rgba(245, 158, 11, 0.4);
	}
	.av-save:disabled {
		cursor: default;
	}
</style>
