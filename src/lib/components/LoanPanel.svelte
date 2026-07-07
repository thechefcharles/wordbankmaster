<script>
	import { createEventDispatcher } from 'svelte';
	import { takeLoan, repayLoan } from '$lib/stores/statsStore.js';
	import { requirePin } from '$lib/pinConfirm.js';
	import { track } from '$lib/analytics.js';
	import { fx } from '$lib/sound.js';

	/** The get_bank payload: { bank, loan, loan_cap, in_the_red, net_worth }
	 * @type {{ bank:number, net_worth:number, loan:number, loan_cap:number, in_the_red:boolean }|null} */
	export let bank = null;

	const dispatch = createEventDispatcher();

	// 💸 Loan Shark
	let borrowAmt = 100; // $ to borrow (dial)
	let repayAmt = 0; // $ to repay (dial)
	let loanBusy = '';
	let loanMsg = '';
	$: loanCap = bank?.loan_cap ?? 0;
	$: owed = bank?.loan ?? 0;
	$: feeOnBorrow = Math.round(borrowAmt * 0.25);
	$: if (borrowAmt > loanCap) borrowAmt = loanCap;
	$: if (borrowAmt < 10 && loanCap >= 10) borrowAmt = 10;
	$: maxRepay = Math.max(0, Math.min(owed, bank?.bank ?? 0));
	$: if (repayAmt > maxRepay) repayAmt = maxRepay;
	// seed the repay dial when we (re)load into a debt state
	$: if (bank) repayAmt = Math.min(repayAmt || maxRepay, maxRepay);

	const fmt = (/** @type {number} */ n) => '$' + Math.round(n ?? 0).toLocaleString();

	async function borrow() {
		if (loanBusy || borrowAmt < 10) return;
		const total = borrowAmt + Math.round(borrowAmt * 0.25);
		try {
			await requirePin(
				`Borrow $${borrowAmt.toLocaleString()} — you'll owe $${total.toLocaleString()}`,
				[
					{ label: 'You receive', value: '$' + borrowAmt.toLocaleString() },
					{ label: 'Fee (25%)', value: '$' + Math.round(borrowAmt * 0.25).toLocaleString() },
					{ label: 'You owe', value: '$' + total.toLocaleString() }
				]
			);
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
		<p class="loan-note">
			Store is locked and half of every payout auto-pays your debt until it's clear. Your net worth
			is <b class="neg">{fmt(bank.net_worth)}</b>.
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
				<button class="loan-btn pay" disabled={!!loanBusy} on:click={() => repay(null)}
					>Pay max ({fmt(maxRepay)})</button
				>
			</div>
		{:else}
			<p class="loan-note">Earn some Cash (play the Daily) then come back to repay.</p>
		{/if}
		{#if loanMsg}<p class="msg">{loanMsg}</p>{/if}
	</div>
{:else if loanCap > 0}
	<!-- No debt: borrow panel -->
	<details class="loan-card">
		<summary class="loan-summary"
			>🦈 Need Cash? Borrow up to {fmt(loanCap)} <span class="loan-cv">▾</span></summary
		>
		<p class="loan-note">
			A 25% fee, one loan at a time. While you owe, the Store locks and half of every payout
			auto-pays it down.
		</p>
		<div class="loan-dial">
			<button
				class="loan-step"
				on:click={() => (borrowAmt = Math.max(10, borrowAmt - 50))}
				aria-label="Less"
				disabled={borrowAmt <= 10}>−</button
			>
			<div class="loan-amt">
				<span class="loan-usd">{fmt(borrowAmt)}</span><span class="loan-sub"
					>you'll owe {fmt(borrowAmt + feeOnBorrow)}</span
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
			min="10"
			max={loanCap}
			step="10"
			bind:value={borrowAmt}
		/>
		<button class="loan-btn borrow" disabled={!!loanBusy || borrowAmt < 10} on:click={borrow}
			>🦈 Borrow {fmt(borrowAmt)} (fee {fmt(feeOnBorrow)})</button
		>
		{#if loanMsg}<p class="msg">{loanMsg}</p>{/if}
	</details>
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
