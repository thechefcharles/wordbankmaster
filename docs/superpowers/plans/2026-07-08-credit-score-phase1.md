# Credit Score — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a read-only credit score (300–850) — server-computed from financial-discipline signals, stored on the profile, lazily recomputed in `get_bank`, and shown as a `CreditGauge` with a breakdown on the My Account (`/bank`) screen. **No loan effects yet** (that's Phase 2).

**Architecture:** All scoring math lives in one `SECURITY DEFINER` Postgres function `_recompute_credit(uid, event, event_delta)` that derives five components from a 14-day `bank_ledger` window + current profile state, eases the stored score toward a computed target (bounded per day), and appends a `credit_history` row. `get_bank` calls it lazily (at most once/calendar-day on read) and adds `credit_score`/`credit_tier`/`credit_delta` to its JSON. A new `get_credit_detail()` RPC returns the full component breakdown + a sparkline. The frontend adds a `getCreditDetail()` store getter and a `CreditGauge.svelte` component mounted on `/bank`.

**Tech Stack:** SvelteKit 2.16 (Svelte 4 mode in the pages we touch), Supabase Postgres (plpgsql, `SECURITY DEFINER`), Playwright preview screenshots, psql for DB verification.

## Global Constraints

- **Score range:** integer `[300, 850]`; new-account default `650`. — verbatim from spec §3.
- **Component weights:** Utilization 35% · Solvency 25% · Repayment 20% · Restraint 10% · Consistency 10% (sum = 100%). — spec §3.1.
- **Target formula:** `T = round(300 + 550 × (0.35·U + 0.25·S + 0.20·R + 0.10·B + 0.10·C))`. — spec §3.1.
- **Movement caps:** `DROP_CAP = 120`/day, `RISE_CAP = 40`/day. — spec §3.2.
- **New-player grace:** first **7 days** after `profiles.created_at` (or until first loan) → score pinned at `650`, treated as **Good**. — spec §3.
- **Derogatory mark:** default event = `−100` + `credit_derog_until = now() + 30 days`; while active, Repayment component `R` is capped at `0.3`. — spec §3.2, §10.
- **Bands:** Excellent 780–850 · Good 670–779 · Fair 580–669 · Poor 400–579 · Bad 300–399. — spec §4.
- **Phase 1 is read-only:** do **not** modify `_loan_cap`, `_loan_daily_rate_bp`, or `take_loan`. Those are Phase 2.
- **DB workflow:** log the UTC timestamp (PITR point) before every apply; apply against `SUPABASE_DB_URL`; each migration is a new `supabase-credit-*.sql` file kept in-repo. — memory `wordbank-db-management`.
- **All new RPCs:** `SECURITY DEFINER`, key on `auth.uid()`, `GRANT EXECUTE … TO authenticated`.
- **Gates before every commit that touches `src/`:** `npx prettier --write` → `npm run check` → `npm run lint` → `npm run build`. — memory `wordbank-qa-harness`.
- **Verify UI in a preview build**, not dev HMR (dev drops scoped styles). Preview: `npm run preview -- --port 4173`.

---

## File map

- Create `supabase-credit-score-schema.sql` — columns on `profiles`, `credit_history` table, `_credit_tier(int)` helper.
- Create `supabase-credit-score-recompute.sql` — `_recompute_credit(uuid, text, int)`.
- Create `supabase-credit-score-getbank.sql` — patch `get_bank(p_limit)` for lazy recompute + payload; add `get_credit_detail()`.
- Modify `src/lib/stores/statsStore.js` — add `getCreditDetail()`; extend the `getBank` JSDoc return type.
- Create `src/lib/components/CreditGauge.svelte` — the dial + tier + delta, tap → breakdown.
- Modify `src/routes/bank/+page.svelte` — mount `<CreditGauge>` under the account card; load `getCreditDetail()`.

Helper for all DB steps — open a psql session with:

```bash
set -a; . ./.env; set +a
psql "$SUPABASE_DB_URL"
```

Simulate a user inside psql with:

```sql
SELECT set_config('request.jwt.claims', json_build_object('sub', '<UID>')::text, true);
```

---

## Task 1: DB schema + tier helper

**Files:**

- Create: `supabase-credit-score-schema.sql`

**Interfaces:**

