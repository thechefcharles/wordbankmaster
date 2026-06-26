<script>
  // Public, no-auth Terms of Service page. URL: /terms
  // Used for TestFlight external testing + App Store submission.
  const CONTACT = 'charlieforeman77@gmail.com';
  const UPDATED = 'June 26, 2026';
</script>

<svelte:head>
  <title>WordBank — Terms of Service</title>
  <meta name="robots" content="index" />
</svelte:head>

<main class="legal">
  <h1>WordBank Terms of Service</h1>
  <p class="updated">Last updated: {UPDATED}</p>

  <p>
    Welcome to WordBank ("we," "us," or "the app"), a word-puzzle game. By creating an
    account or using the app, you agree to these Terms. If you don't agree, please don't
    use WordBank.
  </p>

  <h2>The service</h2>
  <p>
    WordBank is a game where you solve hidden phrases, play a shared Daily, climb for
    in-game Cash, and challenge other players. We provide the app "as is" and may add,
    change, or remove features over time.
  </p>

  <h2>Virtual currency ("Cash")</h2>
  <ul>
    <li>The "Cash," "$", and balances in WordBank are <strong>virtual, in-game points
      only</strong>. They have <strong>no real-world monetary value</strong>.</li>
    <li>Virtual Cash <strong>cannot be purchased, sold, withdrawn, or exchanged</strong>
      for real money or anything of value.</li>
    <li>Challenges and wagers between players are played entirely with this virtual
      Cash. They are <strong>not gambling</strong> and involve no real money.</li>
    <li>We may adjust, reset, or remove virtual balances as part of running and balancing
      the game.</li>
  </ul>

  <h2>Your account</h2>
  <ul>
    <li>You're responsible for activity on your account and for keeping your login secure.</li>
    <li>Provide accurate information and use the app only if you're old enough to do so
      in your country (and at least 13).</li>
    <li>Pick a username that isn't offensive or impersonating someone else; we may
      reclaim or change usernames that violate this.</li>
  </ul>

  <h2>Fair play &amp; acceptable use</h2>
  <p>You agree not to:</p>
  <ul>
    <li>Cheat, exploit bugs, automate play, or use tools/bots to gain an unfair advantage.</li>
    <li>Harass other players or post abusive, illegal, or infringing content (e.g., in
      challenge or group chat).</li>
    <li>Attempt to access, disrupt, or reverse-engineer the app, its servers, or other
      players' accounts.</li>
  </ul>
  <p>We may suspend or terminate accounts that break these rules.</p>

  <h2>Deleting your account</h2>
  <p>
    You can permanently delete your account and all associated data at any time from
    <strong>My Account → Delete Account</strong>. This is immediate and can't be undone.
    We may also terminate accounts that violate these Terms.
  </p>

  <h2>No warranty</h2>
  <p>
    WordBank is provided "as is" and "as available," without warranties of any kind. We
    don't guarantee the app will always be available, error-free, or that scores,
    streaks, or balances will never be affected by maintenance or fixes.
  </p>

  <h2>Limitation of liability</h2>
  <p>
    To the fullest extent permitted by law, we are not liable for any indirect,
    incidental, or consequential damages, or for loss of virtual Cash, progress, or
    data, arising from your use of the app.
  </p>

  <h2>Changes to these Terms</h2>
  <p>
    We may update these Terms from time to time. We'll revise the "Last updated" date
    above when we do; continuing to use the app means you accept the updated Terms.
  </p>

  <h2>Contact</h2>
  <p>
    Questions about these Terms? Email <a href={`mailto:${CONTACT}`}>{CONTACT}</a>. See
    also our <a href="/privacy">Privacy Policy</a>.
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
    margin: 0 0 0.25rem;
  }
  .updated { color: var(--text-faint, #8b98a9); font-size: 0.9rem; margin: 0 0 1.5rem; }
  h2 {
    font-family: var(--font-display, system-ui, sans-serif);
    font-size: 1.15rem;
    margin: 1.8rem 0 0.5rem;
  }
  ul { padding-left: 1.2rem; }
  li { margin: 0.3rem 0; }
  a { color: var(--brand-2, #fde047); }
</style>
