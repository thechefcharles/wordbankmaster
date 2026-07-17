# Push Notifications + Retention Engine — Design Spec

**Date:** 2026-07-17

## Goal

Native iOS push for WordBank, hooked into the existing `_notify` funnel so **every current and
future notification type gets push for free**, plus a retention engine (cron) to bring lapsed
players back.

## Confirmed config

| | |
|---|---|
| APNs Key ID | `FK7CVR37N2` (Team scoped, **Sandbox & Production**) |
| Team ID | `RRWC9ZHLUG` |
| Bundle ID | `com.wordbank.app` |
| `.p8` | local, gitignored — uploaded to Supabase as a secret by the owner (never in repo/git) |
| Supabase ref | `heckmdvnetatqgnsdtoz` |
| APNs host | `api.sandbox.push.apple.com` (dev builds) / `api.push.apple.com` (TestFlight+App Store) |

## Architecture

```
_notify(...) ──INSERT──> notifications ──trigger──> pg_net.http_post ──> Edge Function `push`
                                                                            │ signs ES256 JWT (.p8)
                                                                            ▼
                                                                    APNs ──> device
pg_cron (retention) ─────────────────────────────────────────────────> same Edge Function
```
- `_notify` is already the single funnel (12 emitters) → **zero feature code touched**.
- Edge Function (Deno) signs the APNs **ES256 JWT** via Web Crypto (plpgsql can't do ES256).
- `pg_net` (enabled, v0.14.0) makes the DB→Function call.

## Data model

- **`device_tokens`** (created): `user_id, token, platform, updated_at`, PK `(user_id, token)`,
  RLS on, self-SELECT only, writes revoked (registered via a SECURITY DEFINER RPC).
- **`profiles`** additions: `timezone text` (for quiet hours / local-time sends),
  `push_prefs jsonb NOT NULL DEFAULT '{"challenges":true,"social":true,"daily":true,"streak":true}'`.
- **`push_log`**: `user_id, kind, sent_at` — for rate-limiting/dedupe of retention sends
  (never send the same retention push twice in a day).

## Push policy (which `_notify` types actually push)

**Tier 1 — always push** (the async game breaks without them):
`challenge_incoming`, `challenge_your_turn`, `challenge_result`, + new `challenge_expiring`.

**Tier 2 — push (social/fun):**
`sabotaged`, `friend_request`, `friend_accepted`, `group_added`, `group_join`.

**Tier 3 — never push** (in-app only, noise):
`powerup_used`, `decline_match`, ownership transfer, and anything unlisted (default: no push).

Mapping lives in a `push_policy(type) -> category|null` SQL function; `null` = in-app only.
Category is checked against the user's `push_prefs` before sending.

## Retention engine (pg_cron → Edge Function)

Ordered by impact:
1. **🔥 Streak at risk** — `current_daily_play_streak >= 2` AND `last_daily_play_date < today` →
   fire ~3h before the user's local midnight. Mentions `streak_freezes` if they have one.
   *The single highest-value hook (loss aversion).*
2. **Daily reminder** — hasn't played today, at a sensible local hour (default 18:00).
3. **Challenge expiring** — match `settles_at` within ~2h and the player hasn't finished →
   "play or forfeit." (Reuses the existing `settle-expired-matches` cadence.)
4. *(later)* streak milestone, loan-interest nudge, broke win-back, leaderboard bump,
   lapsed D3/D7, weekly recap.

All retention sends: respect `push_prefs`, respect **quiet hours (no sends 22:00–08:00 local)**,
and dedupe via `push_log` (max one of each kind per user per day).

## Client

- `@capacitor/push-notifications` (v8.1.2, installed). Native-only — no-op on web (guard with
  `Capacitor.isNativePlatform()`).
- **Permission priming (critical — iOS gives ONE prompt, ever):** do NOT ask on launch. Show an
  in-app primer at a high-intent moment — right after the user creates/accepts their first
  challenge ("Want to know when they play?") — and only then call `requestPermissions()`.
  Remember the ask so we never re-prompt.
- On `registration` → save token via the RPC. On `registrationError` → log, no crash.
- **Deep links:** `pushNotificationActionPerformed` → route from `data` (existing convention:
  `match_id`, `group_id`, `route`) to the right screen.
- **Badge:** unread `notifications` count on the app icon; cleared on read.
- **Settings:** per-category toggles (Challenges / Social / Daily / Streak) writing `push_prefs`.

## Security

- The `.p8` NEVER enters the repo or git (already gitignored) — it lives only as a Supabase
  Edge Function secret, set by the owner.
- The Edge Function is service-role/secret-guarded; the DB trigger calls it with a shared secret
  so it can't be invoked by the public.
- `device_tokens` writes only via SECURITY DEFINER RPC keyed on `auth.uid()`.

## Testing

- Edge Function unit-ish: JWT signs, APNs accepts (a real send to the dev device).
- Trigger: inserting a `notifications` row of a Tier-1 type fires exactly one push; Tier-3 fires none.
- Prefs/quiet-hours/dedupe honored.
- **Device test** is the real gate — the app is already installed on the owner's iPhone.

## Out of scope

- Android/FCM (no Android build yet).
- Web push (no service worker; iOS web push needs a Home-Screen PWA — skip, we're native).
- Rich/media notifications, notification actions (v2).
