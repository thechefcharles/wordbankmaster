<script>
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import PageNav from '$lib/components/PageNav.svelte';
	import {
		getShop,
		buyCosmetic,
		equipCosmetic,
		unequipCosmetic,
		getPowerups,
		buyPowerup
	} from '$lib/stores/statsStore.js';
	import { track } from '$lib/analytics.js';
	import { fx } from '$lib/sound.js';
	import { requirePin } from '$lib/pinConfirm.js';
	import InventoryList from '$lib/components/InventoryList.svelte';
	import Icon from '$lib/components/Icon.svelte';

	// Back goes to the Bank when you came from its empty-slot "+", else the menu.
	let backTo = $derived($page.url.searchParams.get('from') === 'bank' ? '/bank' : '/');

	let bank = $state(0);
	let loan = $state(0); // Store is locked while you owe — no buying anything until it's paid off.
	/** @type {any[]} */
	let items = $state([]);
	/** @type {any[]} */
	let pups = $state([]);
	let loading = $state(true);
	let busy = $state('');
	let msg = $state('');

	// icon = Icon.svelte name (see <Icon>); rendered via the component below.
	const PUP_META = /** @type {Record<string,{icon:string,desc:string}>} */ ({
		free_reveal: { icon: 'search', desc: 'Reveal the most useful letter' },
		free_vowel: { icon: 'letter-a', desc: 'Reveal one vowel free' },
		half_off: { icon: 'tag', desc: 'Letters cost 50% less this puzzle' },
		vowel_vision: { icon: 'eye', desc: 'Reveal every vowel' },
		heat_shield: {
			icon: 'shield',
			desc: 'Escape one bust — keep your Payout & Interest and jump to a fresh puzzle'
		},
		overdrive: {
			icon: 'coin',
			desc: 'Out of money? Reveal one more letter of your choice — free'
		},
		free_skip: {
			icon: 'skip',
			desc: 'Swap this puzzle for a fresh one — keep your Interest, Payout & run. Anytime, no streak lost'
		},
		reveal_word: { icon: 'book', desc: 'Reveal a whole word' },
		extra_hint: { icon: 'bulb', desc: 'Reveal the first letter of each word' },
		last_letters: { icon: 'chevron-right', desc: 'Reveal the last letter of each word' },
		sabotage_tax: { icon: 'percent', desc: "An opponent's letters cost +50%" },
		sabotage_fog: { icon: 'fog', desc: "Hide an opponent's clue" },
		sabotage_toll: { icon: 'toll', desc: "An opponent's next letter costs 3×" },
		sabotage_vowel_block: { icon: 'block', desc: "An opponent's vowels cost 3× for their next 3 buys" },
		sabotage_lock: { icon: 'trash', desc: "Wipe the opponent's most-recently-revealed letter" },
		bounty_boost: { icon: 'boost', desc: 'Adds +50% Interest to your Daily deposit' },
		jackpot_boost: { icon: 'gem', desc: 'Adds +100% Interest to your Daily deposit' }
	});

	/** @type {any[]} */
	let sabs = $state([]);
	/** @type {any[]} */
	let dboost = $state([]);

	let inventoryKey = $state(0); // bump to re-mount the bag after a purchase

	async function load() {
		const [shop, pu] = await Promise.all([getShop(), getPowerups()]);
		bank = shop.bank;
		loan = shop.loan ?? 0;
		items = shop.items;
		pups = (pu.items || []).filter((/** @type {any} */ i) => i.kind === 'climb');
		sabs = (pu.items || []).filter((/** @type {any} */ i) => i.kind === 'sabotage');
		dboost = (pu.items || []).filter((/** @type {any} */ i) => i.kind === 'daily');
		inventoryKey++;
	}

	/** @param {any} item */
	async function buyPup(item) {
		if (busy) return;
		// Money-out → PIN confirm (lazy-creates the PIN on the first purchase).
		try {
			await requirePin(`Buy ${item.name}`, [
				{ label: item.name, value: '$' + Number(item.price ?? 0).toLocaleString() }
			]);
		} catch {
			return; // cancelled at the PIN
		}
		busy = item.id;
		msg = '';
		const res = await buyPowerup(item.id);
		busy = '';
		if (res?.ok) {
			fx('win');
			track('powerup_buy', { id: item.id });
			await load();
		} else {
			if (res?.reason === 'in_debt') {
				await load(); // loan outstanding → lock the whole Store
				return;
			}
			msg =
				res?.reason === 'insufficient'
					? 'Not enough Cash.'
					: res?.reason === 'owned'
						? 'You already own one — use it first.'
						: res?.reason === 'in_game'
							? "Can't buy items during a game — finish first."
							: 'Could not buy that.';
		}
	}
	onMount(async () => {
		track('shop_view');
		try {
			await load();
		} finally {
			loading = false;
		}
	});

	let titles = $derived(items.filter((i) => i.kind === 'title'));
	let colors = $derived(items.filter((i) => i.kind === 'color'));

	/** @param {any} item */
	async function buy(item) {
		if (busy) return;
		busy = item.id;
		msg = '';
		const res = await buyCosmetic(item.id);
		busy = '';
		if (res.ok) {
			fx('win');
			track('cosmetic_buy', { id: item.id });
			await load();
		} else if (res.reason === 'in_debt') {
			await load(); // loan outstanding → lock the whole Store
		} else {
			msg = res.reason === 'insufficient' ? 'Not enough Cash.' : 'Could not buy that.';
		}
	}
	/** @param {any} item */
	async function equip(item) {
		if (busy) return;
		busy = item.id;
		const res = item.equipped ? await unequipCosmetic(item.kind) : await equipCosmetic(item.id);
		busy = '';
		if (res.ok) {
			await load();
		}
	}
