# Bundling-Ready SPA — Design Spec

**Date:** 2026-07-17

## Goal

Make WordBank a client-side SPA (localStorage auth, no server routes) so it can bundle into
the native iOS app for App Store submission — while preserving current web behavior and keeping
the remote-shell dev loop (instant Vercel deploys) intact until we flip at submission time.

## Why

App Store review (Guidelines 2.5.2 / 4.2) flags apps that load remote content via `server.url`.
The fix is bundling the web assets into the binary — which requires a static build. A static
build can't contain SvelteKit server routes, and today auth depends on 4 server pieces:

- `+page.server.js` — SSR reads the session cookie, hydrates `data.user`.
- `auth/callback/+server.js` — exchanges OAuth `?code` for a session (server-side).
- `auth/confirm/+server.js` — `verifyOtp` for email recovery/confirm (server-side).
- `signout/+server.js` — clears httpOnly cookies.

All 4 exist ONLY because of the cookie/SSR session model (`@supabase/ssr` `createServerClient`).
The Supabase **client** can do every one of these itself, using localStorage — the standard
Capacitor pattern.

## Approach (chosen)

Convert to a client-rendered SPA with client-side auth. Keep `adapter-vercel` for now (it serves
an SPA fine); the actual `adapter-static` + drop-`server.url` flip happens at submission and is a
config change, not a code change. Web behavior is preserved throughout.

**Not doing:** a truly "parallel" static target alongside the SSR app — SvelteKit can't build a
static export while server routes exist, so there is no clean coexistence. This is the honest
version of "bundling-ready."

## Changes

1. **Session storage → localStorage.** Replace `createBrowserClient` (`@supabase/ssr`, cookie-based)
   with `createClient` (`@supabase/supabase-js`) configured `persistSession`, `autoRefreshToken`,
   `detectSessionInUrl`, `flowType: 'pkce'`. Works identically in a browser and the Capacitor WebView.
   - **One-time cost:** existing cookie sessions don't carry over → every logged-in user is signed
     out once and re-logs in. Acceptable at 40 pre-launch users.

2. **OAuth callback → client.** `detectSessionInUrl: true` makes the client auto-exchange `?code=`
   on load. `/auth/callback` becomes redundant.

3. **Email confirm/reset → client.** Convert `/auth/confirm` to client-side `verifyOtp` (a
   `+page.svelte`, or fold into the existing `/reset-password` page). Token-hash flow is cross-device
   and needs no code verifier, so it still works from any device.

4. **Signout → client.** `supabase.auth.signOut()` clears localStorage; drop the server route.

5. **Drop SSR hydration.** Remove `+page.server.js`; set `ssr = false` (root `+layout.js`). The app
   already re-checks the session client-side in `onMount`, so `data.user` is redundant.

6. **Verify a static build boots.** After 1–5, a throwaway local `adapter-static` build must build
   clean (no server routes) and boot in a browser + the Capacitor WebView. This proves flip-readiness
   without changing the deployed adapter.

## Order of work (risk-managed)

Each step verified with `scripts/qa-e2e.mjs` against **localhost** before moving on. Nothing deploys
to prod until the full email/password + OAuth + reset flow passes locally.

1. localStorage client (keep server routes as fallback) → verify email/password login + session
   persistence across reload.
2. Client-side OAuth + reset handling → verify Google/Apple + password reset.
3. `ssr = false` + drop `data.user` dependence → verify cold load shows correct auth state.
4. Remove the now-dead server routes.
5. Throwaway `adapter-static` build → verify boot. Do NOT change the committed adapter.

## Out of scope (deferred to submission)

- The actual `adapter-static` switch + removing `server.url` from `capacitor.config`.
- Native OAuth (`@capacitor/browser` + deep-link return) — `detectSessionInUrl` covers the
  WebView case for now; native-polished OAuth is a submission-time refinement.
- Enforced email verification (separate decision; unblocked once auth is client-side).
- OTA update strategy (so bundled apps can update without a full submission) — post-launch.

## Testing / rollback

- `qa-e2e.mjs` (localhost) is the gate at each step.
- Auth touches all users, so each step is small and independently revertible.
- The riskiest step is #1 (session storage). If login breaks, revert the single client file.
