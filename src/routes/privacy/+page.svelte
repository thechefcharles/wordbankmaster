<script>
  // Public, no-auth privacy policy page. URL: /privacy
  // Used for TestFlight external testing + App Store submission.
  const CONTACT = 'charlieforeman77@gmail.com'; // ← change to your support email if you prefer
  const UPDATED = 'June 21, 2026';
</script>

<svelte:head>
  <title>WordBank — Privacy Policy</title>
  <meta name="robots" content="index" />
</svelte:head>

<main class="legal">
  <h1>WordBank Privacy Policy</h1>
  <p class="updated">Last updated: {UPDATED}</p>

  <p>
    WordBank ("we," "us," or "the app") is a word-puzzle game. This policy explains
    what we collect, how we use it, and the choices you have. We keep it short
    because we collect very little.
  </p>

  <h2>Information we collect</h2>
  <ul>
    <li><strong>Account info:</strong> the email address you sign up with. Passwords
      are handled by our authentication provider and stored only as a secure hash —
      we never see your password.</li>
    <li><strong>Gameplay data:</strong> your progress and results — puzzles played,
      scores, bankrolls, win/loss, streaks, badges, and leaderboard standings.</li>
    <li><strong>Basic technical data:</strong> standard information needed to run the
      app reliably (e.g., that comes with normal network requests).</li>
    <li><strong>Usage analytics:</strong> anonymous, first‑party events about how the
      app is used (e.g., opening the app, starting/finishing a puzzle) so we can
      understand engagement and improve the game. This stays in our own systems;
      we don't use third‑party ad trackers.</li>
  </ul>

  <h2>What we do NOT collect</h2>
  <ul>
    <li>No payment or financial information (the app has no purchases).</li>
    <li>No precise location, contacts, photos, microphone, or camera access.</li>
    <li>No advertising identifiers — we don't run ads.</li>
  </ul>

  <h2>How we use your information</h2>
  <ul>
    <li>To create your account and let you sign in.</li>
    <li>To save your progress and show your scores, streaks, badges, and leaderboard rank.</li>
    <li>To operate, maintain, and improve the game.</li>
  </ul>

  <h2>How your data is stored and shared</h2>
  <p>
    We use trusted infrastructure providers to run WordBank: <strong>Supabase</strong>
    (database and authentication) and <strong>Vercel</strong> (app hosting). Your data
    is stored on their secure infrastructure on our behalf. We do
    <strong>not sell your data</strong>, and we do not share it for advertising. We may
    disclose information if required by law.
  </p>

  <h2>Data security</h2>
  <p>
    Connections use HTTPS encryption, and your answers/scores are validated on the
    server. No system is perfectly secure, but we take reasonable measures to protect
    your information.
  </p>

  <h2>Your choices &amp; deleting your account</h2>
  <p>
    You can permanently delete your account and all associated data at any time from
    inside the app: <strong>My Account → Delete Account</strong>. This erases your
    account immediately and can't be undone. You can also email
    <a href={`mailto:${CONTACT}`}>{CONTACT}</a> and we'll delete it for you.
  </p>

  <h2>Children</h2>
  <p>
    WordBank is not directed to children under 13, and we do not knowingly collect
    personal information from children under 13.
  </p>

  <h2>Changes to this policy</h2>
  <p>
    We may update this policy from time to time. We'll revise the "Last updated" date
    above when we do.
  </p>

  <h2>Contact</h2>
  <p>
    Questions about privacy? Email <a href={`mailto:${CONTACT}`}>{CONTACT}</a>.
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
