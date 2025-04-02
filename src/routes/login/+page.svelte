<script>
    import { supabase } from '$lib/supabaseClient'; // Make sure this exists
    import { user, userProfile } from '$lib/stores/userStore.js';
  
    let email = '';
    let password = '';
    let error = '';
    let isLoading = false;
  
    async function handleLogin() {
      isLoading = true;
      error = '';
      
      const { data, error: authError } = await supabase.auth.signInWithPassword({
        email,
        password
      });
  
      if (authError) {
        error = authError.message;
      } else {
        user.set(data.user);
        await fetchUserProfile(data.user.id);
      }
  
      isLoading = false;
    }
  
    async function handleSignup() {
      isLoading = true;
      error = '';
  
      const { data, error: signupError } = await supabase.auth.signUp({
        email,
        password
      });
  
      if (signupError) {
        error = signupError.message;
      } else {
        user.set(data.user);
        // After signup, create a default profile for this user
        await supabase.from('profiles').insert({
          id: data.user.id,
          bankroll: 1000,
          games_played: 0,
          games_won: 0
        });
        await fetchUserProfile(data.user.id);
      }
  
      isLoading = false;
    }
  
    async function fetchUserProfile(userId) {
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', userId)
        .single();
  
      if (data) {
        userProfile.set(data);
      }
    }
  </script>
  
  <h1>Login or Sign Up</h1>
  
  <form on:submit|preventDefault={handleLogin}>
    <input type="email" bind:value={email} placeholder="Email" required />
    <input type="password" bind:value={password} placeholder="Password" required />
    <button disabled={isLoading}>Login</button>
  </form>
  
  <p>OR</p>
  
  <form on:submit|preventDefault={handleSignup}>
    <input type="email" bind:value={email} placeholder="Email" required />
    <input type="password" bind:value={password} placeholder="Password" required />
    <button disabled={isLoading}>Sign Up</button>
  </form>
  
  {#if error}
    <p style="color:red">{error}</p>
  {/if}
    