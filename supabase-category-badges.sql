-- ============================================================
-- Category badges: all-time per-category solve counts (daily + arcade + free
-- play) that drive the per-category level-up badges and total-solved
-- milestones. Run AFTER the daily / arcade / freeplay engines — it redefines
-- their resolve functions to record a solve on a win.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.category_stats (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  category TEXT NOT NULL,
  solves INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, category)
);
ALTER TABLE public.category_stats ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "read own category stats" ON public.category_stats;
CREATE POLICY "read own category stats" ON public.category_stats FOR SELECT USING (auth.uid() = user_id);
REVOKE INSERT, UPDATE, DELETE ON public.category_stats FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public._record_category_solve(p_uid UUID, p_category TEXT)
RETURNS void LANGUAGE sql SECURITY DEFINER AS $fn$
  INSERT INTO public.category_stats (user_id, category, solves) VALUES (p_uid, p_category, 1)
  ON CONFLICT (user_id, category) DO UPDATE SET solves = public.category_stats.solves + 1, updated_at = NOW();
$fn$;
REVOKE EXECUTE ON FUNCTION public._record_category_solve(UUID, TEXT) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_category_stats()
RETURNS TABLE(category TEXT, solves INT) LANGUAGE sql SECURITY DEFINER AS $fn$
  SELECT category, solves FROM public.category_stats WHERE user_id = auth.uid();
$fn$;
GRANT EXECUTE ON FUNCTION public.get_category_stats() TO authenticated;

-- The resolve functions below are the daily / arcade / freeplay versions with a
-- single added line: PERFORM _record_category_solve(...) on a win. Full bodies
-- live in their engine files; reproduced here so the hook re-applies on reseed.
-- (See migration "category_stats_tracking" for the applied definitions.)
