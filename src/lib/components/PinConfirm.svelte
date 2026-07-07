<script>
	import { get } from 'svelte/store';
	import PinPad from '$lib/components/PinPad.svelte';
	import { pinConfirm } from '$lib/pinConfirm.js';
	import { verifyPin, tooManyFails } from '$lib/pin.js';

	let error = false;
	let msg = '';
	/** @type {any} */
	let pad;

	/** @param {CustomEvent<string>} e */
	async function onSubmit(e) {
		const uid = get(pinConfirm)?.uid;
		if (!uid) return;
		const ok = await verifyPin(uid, e.detail);
		if (ok) {
			const s = get(pinConfirm);
			pinConfirm.set(null);
			msg = '';
			s?.resolve(true);
		} else {
			error = true;
			msg = tooManyFails() ? 'Too many tries.' : 'Wrong PIN — try again.';
			setTimeout(() => {
				error = false;
				pad?.reset();
			}, 480);
		}
	}
	function cancel() {
		const s = get(pinConfirm);
		pinConfirm.set(null);
		msg = '';
		s?.reject(new Error('cancelled'));
	}
</script>

{#if $pinConfirm}
	<div class="pc-overlay" role="dialog" aria-modal="true" aria-label="Confirm with PIN">
		<div class="pc-card">
			<h2 class="pc-title">Enter your PIN</h2>
			<p class="pc-reason">{$pinConfirm.reason}</p>
			{#if $pinConfirm.details?.length}
				<div class="pc-stakes">
					{#each $pinConfirm.details as d}
						<div class="pc-stake">
							<span class="pc-sk-label">{d.label}</span><span class="pc-sk-value">{d.value}</span>
						</div>
					{/each}
				</div>
			{/if}
			<PinPad bind:this={pad} {error} on:submit={onSubmit} on:change={() => (msg = '')} />
			{#if msg}<p class="pc-msg">{msg}</p>{/if}
			<button class="pc-cancel" on:click={cancel}>Cancel</button>
		</div>
	</div>
{/if}

<style>
	.pc-overlay {
		/* above every in-page modal (challenge/shop modals are z-index 9999) so the
       PIN pad is actually visible + tappable when confirming from inside one */
		position: fixed;
		inset: 0;
		z-index: 100000;
		display: grid;
		place-items: center;
		padding: 1.2rem;
		background:
			radial-gradient(70% 50% at 50% 18%, rgba(251, 191, 36, 0.12), rgba(0, 0, 0, 0) 60%),
			rgba(5, 5, 5, 0.92);
		backdrop-filter: blur(4px);
	}
	.pc-card {
		width: 100%;
		max-width: 360px;
		text-align: center;
	}
	.pc-title {
		font-family: var(--font-display);
		font-size: 1.35rem;
		margin: 0 0 0.2rem;
	}
	.pc-reason {
		color: #fbbf24;
		font-weight: 700;
		font-size: 0.95rem;
		margin: 0 0 1rem;
	}
	.pc-stakes {
		width: 100%;
		max-width: 280px;
		margin: 0 auto 1.3rem;
		display: flex;
		flex-direction: column;
		gap: 6px;
		padding: 12px 14px;
		border-radius: 14px;
		border: 1px solid rgba(253, 224, 71, 0.3);
		background: rgba(251, 191, 36, 0.06);
	}
	.pc-stake {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 12px;
		font-size: 0.86rem;
	}
	.pc-sk-label {
		color: var(--text-muted, #aeb8c6);
	}
	.pc-sk-value {
		font-family: var(--font-display);
		font-weight: 700;
		color: var(--text, #fff);
	}
	.pc-msg {
		margin-top: 0.9rem;
		font-size: 0.86rem;
		color: #f87171;
	}
	.pc-cancel {
		margin-top: 1.4rem;
		background: none;
		border: none;
		color: var(--text-faint);
		font-size: 0.85rem;
		text-decoration: underline;
		cursor: pointer;
	}
</style>
