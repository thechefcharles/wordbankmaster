<script>
  import { supabase } from '$lib/supabaseClient';
  import { goto } from '$app/navigation';
  import { onMount } from 'svelte';

  let password = '';
  let confirmPassword = '';
  let message = '';
  let token = '';
  let isTokenReady = false;
  let success = false;

  onMount(() => {
    const hash = window.location.hash;
    const params = new URLSearchParams(hash.substring(1));
    token = params.get('access_token');
    const refresh_token = params.get('refresh_token');

    if (!token || !refresh_token) {
      message = '⛔ Invalid or missing reset token.';
      return;
    }

    supabase.auth.setSession({
      access_token: token,
      refresh_token
    }).then(({ error }) => {
      if (error) {
        message = `❌ Failed to authenticate: ${error.message}`;
        success = false;
      } else {
        isTokenReady = true;
        message = '';
        success = false;
      }
    });
  });

  async function updatePassword() {
    if (!password || !confirmPassword) {
      message = '⚠️ Please enter and confirm your password.';
      success = false;
      return;
    }

    if (password !== confirmPassword) {
      message = '❌ Passwords do not match.';
      success = false;
      return;
    }

    const { error } = await supabase.auth.updateUser({ password });

    if (error) {
      message = `❌ ${error.message}`;
      success = false;
    } else {
      message = '✅ Password updated! Redirecting...';
      success = true;
      setTimeout(() => goto('/'), 2000);
    }
  }
</script>

<main class="reset-wrapper">
  <h2>🔑 Reset Your Password</h2>

  {#if message}
    <p class="message {success ? 'success' : 'error'}">{message}</p>
  {/if}

  {#if isTokenReady}
    <input type="password" placeholder="New Password" bind:value={password} />
    <input type="password" placeholder="Confirm Password" bind:value={confirmPassword} />
    <button on:click={updatePassword}>Update Password</button>
  {/if}
</main>

<style>
  .reset-wrapper {
    max-width: 400px;
    margin: 60px auto;
    padding: 1rem;
    text-align: center;
  }

  input {
    display: block;
    width: 100%;
    margin: 0.5rem 0;
    padding: 0.75rem;
    font-size: 1rem;
  }

  button {
    background: limegreen;
    color: white;
    font-weight: bold;
    padding: 10px 16px;
    border: none;
    border-radius: 6px;
    cursor: pointer;
  }

  .message {
    margin: 1rem 0;
    font-weight: bold;
  }

  .message.success {
    color: green;
  }

  .message.error {
    color: red;
  }
</style>
