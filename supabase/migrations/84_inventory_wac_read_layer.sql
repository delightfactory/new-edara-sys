-- ============================================================
-- 84_inventory_wac_read_layer.sql
-- EDARA v2 — Unified read layer for actual cost metrics based on stock
-- Idempotent: Safe to run multiple times
-- ============================================================

-- ── 1. Read RPC: get_product_cost_metrics ───────────────────
CREATE OR REPLACE FUNCTION get_product_cost_metrics(
  p_product_ids UUID[] DEFAULT NULL
) RETURNS TABLE (
  product_id UUID,
  global_quantity NUMERIC,
  global_total_cost_value NUMERIC,
  global_wac NUMERIC,        -- NULL when no stock exists (not 0)
  warehouse_breakdown JSONB,
  cost_price NUMERIC,
  last_purchase_price NUMERIC
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- SECURITY: Ensure the user has finance.view_costs permission
  IF NOT check_permission(auth.uid(), 'finance.view_costs') THEN
    RAISE EXCEPTION 'Unauthorized: User lacks finance.view_costs permission';
  END IF;

  RETURN QUERY
  WITH valid_stock AS (
    SELECT
      s.product_id,
      s.warehouse_id,
      w.name AS warehouse_name,
      s.quantity,
      s.total_cost_value,
      s.wac
    FROM stock s
    JOIN warehouses w ON s.warehouse_id = w.id
    WHERE s.quantity > 0
      AND (p_product_ids IS NULL OR s.product_id = ANY(p_product_ids))
  ),
  aggregated_metrics AS (
    SELECT
      v.product_id,
      SUM(v.quantity)          AS total_qty,
      SUM(v.total_cost_value)  AS total_val,
      jsonb_agg(jsonb_build_object(
        'warehouse_id',       v.warehouse_id,
        'warehouse_name',     v.warehouse_name,
        'quantity',           v.quantity,
        'total_cost_value',   v.total_cost_value,
        'wac',                v.wac
      )) AS breakdown
    FROM valid_stock v
    GROUP BY v.product_id
  )
  SELECT
    p.id                                                     AS product_id,
    COALESCE(a.total_qty,  0)                                AS global_quantity,
    COALESCE(a.total_val,  0)                                AS global_total_cost_value,
    -- Return NULL (not 0) when there is no stock, so the fallback chain works correctly:
    -- last_purchase_price -> global_wac (NULL = skip) -> cost_price -> 0
    CASE
      WHEN a.total_qty > 0 THEN ROUND(a.total_val / a.total_qty, 4)
      ELSE NULL
    END                                                      AS global_wac,
    COALESCE(a.breakdown, '[]'::jsonb)                       AS warehouse_breakdown,
    p.cost_price,
    p.last_purchase_price
  FROM products p
  LEFT JOIN aggregated_metrics a ON a.product_id = p.id
  WHERE p_product_ids IS NULL OR p.id = ANY(p_product_ids);
END;
$$;

GRANT EXECUTE ON FUNCTION get_product_cost_metrics(UUID[]) TO authenticated;


-- ── 2. Backend guard: prevent cost_price writes without finance.view_costs ──
-- This closes the gap where a user with products.create but no finance access
-- could tamper the cost_price field directly via the API.

CREATE OR REPLACE FUNCTION guard_product_cost_price()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- On INSERT: if cost_price supplied and non-zero, require finance permission
  IF TG_OP = 'INSERT' THEN
    IF NEW.cost_price IS NOT NULL AND NEW.cost_price <> 0 THEN
      IF NOT check_permission(auth.uid(), 'finance.view_costs') THEN
        RAISE EXCEPTION 'Permission denied: finance.view_costs required to set cost_price';
      END IF;
    END IF;
  END IF;

  -- On UPDATE: if cost_price is being changed, require finance permission
  IF TG_OP = 'UPDATE' THEN
    IF NEW.cost_price IS DISTINCT FROM OLD.cost_price THEN
      IF NOT check_permission(auth.uid(), 'finance.view_costs') THEN
        RAISE EXCEPTION 'Permission denied: finance.view_costs required to modify cost_price';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Attach trigger (idempotent)
DROP TRIGGER IF EXISTS trg_guard_product_cost_price ON products;
CREATE TRIGGER trg_guard_product_cost_price
  BEFORE INSERT OR UPDATE ON products
  FOR EACH ROW EXECUTE FUNCTION guard_product_cost_price();
