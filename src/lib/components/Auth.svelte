<script>
  import { supabase } from '$lib/supabaseClient';
  import { user, userProfile } from '$lib/stores/userStore.js';
  import { gameStore, fetchRandomGame } from '$lib/stores/GameStore.js';

  let email = '';
  let password = '';
  let errorMsg = '';
  let isLoading = false;
  let isLogin = true;

  // 🔐 Handle Auth (Login / Signup)
  async function handleAuth() {
    isLoading = true;
    errorMsg = '';

    if (!email || !password) {
      errorMsg = 'Email and password are required.';
      isLoading = false;
      return;
    }

    try {
      const authData = { email, password };
      let authResponse = isLogin
        ? await supabase.auth.signInWithPassword(authData)
        : await supabase.auth.signUp(authData);

      const { data, error } = authResponse;

      if (error) {
        console.error("❌ Error during signup or login:", error);
        errorMsg = error.message;
        isLoading = false;
        return;
      }

      user.set(data.user);

      // ✅ Load profile (which should be auto-created by trigger)
      await loadUserProfile(data.user.id);

      // ✅ Fetch a random puzzle
      await fetchRandomGame();
    } catch (err) {
      console.error("❌ Unexpected error during auth:", err);
      errorMsg = err.message || 'Unexpected error occurred.';
    }

    isLoading = false;
  }

  // 🧾 Load profile from Supabase
  async function loadUserProfile(userId) {
    const { data: profile, error } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .single();

    if (error) {
      console.error("❌ Error fetching profile:", error.message);
      errorMsg = error.message;
      return;
    }

    if (profile) {
      userProfile.set(profile);
      gameStore.update(state => ({
        ...state,
        bankroll: profile.bankroll ?? 1000
      }));
    }
  }
</script>

<div class="auth-container">
  <div class="auth-box">
    <h2>{isLogin ? 'Login' : 'Sign Up'} to Play</h2>

    <input type="email" bind:value={email} placeholder="Email" />
    <input type="password" bind:value={password} placeholder="Password" />

    <button on:click={handleAuth} disabled={isLoading}>
      {isLoading ? 'Loading...' : (isLogin ? 'Login' : 'Sign Up')}
    </button>

    {#if errorMsg}
      <div class="error-text">{errorMsg}</div>
    {/if}

    <p class="toggle-mode">
      {isLogin ? "Don't have an account?" : 'Already have an account?'}
      <button type="button" on:click={() => isLogin = !isLogin}>
        {isLogin ? 'Sign up here' : 'Log in here'}
      </button>
    </p>
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
</style>