- Produces: `profiles.credit_score int`, `profiles.credit_updated_at timestamptz`, `profiles.credit_derog_until timestamptz`; table `public.credit_history(user_id, at, score, target, tier, components)`; function `public._credit_tier(int) → text` returning one of `Excellent|Good|Fair|Poor|Bad`.

- [ ] **Step 1: Write the migration file**

Create `supabase-credit-score-schema.sql`:

```sql
-- Credit Score Phase 1 — storage + tier helper. Read-only; no loan effects yet.
-- PITR point logged before apply (see below).
BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS credit_score       INT         NOT NULL DEFAULT 650,
  ADD COLUMN IF NOT EXISTS credit_updated_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS credit_derog_until TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS public.credit_history (
  id         BIGSERIAL PRIMARY KEY,
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  score      INT  NOT NULL,
  target     INT  NOT NULL,
  tier       TEXT NOT NULL,
  components JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_credit_history_user_time
  ON public.credit_history(user_id, at DESC);

CREATE OR REPLACE FUNCTION public._credit_tier(p_score INT)
  RETURNS TEXT LANGUAGE sql IMMUTABLE AS $fn$
  SELECT CASE
    WHEN p_score >= 780 THEN 'Excellent'
    WHEN p_score >= 670 THEN 'Good'
    WHEN p_score >= 580 THEN 'Fair'
    WHEN p_score >= 400 THEN 'Poor'
    ELSE 'Bad'
  END;
$fn$;

COMMIT;
```

- [ ] **Step 2: Log the PITR point (verify-it-fails analogue)**

Run in psql — capture the current time so we can roll back if needed, and prove the columns do NOT yet exist:

```sql
SELECT now() AT TIME ZONE 'utc' AS pitr_point;
SELECT column_name FROM information_schema.columns
 WHERE table_name='profiles' AND column_name LIKE 'credit%';
```

Expected: `pitr_point` prints; the second query returns **0 rows**.

- [ ] **Step 3: Apply the migration**

```bash
set -a; . ./.env; set +a
psql "$SUPABASE_DB_URL" -f supabase-credit-score-schema.sql
```

Expected: `BEGIN … COMMIT`, no errors.

- [ ] **Step 4: Verify schema + tier boundaries**

Run in psql:

```sql
SELECT column_name FROM information_schema.columns
 WHERE table_name='profiles' AND column_name LIKE 'credit%' ORDER BY 1;
SELECT public._credit_tier(850) AS s850, public._credit_tier(780) AS s780,
       public._credit_tier(779) AS s779, public._credit_tier(670) AS s670,
       public._credit_tier(580) AS s580, public._credit_tier(400) AS s400,
       public._credit_tier(399) AS s399;
```

Expected: 3 credit columns listed; tiers = `Excellent, Excellent, Good, Good, Fair, Poor, Bad`.

- [ ] **Step 5: Commit**

```bash
git add supabase-credit-score-schema.sql
git commit -m "Credit score: profiles columns + credit_history + _credit_tier"
```

---

## Task 2: `_recompute_credit` function

**Files:**

- Create: `supabase-credit-score-recompute.sql`

**Interfaces:**

- Consumes: `_credit_tier(int)`, `_loan_cap(uuid)`, `_ensure_bank(uuid)`, `bank_ledger`, `profiles(credit_score, credit_updated_at, credit_derog_until, created_at, bank, loan, streak)`.
- Produces: `public._recompute_credit(p_uid UUID, p_event TEXT DEFAULT NULL, p_event_delta INT DEFAULT 0) → INT` (new score). Writes `profiles.credit_score`/`credit_updated_at`, appends `credit_history`. Applies grace, per-day ease clamp, and multi-day catch-up (≤7 eases).

- [ ] **Step 1: Write the function file**

Create `supabase-credit-score-recompute.sql`:

