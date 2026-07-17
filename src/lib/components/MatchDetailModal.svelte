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
	$: winner = parts.find((/** @type {any} */ p) => Number(p.rank) === 1);
	$: iWon = me && Number(me.rank) === 1;
	// A 1v1 tie: both participants share rank 1 (equal kept score AND equal time).
	$: isTie = field === 2 && !!me && !!opp && Number(me.rank) === 1 && Number(opp.rank) === 1;
	// 1v1 speed gap — the decider when kept scores are equal.
	$: haveTimes = field === 2 && me?.elapsed_seconds != null && opp?.elapsed_seconds != null;
	$: speedGap = haveTimes ? Math.abs(me.elapsed_seconds - opp.elapsed_seconds) : null;
	$: sameScore = !!me && !!opp && Number(me.score) === Number(opp.score);

	$: verdictKind = noSolve || isTie ? 'tie' : iWon ? 'win' : 'loss';
	$: verdictHead = noSolve ? 'NO CONTEST' : isTie ? 'TIE' : iWon ? 'VICTORY' : 'DEFEAT';

	// The one-line reason: solve count first (the real driver), then kept score,
	// then speed — never leads with "spent" (inverted: lower used to read as better).
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
			return `@${winner.name || 'player'} solved ${winner.solved} — you placed ${ordinal(Number(me.rank))} with ${me.solved}.`;
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
					· {field >= 3 ? 'podium 3·2·1' : 'winner-take-all'}
					{#if !wagered}· friendly{/if}
					{#if m?.status !== 'settled'}· <em>in progress</em>{/if}
					{#if noSolve && wagered}· buy-in refunded{/if}
				</p>

				{#if settled && me}
					<div class="md-verdict {verdictKind}">
						<div class="md-verdict-head">{verdictHead}</div>
						{#if reason}<div class="md-verdict-reason">{reason}</div>{/if}
					</div>
				{/if}

				{#if wagered && settled && !noSolve && me?.net != null}
					<p class="md-pot {Number(me.net) >= 0 ? 'win' : 'loss'}">
						<span class="md-pot-amt">{money(me.net)}</span>
						<span class="md-pot-lbl"
							>{Number(me.net) >= 0 ? 'Pot won' : 'Buy-in lost'}{#if Number(me.net) >= 0 && mult(me.multiple_x100)}
								· {mult(me.multiple_x100)}{/if}</span
						>
					</p>
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
								{#if p.state === 'done'}Kept {dollars(p.score)} · solved {p.solved ?? 0}/{m?.pack_size}{#if p.elapsed_seconds != null}
										· {fmtSecs(p.elapsed_seconds)}{/if}
								{:else}{p.state}{/if}
							</span>
						</div>
					{/each}
				</div>

				{#if detail.pack?.length}
					<div class="md-pack">
						<div class="md-pack-h">
							<span>Puzzles</span>
							{#if hasMarks}
								<span class="md-pack-legend">
									{#each parts as p}
										<span
											class="md-pack-who"
											title={p.is_me ? 'You' : '@' + (p.name || 'player')}
											>{p.is_me ? 'Y' : (p.name || '?').charAt(0).toUpperCase()}</span
										>
									{/each}
								</span>
							{/if}
						</div>
						{#each detail.pack as pk}
							<div class="md-pk">
								<span class="md-pos">{pk.position}</span>
								<span class="md-cat"
									><CategoryIcon category={pk.category} size={13} /> {catLabel(pk.category)}</span
								>
								<span class="md-ans"
									>{#if pk.phrase}“{pk.phrase}”{:else}<Icon name="lock" size={13} /> hidden until settled{/if}</span
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
												><Icon name={got ? 'check' : 'close'} size={11} /></span
											>
										{/each}
									</span>
								{/if}
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

	.md-verdict {
		text-align: center;
		padding: 16px 12px;
		margin: 0 0 12px;
		border-radius: var(--r-md);
		border: 1px solid var(--border);
		background: var(--surface);
	}
	.md-verdict.win {
		background: rgba(126, 224, 168, 0.1);
		border-color: rgba(126, 224, 168, 0.3);
	}
	.md-verdict.loss {
		background: rgba(251, 113, 133, 0.08);
		border-color: rgba(251, 113, 133, 0.25);
	}
	.md-verdict.tie {
		background: var(--surface);
		border-color: var(--border-strong);
	}
	.md-verdict-head {
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		font-size: 1.7rem;
		letter-spacing: 0.04em;
	}
	.md-verdict.win .md-verdict-head {
		color: #7ee0a8;
	}
	.md-verdict.loss .md-verdict-head {
		color: #fb7185;
	}
	.md-verdict.tie .md-verdict-head {
		color: var(--text);
	}
	.md-verdict-reason {
		margin-top: 6px;
		color: var(--text-muted);
		font-size: 0.86rem;
	}

	.md-pot {
		display: flex;
		align-items: baseline;
		justify-content: center;
		gap: 8px;
		margin: 0 0 16px;
	}
	.md-pot-amt {
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		font-size: 1.1rem;
	}
	.md-pot.win .md-pot-amt {
		color: #7ee0a8;
	}
	.md-pot.loss .md-pot-amt {
		color: #fb7185;
	}
	.md-pot-lbl {
		color: var(--text-faint);
		font-size: 0.8rem;
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
		display: flex;
		align-items: center;
		justify-content: space-between;
		color: var(--text-faint);
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		margin-bottom: 8px;
	}
	.md-pack-legend {
		display: flex;
		gap: 4px;
		text-transform: none;
		letter-spacing: normal;
	}
	.md-pack-who {
		display: flex;
		align-items: center;
		justify-content: center;
		width: 16px;
		height: 16px;
		border-radius: 4px;
		font-size: 0.62rem;
		font-weight: 700;
		color: var(--text-faint);
		background: rgba(255, 255, 255, 0.04);
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
		flex: 1 1 auto;
		min-width: 0;
		color: var(--gold);
		font-weight: 600;
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
		display: flex;
		align-items: center;
		justify-content: center;
		width: 16px;
		height: 16px;
		border-radius: 4px;
		color: var(--text-faint);
		background: rgba(255, 255, 255, 0.04);
	}
	.md-mark.got {
		color: #7ee0a8;
		background: rgba(126, 224, 168, 0.12);
	}
</style>
