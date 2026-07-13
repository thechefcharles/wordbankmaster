<script>
	// 💳 Phase 2 Account card — a debit-card view of the player's identity + balance.
	// Reused on the main menu, the Bank hub sheet, and /profile.
	/** @type {any} */ export let holder = '';
	/** @type {any} */ export let account = '';
	/** @type {any} */ export let member = null;
	/** @type {any} */ export let balance = 0;
	import { cardName } from '$lib/creditTiers.js';
	/** Credit tier — skins the card (Excellent = black card; Poor/Bad = distressed). */
	/** @type {string} */ export let tier = 'Good';
	/** Outstanding loan — shows a small "Loan −$X" debit line under the balance. 0 = hidden. */
	/** @type {any} */ export let loan = 0;

	$: loanAmt = Math.round(Number(loan) || 0);
	$: cardTitle = cardName(tier);
	$: tierClass =
		tier === 'Excellent'
			? 'ac-excellent'
			: tier === 'Poor'
				? 'ac-poor'
				: tier === 'Bad'
					? 'ac-bad'
					: '';
	$: last4 = (account ?? '').toString().slice(-4) || '••••';
	$: holderName = (holder ? String(holder) : 'Wordbanker').toUpperCase();
	$: memberLabel = member != null ? '#' + String(member).padStart(4, '0') : '—';
	$: amount = Math.round(Number(balance) || 0).toLocaleString();
	// True net worth = Available Balance − loan owed. Can go negative when deep in debt.
	$: netWorthAmt = (Math.round(Number(balance) || 0) - loanAmt) | 0;
	$: netWorthLabel = (netWorthAmt < 0 ? '−$' : '$') + Math.abs(netWorthAmt).toLocaleString();
</script>