```sql
-- Credit Score Phase 1 — core recompute. Derives 5 discipline components from a
-- 14-day bank_ledger window, eases the stored score toward a target (bounded per
-- day), applies new-player grace + derogatory cap + event jolts, logs history.
-- PITR point logged before apply.
BEGIN;

CREATE OR REPLACE FUNCTION public._recompute_credit(
  p_uid UUID,
  p_event TEXT DEFAULT NULL,
  p_event_delta INT DEFAULT 0
) RETURNS INT LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  DROP_CAP CONSTANT INT := 120;
  RISE_CAP CONSTANT INT := 40;
  v_bank BIGINT; v_loan BIGINT; v_created TIMESTAMPTZ;
  v_prev INT; v_updated TIMESTAMPTZ; v_derog TIMESTAMPTZ; v_streak INT;
  v_cap BIGINT;
  u NUMERIC; s NUMERIC; r NUMERIC; b NUMERIC; c NUMERIC;
  v_neg_days INT; v_repay INT; v_skim INT; v_take INT; v_active_days INT;
  v_target INT; v_new INT; v_days_elapsed INT; i INT;
  v_had_loan BOOLEAN;
BEGIN
  PERFORM public._ensure_bank(p_uid);
  SELECT bank, loan, created_at, credit_score, credit_updated_at, credit_derog_until,
         COALESCE(streak, 0)
    INTO v_bank, v_loan, v_created, v_prev, v_updated, v_derog, v_streak
    FROM public.profiles WHERE id = p_uid;
  v_prev := COALESCE(v_prev, 650);

  -- Has this user ever taken a loan? (ends grace early)
  SELECT (v_loan > 0) OR EXISTS(
    SELECT 1 FROM public.bank_ledger WHERE user_id = p_uid AND reason = 'loan_take'
  ) INTO v_had_loan;

  -- New-player grace: first 7 days and no loan yet → pin 650 / Good.
  IF v_created IS NOT NULL AND v_created > now() - INTERVAL '7 days' AND NOT v_had_loan THEN
    UPDATE public.profiles
       SET credit_score = 650, credit_updated_at = now() WHERE id = p_uid;
    INSERT INTO public.credit_history(user_id, score, target, tier, components)
      VALUES (p_uid, 650, 650, 'Good', jsonb_build_object('grace', true));
    RETURN 650;
  END IF;

  v_cap := GREATEST(public._loan_cap(p_uid), 1);

  -- Utilization (35%): 1 - current loan/cap.
  u := 1 - LEAST(v_loan::numeric / v_cap, 1);

  -- Solvency (25%): 1 - (distinct days in last 14 with a negative balance)/14.
  SELECT COUNT(DISTINCT date(created_at)) INTO v_neg_days
    FROM public.bank_ledger
   WHERE user_id = p_uid AND created_at > now() - INTERVAL '14 days'
     AND balance_after < 0;
  s := 1 - LEAST(v_neg_days::numeric / 14, 1);
  IF (v_bank - v_loan) < 0 THEN s := LEAST(s, 0.5); END IF; -- currently in the red

  -- Repayment (20%): repays / (repays + skims) over 14 days; 1 if no loans closed.
  SELECT COUNT(*) FILTER (WHERE reason = 'loan_repay'),
         COUNT(*) FILTER (WHERE reason = 'loan_skim'),
         COUNT(*) FILTER (WHERE reason = 'loan_take')
    INTO v_repay, v_skim, v_take
    FROM public.bank_ledger
   WHERE user_id = p_uid AND created_at > now() - INTERVAL '14 days';
  r := CASE WHEN (v_repay + v_skim) = 0 THEN 1
            ELSE v_repay::numeric / (v_repay + v_skim) END;
  IF v_derog IS NOT NULL AND v_derog > now() THEN r := LEAST(r, 0.3); END IF;

  -- Restraint (10%): 1 - min(takes/6, 1).
  b := 1 - LEAST(v_take::numeric / 6, 1);

  -- Consistency (10%): min(streak/14, 1), falling back to distinct active days.
  IF v_streak > 0 THEN
    c := LEAST(v_streak::numeric / 14, 1);
  ELSE
    SELECT COUNT(DISTINCT date(created_at)) INTO v_active_days
      FROM public.bank_ledger
     WHERE user_id = p_uid AND created_at > now() - INTERVAL '14 days';
    c := LEAST(v_active_days::numeric / 14, 1);
  END IF;

  v_target := round(300 + 550 * (0.35*u + 0.25*s + 0.20*r + 0.10*b + 0.10*c));
  v_target := GREATEST(300, LEAST(850, v_target));

  -- Multi-day catch-up: one ease per elapsed calendar day, capped at 7.
  v_days_elapsed := GREATEST(1, LEAST(7,
    COALESCE(date_part('day', now() - v_updated)::int, 1)));
  v_new := v_prev;
  FOR i IN 1..v_days_elapsed LOOP
    v_new := v_new + GREATEST(LEAST(v_target - v_new, RISE_CAP), -DROP_CAP);
  END LOOP;

  v_new := GREATEST(300, LEAST(850, v_new + COALESCE(p_event_delta, 0)));

  UPDATE public.profiles
     SET credit_score = v_new, credit_updated_at = now() WHERE id = p_uid;
  INSERT INTO public.credit_history(user_id, score, target, tier, components)
    VALUES (p_uid, v_new, v_target, public._credit_tier(v_new),
      jsonb_build_object('U',round(u,3),'S',round(s,3),'R',round(r,3),
                         'B',round(b,3),'C',round(c,3),'event',p_event));
  RETURN v_new;
END; $fn$;

GRANT EXECUTE ON FUNCTION public._recompute_credit(UUID, TEXT, INT) TO authenticated;
COMMIT;
```

