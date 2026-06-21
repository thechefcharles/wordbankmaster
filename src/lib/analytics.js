// First-party product analytics. Fire-and-forget: track() must NEVER throw or
// block the UI. Events are stamped with user_id server-side by the log_event RPC.
import { supabase } from '$lib/supabaseClient';

/** @type {string|null} */
let _session = null;
function sessionId() {
  if (_session) return _session;
  try { _session = crypto.randomUUID(); }
  catch { _session = `${Date.now()}-${Math.floor(Math.random() * 1e9)}`; }
  return _session;
}

/** web | pwa | ios — so we can split traffic by surface. */
function platform() {
  if (typeof window === 'undefined') return 'ssr';
  const ua = navigator.userAgent || '';
  const cap = /** @type {any} */ (window).Capacitor;
  if (/WordBankApp/i.test(ua) || (cap && (cap.isNativePlatform ? cap.isNativePlatform() : cap.isNative))) return 'ios';
  const standalone = (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches)
    || /** @type {any} */ (window.navigator).standalone === true;
  return standalone ? 'pwa' : 'web';
}

/**
 * Record a product event. Never awaits in callers; swallows all errors.
 * @param {string} name
 * @param {Record<string, any>} [props]
 */
export function track(name, props = {}) {
  try {
    supabase.rpc('log_event', {
      p_name: name,
      p_props: props ?? {},
      p_session: sessionId(),
      p_platform: platform()
    }).then(() => {}, () => {}); // ignore success + failure
  } catch { /* analytics must never break the app */ }
}
