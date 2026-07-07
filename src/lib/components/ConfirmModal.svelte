<script>
	import { confirmStore } from '$lib/confirm.js';
	/** @param {boolean} v */
	function done(v) {
		const s = $confirmStore;
		confirmStore.set(null);
		s?.resolve(v);
	}
</script>

{#if $confirmStore}
	<div class="cm-overlay" role="dialog" aria-modal="true" aria-label={$confirmStore.title}>
		<button
			type="button"
			class="cm-backdrop"
			aria-label={$confirmStore.cancelText}
			on:click={() => done(false)}
		></button>
		<div class="cm-card" role="document">
			<h3 class="cm-title">{$confirmStore.title}</h3>
			{#if $confirmStore.message}<p class="cm-msg">{$confirmStore.message}</p>{/if}
			<button class="cm-go" class:danger={$confirmStore.danger} on:click={() => done(true)}
				>{$confirmStore.confirmText}</button
			>
			<button class="cm-cancel" on:click={() => done(false)}>{$confirmStore.cancelText}</button>
		</div>
	</div>
{/if}

<style>
	/* above every in-page modal (settings modal is 9999, PinConfirm is 100000) */
	.cm-overlay {
		position: fixed;
		inset: 0;
		z-index: 100001;
		display: grid;
		place-items: center;
		padding: 20px;
	}
	.cm-backdrop {
		position: absolute;
		inset: 0;
		background: rgba(4, 8, 14, 0.72);
		backdrop-filter: blur(6px);
		border: none;
		cursor: pointer;
	}
	.cm-card {
		position: relative;
		z-index: 1;
		width: 100%;
		max-width: 340px;
		padding: 22px;
		border-radius: 20px;
		text-align: center;
		background: var(--surface-strong, rgba(20, 26, 38, 0.96));
		border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.16));
		box-shadow: 0 24px 60px rgba(0, 0, 0, 0.5);
		display: flex;
		flex-direction: column;
		gap: 10px;
		animation: cmPop 0.22s cubic-bezier(0.34, 1.56, 0.64, 1);
	}
	@keyframes cmPop {
		from {
			transform: translateY(10px) scale(0.96);
			opacity: 0;
		}
		to {
			transform: none;
			opacity: 1;
		}
	}
	.cm-title {
		font-family: var(--font-display);
		font-size: 1.2rem;
		margin: 0;
		color: var(--text);
	}
	.cm-msg {
		font-size: 0.9rem;
		line-height: 1.5;
		color: var(--text-muted);
		margin: 0 0 4px;
	}
	.cm-go {
		width: 100%;
		height: 48px;
		border-radius: 14px;
		border: none;
		cursor: pointer;
		font-weight: 800;
		font-size: 1rem;
		color: #3a2a00;
		background: linear-gradient(135deg, #fde047, #f59e0b);
	}
	.cm-go.danger {
		color: #fff;
		background: linear-gradient(135deg, #f87171, #dc2626);
	}
	.cm-go:active {
		transform: scale(0.98);
	}
	.cm-cancel {
		background: none;
		border: none;
		color: var(--text-muted);
		cursor: pointer;
		font-weight: 600;
		padding: 4px;
		font-size: 0.95rem;
	}
</style>