- [ ] **Step 2: Log PITR + prove it fails**

In psql:

```sql
SELECT now() AT TIME ZONE 'utc' AS pitr_point;
SELECT public._recompute_credit('00000000-0000-0000-0000-000000000000');
```

Expected: `pitr_point` prints; the call ERRORs with `function public._recompute_credit(...) does not exist`.

- [ ] **Step 3: Apply**

```bash
psql "$SUPABASE_DB_URL" -f supabase-credit-score-recompute.sql
```

Expected: `BEGIN … COMMIT`.

- [ ] **Step 4: Verify with a real user (grace + normal paths)**

Pick a real UID (`SELECT id, created_at FROM public.profiles LIMIT 1;`). Then:

```sql
-- Force out of grace so we exercise the real math: backdate created_at in a tx we roll back.
BEGIN;
UPDATE public.profiles SET created_at = now() - INTERVAL '30 days',
       credit_updated_at = now() - INTERVAL '1 day', credit_score = 650
 WHERE id = '<UID>';
SELECT public._recompute_credit('<UID>') AS new_score;
SELECT score, target, tier, components FROM public.credit_history
 WHERE user_id = '<UID>' ORDER BY at DESC LIMIT 1;
ROLLBACK;
```

Expected: `new_score` in [300,850]; a `credit_history` row with `components` containing `U/S/R/B/C`; `tier` matching the score band. (ROLLBACK restores `created_at`.)

- [ ] **Step 5: Verify the daily-drop cap**

```sql
BEGIN;
UPDATE public.profiles SET created_at = now() - INTERVAL '30 days',
       credit_updated_at = now() - INTERVAL '1 day', credit_score = 820,
       loan = public._loan_cap('<UID>')  -- max utilization → low target
 WHERE id = '<UID>';
SELECT public._recompute_credit('<UID>') AS after_one_day;  -- expect ~820-120=700, not a full crash
ROLLBACK;
```

Expected: `after_one_day` ≈ `700` (drop clamped to 120), **not** near 300.

- [ ] **Step 6: Commit**

```bash
git add supabase-credit-score-recompute.sql
git commit -m "Credit score: _recompute_credit (components, ease, grace, derog)"
```

---

## Task 3: Lazy recompute in `get_bank` + `get_credit_detail()`

**Files:**

- Create: `supabase-credit-score-getbank.sql`

**Interfaces:**

- Consumes: `_recompute_credit`, `_credit_tier`, existing `get_bank(p_limit)`.
- Produces: `get_bank` JSON gains `credit_score INT`, `credit_tier TEXT`, `credit_delta INT` (vs the prior `credit_history` row). New RPC `public.get_credit_detail() → JSONB` = `{ score, target, tier, delta, components:{utilization,solvency,repayment,restraint,consistency}, history:[{at,score}] }` where each component is `{ value:0..1, label, hint }`.

- [ ] **Step 1: Copy the current `get_bank` body to edit from**

Run: `psql "$SUPABASE_DB_URL" -c "\sf public.get_bank"` (note: there is a `p_limit` overload from `supabase-getbank-limit.sql` — target that signature). Confirm the exact current signature before editing so the new file `CREATE OR REPLACE`s the same one.

