<script>
	import { createEventDispatcher } from 'svelte';
	import { takeLoan, repayLoan } from '$lib/stores/statsStore.js';
	import { requirePin } from '$lib/pinConfirm.js';
	import { track } from '$lib/analytics.js';
	import { fx } from '$lib/sound.js';
	import Icon from '$lib/components/Icon.svelte';

	/** The get_bank payload (loan detail added in loans-v3)
	 * @type {{ bank:number, net_worth:number, loan:number, loan_cap:number, in_the_red:boolean,
	 *   loan_principal?:number, loan_rate_bp?:number, loan_days?:number, loan_owed_tomorrow?:number,
	 *   credit_score?:number, credit_tier?:string, credit_delta?:number }|null} */
	export let bank = null;
	/** Open the borrow panel by default (used on the dedicated /loans page). */
	export let expanded = false;

	const dispatch = createEventDispatcher();

	// 🦈 Loan Shark — progressive daily interest (rate scales with amount vs cap; mirrors _loan_daily_rate_bp)
	const MIN_BORROW = 50;
	let borrowAmt = 100; // $ to borrow (dial)
	let repayAmt = 0; // $ to repay (dial)
	let loanBusy = '';
	let loanMsg = '';
	$: loanCap = bank?.loan_cap ?? 0;
	$: owed = bank?.loan ?? 0;
	// 💳 Credit tier sets your cap + a rate adjustment (mirrors _credit_effective_cap / _credit_rate_adjust).
	$: creditTier = bank?.credit_tier ?? 'Good';
	$: creditScore = bank?.credit_score ?? 650;
	/** @param {string} tier */
	function creditAdjBp(tier) {
		return tier === 'Excellent' ? -300 : tier === 'Fair' ? 300 : tier === 'Poor' ? 600 : 0;
	}
	/** @param {number} amt @param {number} cap */
	function rateBpFor(amt, cap) {
		if (cap <= 0) return 1500;
		const p = amt / cap;
		return p <= 0.25 ? 500 : p <= 0.5 ? 800 : p <= 0.75 ? 1200 : 1500;
	}
	$: rateBp = Math.max(
		200,
		Math.min(2500, rateBpFor(borrowAmt, loanCap) + creditAdjBp(creditTier))
	);
	$: ratePct = rateBp / 100; // %/day
	// Upfront charge at borrow (mirrors take_loan): GREATEST(one day's interest, 10% floor).
	$: upfront = Math.max(Math.round((borrowAmt * rateBp) / 10000), Math.round(borrowAmt * 0.1));
	$: owedNow = borrowAmt + upfront;
	$: activeRatePct = (bank?.loan_rate_bp ?? 0) / 100;
	$: owedTomorrow = bank?.loan_owed_tomorrow ?? owed;
	$: loanDays = bank?.loan_days ?? 0;
	$: if (borrowAmt > loanCap) borrowAmt = loanCap;
	$: if (borrowAmt < MIN_BORROW && loanCap >= MIN_BORROW) borrowAmt = MIN_BORROW;
	$: maxRepay = Math.max(0, Math.min(owed, bank?.bank ?? 0));
	// Can you fully clear the loan right now? (Bank covers the whole owed amount.)
	$: canClear = owed > 0 && (bank?.bank ?? 0) >= owed;
	$: if (repayAmt > maxRepay) repayAmt = maxRepay;
	// seed the repay dial when we (re)load into a debt state
	$: if (bank) repayAmt = Math.min(repayAmt || maxRepay, maxRepay);

	const fmt = (/** @type {number} */ n) => '$' + Math.round(n ?? 0).toLocaleString();
	const delay = (/** @type {number} */ ms) => new Promise((r) => setTimeout(r, ms));

	// 🏦 Loan application flow: a short underwriting animation over the (deterministic)
	// server decision — dramatizes the real credit/limit/amount checks, then approves/declines.
	let applyState = ''; // '' | 'reviewing' | 'approved' | 'declined'
	let applyStep = 0; // how many check lines have appeared
	/** @type {any} */ let applyResult = null;
	$: declineReason =
		applyResult?.reason === 'credit_locked'
			? 'Your credit is too low to borrow. Raise it to Poor (400+) to reapply.'
			: applyResult?.reason === 'over_cap'
				? `That exceeds your ${fmt(applyResult?.cap ?? loanCap)} limit.`
				: applyResult?.reason === 'active_loan'
					? 'You already have an active loan to pay off first.'
					: 'We couldn’t approve this application right now.';

	async function borrow() {
		if (loanBusy || borrowAmt < MIN_BORROW) return;
		try {
			await requirePin(`Borrow $${borrowAmt.toLocaleString()}`, [
				{ label: 'You receive', value: '$' + borrowAmt.toLocaleString() },
				{ label: 'You owe', value: '$' + owedNow.toLocaleString() },
				{ label: 'Then', value: ratePct + '%/day, compounding' }
			]);
		} catch {
			return;
		}
		loanBusy = 'borrow';
		loanMsg = '';
		applyResult = null;
		applyStep = 0;
		applyState = 'reviewing';
		const timers = [
			setTimeout(() => (applyStep = 1), 450),
			setTimeout(() => (applyStep = 2), 950),
			setTimeout(() => (applyStep = 3), 1450)
		];
		// Run the real decision, but hold the verdict until the ~2s review has played.
		const [res] = await Promise.all([takeLoan(borrowAmt), delay(2000)]);
		timers.forEach(clearTimeout);
		applyStep = 3;
		applyResult = res;
		loanBusy = '';
		if (res?.ok) {
			applyState = 'approved';
			fx('win');
			track('take_loan', { amount: borrowAmt, owed: res.owed });
		} else {
			applyState = 'declined';
			fx('tap');
		}
	}
	function closeApply() {
		const wasApproved = applyState === 'approved';
		applyState = '';
		applyStep = 0;
		if (wasApproved) dispatch('changed'); // reload into the debt/repay state
	}

	async function repay(/** @type {number|null} */ amt) {
		if (loanBusy) return;
		const pay = amt ?? maxRepay;
		if (pay <= 0) return;
		// 🔐 Money-out → PIN confirm (same gate as store/avatar buys).
		try {
			await requirePin(pay >= owed ? `Pay off ${fmt(pay)}` : `Repay ${fmt(pay)}`, [
				{ label: 'Repay', value: fmt(pay) },
				{ label: 'Owed after', value: fmt(Math.max(0, owed - pay)) }
			]);
		} catch {
			return; // cancelled at the pad
		}
		loanBusy = 'repay';
		loanMsg = '';
		const res = await repayLoan(amt);
		loanBusy = '';
		if (res?.ok) {
			fx('tap');
			track('repay_loan', { amount: res.paid, cleared: res.cleared });
			dispatch('changed');
		} else {
			loanMsg =
				res?.reason === 'insufficient' ? 'Not enough Cash to repay.' : 'Could not repay right now.';
		}
	}
