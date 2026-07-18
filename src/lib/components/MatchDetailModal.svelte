<script>
	import { createEventDispatcher } from 'svelte';
	import Icon from '$lib/components/Icon.svelte';
	import CategoryIcon from '$lib/components/CategoryIcon.svelte';
	import { CATEGORIES } from '$lib/categories.js';
	import { fmtSecs } from '$lib/time.js';

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

	// Per-puzzle breakdown is the "nerd-out" section — collapsed by default so a big
	// group match isn't a wall of rows the moment you open the slip.
	let showPack = false;

	$: parts = detail?.participants ?? [];
	$: m = detail?.match;
	$: opp = parts.find((/** @type {any} */ p) => !p.is_me);
	$: me = parts.find((/** @type {any} */ p) => p.is_me);
	$: noSolve = parts.length > 0 && parts.every((/** @type {any} */ p) => (p.solved ?? 0) === 0);
	$: title = detail?.group_name || (opp ? '@' + (opp.name || 'player') : 'Challenge');
	$: wagered = Number(m?.wager) > 0;
	$: settled = m?.status === 'settled';

	const money = (/** @type {any} */ n) =>
		(Number(n) < 0 ? '−$' : '+$') + Math.abs(Math.round(Number(n ?? 0))).toLocaleString();
	const mult = (/** @type {any} */ x) => (x ? (Number(x) / 100).toFixed(1) + '×' : '');
	const ordinal = (/** @type {number} */ n) => {
		const s = ['th', 'st', 'nd', 'rd'],
			v = n % 100;
		return n + (s[(v - 20) % 10] || s[v] || s[0]);
	};
	const dollars = (/** @type {any} */ n) => '$' + Number(n ?? 0).toLocaleString();

	$: field = parts.length;
	$: isGroup = field >= 3;
	$: winner = parts.find((/** @type {any} */ p) => Number(p.rank) === 1);
	$: iWon = me && Number(me.rank) === 1;
	// A 1v1 tie: both participants share rank 1 (equal kept score AND equal time).
	$: isTie = field === 2 && !!me && !!opp && Number(me.rank) === 1 && Number(opp.rank) === 1;
	// 1v1 speed gap — the decider when kept scores are equal.
	$: haveTimes = field === 2 && me?.elapsed_seconds != null && opp?.elapsed_seconds != null;
	$: speedGap = haveTimes ? Math.abs(me.elapsed_seconds - opp.elapsed_seconds) : null;
	$: sameScore = !!me && !!opp && Number(me.score) === Number(opp.score);

	// Money P&L, exact from the server. game_results stores earned (pot share) and
	// net (= earned − stake), so the stake you paid is recoverable as earned − net.
	$: earned = Number(me?.earned ?? 0);
	$: net = Number(me?.net ?? 0);
	$: ante = Math.max(0, earned - net);
	$: showMoney = wagered && settled && !noSolve && me?.net != null;

	// You placed but didn't win, yet still took a pot share (group podium) — "in the money".
	$: inMoney = wagered && !iWon && earned > 0;

	$: verdictKind = noSolve || isTie ? 'tie' : iWon ? 'win' : inMoney ? 'place' : 'loss';
	$: verdictHead = noSolve
		? 'NO CONTEST'
		: isTie
			? 'TIE'
			: isGroup
				? ordinal(Number(me?.rank ?? 0)).toUpperCase()
				: iWon
					? 'VICTORY'
					: 'DEFEAT';
	// For group results, pair the placement ("2ND") with the field size ("of 5").
	$: verdictSuffix = isGroup && !noSolve && !isTie && me ? `of ${field}` : '';

	// The one-line reason: solve count first (the real driver), then kept score, then speed.
	$: reason = (() => {
		if (!me || !settled) return '';
		if (noSolve) return wagered ? 'Nobody solved — buy-in refunded.' : 'Nobody solved.';
		if (isTie) return me.solved ? `Dead heat — you both kept ${dollars(me.score)}.` : 'Tie — no winner.';
		if (field === 2 && opp) {
			const on = '@' + (opp.name || 'opponent');
			const solvedDiff = Number(me.solved ?? 0) !== Number(opp.solved ?? 0);
			if (iWon) {
				if (!opp.solved) return `You took it — ${on} didn't solve.`;
				if (solvedDiff) return `You solved ${me.solved} — ${on} got ${opp.solved}.`;
				if (sameScore && speedGap) return `Tied on kept — you were ${fmtSecs(speedGap)} faster.`;
				return `You kept ${dollars(me.score)} — ${on} kept ${dollars(opp.score)}.`;
			}
			if (!me.solved) return `${on} solved — you didn't.`;
			if (solvedDiff) return `${on} solved ${opp.solved} — you got ${me.solved}.`;
			if (sameScore && speedGap) return `Tied on kept — ${on} was ${fmtSecs(speedGap)} faster.`;
			return `${on} kept ${dollars(opp.score)} — you kept ${dollars(me.score)}.`;
		}
		// Group / podium (3+).
		if (iWon) return `You solved ${me.solved} — best of ${field}.`;
		if (winner)
			return `@${winner.name || 'player'} won with ${winner.solved} — you got ${me.solved}.`;
		return `You placed ${ordinal(Number(me.rank))}.`;
	})();

	// Per-puzzle ✓/✗ needs solved_positions on at least one participant; older
	// matches (recorded before this field existed) fall back to a plain list.
	$: hasMarks = parts.some((/** @type {any} */ p) => (p.solved_positions?.length ?? 0) > 0);
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
		<div class="md-wrap" role="dialog" tabindex="0" on:click|stopPropagation on:keydown={() => {}}>
			<button class="md-x" on:click={close} aria-label="Close"
				><Icon name="close" size={16} /></button
			>

			<div class="md-scroll">
			{#if detail.loading}
				<p class="md-msg">Loading…</p>
			{:else}
				<div class="receipt" class:void={verdictKind === 'loss'}>
					<div class="rcpt-brand">
						<img class="rcpt-coin" src="/logo-coin.png" alt="" width="40" height="40" />
						<img class="rcpt-mark" src="/wordmark.png" alt="WordBank" />
					</div>
					<div class="rcpt-title" class:void={verdictKind === 'loss'}>CHALLENGE RESULT</div>
					<div class="rcpt-acct">{title}</div>
					<div class="rcpt-sub">
						{m?.pack_size} puzzle{m?.pack_size === 1 ? '' : 's'} ·
						{field >= 3 ? 'podium 3·2·1' : 'winner-take-all'}
						{#if !wagered}· friendly{/if}
					</div>

					{#if !settled}
						<div class="rcpt-rule"></div>
						<div class="rcpt-pending">
							<Icon name="timer" size={15} />
							<span>Still in progress — settles once everyone plays.</span>
						</div>
					{:else if me}
						<!-- Outcome — the emotional headline, big and centered. -->
						<div class="rcpt-rule"></div>
						<div class="rcpt-verdict {verdictKind}">
							<div class="rv-head">
								{#if noSolve}<Icon name="handshake" size={20} /> {/if}{verdictHead}{#if verdictSuffix}<span
										class="rv-of"> {verdictSuffix}</span
									>{/if}
							</div>
							{#if reason}<div class="rv-reason">{reason}</div>{/if}
						</div>

						<!-- The money — where the net came from. -->
						{#if showMoney}
							<div class="rcpt-rule"></div>
							<div class="rcpt-cap">The money</div>
							<div class="rcpt-line">
								<span>Buy-in</span><span class="neg">−${ante.toLocaleString()}</span>
							</div>
							{#if earned > 0}
								<div class="rcpt-line">
									<span
										>Winnings{#if mult(me.multiple_x100)}
											<small>({mult(me.multiple_x100)})</small>{/if}</span
									><span class="pos">+${earned.toLocaleString()}</span>
								</div>
							{/if}
							<div class="rcpt-rule double"></div>
							<div class="rcpt-line total" class:profit={net >= 0}>
								<span>{net >= 0 ? 'NET WON' : 'NET LOST'}</span><span>{money(net)}</span>
							</div>
						{:else if !wagered}
							<div class="rcpt-rule"></div>
							<div class="rcpt-note">Friendly match — no cash on the line.</div>
						{/if}
					{/if}

					<!-- Standings — one compact line per player. -->
					<div class="rcpt-rule"></div>
					<div class="rcpt-cap">Standings</div>
					<div class="md-standings">
						{#each parts as p}
							<div class="md-row" class:me={p.is_me}>
								<span class="md-rank">
									{#if noSolve || isTie}<Icon name="handshake" size={15} />
									{:else if p.rank >= 1 && p.rank <= 3}<span class="rk-{p.rank}"
											><Icon name="medal" size={15} /></span
										>
									{:else}#{p.rank}{/if}
								</span>
								<span class="md-name">{p.is_me ? 'You' : '@' + (p.name || 'player')}</span>
								<span class="md-meta">
									{#if p.state === 'done'}kept {dollars(p.score)} · {p.solved ?? 0}/{m?.pack_size}{#if p.elapsed_seconds != null}
											· {fmtSecs(p.elapsed_seconds)}{/if}
									{:else}{p.state}{/if}
								</span>
							</div>
						{/each}
					</div>

					<!-- Per-puzzle detail — collapsed by default. -->
					{#if detail.pack?.length}
						<div class="rcpt-rule"></div>
						<button class="rcpt-toggle" class:open={showPack} on:click={() => (showPack = !showPack)}>
							<span class="rt-caret"><Icon name="chevron-right" size={13} /></span>
							Puzzles ({detail.pack.length})
						</button>
						{#if showPack}
							<div class="md-pack">
								{#if hasMarks}
									<div class="md-pack-legend">
										{#each parts as p}
											<span class="md-pack-who" title={p.is_me ? 'You' : '@' + (p.name || 'player')}
												>{p.is_me ? 'Y' : (p.name || '?').charAt(0).toUpperCase()}</span
											>
										{/each}
									</div>
								{/if}
								{#each detail.pack as pk}
									<div class="md-pk">
										<span class="md-pos">{pk.position}</span>
										<span class="md-cat"
											><CategoryIcon category={pk.category} size={12} /> {catLabel(pk.category)}</span
										>
										<span class="md-ans"
											>{#if pk.phrase}“{pk.phrase}”{:else}<Icon name="lock" size={12} /> hidden{/if}</span
										>
										{#if hasMarks}
											<span class="md-marks">
												{#each parts as p}
													{@const got = (p.solved_positions ?? []).includes(pk.position)}
													<span
														class="md-mark"
														class:got
														title={(p.is_me ? 'You' : '@' + (p.name || 'player')) +
															(got ? ' solved this' : " didn't solve this")}
														><Icon name={got ? 'check' : 'close'} size={10} /></span
													>
												{/each}
											</span>
										{/if}
									</div>
								{/each}
							</div>
						{/if}
					{/if}

					<div class="rcpt-thanks">
						{settled ? 'Thank you for playing WordBank' : 'Come back when the match settles'}
					</div>
				</div>
			{/if}
			</div>
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
	.md-wrap {
		position: relative;
		width: 100%;
		max-width: 340px;
	}
	.md-scroll {
		max-height: 88vh;
		overflow-y: auto;
		border-radius: 3px;
	}
	.md-x {
		position: absolute;
		top: -2px;
		right: 2px;
		z-index: 3;
		width: 28px;
		height: 28px;
		display: grid;
		place-items: center;
		border-radius: 999px;
		background: rgba(0, 0, 0, 0.55);
		border: 1px solid var(--border-strong);
		color: #fff;
		cursor: pointer;
	}
	.md-msg {
		color: var(--text-muted);
		text-align: center;
		padding: 40px 0;
	}

	/* 🧾 Receipt paper — mirrors the win-slip aesthetic used in the game. */
	.receipt {
		font-family: 'Courier New', 'Courier', ui-monospace, monospace;
		width: 100%;
		margin: 0 auto;
		padding: 20px 20px 22px;
		background: #f6f1e6;
		color: #23201a;
		border-radius: 3px;
		box-shadow: 0 12px 34px rgba(0, 0, 0, 0.55);
		text-align: left;
		-webkit-mask:
			linear-gradient(#000 0 0) top / 100% calc(100% - 7px) no-repeat,
			radial-gradient(6px 7px at 6px 0, #0000 98%, #000) bottom left / 12px 7px repeat-x;
		mask:
			linear-gradient(#000 0 0) top / 100% calc(100% - 7px) no-repeat,
			radial-gradient(6px 7px at 6px 0, #0000 98%, #000) bottom left / 12px 7px repeat-x;
		animation: md-slip-in 0.28s ease both;
	}
	@keyframes md-slip-in {
		from {
			opacity: 0;
			transform: translateY(-8px);
		}
		to {
			opacity: 1;
			transform: translateY(0);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.receipt {
			animation: none;
		}
	}
	.rcpt-brand {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 5px;
		margin-bottom: 2px;
	}
	.rcpt-coin {
		width: 40px;
		height: 40px;
		object-fit: contain;
		filter: drop-shadow(0 2px 3px rgba(0, 0, 0, 0.35));
	}
	.rcpt-mark {
		width: 150px;
		max-width: 72%;
		height: auto;
		filter: drop-shadow(0 1px 1px rgba(0, 0, 0, 0.28)) saturate(1.05) contrast(1.05);
	}
	.rcpt-title {
		text-align: center;
		font-weight: 700;
		font-size: 0.76rem;
		letter-spacing: 0.28em;
		margin-top: 3px;
	}
	.rcpt-title.void {
		color: #b91c1c;
	}
	.rcpt-acct {
		text-align: center;
		font-size: 0.82rem;
		font-weight: 700;
		letter-spacing: 0.06em;
		color: #23201a;
		margin: 6px 0 1px;
	}
	.rcpt-sub {
		text-align: center;
		font-size: 0.66rem;
		letter-spacing: 0.03em;
		color: #6b6455;
	}
	.rcpt-cap {
		font-size: 0.6rem;
		text-transform: uppercase;
		letter-spacing: 0.11em;
		font-weight: 700;
		color: #8a8172;
		margin: 4px 0 3px;
	}
	.rcpt-rule {
		border-top: 1px dashed #b3a88f;
		margin: 8px 0;
	}
	.rcpt-rule.double {
		border-top: 2px solid #23201a;
	}
	.rcpt-line {
		display: flex;
		justify-content: space-between;
		gap: 12px;
		font-size: 0.82rem;
		padding: 2px 0;
		font-variant-numeric: tabular-nums;
	}
	.rcpt-line small {
		color: #8a8172;
	}
	.rcpt-line .neg {
		color: #b91c1c;
	}
	.rcpt-line .pos {
		color: #157a3a;
	}
	.rcpt-line.total {
		font-weight: 800;
		font-size: 0.98rem;
	}
	.rcpt-line.total.profit {
		color: #157a3a;
	}
	.rcpt-note {
		text-align: center;
		font-size: 0.72rem;
		color: #6b6455;
		margin: 4px 0 2px;
	}
	.rcpt-thanks {
		text-align: center;
		font-size: 0.72rem;
		font-style: italic;
		color: #4a4636;
		margin-top: 14px;
		letter-spacing: 0.02em;
	}
	.rcpt-pending {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 7px;
		text-align: center;
		font-size: 0.74rem;
		color: #6b6455;
		padding: 6px 0 2px;
	}

	/* 🏆 Outcome headline block */
	.rcpt-verdict {
		text-align: center;
		padding: 12px 10px;
		margin: 2px 0;
		border-radius: 6px;
		border: 1px solid #d8cfb8;
		background: rgba(255, 255, 255, 0.35);
	}
	.rcpt-verdict.win {
		background: rgba(21, 122, 58, 0.1);
		border-color: rgba(21, 122, 58, 0.35);
	}
	.rcpt-verdict.place {
		background: rgba(180, 130, 20, 0.12);
		border-color: rgba(180, 130, 20, 0.4);
	}
	.rcpt-verdict.loss {
		background: rgba(185, 28, 28, 0.08);
		border-color: rgba(185, 28, 28, 0.28);
	}
	.rv-head {
		font-family: 'Orbitron', var(--font-display), sans-serif;
		font-weight: 800;
		font-size: 1.55rem;
		letter-spacing: 0.05em;
		line-height: 1.1;
		color: #23201a;
	}
	.rcpt-verdict.win .rv-head {
		color: #157a3a;
	}
	.rcpt-verdict.place .rv-head {
		color: #a2711a;
	}
	.rcpt-verdict.loss .rv-head {
		color: #b91c1c;
	}
	.rv-of {
		font-size: 0.9rem;
		font-weight: 700;
		letter-spacing: 0.04em;
		opacity: 0.7;
	}
	.rv-reason {
		margin-top: 5px;
		color: #6b6455;
		font-size: 0.76rem;
	}

	/* 📊 Standings on paper */
	.md-standings {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}
	.md-row {
		display: flex;
		align-items: center;
		gap: 9px;
		padding: 6px 8px;
		border-radius: 4px;
		background: rgba(0, 0, 0, 0.03);
	}
	.md-row.me {
		background: rgba(180, 130, 20, 0.13);
		box-shadow: inset 0 0 0 1px rgba(180, 130, 20, 0.3);
	}
	.md-rank {
		flex: 0 0 26px;
		font-weight: 700;
		display: flex;
		align-items: center;
		color: #6b6455;
	}
	.md-rank .rk-1 {
		color: #c99a1e;
	}
	.md-rank .rk-2 {
		color: #8a8172;
	}
	.md-rank .rk-3 {
		color: #b06a3a;
	}
	.md-name {
		flex: 1;
		font-weight: 700;
		color: #23201a;
		font-size: 0.84rem;
	}
	.md-meta {
		color: #6b6455;
		font-size: 0.68rem;
		text-align: right;
		font-variant-numeric: tabular-nums;
	}

	/* ▸ Collapsible per-puzzle detail */
	.rcpt-toggle {
		display: flex;
		align-items: center;
		gap: 6px;
		width: 100%;
		background: none;
		border: none;
		padding: 2px 0;
		font-family: inherit;
		font-size: 0.6rem;
		text-transform: uppercase;
		letter-spacing: 0.11em;
		font-weight: 700;
		color: #8a8172;
		cursor: pointer;
	}
	.rt-caret {
		display: inline-flex;
		transition: transform 0.18s ease;
	}
	.rcpt-toggle.open .rt-caret {
		transform: rotate(90deg);
	}
	.md-pack {
		margin-top: 6px;
	}
	.md-pack-legend {
		display: flex;
		justify-content: flex-end;
		gap: 4px;
		margin-bottom: 5px;
	}
	.md-pack-who {
		display: grid;
		place-items: center;
		width: 15px;
		height: 15px;
		border-radius: 3px;
		font-size: 0.6rem;
		font-weight: 700;
		color: #6b6455;
		background: rgba(0, 0, 0, 0.06);
	}
	.md-pk {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 4px 0;
		font-size: 0.78rem;
		border-top: 1px dotted #d8cfb8;
	}
	.md-pos {
		flex: 0 0 16px;
		color: #8a8172;
	}
	.md-cat {
		flex: 0 0 auto;
		display: flex;
		align-items: center;
		gap: 3px;
		color: #6b6455;
		font-size: 0.68rem;
	}
	.md-ans {
		flex: 1 1 auto;
		min-width: 0;
		color: #8a5a12;
		font-weight: 700;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.md-marks {
		display: flex;
		flex: 0 0 auto;
		gap: 4px;
	}
	.md-mark {
		display: grid;
		place-items: center;
		width: 15px;
		height: 15px;
		border-radius: 3px;
		color: #b0a894;
		background: rgba(0, 0, 0, 0.05);
	}
	.md-mark.got {
		color: #157a3a;
		background: rgba(21, 122, 58, 0.14);
	}
</style>
