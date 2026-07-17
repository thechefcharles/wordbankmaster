<script>
	// Client-side OAuth (Google/Apple) callback. The Supabase client is configured with
	// detectSessionInUrl:true + flowType:pkce, so it auto-exchanges the ?code in the URL on
	// load using the code-verifier it stored in localStorage when sign-in started. We just
	// wait for the session to settle and route onward — no server round-trip, so this works
	// in the bundled native app too.
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { supabase } from '$lib/supabaseClient';

	let msg = 'Signing you in…';

	onMount(() => {
		const url = new URL(window.location.href);
		const next = url.searchParams.get('next') || '/';
		const providerError =
			url.searchParams.get('error_description') || url.searchParams.get('error');
		if (providerError) {
			goto('/?auth_error=' + encodeURIComponent(providerError));
			return;
		}

		let done = false;
		const finish = (/** @type {string} */ dest) => {
			if (done) return;
			done = true;
			goto(dest);
		};

		// detectSessionInUrl may have already exchanged the code by the time we run.
		supabase.auth.getSession().then(({ data }) => {
			if (data.session) finish(next);
		});
		// Otherwise wait for the exchange to complete.
		const { data: sub } = supabase.auth.onAuthStateChange((_e, session) => {
			if (session) finish(next);
		});
		// Safety net: never strand the user on this screen.
		const t = setTimeout(async () => {
			const { data } = await supabase.auth.getSession();
			finish(data.session ? next : '/?auth_error=exchange');
		}, 6000);

		return () => {
			sub.subscription.unsubscribe();
			clearTimeout(t);
		};
	});
</script>

<div class="cb-wrap">
	<div class="cb-spinner" aria-hidden="true"></div>
	<p>{msg}</p>
</div>

<style>
	.cb-wrap {
		min-height: 100vh;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 1rem;
		background: var(--bg-0, #070b12);
		color: var(--text, #eaf0f7);
		font-family: inherit;
	}
	.cb-spinner {
		width: 2rem;
		height: 2rem;
		border-radius: 50%;
		border: 3px solid color-mix(in srgb, var(--brand-1, #fbbf24) 30%, transparent);
		border-top-color: var(--brand-1, #fbbf24);
		animation: cb-spin 0.8s linear infinite;
	}
	@keyframes cb-spin {
		to {
			transform: rotate(360deg);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.cb-spinner {
			animation: none;
		}
	}
</style>
