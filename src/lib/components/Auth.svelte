<script>
  import { supabase } from '$lib/supabaseClient';
  import { user, userProfile } from '$lib/stores/userStore.js';
  import { gameStore } from '$lib/stores/GameStore.js';
  import { saveGameToLocalStorage } from '$lib/stores/localGameUtils.js';

  let email = '';
  let password = '';
  let errorMsg = '';
  let isLoading = false;
  let isLogin = true;

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

  // Route through the server callback, which exchanges the PKCE recovery code
  // for a session (cookie) and then forwards to /reset-password. Using the
  // current origin keeps it working on any domain (dev or the live Vercel one).
  const redirectUrl = `${window.location.origin}/auth/callback?next=/reset-password`;

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
    const redirectUrl = `${window.location.origin}/auth/callback`;
    await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: redirectUrl }
    });
  }
</script>

<div class="auth-screen">
  <div class="auth-card glass fade-up">
    <div class="brand">
      <img class="mark" src="/logo-mark.png" alt="" width="72" height="72" />
      <img class="wordmark" src="/wordmark-slogan.png" alt="WordBank — Spend Less. Think More." />
    </div>

    <h2 class="auth-title">
      {#if showReset}
        Reset password
      {:else}
        {isLogin ? 'Welcome back' : 'Create your account'}
      {/if}
    </h2>

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

      <div class="divider"><span>or</span></div>

      <button class="btn-ghost full google" on:click={signInWithGoogle}>
        <img src="/googlelogo.png" alt="Google icon" class="google-icon" />
        Continue with Google
      </button>

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
    width: 72px;
    height: 72px;
    object-fit: contain;
    margin: 0 auto 12px;
    display: block;
    filter: drop-shadow(0 6px 20px rgba(52, 211, 153, 0.28));
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

  .link {
    background: none;
    border: none;
    padding: 0;
    cursor: pointer;
    font-weight: 600;
    color: var(--brand-2);
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
