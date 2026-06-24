# Launch follow-ups (come back to these)

Deferred items from the 2026-06-24 launch security pass (`get_advisors`). None are
launch-blocking; the critical Cash-minting exploit + RLS gaps were already fixed
(see `supabase-security-lockdown.sql`).

## Security hardening (deferred)
- [ ] **Function `search_path` hardening** — ~180 `SECURITY DEFINER` functions have a
      mutable `search_path` (`function_search_path_mutable`). Add `SET search_path = ''`
      (and schema-qualify references) per function. Do as a careful, tested batch.
- [ ] **Upgrade Postgres** — advisor flagged a vulnerable version. Dashboard →
      Settings → Infrastructure → upgrade (has downtime; schedule it).
- [ ] **Enable leaked-password protection** — Auth → Settings → turn on the
      HaveIBeenPwned check (`auth_leaked_password_protection`).
- [ ] Review the 9 `rls_enabled_no_policy` INFO tables — confirm deny-all is intended
      (it is for definer-RPC-only tables); add read policies only where a table is read
      directly by the client.

## Reminder / rule
Any NEW internal `SECURITY DEFINER` helper named `public._*` must
`REVOKE EXECUTE ON FUNCTION ... FROM anon, authenticated, PUBLIC` or PostgREST exposes
it directly (that was the Cash-minting hole).
