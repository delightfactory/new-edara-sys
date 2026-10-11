BEGIN;

-- Preserve the base table and its inventory write RPCs. This read surface
-- authorizes rows explicitly because the view reads with its owner's rights.
CREATE OR REPLACE VIEW public.stock_read_safe
WITH (security_barrier = true) AS
SELECT
  s.id,
  s.warehouse_id,
  s.product_id,
  s.quantity,
  s.reserved_quantity,
  s.available_quantity,
  CASE WHEN (SELECT public.check_permission((SELECT auth.uid()), 'finance.view_costs'))
    THEN s.wac ELSE NULL::NUMERIC END AS wac,
  CASE WHEN (SELECT public.check_permission((SELECT auth.uid()), 'finance.view_costs'))
    THEN s.total_cost_value ELSE NULL::NUMERIC END AS total_cost_value,
  s.created_at,
  s.updated_at
FROM public.stock s
WHERE (SELECT auth.uid()) IS NOT NULL
  AND (
    (SELECT public.check_permission((SELECT auth.uid()), 'inventory.read_all'))
    OR (
      (SELECT public.check_permission((SELECT auth.uid()), 'inventory.read'))
      AND s.warehouse_id IN (SELECT public.user_warehouse_ids_set())
    )
  );

-- Default privileges can give new views write access: make this surface
-- SELECT-only explicitly, including on repeated application.
REVOKE ALL ON public.stock_read_safe FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.stock_read_safe TO authenticated;

-- A table-wide SELECT overrides column restrictions. Remove both table and
-- explicit cost-column SELECT grants before allowing noncost readers.
REVOKE SELECT ON public.stock FROM PUBLIC, anon, authenticated;
REVOKE SELECT (wac, total_cost_value) ON public.stock FROM PUBLIC, anon, authenticated;
GRANT SELECT (
  id, warehouse_id, product_id, quantity, reserved_quantity,
  available_quantity, created_at, updated_at
) ON public.stock TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
