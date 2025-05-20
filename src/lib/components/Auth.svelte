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

      user.set(data.user);

      const profile = await loadUserProfile(data.user.id);
      if (profile) {
        window.location.href = '/';
      }

    } catch (err) {
      errorMsg = err.message || "Unexpected error.";
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

  const redirectUrl =
    import.meta.env.DEV
      ? 'http://localhost:5173/reset-password'
      : 'https://wordbanksvelte1.vercel.app/reset-password';

  const { error } = await supabase.auth.resetPasswordForEmail(resetEmail, {
    redirectTo: redirectUrl
  });

  if (error) {
    resetMsg = `❌ ${error.message}`;
  } else {
    resetMsg = '✅ Check your email to reset your password.';
  }
}

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
    await supabase.auth.signInWithOAuth({ provider: 'google' });
  }
</script>

<div class="auth-container">
  <div class="auth-box">
    <!-- 🟢 WordBank Logo -->
    <img src="/1.png" alt="WordBank Logo" class="wordbank-logo" />

    <h2>
      {#if showReset}
        Reset Password
      {:else}
        {isLogin ? 'Login' : 'Sign Up'} to Play
      {/if}
    </h2>

    {#if showReset}
      <input type="email" bind:value={resetEmail} placeholder="Your email" />

      <button on:click={handlePasswordReset} disabled={isLoading}>
        {isLoading ? 'Sending...' : 'Send Reset Link'}
      </button>

      {#if resetMsg}
        <p class="reset-msg">{resetMsg}</p>
      {/if}

      <p class="toggle-mode">
        <button type="button" on:click={() => showReset = false}>
          ← Back to Login
        </button>
      </p>

    {:else}
      <input type="email" bind:value={email} placeholder="Email" />
      <input type="password" bind:value={password} placeholder="Password" />

      <button on:click={handleAuth} disabled={isLoading}>
        {isLoading ? 'Loading...' : (isLogin ? 'Login' : 'Sign Up')}
      </button>

      <div class="divider">or</div>

      <!-- 🟥 Google Sign-In Button -->
      <button class="google-btn" on:click={signInWithGoogle}>
        <img src="/googlelogo.png" alt="Google icon" class="google-icon" />
        Continue with Google
      </button>

      {#if errorMsg}
        <div class="error-text">{errorMsg}</div>
      {/if}

      <p class="toggle-mode">
        <button type="button" on:click={() => showReset = true}>
          Forgot Password?
        </button>
      </p>

      <p class="toggle-mode">
        {isLogin ? "Don't have an account?" : 'Already have an account?'}
        <button type="button" on:click={() => isLogin = !isLogin}>
          {isLogin ? 'Sign up here' : 'Log in here'}
        </button>
      </p>
    {/if}
  </div>
</div>

<style>
  .auth-container {
    display: flex;
    justify-content: center;
    align-items: center;
    height: 100vh;
    padding: 16px;
  }

  .auth-box {
    background-color: white;
    padding: 24px 32px;
    border-radius: 12px;
    box-shadow: 0 0 16px rgba(0, 0, 0, 0.15);
    width: 100%;
    max-width: 400px;
    text-align: center;
  }

  input {
    display: block;
    width: 100%;
    padding: 10px;
    margin: 12px 0;
    font-size: 1rem;
    border: 2px solid #ccc;
    border-radius: 8px;
    background-color: white;
    color: black;
  }

  button {
    padding: 10px;
    font-size: 1rem;
    background-color: limegreen;
    color: white;
    border: none;
    font-weight: bold;
    border-radius: 8px;
    cursor: pointer;
    transition: background 0.2s ease;
  }

  button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .toggle-mode {
    margin-top: 15px;
    font-size: 0.9rem;
    color: black;
  }

  .toggle-mode button {
    color: #007bff;
    text-decoration: underline;
    cursor: pointer;
    background: none;
    border: none;
  }

  .error-text {
    color: red;
    margin-top: 10px;
  }

  :global(body.dark-mode) .auth-box {
    background-color: #222;
  }

  :global(body.dark-mode) .auth-box h2,
  :global(body.dark-mode) .toggle-mode,
  :global(body.dark-mode) .error-text {
    color: white;
  }

  :global(body.dark-mode) input {
    background-color: #333;
    color: white;
    border: 2px solid #666;
  }

  :global(body.dark-mode) .toggle-mode button {
    color: #4da3ff;
  }
  .wordbank-logo {
  width: 280px;
  max-width: 80%;
  margin-bottom: 20px;
  height: auto;
}

@media (max-width: 600px) {
  .wordbank-logo {
    width: 200px;
  }
}

.google-btn {
  background-color: #fff;
  color: #444;
  border: 2px solid #ccc;
  padding: 10px;
  width: 100%;
  font-weight: bold;
  border-radius: 8px;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  transition: background 0.2s ease;
}

.google-btn:hover {
  background-color: #f1f1f1;
}

.google-icon {
  width: 20px;
  height: 20px;
}

.divider {
  margin: 20px 0;
  font-size: 0.9rem;
  color: #888;
}

.reset-box {
  margin-top: 1rem;
}

.reset-box input {
  margin: 8px 0;
  width: 100%;
  padding: 10px;
}

.reset-box button {
  background-color: dodgerblue;
  margin-top: 8px;
  padding: 10px;
}

.reset-msg {
  font-size: 0.9rem;
  color: #444;
  margin-top: 6px;
}


</style>
