<script>
	// 💳 Phase 2 Account card — a debit-card view of the player's identity + balance.
	// Reused on the main menu, the Bank hub sheet, and /profile.
	/** @type {any} */ export let holder = '';
	/** @type {any} */ export let account = '';
	/** @type {any} */ export let member = null;
	/** @type {any} */ export let balance = 0;

	$: last4 = (account ?? '').toString().slice(-4) || '••••';
	$: holderName = (holder ? String(holder) : 'Wordbanker').toUpperCase();
	$: memberLabel = member != null ? '#' + String(member).padStart(4, '0') : '—';
	$: amount = Math.round(Number(balance) || 0).toLocaleString();
</script>

<div class="acct-card">
	<div class="ac-sheen"></div>
	<div class="ac-inner">
		<div class="ac-top">
			<span class="ac-brand"><span class="ac-gold">WORD</span>BANK</span>
			<span class="ac-chip" aria-hidden="true"></span>
		</div>
		<div class="ac-bal">
			<div class="ac-cap">Available Balance</div>
			<div class="ac-amt">${amount}</div>
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
		width: 100%;
		max-width: 360px;
		margin: 0 auto;
		aspect-ratio: 1.586;
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
		height: 100%;
		justify-content: space-between;
	}
	.ac-top {
		display: flex;
		justify-content: space-between;
		align-items: center;
	}
	.ac-brand {
		font-family: var(--font-display, sans-serif);
		font-weight: 800;
		letter-spacing: 0.14em;
		font-size: 0.82rem;
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
