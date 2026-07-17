<script>
	// Client-side email-OTP confirmation (email change / signup confirm). Mirrors what the old
	// /auth/confirm/+server.js did, but client-side so it survives static bundling. The
	// token_hash flow needs no code verifier, so the link works from any device.
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { supabase } from '$lib/supabaseClient';

	onMount(async () => {
		const url = new URL(window.location.href);
		const token_hash = url.searchParams.get('token_hash');
		const type = url.searchParams.get('type');
		const next = url.searchParams.get('next') || '/';

		if (token_hash && type) {
			const { error } = await supabase.auth.verifyOtp({
				type: /** @type {any} */ (type),
				token_hash
			});
			if (!error) {
				goto(next);
				return;
			}
		}
		goto('/reset-password?error_description=Email+link+is+invalid+or+has+expired');
	});
</script>

<div class="cf-wrap"><p>Confirming…</p></div>

<style>
	.cf-wrap {
		min-height: 100vh;
		display: flex;
		align-items: center;
		justify-content: center;
		background: var(--bg-0, #070b12);
		color: var(--text, #eaf0f7);
		font-family: inherit;
	}
</style>
