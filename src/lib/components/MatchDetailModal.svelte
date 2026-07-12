<script>
	import { createEventDispatcher } from 'svelte';
	import Icon from '$lib/components/Icon.svelte';
	import CategoryIcon from '$lib/components/CategoryIcon.svelte';
	import { CATEGORIES } from '$lib/categories.js';

	// daily_puzzles.category carries a trailing emoji in the string; show the clean
	// label + the line icon instead of the raw emoji.
	const catLabel = (/** @type {string} */ v) =>
		CATEGORIES.find((c) => c.value === v)?.label ??
		String(v ?? '')
			.replace(/[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}️]/gu, '')
			.trim();

	/** @type {any} */
	export let detail = null; // get_match_detail() result, or { loading:true }

	const dispatch = createEventDispatcher();
	const close = () => dispatch('close');

	$: parts = detail?.participants ?? [];
	$: m = detail?.match;
	$: opp = parts.find((/** @type {any} */ p) => !p.is_me);
	$: me = parts.find((/** @type {any} */ p) => p.is_me);
	$: noSolve = parts.length > 0 && parts.every((/** @type {any} */ p) => (p.solved ?? 0) === 0);
	$: title = detail?.group_name || (opp ? '@' + (opp.name || 'player') : 'Challenge');
	$: wagered = Number(m?.wager) > 0;
	const money = (/** @type {any} */ n) =>
		(Number(n) < 0 ? '−$' : '+$') + Math.abs(Math.round(Number(n ?? 0))).toLocaleString();
	const mult = (/** @type {any} */ x) => (x ? (Number(x) / 100).toFixed(1) + '×' : '');
	const ordinal = (/** @type {number} */ n) => {
		const s = ['th', 'st', 'nd', 'rd'],
			v = n % 100;
		return n + (s[(v - 20) % 10] || s[v] || s[0]);
	};
	const dollars = (/** @type {any} */ n) => '$' + Number(n ?? 0).toLocaleString();

	// The spend "tie-back": frame the outcome in the universal metric — who solved
	// for the least. Works for 1v1 and groups, wagered or friendly.
	$: field = parts.length;
	$: winner = parts.find((/** @type {any} */ p) => Number(p.rank) === 1);
	$: iWon = me && Number(me.rank) === 1;
	// A 1v1 tie: both participants share rank 1 (equal spend). Never call that a win.
	$: isTie = field === 2 && !!me && !!opp && Number(me.rank) === 1 && Number(opp.rank) === 1;
	$: tieback = (() => {
		if (!me || noSolve || m?.status !== 'settled') return '';
		const myS = dollars(me.spent);
		if (isTie) return me.solved ? `Tie — you both solved for ${myS}.` : `Tie — no winner.`;
		if (field === 2 && opp) {
			const oS = dollars(opp.spent),
				on = '@' + (opp.name || 'opponent');
			if (iWon)
				return me.solved
					? `You solved for ${myS} — beat ${on}'s ${oS}.`
					: `You took it — ${on} didn't solve.`;
			if (Number(opp.rank) === 1)
				return opp.solved ? `${on} solved for ${oS} — you spent ${myS}.` : `You spent ${myS}.`;
			return `You spent ${myS}.`;
		}
		if (iWon) return `You solved for ${myS} — cheapest of ${field}.`;
		if (winner)
			return `Winner @${winner.name || 'player'} solved for ${dollars(winner.spent)} — you placed ${ordinal(Number(me.rank))} (${myS}).`;
		return `You placed ${ordinal(Number(me.rank))} — you spent ${myS}.`;
	})();
</script>

