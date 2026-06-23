<script>
  import { supabase } from '$lib/supabaseClient';
  import { user, userProfile } from '$lib/stores/userStore.js';
  import { gameStore } from '$lib/stores/GameStore.js';
  import { saveGameToLocalStorage } from '$lib/stores/localGameUtils.js';
  import { track } from '$lib/analytics.js';
  import { onMount } from 'svelte';

  let email = '';
  let password = '';
  let errorMsg = '';
  let isLoading = false;
  let isLogin = true;

  // Inside the native (Capacitor) app, Google blocks OAuth in the embedded
  // webview so it kicks out to Safari. Hide it there — native testers use
  // email/password (stays in-app). On the web, Google shows normally.
  let isNativeApp = false;
  onMount(() => {
    try {
      const c = /** @type {any} */ (window).Capacitor;
      isNativeApp = !!(c && (c.isNativePlatform ? c.isNativePlatform() : c.isNative))
        || /WordBankApp/i.test(navigator.userAgent);
    } catch { isNativeApp = false; }

    // Surface a failed OAuth/callback round-trip (set by /auth/callback).
    try {
      const params = new URLSearchParams(window.location.search);
      const ae = params.get('auth_error');
      const detail = params.get('auth_detail');
      if (ae) {
        errorMsg = ae === 'exchange' || ae === 'nocode'
          ? 'Sign-in didn’t complete — please try again, or use email & password.'
          : ae === 'config'
          ? 'Sign-in is temporarily unavailable. Please try again shortly.'
          : `Google sign-in was cancelled or blocked: ${decodeURIComponent(ae)}`;
        if (detail) errorMsg += ` (${decodeURIComponent(detail)})`;
        track('oauth_callback_error', { reason: ae, detail: detail ? decodeURIComponent(detail) : '' });
        // strip the param so it doesn't stick around on refresh
        params.delete('auth_error');
        params.delete('auth_detail');
        const qs = params.toString();
        window.history.replaceState({}, '', window.location.pathname + (qs ? '?' + qs : ''));
      }
    } catch { /* non-fatal */ }
  });

  let showReset = false;
  let resetEmail = '';
  let resetMsg = '';

  async function handleAuth() {
    isLoading = true;
    errorMsg = '';

    if (!email || !password) {
      errorMsg = 'Email and password are required.';
      isLoading = false;
      return;
    }

    try {
      const { data, error } = isLogin
        ? await supabase.auth.signInWithPassword({ email, password })
        : await supabase.auth.signUp({ email, password });

      if (error || !data?.user?.id) {
        errorMsg = error?.message || "Authentication failed.";
        return;
      }

      track(isLogin ? 'login' : 'signup', { platform: isNativeApp ? 'ios' : 'web' });
      user.set(/** @type {{ id: string }} */ (data.user));

      const profile = await loadUserProfile(data.user.id);
      if (profile) {
        window.location.href = '/';
      }

    } catch (err) {
      errorMsg = (err instanceof Error ? err.message : String(err)) || "Unexpected error.";
    } finally {
      isLoading = false;
    }
  }

  async function handlePasswordReset() {
  resetMsg = '';

  if (!resetEmail) {
    resetMsg = 'Please enter your email.';
    return;
  }

  // The reset email links straight to /reset-password with a one-time token_hash
  // (cross-device, no code verifier). redirectTo is just the allow-listed landing
  // page; the actual link is built by the Supabase email template, which must be:
  //   {{ .SiteURL }}/reset-password?token_hash={{ .TokenHash }}&type=recovery
  const redirectUrl = `${window.location.origin}/reset-password`;

  const { error } = await supabase.auth.resetPasswordForEmail(resetEmail, {
    redirectTo: redirectUrl
  });

  if (error) {
    resetMsg = `❌ ${error.message}`;
  } else {
    resetMsg = '✅ Check your email to reset your password.';
  }
}

  /** @param {string} userId */
  async function loadUserProfile(userId) {
    const { data: profile, error } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .single();

    if (error || !profile) {
      errorMsg = error?.message || "Profile not found.";
      return null;
    }

    userProfile.set(profile);
    gameStore.update(state => ({
      ...state,
      bankroll: profile.current_bankroll ?? 1000
    }));

    saveGameToLocalStorage();
    return profile;
  }

  async function signInWithGoogle() {
    errorMsg = '';
    isLoading = true;
    try {
      const redirectUrl = `${window.location.origin}/auth/callback`;
      const { error } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: {
          redirectTo: redirectUrl,
          // Let the user pick which Google account (avoids silently reusing the wrong one).
          queryParams: { prompt: 'select_account' }
        }
      });
      if (error) {
        // Surface failures instead of doing nothing (provider disabled, redirect not
        // allow-listed, popup blocked, etc.).
        errorMsg = `Google sign-in failed: ${error.message}`;
        track('google_signin_error', { message: error.message });
        isLoading = false;
      }
      // On success the browser navigates to Google — no further code runs here.
    } catch (e) {
      errorMsg = 'Google sign-in failed. Try again, or use email & password.';
      isLoading = false;
    }
  }

  async function signInWithApple() {
    errorMsg = '';
    isLoading = true;
    try {
      const redirectUrl = `${window.location.origin}/auth/callback`;
      const { error } = await supabase.auth.signInWithOAuth({
        provider: 'apple',
        options: { redirectTo: redirectUrl }
      });
      if (error) {
        errorMsg = `Apple sign-in failed: ${error.message}`;
        track('apple_signin_error', { message: error.message });
        isLoading = false;
      }
    } catch (e) {
      errorMsg = 'Apple sign-in failed. Try again, or use email & password.';
      isLoading = false;
    }
  }
