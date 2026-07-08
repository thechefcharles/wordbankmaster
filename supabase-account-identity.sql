-- Phase 2 — Account identity: account_number (masked ••••NNNN) + sequential Member #.
-- Adds two columns to profiles, backfills all existing accounts (member_no in signup
-- order via auth.users.created_at), and sets column DEFAULTs so any future INSERT —
-- the on-signup trigger OR the client ensureProfileExists() fallback — auto-populates.
-- PITR checkpoint logged before apply.

BEGIN;

-- 1) Columns
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS account_number text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS member_no integer;

-- 2) Sequence backing the sequential Member #
CREATE SEQUENCE IF NOT EXISTS public.member_no_seq;

-- 3) Unique 12-digit account-number generator. SECURITY DEFINER so the uniqueness
--    check sees every row even when called from a client-side (RLS-scoped) INSERT.
CREATE OR REPLACE FUNCTION public._gen_account_number()
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $fn$
DECLARE n text;
BEGIN
  LOOP
    n := lpad((floor(random() * 1e12))::bigint::text, 12, '0');
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.profiles WHERE account_number = n);
  END LOOP;
  RETURN n;
END;
$fn$;

-- 4) Backfill Member # in signup order (earliest = #1)
WITH ordered AS (
  SELECT p.id, row_number() OVER (ORDER BY u.created_at, p.id) AS rn
  FROM public.profiles p
  JOIN auth.users u ON u.id = p.id
  WHERE p.member_no IS NULL
)
UPDATE public.profiles p
SET member_no = o.rn
FROM ordered o
WHERE p.id = o.id;

-- Advance the sequence past the highest assigned Member # (is_called = true → next is max+1)
SELECT setval('public.member_no_seq', COALESCE((SELECT MAX(member_no) FROM public.profiles), 0), true);

-- 5) Backfill account numbers
UPDATE public.profiles
SET account_number = public._gen_account_number()
WHERE account_number IS NULL;

-- 6) Defaults so future signups auto-populate (trigger insert + client fallback both omit these)
ALTER TABLE public.profiles ALTER COLUMN account_number SET DEFAULT public._gen_account_number();
ALTER TABLE public.profiles ALTER COLUMN member_no SET DEFAULT nextval('public.member_no_seq');

-- 7) Integrity
ALTER TABLE public.profiles ALTER COLUMN account_number SET NOT NULL;
ALTER TABLE public.profiles ALTER COLUMN member_no SET NOT NULL;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_account_number_key UNIQUE (account_number);
ALTER TABLE public.profiles ADD CONSTRAINT profiles_member_no_key UNIQUE (member_no);

COMMIT;