<div class="acct-card {tierClass}">
	<div class="ac-sheen"></div>
	<div class="ac-inner">
		<div class="ac-top">
			<span class="ac-brand">
				<img class="ac-coin" src="/logo-coin.png" alt="" width="22" height="22" />
				<span><span class="ac-gold">WORD</span>BANK</span>
				<span class="ac-cardname">{cardTitle}</span>
			</span>
			<span class="ac-chip" aria-hidden="true"></span>
		</div>
		<div class="ac-bal">
			<div class="ac-cap">Available Balance</div>
			<div class="ac-amt">${amount}</div>
			{#if loanAmt > 0}
				<div class="ac-loan">Loan −${loanAmt.toLocaleString()}</div>
				<div class="ac-net" class:neg={netWorthAmt < 0}>
					<span class="ac-net-cap">Net worth</span>{netWorthLabel}
				</div>
			{/if}
		</div>
		<div class="ac-num">•••• •••• •••• {last4}</div>
		<div class="ac-foot">
			<div>
				<div class="ac-cap sm">Account Holder</div>
				<div class="ac-name">{holderName}</div>
			</div>
			<div class="ac-mem">
				<div class="ac-cap sm">Member</div>
				<div class="ac-mno">{memberLabel}</div>
			</div>
		</div>
	</div>
</div>

<style>
	.acct-card {
		position: relative;
		display: flex;
		flex-direction: column;
		width: 100%;
		max-width: 360px;
		margin: 0 auto;
		/* Credit-card proportion via a min-height floor (not a fixed aspect-ratio) so the
		   card can grow taller when the text is scaled up (large-text accessibility) and
		   the holder name never clips. */
		min-height: 212px;
		border-radius: 18px;
		padding: 20px 22px;
		overflow: hidden;
		text-align: left;
		color: #f4ecdf;
		background: linear-gradient(135deg, #1c1a2e 0%, #2a2140 45%, #3a2a1a 100%);
		border: 1px solid rgba(251, 191, 36, 0.25);
		box-shadow:
			0 18px 44px rgba(0, 0, 0, 0.55),
			inset 0 1px 0 rgba(255, 255, 255, 0.08);
	}
	/* 💳 Excellent — matte "black card" with a brighter gold edge. */
	.acct-card.ac-excellent {
		background: linear-gradient(135deg, #08080b 0%, #1a1a20 45%, #0c0c10 100%);
		border-color: rgba(251, 191, 36, 0.6);
		box-shadow:
			0 18px 44px rgba(0, 0, 0, 0.7),
			inset 0 1px 0 rgba(255, 255, 255, 0.12),
			0 0 0 1px rgba(251, 191, 36, 0.18);
	}
	/* Poor / Bad — distressed, red-tinted. */
	.acct-card.ac-poor {
		background: linear-gradient(135deg, #241c1c 0%, #2a2226 45%, #1c1616 100%);
		border-color: rgba(248, 113, 113, 0.42);
	}
	.acct-card.ac-bad {
		background: linear-gradient(135deg, #251818 0%, #2a1b1b 45%, #190f0f 100%);
		border-color: rgba(248, 113, 113, 0.62);
		filter: saturate(0.92);
	}
	.ac-cardname {
		font-family: var(--font-display, sans-serif);
		font-size: 0.56rem;
		font-weight: 800;
		letter-spacing: 0.22em;
		text-transform: uppercase;
		color: rgba(251, 191, 36, 0.85);
		padding-left: 7px;
		margin-left: 1px;
		border-left: 1px solid rgba(251, 191, 36, 0.35);
		align-self: center;
	}
	.ac-sheen {
		position: absolute;
		inset: 0;
		background: radial-gradient(120% 80% at 85% -10%, rgba(251, 191, 36, 0.22), transparent 55%);
		pointer-events: none;
	}
	.ac-inner {
		position: relative;
		display: flex;
		flex-direction: column;
		flex: 1 1 auto;
		gap: 6px;
		justify-content: space-between;
	}
	.ac-top {
		display: flex;
		justify-content: space-between;
		align-items: center;
	}
	.ac-brand {
		display: flex;
		align-items: center;
		gap: 7px;
		font-family: var(--font-display, sans-serif);
		font-weight: 800;
		letter-spacing: 0.14em;
		font-size: 0.82rem;
	}
	.ac-coin {
		width: 22px;
		height: 22px;
		object-fit: contain;
		filter: drop-shadow(0 1px 2px rgba(0, 0, 0, 0.4));
	}
	.ac-gold {
		color: #fbbf24;
	}
	.ac-chip {
		width: 34px;
		height: 26px;
		border-radius: 6px;
		background: linear-gradient(135deg, #f7d774, #c99a2e);
		box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.2);
		background-image:
			linear-gradient(#0000 45%, rgba(0, 0, 0, 0.25) 46% 54%, #0000 55%),
			linear-gradient(90deg, #0000 45%, rgba(0, 0, 0, 0.25) 46% 54%, #0000 55%),
			linear-gradient(135deg, #f7d774, #c99a2e);
	}
	.ac-cap {
		font-size: 0.58rem;
		letter-spacing: 0.22em;
		text-transform: uppercase;
		color: #b8ac97;
	}
	.ac-cap.sm {
		font-size: 0.52rem;
		letter-spacing: 0.18em;
	}
	.ac-amt {
		font-family: var(--font-display, sans-serif);
		font-size: 2.1rem;
		font-weight: 800;
		line-height: 1.05;
		letter-spacing: 0.01em;
		font-variant-numeric: tabular-nums;
	}
	/* 🔴 Outstanding loan — a small debit line under the balance. */
	.ac-loan {
		margin-top: 3px;
		font-family: var(--font-display, sans-serif);
		font-weight: 700;
		font-size: 0.82rem;
		color: #fb7185;
		font-variant-numeric: tabular-nums;
	}
	/* True net worth (Available − loan) — the real position, one line under the loan. */
	.ac-net {
		margin-top: 2px;
		font-family: var(--font-display, sans-serif);
		font-weight: 700;
		font-size: 0.82rem;
		color: #7ee0a8;
		font-variant-numeric: tabular-nums;
	}
	.ac-net.neg {
		color: #fb7185;
	}
	.ac-net-cap {
		font-weight: 600;
		opacity: 0.7;
		margin-right: 6px;
		text-transform: uppercase;
		font-size: 0.68rem;
		letter-spacing: 0.05em;
	}
	.ac-num {
		font-family: 'Courier New', 'Courier', ui-monospace, monospace;
		font-size: 1.02rem;
		letter-spacing: 0.16em;
	}
	.ac-foot {
		display: flex;
		justify-content: space-between;
		align-items: flex-end;
	}
	.ac-name {
		font-family: var(--font-display, sans-serif);
		font-weight: 700;
		letter-spacing: 0.08em;
		font-size: 0.9rem;
	}
	.ac-mem {
		text-align: right;
	}
	.ac-mno {
		font-family: var(--font-display, sans-serif);
		font-weight: 700;
		font-size: 0.9rem;
		color: #fbbf24;
		font-variant-numeric: tabular-nums;
	}
</style>
