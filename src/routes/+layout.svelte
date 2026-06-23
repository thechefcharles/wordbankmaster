<script>
  import '../app.css';
  import { onMount } from 'svelte';
  import { supabase } from '$lib/supabaseClient';
  import { startNotifications, stopNotifications } from '$lib/stores/notificationStore.js';
  import Toaster from '$lib/components/Toaster.svelte';
  import PinConfirm from '$lib/components/PinConfirm.svelte';

  let { children } = $props();

  onMount(() => {
    // Start the global notification poller whenever a session is present,
    // and react to sign-in / sign-out across every route.
    supabase.auth.getSession().then(({ data }) => {
      if (data.session) startNotifications();
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      if (session) startNotifications();
      else stopNotifications();
    });
    return () => sub.subscription.unsubscribe();
  });
</script>

{@render children()}
<Toaster />
<PinConfirm />
