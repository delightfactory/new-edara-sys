BEGIN;

-- Keep the existing RPC signature and pagination contract. Authorize the
-- stock rows explicitly because this function runs as its owner.
CREATE OR REPLACE FUNCTION public.get_low_stock(
  p_warehouse_id UUID DEFAULT NULL,
  p_offset INTEGER DEFAULT 0,
  p_limit INTEGER DEFAULT 50
)
RETURNS TABLE (
  id UUID,
  warehouse_id UUID,
  product_id UUID,
  quantity NUMERIC,
  reserved_quantity NUMERIC,
  available_quantity NUMERIC,
  wac NUMERIC,
  total_cost_value NUMERIC,
  warehouse_name TEXT,
  product_name TEXT,
  product_sku TEXT,
  min_stock_level NUMERIC,
  unit_name TEXT,
  unit_symbol TEXT,
  total_count BIGINT
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    s.id,
    s.warehouse_id,
    s.product_id,
    s.quantity,
    s.reserved_quantity,
    s.available_quantity,
    CASE WHEN (SELECT public.check_permission((SELECT auth.uid()), 'finance.view_costs'))
      THEN s.wac ELSE NULL::NUMERIC END,
    CASE WHEN (SELECT public.check_permission((SELECT auth.uid()), 'finance.view_costs'))
      THEN s.total_cost_value ELSE NULL::NUMERIC END,
    w.name AS warehouse_name,
    p.name AS product_name,
    p.sku AS product_sku,
    COALESCE(p.min_stock_level, 0)::NUMERIC AS min_stock_level,
    u.name AS unit_name,
    u.symbol AS unit_symbol,
    COUNT(*) OVER() AS total_count
  FROM public.stock s
  JOIN public.warehouses w ON w.id = s.warehouse_id
  JOIN public.products p ON p.id = s.product_id
  LEFT JOIN public.units u ON u.id = p.base_unit_id
  WHERE (SELECT auth.uid()) IS NOT NULL
    AND (
      (SELECT public.check_permission((SELECT auth.uid()), 'inventory.read_all'))
      OR (
        (SELECT public.check_permission((SELECT auth.uid()), 'inventory.read'))
        AND s.warehouse_id IN (SELECT public.user_warehouse_ids_set())
      )
    )
    AND s.available_quantity <= COALESCE(p.min_stock_level, 0)
    AND (p_warehouse_id IS NULL OR s.warehouse_id = p_warehouse_id)
  ORDER BY s.available_quantity ASC
  OFFSET p_offset LIMIT p_limit;
$$;

REVOKE EXECUTE ON FUNCTION public.get_low_stock(UUID, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_low_stock(UUID, INTEGER, INTEGER) TO authenticated;

COMMIT;