</script>

{#if bank?.in_the_red}
	<!-- In debt: repay panel + the teeth -->
	<div class="loan-card debt">
		<div class="loan-head">
			<span class="loan-title">You owe</span>
			<span class="loan-owed">{fmt(owed)}</span>
		</div>
		<div class="loan-facts">
			<span><Icon name="growth" size={13} /> {activeRatePct}%/day</span>
			<span><Icon name="timer" size={13} /> {loanDays}d out</span>
			<span>→ {fmt(owedTomorrow)} tomorrow</span>
		</div>
		<p class="loan-note">
			The Store is locked and half of every payout auto-repays this. Net worth
			<b class="neg">{fmt(bank.net_worth)}</b>.
		</p>
		{#if maxRepay > 0}
			<div class="loan-dial">
				<button
					class="loan-step"
					on:click={() => (repayAmt = Math.max(0, repayAmt - 50))}
					aria-label="Less"
					disabled={repayAmt <= 0}>−</button
				>
				<div class="loan-amt">
					<span class="loan-usd">{fmt(repayAmt)}</span><span class="loan-sub"
						>of {fmt(owed)} owed</span
					>
				</div>
				<button
					class="loan-step"
					on:click={() => (repayAmt = Math.min(maxRepay, repayAmt + 50))}
					aria-label="More"
					disabled={repayAmt >= maxRepay}>+</button
				>
			</div>
			<input
				class="loan-slider"
				type="range"
				min="0"
				max={maxRepay}
				step="10"
				bind:value={repayAmt}
			/>
			<div class="loan-actions">
				<!-- One slider-driven action: reads "Pay off" when the slider clears the whole
             balance, "Repay $X" for a partial payment. -->
				<button
					class="loan-btn pay"
					disabled={!!loanBusy || repayAmt <= 0}
					on:click={() => repay(repayAmt)}
					>{repayAmt >= owed ? `Pay off (${fmt(repayAmt)})` : `Repay ${fmt(repayAmt)}`}</button
				>
			</div>
			{#if !canClear}
				<p class="loan-note" style="margin-bottom:0">
					You don't have enough to clear it — paying all still leaves <b class="neg"
						>{fmt(owed - maxRepay)}</b
					> owed. Earn more Cash (play the Daily) to finish it off.
				</p>
			{/if}
		{:else}
			<p class="loan-note">Earn some Cash (play the Daily) then come back to repay.</p>
		{/if}
		{#if loanMsg}<p class="msg">{loanMsg}</p>{/if}
	</div>
{:else if loanCap > 0}
	<!-- No debt: borrow panel -->
	<details class="loan-card" bind:open={expanded}>
		<summary class="loan-summary">Apply for a Loan <span class="loan-cv">▾</span></summary>
		<p class="loan-tier">
			Credit <b>{creditTier}</b> ({creditScore}) — sets your ${loanCap.toLocaleString()} limit{#if creditAdjBp(creditTier) !== 0}
				and a {creditAdjBp(creditTier) > 0 ? '+' : ''}{creditAdjBp(creditTier) / 100}%/day rate{/if}.
		</p>
		<div class="loan-dial">
			<button
				class="loan-step"
				on:click={() => (borrowAmt = Math.max(MIN_BORROW, borrowAmt - 50))}
				aria-label="Less"
				disabled={borrowAmt <= MIN_BORROW}>−</button
			>
			<div class="loan-amt">
				<span class="loan-usd">{fmt(borrowAmt)}</span><span class="loan-sub"
					>owe {fmt(owedNow)} · {ratePct}%/day</span
				>
			</div>
			<button
				class="loan-step"
				on:click={() => (borrowAmt = Math.min(loanCap, borrowAmt + 50))}
				aria-label="More"
				disabled={borrowAmt >= loanCap}>+</button
			>
		</div>
		<input
			class="loan-slider"
			type="range"
			min={MIN_BORROW}
			max={loanCap}
			step="10"
			bind:value={borrowAmt}
		/>
		<button
			class="loan-btn borrow"
			disabled={!!loanBusy || borrowAmt < MIN_BORROW}
			on:click={borrow}>Borrow {fmt(borrowAmt)}</button
		>
		{#if loanMsg}<p class="msg">{loanMsg}</p>{/if}
	</details>
{:else}
	<!-- Bad tier: borrowing locked -->
	<div class="loan-card locked">
		<div class="loan-locked-h">Borrowing locked</div>
		<p class="loan-note" style="margin:0">
			Your credit is <b class="neg">{creditTier}</b> ({creditScore}). You can't borrow right now —
			repay on time, stay out of the red, and keep utilization low to climb back to <b>Poor</b>
			(400+) and unlock loans.
		</p>
	</div>
{/if}

{#if applyState}
	<!-- 🏦 Loan application review overlay -->
	<div class="la-overlay" role="dialog" aria-modal="true" aria-label="Loan application">
		<div class="la-card">
			{#if applyState === 'reviewing'}
				<div class="la-spinner" aria-hidden="true"></div>
				<div class="la-title">Reviewing your application…</div>
				<ul class="la-checks">
					{#if applyStep >= 1}<li>
							<Icon name="check" size={13} /> Credit — {creditScore}
							{creditTier}
						</li>{/if}
					{#if applyStep >= 2}<li>
							<Icon name="check" size={13} /> Limit — up to {fmt(loanCap)}
						</li>{/if}
					{#if applyStep >= 3}<li>
							<Icon name="check" size={13} /> Amount — {fmt(borrowAmt)}
						</li>{/if}
				</ul>
			{:else if applyState === 'approved'}
				<div class="la-verdict ok"><Icon name="check" size={20} /> Approved</div>
				<div class="la-sub">
					{fmt(applyResult?.borrowed ?? borrowAmt)} deposited to your account.
				</div>
				<div class="la-terms">
					You owe {fmt(applyResult?.owed ?? owedNow)} · {(applyResult?.rate_bp ?? rateBp) /
						100}%/day
				</div>
				<button class="loan-btn borrow la-btn" on:click={closeApply}>Done</button>
			{:else}
				<div class="la-verdict no"><Icon name="close" size={20} /> Not Approved</div>
				<div class="la-sub">{declineReason}</div>
				<button class="loan-btn ghost la-btn" on:click={closeApply}>Close</button>
			{/if}
		</div>
	</div>
{/if}

<style>
	/* 🏦 Loan application overlay */
	.la-overlay {
		position: fixed;
		inset: 0;
		z-index: 4000;
		display: grid;
		place-items: center;
		padding: 24px;
		background: rgba(4, 8, 14, 0.72);
		backdrop-filter: blur(6px);
	}
	.la-card {
		width: 100%;
		max-width: 320px;
		padding: 26px 22px;
		border-radius: 18px;
		text-align: center;
		background: var(--surface-strong, rgba(20, 26, 38, 0.96));
		border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.16));
		box-shadow: 0 20px 50px rgba(0, 0, 0, 0.5);
	}
	.la-spinner {
		width: 34px;
		height: 34px;
		margin: 0 auto 14px;
		border-radius: 50%;
		border: 3px solid var(--border, rgba(255, 255, 255, 0.14));
		border-top-color: var(--brand-2, #fde047);
		animation: la-spin 0.8s linear infinite;
	}
	@keyframes la-spin {
		to {
			transform: rotate(360deg);
		}
	}
	.la-title {
		font-family: var(--font-display, sans-serif);
		font-weight: 700;
		font-size: 1rem;
	}
	.la-checks {
		list-style: none;
		margin: 12px 0 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 7px;
		text-align: left;
	}
	.la-checks li {
		font-size: 0.85rem;
		color: var(--text);
		animation: la-in 0.25s ease;
	}
	@keyframes la-in {
		from {
			opacity: 0;
			transform: translateY(4px);
		}
	}
	.la-verdict {
		font-family: var(--font-display, sans-serif);
		font-weight: 800;
		font-size: 1.7rem;
	}
	.la-verdict.ok {
		color: #34d399;
	}
	.la-verdict.no {
		color: #fb7185;
	}
	.la-sub {
		margin-top: 8px;
		color: var(--text-muted);
		font-size: 0.9rem;
		line-height: 1.4;
	}
	.la-terms {
		margin-top: 4px;
		font-size: 0.78rem;
		color: var(--text-faint);
	}
	.la-btn {
		margin-top: 18px;
		width: 100%;
	}
	@media (prefers-reduced-motion: reduce) {
		.la-spinner {
			animation: none;
		}
	}
	.loan-card {
		border-radius: 16px;
		padding: 14px 16px;
		margin: 0 0 14px;
		border: 1px solid var(--border);
		background: var(--surface);
	}
	.loan-card.debt {
		border-color: rgba(248, 113, 113, 0.5);
		background: linear-gradient(135deg, rgba(248, 113, 113, 0.12), rgba(248, 113, 113, 0.03));
	}
	.loan-card.locked {
		border-color: rgba(248, 113, 113, 0.45);
		background: linear-gradient(135deg, rgba(248, 113, 113, 0.1), rgba(248, 113, 113, 0.02));
	}
	.loan-locked-h {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1rem;
		margin-bottom: 6px;
	}
	.loan-tier {
		margin: 0 0 10px;
		font-size: 0.76rem;
		color: var(--text-muted);
	}
	.loan-tier b {
		color: var(--brand-2, #fde047);
	}
	.loan-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: 10px;
	}
	.loan-title {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1rem;
	}
	.loan-owed {
		font-family: var(--font-display, sans-serif);
		font-weight: 800;
		font-size: 1.5rem;
		font-variant-numeric: tabular-nums;
		color: #fb7185;
	}
	.loan-summary {
		position: relative;
		cursor: pointer;
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.95rem;
		list-style: none;
		display: flex;
		align-items: center;
		justify-content: center;
		text-align: center;
	}
	.loan-summary::-webkit-details-marker {
		display: none;
	}
	.loan-cv {
		position: absolute;
		right: 0;
		color: var(--text-faint);
		font-size: 0.8rem;
	}
	.loan-note {
		font-size: 0.78rem;
		color: var(--text-muted);
		margin: 8px 0;
		line-height: 1.4;
	}
	.loan-note .neg {
		color: #fb7185;
	}
	.loan-facts {
		display: flex;
		flex-wrap: wrap;
		gap: 6px 14px;
		margin: 8px 0 2px;
		font-family: var(--font-display);
		font-size: 0.76rem;
		font-weight: 700;
		color: #fca5a5;
	}
	.loan-dial {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 12px;
		width: 100%;
		max-width: 320px;
		margin: 4px auto 0;
	}
	.loan-step {
		width: 44px;
		height: 44px;
		flex: none;
		border-radius: 12px;
		cursor: pointer;
		font-size: 1.5rem;
		font-weight: 800;
		background: var(--surface);
		border: 1px solid var(--border);
		color: var(--text);
		display: grid;
		place-items: center;
	}
	.loan-step:disabled {
		opacity: 0.3;
		cursor: default;
	}
	.loan-amt {
		flex: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 1px;
	}
	.loan-usd {
		font-family: var(--font-display, sans-serif);
		font-weight: 800;
		color: var(--brand-2);
		font-size: 1.7rem;
		line-height: 1;
		font-variant-numeric: tabular-nums;
	}
	.loan-sub {
		font-size: 0.68rem;
		color: var(--text-faint);
	}
	.loan-slider {
		width: 100%;
		max-width: 320px;
		display: block;
		margin: 12px auto;
		accent-color: #fb7185;
	}
	.loan-actions {
		display: flex;
		gap: 8px;
	}
	.loan-btn {
		flex: 1;
		padding: 0.8rem;
		border: none;
		border-radius: 12px;
		cursor: pointer;
		font-weight: 800;
		font-size: 0.92rem;
	}
	.loan-btn.borrow {
		width: 100%;
		color: #2a1005;
		background: linear-gradient(135deg, #fbbf24, #f59e0b);
	}
	.loan-btn.pay {
		color: #06281d;
		background: linear-gradient(135deg, #6ee7b7, #34d399);
	}
	.loan-btn.ghost {
		background: var(--surface);
		border: 1px solid var(--border);
		color: var(--text);
	}
	.loan-btn:disabled {
		opacity: 0.45;
		cursor: default;
	}
	.msg {
		font-size: 0.8rem;
		color: #fb7185;
		margin: 8px 0 0;
		text-align: center;
	}
</style>
