<script>
  import { supabase } from '$lib/supabaseClient';
  import { user, userProfile } from '$lib/stores/userStore.js';
  import { fetchRandomGame } from '$lib/stores/GameStore.js'; // ✅ ADDED

  let email = '';
  let password = '';
  let errorMsg = '';
  let isLoading = false;
  let isLogin = true;

  async function handleAuth() {
    isLoading = true;
    errorMsg = '';

    if (!email || !password) {
      errorMsg = 'Email and password are required.';
      isLoading = false;
      return;
    }

    try {
      let authResponse;

      if (isLogin) {
        authResponse = await supabase.auth.signInWithPassword({ email, password });
      } else {
        authResponse = await supabase.auth.signUp({ email, password });
      }

      const { data, error } = authResponse;

      if (error) {
        errorMsg = error.message;
      } else {
        user.set(data.user);

        // On signup, initialize profile in DB
        if (!isLogin) {
          await supabase.from('profiles').insert({
            id: data.user.id,
            bankroll: 1000,
            games_played: 0,
            games_won: 0
          });
        }

        // Fetch profile either way
        const { data: profile } = await supabase
          .from('profiles')
          .select('*')
          .eq('id', data.user.id)
          .single();

        if (profile) userProfile.set(profile);

        // ✅ FETCH A PUZZLE IMMEDIATELY AFTER AUTH
        await fetchRandomGame();
      }
    } catch (err) {
      errorMsg = err.message || 'Unexpected error occurred.';
    }

    isLoading = false;
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
      <a href="#" on:click={() => isLogin = !isLogin}>
        {isLogin ? 'Sign up here' : 'Log in here'}
      </a>
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

  .toggle-mode a {
    color: #007bff;
    text-decoration: underline;
    cursor: pointer;
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

  :global(body.dark-mode) .toggle-mode a {
    color: #4da3ff;
  }
</style>
