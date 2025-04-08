<script>
  import { supabase } from '$lib/supabaseClient';
  import { user, userProfile } from '$lib/stores/userStore.js';
  import { gameStore, fetchRandomGame } from '$lib/stores/GameStore.js';

  // ============================
  // 🧾 Local State
  // ============================
  let email = '';
  let password = '';
  let errorMsg = '';
  let isLoading = false;
  let isLogin = true;

  // ============================
  // 🔐 Handle Auth (Login / Signup)
  // ============================
  async function handleAuth() {
    isLoading = true;
    errorMsg = '';  // Clear previous error messages

    // Validate input
    if (!email || !password) {
      errorMsg = 'Email and password are required.';
      isLoading = false;
      return;
    }

    try {
      let authResponse;
      const authData = { email, password };

      // Perform login or signup based on isLogin flag
      if (isLogin) {
        authResponse = await supabase.auth.signInWithPassword(authData);
      } else {
        authResponse = await supabase.auth.signUp(authData);
      }

      const { data, error } = authResponse;

      if (error) {
        errorMsg = error.message;
        isLoading = false;
        return;
      }

      // ✅ Save authenticated user to store
      user.set(data.user);

      // If new signup, create user profile if not already exists
      if (!isLogin) {
        await handleNewUserProfile(data.user.id);
      }

      // ✅ Fetch user profile after login/signup
      await loadUserProfile(data.user.id);

      // ✅ Fetch a random puzzle after successful login/signup
      await fetchRandomGame();

    } catch (err) {
      errorMsg = err.message || 'Unexpected error occurred.';
    }

    isLoading = false;
  }

  // Function to handle new user profile creation
  async function handleNewUserProfile(userId) {
    const { data: profileData, error: profileError } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .single();

    if (profileError && profileError.code === 'PGRST116') {
      // If profile not found, create a new profile
      const { error: insertError } = await supabase.from('profiles').insert({
        id: userId,
        bankroll: 1000,
        games_played: 0,
        games_won: 0,
        games_lost: 0,
        highest_streak: 0
      });

      if (insertError) {
        errorMsg = insertError.message;
        isLoading = false;
        return;
      }
    } else if (profileError) {
      errorMsg = profileError.message;
      isLoading = false;
      return;
    }
  }

  // Function to load user profile from database and update stores
  async function loadUserProfile(userId) {
    const { data: profile, error: profileErrorFetch } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .single();

    if (profileErrorFetch) {
      errorMsg = profileErrorFetch.message;
      isLoading = false;
      return;
    }

    if (profile) {
      userProfile.set(profile);  // Store the user profile
      gameStore.update(state => ({
        ...state,
        bankroll: profile.bankroll ?? 1000  // Use profile bankroll or default to 1000
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
