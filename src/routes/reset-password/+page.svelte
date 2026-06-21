<script>
  import { supabase } from '$lib/supabaseClient';
  import { goto } from '$app/navigation';
  import { onMount } from 'svelte';

  let password = '';
  let confirmPassword = '';
  let message = '';
  let isTokenReady = false;
  let success = false;
  // A one-time recovery token (token_hash) from the email link. We DON'T verify
  // it on load — email scanners/prefetchers GET links and would burn the
  // one-time token. We hold it and verify only when the user submits the form.
  let tokenHash = '';
  let otpType = '';

  onMount(() => {
    const url = new URL(window.location.href);

    // Supabase passes errors (expired/used link) back as query params.
    const errDesc = url.searchParams.get('error_description');
    if (errDesc) {
      message = `⛔ ${decodeURIComponent(errDesc.replace(/\+/g, ' '))}`;
      return;
    }

    // Recovery link landed here directly with a token_hash → show the form now,
    // verify on submit (prefetch-safe, no local code verifier, works cross-device).
    tokenHash = url.searchParams.get('token_hash') ?? '';
    otpType = url.searchParams.get('type') ?? '';
    if (tokenHash && otpType) {
      isTokenReady = true;
      return;
    }

    // Otherwise a session was already established (e.g. via /auth/confirm, or the
    // user is signed in) — surface the form once we see it.
    let settled = false;
    const ready = () => { settled = true; isTokenReady = true; message = ''; };
    supabase.auth.getSession().then(({ data }) => { if (data.session) ready(); });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      if (session) ready();
    });
    const timer = setTimeout(() => {
      if (!settled) message = '⛔ This reset link is invalid or has expired. Please request a new one.';
    }, 3000);

    return () => { clearTimeout(timer); sub.subscription.unsubscribe(); };
  });

  async function updatePassword() {
    if (!password || !confirmPassword) {
      message = '⚠️ Please fill in both fields.';
      success = false;
      return;
    }

    if (password !== confirmPassword) {
      message = '❌ Passwords do not match.';
      success = false;
      return;
    }

    // Verify the one-time token now (deferred from page load). This establishes
    // the recovery session; if the link is expired/used, the user finds out here.
    if (tokenHash && otpType) {
      const { error: verifyErr } = await supabase.auth.verifyOtp({
        token_hash: tokenHash, type: /** @type {any} */ (otpType)
      });
      if (verifyErr) {
        message = `⛔ ${verifyErr.message}`;
        success = false;
        return;
      }
      tokenHash = ''; // consumed
    }

    console.log("🔐 Attempting password update...");
    const { error } = await supabase.auth.updateUser({ password });

    if (error) {
      message = `❌ ${error.message}`;
      success = false;
      console.error("❌ Password update error:", error.message);
    } else {
      message = '✅ Password updated! Redirecting...';
      success = true;
      console.log("✅ Password update successful.");
      setTimeout(() => goto('/'), 2000);
    }
  }
</script>

<main class="reset-wrapper">
  <div class="reset-card glass fade-up">
    <h2>Reset your password</h2>

    {#if message}
      <p class="message {success ? 'success' : 'error'}">{message}</p>
    {/if}

    {#if isTokenReady}
      <input class="field" type="password" placeholder="New password" bind:value={password} />
      <input class="field" type="password" placeholder="Confirm password" bind:value={confirmPassword} />
      <button class="btn-brand full" on:click={updatePassword}>Update password</button>
    {/if}
  </div>
</main>

<style>
  .reset-wrapper {
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 100vh;
    padding: 20px;
  }
  .reset-card {
    width: 100%;
    max-width: 400px;
    padding: 30px 26px;
    text-align: center;
    box-shadow: var(--shadow-lg);
  }
  h2 {
    font-family: var(--font-display);
    font-size: 1.4rem;
    margin: 0 0 1.2rem;
  }
  .field { margin: 10px 0; text-align: left; }
  .full { width: 100%; margin-top: 8px; }

  .message {
    margin: 0 0 1rem;
    font-weight: 600;
    font-size: 0.9rem;
  }
  .message.success { color: var(--brand-2); }
  .message.error { color: var(--danger); }
</style>