</script>

<svelte:head><title>WordBank — Store</title></svelte:head>

<main class="shop-page">
	<PageNav back={backTo} showHome={false} />

	<div class="head">
		<h1><Icon name="bag" size={22} /> Store</h1>
		<span class="bank-chip"><Icon name="cash" size={16} /> ${bank.toLocaleString()}</span>
	</div>
	<p class="sub">Power-ups for the Cash Game &amp; challenges, plus cosmetics.</p>

	{#if loading}
		<p class="loading">Loading…</p>
	{:else if loan > 0}
		<!-- 🔒 Store locked while you owe — no buying anything until the loan is paid off. -->
		<div class="locked">
			<div class="locked-ic"><Icon name="lock" size={30} /></div>
			<h2>Store locked</h2>
			<p class="locked-msg">
				You owe <b>${loan.toLocaleString()}</b> on a loan. The Store stays closed until it's paid off
				— no cosmetics, power-ups, or boosts.
			</p>
			<a class="pay-btn" href="/loans"><Icon name="shark" size={16} /> Pay off loan →</a>
			<p class="locked-sub">
				Solve the Daily or a Cash Game to earn — half of every deposit auto-pays your loan down.
			</p>
		</div>
	{:else}
		{#if msg}<p class="msg">{msg}</p>{/if}

		{#key inventoryKey}
			<details class="inv-details">
				<summary class="inv-summary"><Icon name="bag" size={16} /> What you own</summary>
				<InventoryList />
			</details>
		{/key}

		{#if dboost.length}
			<h2 class="section"><Icon name="boost" size={18} /> Interest Boosts</h2>
			<p class="section-note">
				Stock up, then tap one in before you solve the Daily to add Interest to your deposit — they
				stack (carry up to 5 of each).
			</p>
			<div class="grid">
				{#each dboost as item}
					<div class="card pup" class:owned={item.owned > 0}>
						<span class="pup-ic"><Icon name={PUP_META[item.id]?.icon ?? 'boost'} size={26} /></span>
						<span class="c-label"
							>{item.name}{#if item.owned > 0}
								<span class="owned-x">×{item.owned}</span>{/if}</span
						>
						<span class="pup-desc">{PUP_META[item.id]?.desc ?? ''}</span>
						{#if item.owned >= 5}
							<button class="c-btn equip on" disabled
								><Icon name="check" size={14} /> Maxed (5)</button
							>
						{:else}
							<button
								class="c-btn buy"
								disabled={busy === item.id || bank < item.price}
								onclick={() => buyPup(item)}
							>
								<Icon name="cash" size={14} /> ${item.price.toLocaleString()}
							</button>
						{/if}
					</div>
				{/each}
			</div>
		{/if}

		<h2 class="section"><Icon name="bolt" size={18} /> Power-ups</h2>
		<div class="grid">
			{#each pups as item}
				<div class="card pup" class:owned={item.owned > 0}>
					<span class="pup-ic"><Icon name={PUP_META[item.id]?.icon ?? 'boost'} size={26} /></span>
					<span class="c-label">{item.name}</span>
					<span class="pup-desc">{PUP_META[item.id]?.desc ?? ''}</span>
					{#if item.owned > 0}
						<button class="c-btn equip on" disabled
							><Icon name="check" size={14} /> In your bag</button
						>
					{:else}
						<button
							class="c-btn buy"
							disabled={busy === item.id || bank < item.price}
							onclick={() => buyPup(item)}
						>
							<Icon name="cash" size={14} /> ${item.price.toLocaleString()}
						</button>
					{/if}
				</div>
			{/each}
		</div>

		{#if sabs.length}
			<h2 class="section"><Icon name="sabotage" size={18} /> Sabotage</h2>
			<p class="section-note">
				Bring these to a challenge with power-ups on, then hit an opponent — they get notified.
			</p>
			<div class="grid">
				{#each sabs as item}
					<div class="card pup" class:owned={item.owned > 0}>
						<span class="pup-ic"
							><Icon name={PUP_META[item.id]?.icon ?? 'sabotage'} size={26} /></span
						>
						<span class="c-label">{item.name}</span>
						<span class="pup-desc">{PUP_META[item.id]?.desc ?? ''}</span>
						{#if item.owned > 0}
							<button class="c-btn equip on" disabled
								><Icon name="check" size={14} /> In your bag</button
							>
						{:else}
							<button
								class="c-btn buy"
								disabled={busy === item.id || bank < item.price}
								onclick={() => buyPup(item)}
							>
								<Icon name="cash" size={14} /> ${item.price.toLocaleString()}
							</button>
						{/if}
					</div>
				{/each}
			</div>
		{/if}

		<h2 class="section">Titles</h2>
		<div class="grid">
			{#each titles as item}
				<div class="card" class:owned={item.owned}>
					<span class="c-label">{item.label}</span>
					{#if item.owned}
						<button
							class="c-btn equip"
							class:on={item.equipped}
							disabled={busy === item.id}
							onclick={() => equip(item)}
						>
							{#if item.equipped}<Icon name="check" size={14} /> Equipped{:else}Equip{/if}
						</button>
					{:else}
						<button
							class="c-btn buy"
							disabled={busy === item.id || bank < item.price}
							onclick={() => buy(item)}
						>
							<Icon name="cash" size={14} /> ${item.price.toLocaleString()}
						</button>
					{/if}
				</div>
			{/each}
		</div>

		<h2 class="section">Name Colors</h2>
		<div class="grid">
			{#each colors as item}
				<div class="card" class:owned={item.owned}>
					<span class="c-label" style="color:{item.value}">{item.label}</span>
					{#if item.owned}
						<button
							class="c-btn equip"
							class:on={item.equipped}
							disabled={busy === item.id}
							onclick={() => equip(item)}
						>
							{#if item.equipped}<Icon name="check" size={14} /> Equipped{:else}Equip{/if}
						</button>
					{:else}
						<button
							class="c-btn buy"
							disabled={busy === item.id || bank < item.price}
							onclick={() => buy(item)}
						>
							<Icon name="cash" size={14} /> ${item.price.toLocaleString()}
						</button>
					{/if}
				</div>
			{/each}
		</div>
	{/if}
</main>

<style>
	.shop-page {
		max-width: 480px;
		margin: 0 auto;
		padding: 1.5rem 1rem 3rem;
	}

	.head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
	}
	h1 {
		font-family: var(--font-display);
		font-size: 1.7rem;
		margin: 0;
	}
	.bank-chip {
		font-family: var(--font-display);
		font-weight: 800;
		color: #fbbf24;
		font-size: 1.05rem;
	}
	.sub {
		color: var(--text-muted);
		font-size: 0.9rem;
		margin: 0.2rem 0 1.4rem;
	}
	.loading {
		color: var(--text-muted);
		padding: 2rem;
		text-align: center;
	}
	.locked {
		display: flex;
		flex-direction: column;
		align-items: center;
		text-align: center;
		gap: 0.5rem;
		margin: 2rem auto 0;
		padding: 2rem 1.4rem;
		max-width: 340px;
		border: 1px solid rgba(248, 113, 113, 0.32);
		border-radius: 18px;
		background: linear-gradient(160deg, rgba(248, 113, 113, 0.08), rgba(248, 113, 113, 0.02));
	}
	.locked-ic {
		font-size: 2.4rem;
		line-height: 1;
	}
	.locked h2 {
		font-family: var(--font-display);
		font-size: 1.35rem;
		margin: 0.2rem 0 0;
	}
	.locked-msg {
		color: var(--text-muted);
		font-size: 0.92rem;
		line-height: 1.45;
		margin: 0;
	}
	.locked-msg b {
		color: #fca5a5;
		font-family: var(--font-display);
	}
	.pay-btn {
		display: inline-block;
		margin: 0.7rem 0 0.2rem;
		padding: 0.7rem 1.4rem;
		border-radius: 12px;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 0.98rem;
		text-decoration: none;
		color: #3a2a00;
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
	}
	.locked-sub {
		color: var(--text-faint);
		font-size: 0.78rem;
		line-height: 1.4;
		margin: 0.4rem 0 0;
	}
	.msg {
		text-align: center;
		color: #f87171;
		font-size: 0.88rem;
		margin: 0 0 1rem;
	}
	.owned-x {
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		font-size: 0.78rem;
		color: #fde047;
	}
	.inv-details {
		margin: 0 0 0.4rem;
		border: 1px solid var(--border);
		border-radius: 14px;
		background: var(--surface);
		padding: 0 0.9rem;
	}
	.inv-summary {
		cursor: pointer;
		padding: 0.85rem 0;
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.98rem;
		list-style: none;
	}
	.inv-summary::-webkit-details-marker {
		display: none;
	}
	.inv-summary::after {
		content: ' ▾';
		color: var(--text-faint);
	}
	.inv-details[open] .inv-summary::after {
		content: ' ▴';
	}
	.inv-details[open] {
		padding-bottom: 0.9rem;
	}
	.section {
		font-family: var(--font-display);
		font-size: 1.05rem;
		margin: 1.4rem 0 0.4rem;
	}
	.section-note {
		font-size: 0.76rem;
		color: var(--text-faint);
		margin: 0 0 0.8rem;
	}
	.card.pup {
		align-items: center;
		text-align: center;
		gap: 0.3rem;
	}
	.pup-ic {
		font-size: 1.7rem;
		line-height: 1;
	}
	.pup-desc {
		font-size: 0.72rem;
		color: var(--text-muted);
		line-height: 1.3;
		min-height: 2.1em;
	}
	.card.pup .c-btn {
		margin-top: 0.3rem;
	}
	.grid {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 0.6rem;
	}
	.card {
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
		align-items: flex-start;
		padding: 0.9rem;
		border-radius: 14px;
		border: 1px solid var(--border);
		background: var(--surface);
	}
	.card.owned {
		border-color: rgba(253, 224, 71, 0.35);
	}
	.c-label {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1rem;
	}
	.c-btn {
		width: 100%;
		padding: 0.5rem 0.7rem;
		border-radius: 10px;
		cursor: pointer;
		font-weight: 700;
		font-size: 0.85rem;
		border: 1px solid var(--border);
		background: var(--surface-2, rgba(255, 255, 255, 0.04));
		color: var(--text);
	}
	.c-btn.buy {
		color: #3a2a00;
		border: none;
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
	}
	.c-btn.buy:disabled {
		opacity: 0.45;
		cursor: default;
	}
	.c-btn.equip.on {
		color: var(--brand-2);
		border-color: rgba(253, 224, 71, 0.5);
		background: rgba(253, 224, 71, 0.1);
	}
	.c-btn:disabled {
		opacity: 0.6;
	}
</style>
