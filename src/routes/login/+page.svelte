<script>
    import { goto } from '$app/navigation';

    let username = '';

    function handleLogin() {
        if (username.trim() !== '') {
            localStorage.setItem('username', username);
            goto('/');
        }
    }
</script>

<main class="login-container">
    <h1>Welcome to WordBank</h1>
    <input type="text" bind:value={username} placeholder="Enter your username..." />
    <button on:click={handleLogin}>Login</button>
</main>

<style>
    .login-container {
        text-align: center;
        max-width: 400px;
        margin: auto;
        font-family: Arial, sans-serif;
    }
    input {
        width: 80%;
        padding: 10px;
        font-size: 1.2em;
        margin-top: 10px;
    }
    button {
        padding: 10px 20px;
        font-size: 1.2em;
        margin-top: 10px;
        cursor: pointer;
    }
</style>