</script>

<div class="auth-screen">
  <div class="auth-card glass fade-up">
    <div class="brand">
      <video class="mark" src="/coin.mp4" poster="/coin-poster.jpg" autoplay loop muted playsinline disablepictureinpicture></video>
      <img class="wordmark" src="/wordmark-slogan.png" alt="WordBank — Spend Less. Think More." />
    </div>

    {#if showReset}
      <h2 class="auth-title">Reset password</h2>
    {:else if !isLogin}
      <h2 class="auth-title">Create your account</h2>
    {/if}

    {#if showReset}
      <input class="field" type="email" bind:value={resetEmail} placeholder="Your email" />

      <button class="btn-brand full" on:click={handlePasswordReset} disabled={isLoading}>
        {isLoading ? 'Sending…' : 'Send reset link'}
      </button>

      {#if resetMsg}
        <p class="reset-msg">{resetMsg}</p>
      {/if}

      <p class="toggle-mode">
        <button type="button" class="link" on:click={() => showReset = false}>
          ← Back to login
        </button>
      </p>

    {:else}
      <input class="field" type="email" bind:value={email} placeholder="Email" />
      <input class="field" type="password" bind:value={password} placeholder="Password" />

      <button class="btn-brand full" on:click={handleAuth} disabled={isLoading}>
        {isLoading ? 'Loading…' : (isLogin ? 'Log in' : 'Sign up')}
      </button>

      {#if !isNativeApp}
        <div class="divider"><span>or</span></div>

        <button class="btn-ghost full google" on:click={signInWithGoogle}>
          <img src="/googlelogo.png" alt="Google icon" class="google-icon" />
          Continue with Google
        </button>

        <button class="btn-ghost full apple" on:click={signInWithApple}>
          <svg class="apple-icon" viewBox="0 0 384 512" aria-hidden="true"><path fill="currentColor" d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184.8 4 273.5q0 39.3 14.4 81.2c12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z"/></svg>
          Continue with Apple
        </button>
      {/if}

      {#if errorMsg}
        <div class="error-text">{errorMsg}</div>
      {/if}

      <p class="toggle-mode">
        <button type="button" class="link subtle" on:click={() => showReset = true}>
          Forgot password?
        </button>
      </p>

      <p class="toggle-mode">
        {isLogin ? "Don't have an account?" : 'Already have an account?'}
        <button type="button" class="link" on:click={() => isLogin = !isLogin}>
          {isLogin ? 'Sign up' : 'Log in'}
        </button>
      </p>
    {/if}
  </div>
</div>

<style>
  .auth-screen {
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 100vh;
    padding: 20px;
  }

  .auth-card {
    width: 100%;
    max-width: 400px;
    padding: 32px 28px 28px;
    text-align: center;
    box-shadow: var(--shadow-lg);
  }

  .brand { margin-bottom: 22px; }

  .mark {
    width: min(44vw, 160px);
    aspect-ratio: 1;
    height: auto;
    object-fit: cover;
    border-radius: 50%;
    margin: 0 auto 6px;
    display: block;
    box-shadow: 0 0 24px rgba(251, 191, 36, 0.5), 0 8px 28px rgba(251, 191, 36, 0.35);
  }

  .wordmark {
    width: min(72vw, 270px);
    height: auto;
    margin: 2px auto 0;
    display: block;
    filter: drop-shadow(0 2px 14px rgba(0, 0, 0, 0.5));
  }

  .auth-title {
    font-family: var(--font-display);
    font-size: 1.15rem;
    font-weight: 600;
    color: var(--text);
    margin: 0 0 18px;
  }

  .field { margin: 10px 0; text-align: left; }

  .full { width: 100%; }
  .btn-brand.full { margin-top: 6px; padding: 15px; font-size: 1.02rem; }

  .divider {
    display: flex;
    align-items: center;
    gap: 12px;
    margin: 20px 2px;
    color: var(--text-faint);
    font-size: 0.82rem;
  }
  .divider::before, .divider::after {
    content: '';
    flex: 1;
    height: 1px;
    background: var(--border);
  }

  .google {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
    width: 100%;
  }
  .google-icon { width: 18px; height: 18px; }

  .toggle-mode {
    margin-top: 16px;
    font-size: 0.9rem;
    color: var(--text-muted);
  }

  /* Gold primary button (Log in / Sign up / reset) */
  .btn-brand {
    background: linear-gradient(135deg, #fde047, #f59e0b);
    color: #3a2a00;
    box-shadow: 0 4px 16px rgba(251, 191, 36, 0.3);
  }
  .apple {
    display: flex; align-items: center; justify-content: center; gap: 10px; width: 100%;
    margin-top: 10px;
  }
  .apple-icon { width: 17px; height: 17px; color: var(--text); }

  .link {
    background: none;
    border: none;
    padding: 0;
    cursor: pointer;
    font-weight: 700;
    color: #fbbf24;
  }
  .link:hover { text-decoration: underline; }
  .link.subtle { color: var(--text-muted); font-weight: 500; }

  .error-text {
    margin-top: 12px;
    color: var(--danger);
    font-size: 0.9rem;
  }

  .reset-msg {
    margin-top: 10px;
    font-size: 0.9rem;
    color: var(--text-muted);
  }
</style>
