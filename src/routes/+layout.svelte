<script>
  import '../app.css';
  import { onMount } from 'svelte';
  import { supabase } from '$lib/supabaseClient';
  import { startNotifications, stopNotifications } from '$lib/stores/notificationStore.js';
  import { fx } from '$lib/sound.js';
  import Toaster from '$lib/components/Toaster.svelte';
  import PinConfirm from '$lib/components/PinConfirm.svelte';

  let { children } = $props();

  // Every button beeps on press, app-wide. touchstart no-op also enables :active on iOS.
  /** @param {Event} e */
  function buttonBeep(e) {
    const el = /** @type {HTMLElement} */ (e.target)?.closest?.('button, [role="button"]');
    // .key = keyboard letters (their own 'select' cue); skip so they don't double-beep.
    if (el && !(/** @type {HTMLButtonElement} */ (el).disabled) && !el.classList.contains('key')) fx('tap');
  }
  onMount(() => {
    document.addEventListener('pointerdown', buttonBeep, true);
    const noop = () => {};
    document.addEventListener('touchstart', noop, { passive: true });
    return () => { document.removeEventListener('pointerdown', buttonBeep, true); document.removeEventListener('touchstart', noop); };
  });

  onMount(() => {
    // "Keep me logged in" = off → end the session on a cold open (new browser
    // session) but not on in-app reloads. wb_sess marks the live browser session.
    try {
      const keep = localStorage.getItem('wb_keep');
      const sessActive = sessionStorage.getItem('wb_sess');
      if (keep === '0' && !sessActive) {
        supabase.auth.signOut().finally(() => { try { localStorage.removeItem('wb_keep'); } catch {} });
      } else {
        sessionStorage.setItem('wb_sess', '1');
      }
    } catch { /* storage blocked — keep default persistent session */ }

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
