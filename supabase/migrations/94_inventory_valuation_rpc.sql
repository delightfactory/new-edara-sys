-- ════════════════════════════════════════════════════════════════
-- 94_inventory_valuation_rpc.sql
-- Inventory Valuation Report — RPCs
-- ════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- PART 0: Seed patch — grant finance.view_costs to key roles
-- ────────────────────────────────────────────────────────────────
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, 'finance.view_costs'
FROM roles r
WHERE r.name IN ('ceo', 'branch_manager', 'accountant')
ON CONFLICT (role_id, permission) DO NOTHING;

-- ────────────────────────────────────────────────────────────────
-- PART 1: RPC — get_inventory_valuation_summary()
-- Returns a single JSONB object with key inventory metrics
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_inventory_valuation_summary()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  -- Guard: require finance.view_costs
  IF NOT check_permission(auth.uid(), 'finance.view_costs') THEN
    RAISE EXCEPTION 'permission_denied: finance.view_costs required';
  END IF;

  SELECT jsonb_build_object(
    'total_value',       COALESCE(SUM(s.total_cost_value), 0),
    'total_quantity',    COALESCE(SUM(s.quantity), 0),
    'unique_products',  (
      SELECT COUNT(DISTINCT s2.product_id)
      FROM stock s2
      JOIN warehouses w2 ON w2.id = s2.warehouse_id AND w2.is_active = true
      WHERE s2.quantity > 0
    ),
    'total_warehouses', (
      SELECT COUNT(DISTINCT s3.warehouse_id)
      FROM stock s3
      JOIN warehouses w3 ON w3.id = s3.warehouse_id AND w3.is_active = true
      WHERE s3.quantity > 0
    ),
    'out_of_stock_count', (
      SELECT COUNT(*)
      FROM products p
      WHERE p.is_active = true
        AND NOT EXISTS (
          SELECT 1
          FROM stock s4
          JOIN warehouses w4 ON w4.id = s4.warehouse_id AND w4.is_active = true
          WHERE s4.product_id = p.id
            AND s4.available_quantity > 0
        )
    ),
    'low_stock_count', (
      SELECT COUNT(*)
      FROM stock s5
      JOIN warehouses w5 ON w5.id = s5.warehouse_id AND w5.is_active = true
      JOIN products p5 ON p5.id = s5.product_id
      WHERE s5.available_quantity > 0
        AND p5.min_stock_level > 0
        AND s5.available_quantity <= p5.min_stock_level
    ),
    'total_retail_value', (
      SELECT COALESCE(SUM(s6.quantity * p2.selling_price), 0)
      FROM stock s6
      JOIN warehouses w6 ON w6.id = s6.warehouse_id AND w6.is_active = true
      JOIN products p2 ON p2.id = s6.product_id
    )
  )
  INTO v_result
  FROM stock s
  JOIN warehouses w ON w.id = s.warehouse_id AND w.is_active = true;

  RETURN v_result;
END;
$$;

-- ────────────────────────────────────────────────────────────────
-- PART 2: RPC — get_inventory_by_warehouse()
-- Returns one row per active warehouse with stock metrics
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_inventory_by_warehouse()
RETURNS TABLE (
  warehouse_id   UUID,
  warehouse_name TEXT,
  warehouse_type TEXT,
  product_count  BIGINT,
  total_quantity NUMERIC,
  total_value    NUMERIC,
  value_percentage NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_grand_total NUMERIC;
BEGIN
  -- Guard: require finance.view_costs
  IF NOT check_permission(auth.uid(), 'finance.view_costs') THEN
    RAISE EXCEPTION 'permission_denied: finance.view_costs required';
  END IF;

  -- Calculate grand total for percentage computation
  SELECT COALESCE(SUM(s.total_cost_value), 0)
  INTO v_grand_total
  FROM stock s
  JOIN warehouses w ON w.id = s.warehouse_id AND w.is_active = true;

  RETURN QUERY
  SELECT
    w.id                                             AS warehouse_id,
    w.name::TEXT                                     AS warehouse_name,
    w.type::TEXT                                     AS warehouse_type,
    COUNT(DISTINCT s.product_id)                     AS product_count,
    COALESCE(SUM(s.quantity), 0)                     AS total_quantity,
    COALESCE(SUM(s.total_cost_value), 0)             AS total_value,
    CASE
      WHEN v_grand_total > 0
      THEN ROUND(COALESCE(SUM(s.total_cost_value), 0) / v_grand_total * 100, 2)
      ELSE 0
    END                                              AS value_percentage
  FROM warehouses w
  JOIN stock s ON s.warehouse_id = w.id
  WHERE w.is_active = true
    AND s.quantity > 0
  GROUP BY w.id, w.name, w.type
  ORDER BY total_value DESC;
END;
$$;

-- ────────────────────────────────────────────────────────────────
-- PART 3: RPC — get_inventory_by_category()
-- Returns one row per category with stock metrics
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_inventory_by_category()
RETURNS TABLE (
  category_id   UUID,
  category_name TEXT,
  product_count BIGINT,
  total_quantity NUMERIC,
  total_value   NUMERIC,
  value_percentage NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_grand_total NUMERIC;
BEGIN
  -- Guard: require finance.view_costs
  IF NOT check_permission(auth.uid(), 'finance.view_costs') THEN
    RAISE EXCEPTION 'permission_denied: finance.view_costs required';
  END IF;

  -- Calculate grand total for percentage computation
  SELECT COALESCE(SUM(s.total_cost_value), 0)
  INTO v_grand_total
  FROM stock s
  JOIN warehouses w ON w.id = s.warehouse_id AND w.is_active = true;

  RETURN QUERY
  SELECT
    p.category_id                                    AS category_id,
    COALESCE(c.name, 'بدون تصنيف')::TEXT             AS category_name,
    COUNT(DISTINCT s.product_id)                     AS product_count,
    COALESCE(SUM(s.quantity), 0)                     AS total_quantity,
    COALESCE(SUM(s.total_cost_value), 0)             AS total_value,
    CASE
      WHEN v_grand_total > 0
      THEN ROUND(COALESCE(SUM(s.total_cost_value), 0) / v_grand_total * 100, 2)
      ELSE 0
    END                                              AS value_percentage
  FROM stock s
  JOIN warehouses w ON w.id = s.warehouse_id AND w.is_active = true
  JOIN products p ON p.id = s.product_id
  LEFT JOIN product_categories c ON c.id = p.category_id
  WHERE s.quantity > 0
  GROUP BY p.category_id, c.name
  ORDER BY total_value DESC;
END;
$$;

-- ────────────────────────────────────────────────────────────────
-- PART 4: Grants
-- ────────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.get_inventory_valuation_summary() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_inventory_by_warehouse() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_inventory_by_category() TO authenticated;

-- Verification comment:
-- All 3 RPCs are SECURITY DEFINER with check_permission guard.
-- Grants allow authenticated users to call; permission check is inside the function.
