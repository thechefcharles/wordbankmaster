<script>
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';

    let isLoggedIn = false;
    let username = '';

    onMount(() => {
        if (typeof window !== 'undefined') {
            username = localStorage.getItem('username') || '';
            isLoggedIn = !!username;
            console.log('User Logged In:', isLoggedIn ? `Yes (Username: ${username})` : 'No');

            if (!isLoggedIn && window.location.pathname !== '/login') {
                goto('/login');
            }
        }
    });
</script>

{#if isLoggedIn}
    <slot />
{:else}
    <p>Redirecting to login...</p>
{/if}
