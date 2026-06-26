<script>
  import '../app.css';
  import { onMount } from 'svelte';
  import { supabase } from '$lib/supabaseClient';
  import { startNotifications, stopNotifications } from '$lib/stores/notificationStore.js';
  import { fx } from '$lib/sound.js';
  import Toaster from '$lib/components/Toaster.svelte';
  import PinConfirm from '$lib/components/PinConfirm.svelte';
  import ConfirmModal from '$lib/components/ConfirmModal.svelte';

  let { children } = $props();

  // Every button beeps + flashes gold on a REAL click/tap. Using 'click' (not
  // pointerdown/:active) means scrolling or brushing a button on a phone never
  // triggers it — click only fires on a genuine activation.
  /** @param {Event} e */
  function buttonPress(e) {
    const el = /** @type {HTMLElement} */ (e.target)?.closest?.('button, [role="button"]');
    if (!el || /** @type {HTMLButtonElement} */ (el).disabled) return;
    if (!el.classList.contains('key')) fx('tap'); // .key has its own 'select' cue
    el.classList.add('gold-flash');
    setTimeout(() => el.classList.remove('gold-flash'), 200);
  }
  onMount(() => {
    document.addEventListener('click', buttonPress, true);
    return () => document.removeEventListener('click', buttonPress, true);
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
      if (data.session) startNotifications(data.session.user?.id);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      if (session) startNotifications(session.user?.id);
      else stopNotifications();
    });
    return () => sub.subscription.unsubscribe();
  });
</script>

{@render children()}
<Toaster />
<PinConfirm />
<ConfirmModal />
