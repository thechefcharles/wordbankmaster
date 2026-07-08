<script>
	import { createEventDispatcher } from 'svelte';
	import { takeLoan, repayLoan } from '$lib/stores/statsStore.js';
	import { requirePin } from '$lib/pinConfirm.js';
	import { track } from '$lib/analytics.js';
	import { fx } from '$lib/sound.js';

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
	$: ratePct = rateBp / 100; // 2 / 4 / 6 / 8 (%/day)
	$: proj7 = Math.min(
		Math.round(borrowAmt * Math.pow(1 + rateBp / 10000, 7)),
		Math.round(borrowAmt * 2.5)
	);
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

	async function borrow() {
		if (loanBusy || borrowAmt < MIN_BORROW) return;
		try {
			await requirePin(`Borrow $${borrowAmt.toLocaleString()} from the Shark`, [
				{ label: 'You receive', value: '$' + borrowAmt.toLocaleString() },
				{ label: 'Interest', value: ratePct + '%/day, compounding' },
				{ label: '~Owe in a week', value: '$' + proj7.toLocaleString() }
			]);
		} catch {
			return;
		}
		loanBusy = 'borrow';
		loanMsg = '';
		const res = await takeLoan(borrowAmt);
		loanBusy = '';
		if (res?.ok) {
			fx('win');
			track('take_loan', { amount: borrowAmt, owed: res.owed });
			dispatch('changed');
		} else {
			loanMsg =
				res?.reason === 'active_loan'
					? 'Pay off your current loan first.'
					: res?.reason === 'credit_locked'
						? 'Borrowing is locked — raise your credit score to borrow again.'
						: res?.reason === 'over_cap'
							? `Over your $${(res.cap ?? loanCap).toLocaleString()} limit.`
							: 'Could not borrow right now.';
		}
	}

	async function repay(/** @type {number|null} */ amt) {
		if (loanBusy) return;
		const pay = amt ?? maxRepay;
		if (pay <= 0) return;
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
			<span class="loan-title">🦈 You owe the Shark</span>
			<span class="loan-owed">{fmt(owed)}</span>
		</div>
		<div class="loan-facts">
			<span>📈 {activeRatePct}%/day</span>
			<span>⏳ {loanDays}d out</span>
			<span>→ {fmt(owedTomorrow)} tomorrow</span>
		</div>
		<p class="loan-note">
			Interest compounds daily. The Store is locked and half of every payout auto-pays your debt
			until it's clear. Your net worth is <b class="neg">{fmt(bank.net_worth)}</b>.
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
				<button
					class="loan-btn ghost"
					disabled={!!loanBusy || repayAmt <= 0}
					on:click={() => repay(repayAmt)}>Repay {fmt(repayAmt)}</button
				>
				{#if canClear}
					<button class="loan-btn pay" disabled={!!loanBusy} on:click={() => repay(owed)}
						>Pay off ({fmt(owed)})</button
					>
				{:else}
					<button class="loan-btn pay" disabled={!!loanBusy} on:click={() => repay(maxRepay)}
						>Repay all ({fmt(maxRepay)})</button
					>
				{/if}
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
	<details class="loan-card" open={expanded}>
		<summary class="loan-summary">🦈 Apply for a Loan <span class="loan-cv">▾</span></summary>
		<p class="loan-note">
			Interest compounds daily — the more you take, the higher the rate. One loan at a time; while
			you owe, the Store locks and half of every payout auto-pays it down.
		</p>
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
					>{ratePct}%/day · ~{fmt(proj7)} in a week</span
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
			on:click={borrow}>🦈 Borrow {fmt(borrowAmt)}</button
		>
		{#if loanMsg}<p class="msg">{loanMsg}</p>{/if}
	</details>
{:else}
	<!-- Bad tier: borrowing locked -->
	<div class="loan-card locked">
		<div class="loan-locked-h">🦈 Borrowing locked</div>
		<p class="loan-note" style="margin:0">
			Your credit is <b class="neg">{creditTier}</b> ({creditScore}). The Shark won't lend to you
			right now — repay on time, stay out of the red, and keep utilization low to climb back to
			<b>Poor</b> (400+) and unlock loans again.
		</p>
	</div>
{/if}

<style>
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
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		font-size: 1.5rem;
		color: #fb7185;
	}
	.loan-summary {
		cursor: pointer;
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.95rem;
		list-style: none;
		display: flex;
		align-items: center;
		justify-content: space-between;
	}
	.loan-summary::-webkit-details-marker {
		display: none;
	}
	.loan-cv {
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
		font-family: 'Orbitron', var(--font-display);
		font-weight: 800;
		color: var(--brand-2);
		font-size: 1.6rem;
		line-height: 1;
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