{#if detail}
	<div
		class="md-overlay"
		role="button"
		tabindex="0"
		on:click={close}
		on:keydown={(e) => {
			if (e.key === 'Escape') close();
		}}
	>
		<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions a11y_no_noninteractive_element_interactions a11y_no_noninteractive_tabindex -->
		<div class="md" role="dialog" tabindex="0" on:click|stopPropagation on:keydown={() => {}}>
			<button class="md-x" on:click={close}><Icon name="close" size={16} /></button>
			{#if detail.loading}
				<p class="md-msg">Loading…</p>
			{:else}
				<h2 class="md-title">
					{#if noSolve}<Icon name="handshake" size={18} />{:else}<Icon
							name="swords"
							size={18}
						/>{/if}
					{title}
				</h2>
				<p class="md-sub">
					{m?.pack_size} puzzle{m?.pack_size === 1 ? '' : 's'}
					· {m?.payout === 'podium' ? 'podium 3·2·1' : 'winner-take-all'}
					{#if wagered}· ${Number(m.wager).toLocaleString()} buy-in{:else}· friendly{/if}
					{#if m?.status !== 'settled'}· <em>in progress</em>{/if}
					{#if noSolve && wagered}· buy-in refunded{/if}
				</p>

				{#if wagered && m?.status === 'settled' && me && me.net != null && !noSolve}
					<div class="md-outcome {Number(me.net) >= 0 ? 'win' : 'loss'}">
						<span class="md-out-net">{money(me.net)}</span>
						<span class="md-out-lbl">
							{#if Number(me.net) >= 0}you took the pot{#if mult(me.multiple_x100)}
									· {mult(me.multiple_x100)}{/if}{:else}you spent ${me.spent}{/if}
						</span>
					</div>
				{/if}

				{#if tieback}
					<p class="md-tieback"><Icon name="target" size={14} /> {tieback}</p>
				{/if}

				<div class="md-standings">
					{#each parts as p}
						<div class="md-row" class:me={p.is_me}>
							<span class="md-rank"
								>{#if noSolve || isTie}<Icon
										name="handshake"
										size={16}
									/>{:else if p.rank >= 1 && p.rank <= 3}<span class="rk-{p.rank}"
										><Icon name="medal" size={16} /></span
									>{:else}#{p.rank}{/if}</span
							>
							<span class="md-name">{p.is_me ? 'You' : '@' + (p.name || 'player')}</span>
							<span class="md-meta">
								{#if p.state === 'done'}solved {p.solved ?? 0}/{m?.pack_size}{#if p.spent != null}
										· ${Number(p.spent).toLocaleString()} spent{/if}{#if wagered && p.net != null}
										· <span class:pos={Number(p.net) >= 0} class:neg={Number(p.net) < 0}
											>{money(p.net)}</span
										>{/if}
								{:else}{p.state}{/if}
							</span>
						</div>
					{/each}
				</div>

				{#if detail.pack?.length}
					<div class="md-pack">
						<div class="md-pack-h">Puzzles</div>
						{#each detail.pack as pk}
							<div class="md-pk">
								<span class="md-pos">{pk.position}</span>
								<span class="md-cat"
									><CategoryIcon category={pk.category} size={13} /> {catLabel(pk.category)}</span
								>
								<span class="md-ans"
									>{#if pk.phrase}“{pk.phrase}”{:else}<Icon name="lock" size={13} /> hidden until settled{/if}</span
								>
							</div>
						{/each}
					</div>
				{/if}
			{/if}
		</div>
	</div>
{/if}

<style>
	.md-overlay {
		position: fixed;
		inset: 0;
		z-index: 10000;
		display: grid;
		place-items: center;
		padding: 18px;
		background: rgba(5, 5, 5, 0.8);
		backdrop-filter: blur(4px);
	}
	.md {
		width: 100%;
		max-width: 440px;
		max-height: 86vh;
		overflow-y: auto;
		position: relative;
		background: var(--surface-strong);
		border: 1px solid var(--border-strong);
		border-radius: var(--r-lg);
		padding: 20px;
	}
	.md-x {
		position: absolute;
		top: 12px;
		right: 14px;
		background: none;
		border: none;
		color: var(--text-muted);
		font-size: 1rem;
		cursor: pointer;
	}
	.md-title {
		font-family: var(--font-display);
		font-size: 1.25rem;
		margin: 0 0 4px;
	}
	.md-sub {
		color: var(--text-faint);
		font-size: 0.8rem;
		margin: 0 0 16px;
	}
	.md-msg {
		color: var(--text-muted);
		text-align: center;
		padding: 24px 0;
	}

	.md-outcome {
		display: flex;
		align-items: baseline;
		gap: 10px;
		justify-content: center;
		padding: 12px;
		margin: 0 0 16px;
		border-radius: var(--r-md);
		border: 1px solid var(--border);
	}
	.md-outcome.win {
		background: rgba(126, 224, 168, 0.1);
		border-color: rgba(126, 224, 168, 0.3);
	}
	.md-outcome.loss {
		background: rgba(251, 113, 133, 0.08);
		border-color: rgba(251, 113, 133, 0.25);
	}
	.md-out-net {
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		font-size: 1.6rem;
	}
	.md-outcome.win .md-out-net {
		color: #7ee0a8;
	}
	.md-outcome.loss .md-out-net {
		color: #fb7185;
	}
	.md-out-lbl {
		color: var(--text-muted);
		font-size: 0.82rem;
	}
	.md-tieback {
		text-align: center;
		font-size: 0.9rem;
		font-weight: 600;
		color: var(--text);
		margin: 0 0 16px;
		padding: 10px 12px;
		border-radius: var(--r-md);
		background: rgba(251, 191, 36, 0.08);
		border: 1px solid rgba(251, 191, 36, 0.25);
	}
	.md-meta .pos {
		color: #7ee0a8;
	}
	.md-meta .neg {
		color: #fb7185;
	}

	.md-standings {
		display: flex;
		flex-direction: column;
		gap: 6px;
		margin-bottom: 16px;
	}
	.md-row {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 9px 11px;
		border-radius: var(--r-sm);
		background: var(--surface);
	}
	.md-row.me {
		background: rgba(251, 191, 36, 0.12);
		border: 1px solid rgba(251, 191, 36, 0.3);
	}
	.md-rank {
		flex: 0 0 28px;
		font-weight: 700;
	}
	.md-rank .rk-1 {
		color: #fbbf24;
	}
	.md-rank .rk-2 {
		color: #cbd5e1;
	}
	.md-rank .rk-3 {
		color: #d19a66;
	}
	.md-name {
		flex: 1;
		font-weight: 700;
		color: var(--text);
	}
	.md-meta {
		color: var(--text-faint);
		font-size: 0.76rem;
		text-align: right;
	}

	.md-pack {
		border-top: 1px solid var(--border);
		padding-top: 12px;
	}
	.md-pack-h {
		color: var(--text-faint);
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		margin-bottom: 8px;
	}
	.md-pk {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 5px 0;
		font-size: 0.84rem;
	}
	.md-pos {
		flex: 0 0 20px;
		color: var(--text-faint);
	}
	.md-cat {
		flex: 0 0 auto;
		color: var(--text-muted);
		font-size: 0.74rem;
	}
	.md-ans {
		color: var(--gold);
		font-weight: 600;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
</style>
