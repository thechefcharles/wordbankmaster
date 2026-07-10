-- ============================================================================
-- get_shop: also return `loan` so the Store can lock itself while you owe.
-- ============================================================================
-- buy_cosmetic / buy_powerup already reject with reason 'in_debt' when loan>0;
-- this just lets the client gate the UI instead of failing on click.
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.get_shop()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_bank BIGINT; v_loan BIGINT; v_items JSONB; v_t TEXT; v_c TEXT;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('bank',0,'loan',0,'items','[]'::jsonb); END IF;
  PERFORM public._ensure_bank(v_uid);
  PERFORM public._accrue_loan(v_uid);   -- keep the owed figure current
  SELECT bank, COALESCE(loan,0), equipped_title, equipped_color INTO v_bank, v_loan, v_t, v_c
    FROM public.profiles WHERE id = v_uid;
  SELECT jsonb_agg(jsonb_build_object(
    'id', c.id, 'kind', c.kind, 'label', c.label, 'value', c.value, 'price', c.price,
    'owned', EXISTS (SELECT 1 FROM public.user_cosmetics uc WHERE uc.user_id = v_uid AND uc.cosmetic_id = c.id),
    'equipped', (c.id = v_t OR c.id = v_c)
  ) ORDER BY c.sort) INTO v_items FROM public.cosmetics c WHERE NOT COALESCE(c.earned, false);
  RETURN jsonb_build_object('bank', COALESCE(v_bank,0), 'loan', COALESCE(v_loan,0),
    'items', COALESCE(v_items,'[]'::jsonb));
END; $function$;

COMMIT;
