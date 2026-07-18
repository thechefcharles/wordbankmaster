<script>
	import { get } from 'svelte/store';
	import PinPad from '$lib/components/PinPad.svelte';
	import { pinConfirm } from '$lib/pinConfirm.js';
	import { verifyPin, setPin, tooManyFails } from '$lib/pin.js';

	let error = false;
	let msg = '';
	/** @type {any} */
	let pad;

	// Create-mode (first money action, no PIN yet): 'set' then 'confirm'.
	let createStep = 'set';
	let firstPin = '';
	// Reset the create sub-state whenever a fresh gate opens.
	$: if ($pinConfirm) {
		if ($pinConfirm.mode !== 'create') {
			createStep = 'set';
			firstPin = '';
		}
	} else {
		createStep = 'set';
		firstPin = '';
	}

	/** @param {string} text */
	function flash(text) {
		error = true;
		msg = text;
		setTimeout(() => {
			error = false;
			pad?.reset();
		}, 480);
	}

	/** @param {CustomEvent<string>} e */
	async function onSubmit(e) {
		const s = get(pinConfirm);
		if (!s?.uid) return;
		const pin = e.detail;

		if (s.mode === 'create') {
			if (createStep === 'set') {
				firstPin = pin;
				createStep = 'confirm';
				msg = '';
				pad?.reset();
				return;
			}
			// confirm step
			if (pin === firstPin) {
				await setPin(s.uid, s.name, pin);
				pinConfirm.set(null);
				msg = '';
				s.resolve(true); // PIN created → the action proceeds
			} else {
				createStep = 'set';
				firstPin = '';
				flash('PINs didn’t match — try again.');
			}
			return;
		}

		// verify mode
		const ok = await verifyPin(s.uid, pin);
		if (ok) {
			pinConfirm.set(null);
			msg = '';
			s.resolve(true);
		} else {
			flash(tooManyFails() ? 'Too many tries.' : 'Wrong PIN — try again.');
		}
	}
	function cancel() {
		const s = get(pinConfirm);
		pinConfirm.set(null);
		msg = '';
		s?.reject(new Error('cancelled'));
	}

	$: isCreate = $pinConfirm?.mode === 'create';
	$: title = isCreate
		? createStep === 'set'
			? 'Create your PIN'
			: 'Confirm your PIN'
		: 'Enter your PIN';
	$: subtext = isCreate
		? createStep === 'set'
			? 'Set a 4-digit PIN — you’ll use it to confirm purchases & wagers.'
			: 'Type it once more to confirm.'
		: $pinConfirm?.reason;
</script>

{#if $pinConfirm}
	<div class="pc-overlay" role="dialog" aria-modal="true" aria-label="Confirm with PIN">
		<div class="pc-card">
			<h2 class="pc-title">{title}</h2>
			<p class="pc-reason" class:soft={isCreate}>{subtext}</p>
			{#if !isCreate && $pinConfirm.details?.length}
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
	.pc-reason.soft {
		color: var(--text-muted, #aeb8c6);
		font-weight: 400;
		max-width: 300px;
		margin-left: auto;
		margin-right: auto;
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