- [ ] **Step 2: Write the patch file**

Create `supabase-credit-score-getbank.sql` (adjust the `get_bank` signature/body to match Step 1's output; the credit additions are the point):

```sql
-- Credit Score Phase 1 — surface credit in get_bank (lazy daily recompute) and add
-- get_credit_detail() for the gauge breakdown. PITR point logged before apply.
BEGIN;

-- Recompute at most once per calendar day on read; return current score+tier+delta.
CREATE OR REPLACE FUNCTION public._credit_read(p_uid UUID)
  RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_score INT; v_upd TIMESTAMPTZ; v_prev INT;
BEGIN
  SELECT credit_score, credit_updated_at INTO v_score, v_upd
    FROM public.profiles WHERE id = p_uid;
  IF v_upd IS NULL OR v_upd::date < current_date THEN
    -- previous score for delta (last history row before this recompute)
    SELECT score INTO v_prev FROM public.credit_history
      WHERE user_id = p_uid ORDER BY at DESC LIMIT 1;
    v_score := public._recompute_credit(p_uid);
    RETURN jsonb_build_object('credit_score', v_score,
      'credit_tier', public._credit_tier(v_score),
      'credit_delta', v_score - COALESCE(v_prev, v_score));
  END IF;
  RETURN jsonb_build_object('credit_score', COALESCE(v_score,650),
    'credit_tier', public._credit_tier(COALESCE(v_score,650)),
    'credit_delta', 0);
END; $fn$;

-- get_bank: merge the credit fields into the existing payload.
CREATE OR REPLACE FUNCTION public.get_bank(p_limit INT DEFAULT 12)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid UUID := auth.uid(); v_bank BIGINT; v_loan BIGINT; v_led JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  PERFORM public._ensure_bank(v_uid);
  SELECT bank, loan INTO v_bank, v_loan FROM public.profiles WHERE id = v_uid;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('delta',delta,'reason',reason,
           'balance_after',balance_after,'at',created_at) ORDER BY created_at DESC),'[]'::jsonb)
    INTO v_led FROM (SELECT * FROM public.bank_ledger WHERE user_id = v_uid
                      ORDER BY created_at DESC LIMIT p_limit) t;
  RETURN jsonb_build_object('bank', COALESCE(v_bank,0), 'loan', COALESCE(v_loan,0),
           'net_worth', COALESCE(v_bank,0) - COALESCE(v_loan,0), 'ledger', v_led)
         || public._credit_read(v_uid);
END; $$;
GRANT EXECUTE ON FUNCTION public.get_bank(INT) TO authenticated;

-- Full breakdown for the gauge detail view.
CREATE OR REPLACE FUNCTION public.get_credit_detail()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid UUID := auth.uid(); v_score INT; v_target INT; v_comp JSONB; v_hist JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  PERFORM public._credit_read(v_uid); -- ensure fresh
  SELECT score, target, components INTO v_score, v_target, v_comp
    FROM public.credit_history WHERE user_id = v_uid ORDER BY at DESC LIMIT 1;
  v_score := COALESCE(v_score, 650);
  SELECT COALESCE(jsonb_agg(jsonb_build_object('at', at, 'score', score) ORDER BY at), '[]')
    INTO v_hist FROM (SELECT at, score FROM public.credit_history
                       WHERE user_id = v_uid ORDER BY at DESC LIMIT 30) h;
  RETURN jsonb_build_object(
    'score', v_score, 'target', COALESCE(v_target, v_score),
    'tier', public._credit_tier(v_score), 'history', v_hist,
    'components', jsonb_build_object(
      'utilization', jsonb_build_object('value', COALESCE((v_comp->>'U')::numeric,1),
        'label','Utilization','hint','Repay loans and keep debt low.'),
      'solvency', jsonb_build_object('value', COALESCE((v_comp->>'S')::numeric,1),
        'label','Solvency','hint','Stay out of the red.'),
      'repayment', jsonb_build_object('value', COALESCE((v_comp->>'R')::numeric,1),
        'label','Repayment','hint','Repay loans yourself before they auto-collect.'),
      'restraint', jsonb_build_object('value', COALESCE((v_comp->>'B')::numeric,1),
        'label','Restraint','hint','Avoid frequent borrowing.'),
      'consistency', jsonb_build_object('value', COALESCE((v_comp->>'C')::numeric,1),
        'label','Consistency','hint','Play daily to build history.')));
END; $$;
GRANT EXECUTE ON FUNCTION public.get_credit_detail() TO authenticated;
COMMIT;
```

- [ ] **Step 3: Log PITR + apply**

```bash
psql "$SUPABASE_DB_URL" -c "SELECT now() AT TIME ZONE 'utc';"
psql "$SUPABASE_DB_URL" -f supabase-credit-score-getbank.sql
```

Expected: `BEGIN … COMMIT`.

- [ ] **Step 4: Verify payload + detail as a real user**

In psql:

```sql
SELECT set_config('request.jwt.claims', json_build_object('sub','<UID>')::text, true);
SELECT public.get_bank(5) -> 'credit_score' AS score,
       public.get_bank(5) -> 'credit_tier'  AS tier;
SELECT public.get_credit_detail() -> 'components' -> 'utilization';
```

Expected: `score` is a number 300–850; `tier` a band string; the component object has `value/label/hint`.

- [ ] **Step 5: Commit**

```bash
git add supabase-credit-score-getbank.sql
git commit -m "Credit score: lazy recompute in get_bank + get_credit_detail RPC"
```

---

## Task 4: Store getter + types

**Files:**

- Modify: `src/lib/stores/statsStore.js`

**Interfaces:**

- Consumes: `get_bank` (now returns credit fields), `get_credit_detail`.
- Produces: `getCreditDetail()` → the detail object (or `null`); `getBank`'s JSDoc return type documents `credit_score`, `credit_tier`, `credit_delta`.

- [ ] **Step 1: Add the getter next to `getBank`**

In `src/lib/stores/statsStore.js`, immediately after the `getBank` function, add:

```js
/** Full credit-score breakdown for the gauge detail view. Returns null if signed out. */
export async function getCreditDetail() {
	const { data, error } = await supabase.rpc('get_credit_detail');
	if (error) {
		console.error('getCreditDetail', error);
		return null;
	}
	return data;
}
```

- [ ] **Step 2: Extend the `getBank` JSDoc**

Find the JSDoc `@returns` (or the type comment) on `getBank` and append the three fields so consumers see them, e.g. add to the documented shape: `credit_score:number, credit_tier:string, credit_delta:number`. (If `getBank` has no typed return, add a one-line `/** … credit_score/credit_tier/credit_delta included … */` above it.)

- [ ] **Step 3: Gate**

Run:

```bash
npx prettier --write src/lib/stores/statsStore.js
npm run check
```

Expected: prettier reformats/clean; svelte-check `0 errors`.

- [ ] **Step 4: Commit**

```bash
git add src/lib/stores/statsStore.js
git commit -m "Credit score: getCreditDetail() store getter"
```

---

## Task 5: `CreditGauge.svelte` component

**Files:**

- Create: `src/lib/components/CreditGauge.svelte`

**Interfaces:**

- Consumes (props): `score:number`, `tier:string`, `delta:number = 0`, and `detail` (the `getCreditDetail()` object, or `null` while loading).
- Produces: a self-contained gauge; tapping it toggles an inline breakdown panel built from `detail.components`. No external calls (parent passes data in).

- [ ] **Step 1: Write the component**

Create `src/lib/components/CreditGauge.svelte`:

```svelte
<script>
	// 💳 Credit score gauge — 300–850 arc dial + tier + delta, tap for breakdown.
	export let score = 650;
	export let tier = 'Good';
	export let delta = 0;
	/** @type {any} */ export let detail = null;

	let open = false;
	const MIN = 300,
		MAX = 850;
	// Arc: 300° sweep from 120° (bottom-left) clockwise. Map score → angle → dash.
	$: pct = Math.max(0, Math.min(1, (score - MIN) / (MAX - MIN)));
	const R = 80,
		C = 2 * Math.PI * R,
		SWEEP = 0.75; // 3/4 circle
	$: dash = pct * C * SWEEP;
	$: tierColor =
		tier === 'Excellent'
			? '#34d399'
			: tier === 'Good'
				? '#fbbf24'
				: tier === 'Fair'
					? '#f59e0b'
					: tier === 'Poor'
						? '#fb7185'
						: '#ef4444';
	$: comps = detail?.components
		? [
				detail.components.utilization,
				detail.components.solvency,
				detail.components.repayment,
				detail.components.restraint,
				detail.components.consistency
			].filter(Boolean)
		: [];
</script>

<div class="cg">
	<button class="cg-face" on:click={() => (open = !open)} aria-expanded={open}>
		<svg viewBox="0 0 200 200" class="cg-svg">
			<circle
				class="cg-track"
				cx="100"
				cy="100"
				r="80"
				stroke-dasharray="{C * 0.75} {C}"
				transform="rotate(135 100 100)"
			/>
			<circle
				class="cg-fill"
				cx="100"
				cy="100"
				r="80"
				stroke={tierColor}
				stroke-dasharray="{dash} {C}"
				transform="rotate(135 100 100)"
			/>
		</svg>
		<div class="cg-center">
			<span class="cg-score">{score}</span>
			<span class="cg-tier" style="color:{tierColor}">{tier}</span>
			{#if delta !== 0}
				<span class="cg-delta" class:pos={delta > 0} class:neg={delta < 0}
					>{delta > 0 ? '▲' : '▼'} {Math.abs(delta)}</span
				>
			{/if}
		</div>
	</button>
	{#if open && comps.length}
		<div class="cg-breakdown">
			{#each comps as c}
				<div class="cg-row">
					<span class="cg-rlabel">{c.label}</span>
					<span class="cg-bar"
						><span
							class="cg-barfill"
							style="width:{Math.round((c.value ?? 0) * 100)}%; background:{tierColor}"
						></span></span
					>
					<span class="cg-rhint">{c.hint}</span>
				</div>
			{/each}
		</div>
	{/if}
</div>

<style>
	.cg {
		width: 100%;
	}
	.cg-face {
		position: relative;
		width: 200px;
		max-width: 60%;
		margin: 0 auto;
		display: block;
		background: none;
		border: none;
		cursor: pointer;
		padding: 0;
	}
	.cg-svg {
		width: 100%;
		height: auto;
		display: block;
	}
	.cg-track {
		fill: none;
		stroke: var(--border, rgba(255, 255, 255, 0.1));
		stroke-width: 14;
		stroke-linecap: round;
	}
	.cg-fill {
		fill: none;
		stroke-width: 14;
		stroke-linecap: round;
		transition: stroke-dasharray 0.6s var(--ease-spring, ease);
	}
	.cg-center {
		position: absolute;
		inset: 0;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 2px;
	}
	.cg-score {
		font-family: var(--font-display, sans-serif);
		font-size: 2rem;
		font-weight: 800;
	}
	.cg-tier {
		font-size: 0.8rem;
		font-weight: 700;
		letter-spacing: 0.06em;
		text-transform: uppercase;
	}
	.cg-delta {
		font-size: 0.72rem;
		font-weight: 700;
	}
	.cg-delta.pos {
		color: #34d399;
	}
	.cg-delta.neg {
		color: #fb7185;
	}
	.cg-breakdown {
		display: flex;
		flex-direction: column;
		gap: 8px;
		margin-top: 10px;
	}
	.cg-row {
		display: grid;
		grid-template-columns: 84px 1fr;
		grid-template-rows: auto auto;
		gap: 2px 8px;
		align-items: center;
	}
	.cg-rlabel {
		font-size: 0.78rem;
		font-weight: 700;
		color: var(--text);
	}
	.cg-bar {
		height: 7px;
		border-radius: 999px;
		background: var(--border, rgba(255, 255, 255, 0.1));
		overflow: hidden;
	}
	.cg-barfill {
		display: block;
		height: 100%;
		border-radius: 999px;
	}
	.cg-rhint {
		grid-column: 1 / -1;
		font-size: 0.72rem;
		color: var(--text-muted);
	}
</style>
```

- [ ] **Step 2: Gate the build**

Run:

```bash
npx prettier --write src/lib/components/CreditGauge.svelte
npm run check
npm run build
```

Expected: prettier clean; svelte-check `0 errors`; build OK.

- [ ] **Step 3: Commit**

```bash
git add src/lib/components/CreditGauge.svelte
git commit -m "Credit score: CreditGauge component (dial + breakdown)"
```

---

## Task 6: Mount on My Account + verify end-to-end

**Files:**

- Modify: `src/routes/bank/+page.svelte`

**Interfaces:**

- Consumes: `getCreditDetail()`, the `credit_score`/`credit_tier`/`credit_delta` fields already on the `getBank` result (`b`), `CreditGauge.svelte`.

- [ ] **Step 1: Import + load the detail**

In `src/routes/bank/+page.svelte` `<script>`, add the imports and a `cd` (credit detail) load alongside the existing `getProfileDetail`/`getBank`:

```js
import CreditGauge from '$lib/components/CreditGauge.svelte';
import { getBank, getProfileDetail, getCreditDetail } from '$lib/stores/statsStore.js';
```

Add state `let cd = null;` and load it in `onMount` — extend the existing `Promise.all`:

```js
[prof, cd] = await Promise.all([getProfileDetail(), getCreditDetail(), load()]).then((r) => [
	r[0],
	r[1]
]);
```

(Keep `load()` setting `b`; the `.then` just picks `prof` and `cd`.)

- [ ] **Step 2: Render the gauge under the account card**

Directly after the `.ac-hero` block (the `<AccountCard …/>` wrapper) and before `<LoanPanel …>`, add:

```svelte
<!-- 💳 Credit score -->
{#if b}
	<section class="credit-sec">
		<h2 class="hist-title">Credit Score</h2>
		<CreditGauge
			score={b.credit_score ?? 650}
			tier={b.credit_tier ?? 'Good'}
			delta={b.credit_delta ?? 0}
			detail={cd}
		/>
	</section>
{/if}
```

Add to `<style>`:

```css
.credit-sec {
	margin: 4px 0 16px;
}
.credit-sec .hist-title {
	text-align: center;
	margin-bottom: 8px;
}
```

- [ ] **Step 3: Gate**

```bash
npx prettier --write src/routes/bank/+page.svelte
npm run check
npm run lint
npm run build
```

Expected: all clean; build OK.

- [ ] **Step 4: Preview screenshot verification**

```bash
pkill -f "vite preview" 2>/dev/null
nohup npm run preview -- --port 4173 > /tmp/wb-preview.log 2>&1 &
sleep 4
```

Then a Playwright script (CJS default import per `wordbank-qa-harness`) that logs in as the test user, navigates to `/bank`, waits, and screenshots. Assert in the script: `document.querySelector('.cg-score')` text is a 3-digit number and `.cg-tier` is non-empty. Read the screenshot to confirm the dial renders under the card and the tap-breakdown opens.

Expected: gauge visible with a score + tier; tapping shows the 5-row breakdown.

- [ ] **Step 5: Commit + PR**

```bash
git add src/routes/bank/+page.svelte
git commit -m "Credit score: mount CreditGauge on My Account"
git push -u origin <branch>
gh pr create --title "Credit score Phase 1: score model + read-only gauge" --body "…"
```

Then squash-merge and sync master (standard flow). Phase 1 ships with **no loan effects** — verify on prod that `/bank` shows a gauge and `/loans` behavior is unchanged.

---

## Self-review notes

- **Spec coverage (§3 model, §3.1 components, §3.2 movement, §6 data model, §7 functions, §8 My Account gauge):** Tasks 1–6 cover storage (T1), the weighted target + ease + grace + derog (T2), lazy recompute + payload + detail RPC (T3), store access (T4), the gauge (T5), and the My Account surface (T6). Spec §4 loan effects, §8 Loans/Leaderboard/Badges are **explicitly deferred** (Phase 2–4) per the plan goal.
- **Phase-1 simplifications flagged:** Utilization uses the _instantaneous_ loan/cap (spec's rolling-average anti-abuse matters only once effects exist in Phase 2); Consistency falls back to a ledger-day proxy if `streak` is 0. Both are noted and safe for a read-only display.
- **Type consistency:** `_recompute_credit(uuid,text,int)`, `_credit_tier(int)`, `get_credit_detail()` shape (`score/target/tier/delta/components{value,label,hint}/history`), and `CreditGauge` props (`score/tier/delta/detail`) are used identically across Tasks 2–6.
- **No placeholders:** every DB and Svelte step includes the actual code; PR body text in T6 Step 5 is the one intentional fill-in at ship time.
