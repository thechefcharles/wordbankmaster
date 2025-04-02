<script>
    import { supabase } from '$lib/supabaseClient';
    import { user } from '$lib/stores/userStore.js';
  
    let email = '';
    let password = '';
    let loading = false;
    let errorMsg = '';
    let isLogin = true;
  
    async function handleAuth() {
  loading = true;
  errorMsg = '';

  if (!email || !password) {
    errorMsg = 'Email and password are required.';
    loading = false;
    return;
  }

  try {
    if (isLogin) {
      // ✅ Login format
      const { data, error } = await supabase.auth.signInWithPassword({
        email,
        password
      });

      console.log('Login result:', data, error);

      if (error) {
        errorMsg = error.message;
      } else {
        user.set(data.user);
      }

    } else {
      // ✅ Signup format
      const { data, error } = await supabase.auth.signUp({
        email,
        password
      });

      console.log('Signup result:', data, error);

      if (error) {
        errorMsg = error.message;
      } else {
        user.set(data.user);
      }
    }

  } catch (err) {
    errorMsg = err.message || 'An unexpected error occurred.';
  }

  loading = false;
}
  </script>
  
  <div class="auth-box">
    <h2>{isLogin ? 'Login' : 'Sign Up'} to Play</h2>
  
    <input type="email" bind:value={email} placeholder="Email" />
    <input type="password" bind:value={password} placeholder="Password" />
  
    <button on:click={handleAuth} disabled={loading}>
      {loading ? 'Loading...' : (isLogin ? 'Login' : 'Sign Up')}
    </button>
  
    {#if errorMsg}
      <div class="error">{errorMsg}</div>
    {/if}
  
    <p class="toggle-mode">
      {isLogin ? "Don't have an account?" : 'Already have an account?'}
      <a href="#" on:click={() => isLogin = !isLogin}>
        {isLogin ? 'Sign up here' : 'Log in here'}
      </a>
    </p>
  </div>
  
  <style>
    .auth-box {
      background: white;
      padding: 30px;
      border-radius: 10px;
      max-width: 400px;
      width: 100%;
      text-align: center;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
    }
  
    input {
      display: block;
      width: 100%;
      padding: 10px;
      margin: 12px 0;
      font-size: 16px;
      border: 1px solid #ccc;
      border-radius: 6px;
    }
  
    button {
      background-color: #46a230;
      color: white;
      font-weight: bold;
      border: none;
      padding: 10px 20px;
      border-radius: 6px;
      cursor: pointer;
      transition: background 0.3s;
    }
  
    button:hover {
      background-color: #3b8c26;
    }
  
    .error {
      color: red;
      margin-top: 10px;
      font-weight: bold;
    }
  
    .toggle-mode {
      margin-top: 15px;
      font-size: 14px;
    }
  
    .toggle-mode a {
      color: #007bff;
      cursor: pointer;
      margin-left: 6px;
      text-decoration: underline;
    }
  </style>
  