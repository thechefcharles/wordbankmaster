<script>
	// Public, no-auth support page. URL: /support — used as the App Store "Support URL".
	const CONTACT = 'charlieforeman77@gmail.com';
</script>

<svelte:head>
	<title>WordBank — Support</title>
	<meta name="robots" content="index" />
</svelte:head>

<main class="legal">
	<h1>WordBank Support</h1>
	<p>
		Need a hand? Email <a href={`mailto:${CONTACT}`}>{CONTACT}</a> and we'll get back to you. A few
		quick answers below.
	</p>

	<h2>Frequently asked</h2>

	<h3>Is the "Cash" in the game real money?</h3>
	<p>
		No. All Cash, balances, and wagers in WordBank are <strong>virtual, in-game points only</strong>
		— they have no real-world value and can't be bought, sold, or withdrawn. Challenges are played
		with this virtual Cash; there's no real money and no gambling.
	</p>

	<h3>How do I delete my account?</h3>
	<p>
		Open <strong>My Account → Delete Account</strong> in the app. This permanently deletes your
		account and all associated data immediately, and can't be undone. If you'd rather we do it for
		you, email <a href={`mailto:${CONTACT}`}>{CONTACT}</a>.
	</p>

	<h3>I forgot my password.</h3>
	<p>
		On the login screen, tap <strong>Forgot password?</strong> and follow the email link to reset it.
	</p>

	<h3>How do I turn notifications on or off?</h3>
	<p>
		Manage push notifications in your device's Settings under WordBank, or from the in-app account
		settings.
	</p>

	<h3>I found a bug or want to report a player.</h3>
	<p>
		Please email <a href={`mailto:${CONTACT}`}>{CONTACT}</a> with what happened (and a screenshot if
		you have one). We review reports and may suspend accounts that break the rules.
	</p>

	<h2>More</h2>
	<p>
		See our <a href="/privacy">Privacy Policy</a> and <a href="/terms">Terms of Service</a>.
	</p>
</main>

<style>
	.legal {
		max-width: 720px;
		margin: 0 auto;
		padding: 2.5rem 1.25rem 4rem;
		color: var(--text, #e6edf3);
		line-height: 1.6;
		font-size: 1rem;
	}
	h1 {
		font-family: var(--font-display, system-ui, sans-serif);
		font-size: 1.8rem;
		margin: 0 0 1rem;
	}
	h2 {
		font-family: var(--font-display, system-ui, sans-serif);
		font-size: 1.15rem;
		margin: 1.8rem 0 0.5rem;
	}
	h3 {
		font-size: 1rem;
		margin: 1.2rem 0 0.25rem;
	}
	a {
		color: var(--brand-2, #fde047);
	}
</style>
