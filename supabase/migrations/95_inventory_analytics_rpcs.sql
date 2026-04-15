-- ════════════════════════════════════════════════════════════════
-- 95_inventory_analytics_rpcs.sql
-- Inventory Analytics — Movement Analysis + ABC Classification
-- ════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- PART 0: Performance index for last_out CTE
-- ────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_stock_movements_product_type_date
  ON stock_movements (product_id, type, created_at DESC);


-- ────────────────────────────────────────────────────────────────
-- PART 1: RPC — get_inventory_movement_analysis()
-- Returns per-product movement metrics: velocity, coverage, staleness
--
-- Business definitions (locked):
--   velocity    = SUM(delivered_quantity - returned_quantity) / 30
--                 from sales_orders WHERE status IN ('delivered','completed')
--                 AND delivered_at >= now() - 30 days
--                 NOTE: partially_delivered is excluded because no existing
--                 RPC/trigger sets that status or guarantees delivered_at for it.
--   days_of_cover = SUM(available_quantity) / daily_velocity
--                   Uses available_quantity (not quantity) because reserved
--                   stock is committed to confirmed orders and cannot be sold.
--   last_out    = last movement with type IN ('out','transfer_out')
--                 NOTE: return_out is excluded — it is an administrative exit
--                 (returns processing), not operational demand.
--   coverage_status CASE order: dead → critical → low → ok → surplus
--                   dead first to prevent 999 days_of_cover from matching surplus.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_inventory_movement_analysis()
RETURNS TABLE (
  product_id       UUID,
  product_name     TEXT,
  product_sku      TEXT,
  category_name    TEXT,
  total_quantity   NUMERIC,
  available_qty    NUMERIC,
  total_value      NUMERIC,
  daily_velocity   NUMERIC,
  days_of_cover    NUMERIC,
  last_out_date    TIMESTAMPTZ,
  days_since_last_out INT,
  coverage_status  TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT check_permission(auth.uid(), 'finance.view_costs') THEN
    RAISE EXCEPTION 'permission_denied: finance.view_costs required';
  END IF;

  RETURN QUERY
  WITH product_stock AS (
    SELECT
      s.product_id,
      SUM(s.quantity)           AS total_qty,
      SUM(s.available_quantity) AS available_qty,
      SUM(s.total_cost_value)   AS total_val
    FROM stock s
    JOIN warehouses w ON w.id = s.warehouse_id AND w.is_active = true
    WHERE s.quantity > 0
    GROUP BY s.product_id
  ),
  velocity_30d AS (
    -- Net delivered quantity per product in last 30 days
    SELECT
      soi.product_id,
      SUM(soi.delivered_quantity - soi.returned_quantity) / 30.0 AS daily_vel
    FROM sales_order_items soi
    JOIN sales_orders so ON so.id = soi.order_id
    WHERE so.status IN ('delivered', 'completed')
      AND so.delivered_at >= (now() - INTERVAL '30 days')
    GROUP BY soi.product_id
  ),
  last_out AS (
    -- Last operational outbound movement (excludes return_out)
    SELECT DISTINCT ON (sm.product_id)
      sm.product_id,
      sm.created_at AS last_out_at
    FROM stock_movements sm
    WHERE sm.type IN ('out', 'transfer_out')
    ORDER BY sm.product_id, sm.created_at DESC
  )
  SELECT
    ps.product_id,
    p.name::TEXT                                       AS product_name,
    p.sku::TEXT                                        AS product_sku,
    COALESCE(pc.name, 'بدون تصنيف')::TEXT             AS category_name,
    ps.total_qty                                       AS total_quantity,
    ps.available_qty                                   AS available_qty,
    ps.total_val                                       AS total_value,
    COALESCE(v.daily_vel, 0)                           AS daily_velocity,
    CASE
      WHEN COALESCE(v.daily_vel, 0) <= 0 THEN 999
      ELSE ROUND(ps.available_qty / v.daily_vel, 1)
    END                                                AS days_of_cover,
    lo.last_out_at                                     AS last_out_date,
    CASE
      WHEN lo.last_out_at IS NULL THEN NULL
      ELSE EXTRACT(DAY FROM (now() - lo.last_out_at))::INT
    END                                                AS days_since_last_out,
    -- CASE order: dead → critical → low → ok → surplus
    -- dead is checked FIRST to prevent 999 days_of_cover from matching surplus
    CASE
      WHEN COALESCE(v.daily_vel, 0) <= 0
           AND (lo.last_out_at IS NULL OR lo.last_out_at < now() - INTERVAL '30 days')
        THEN 'dead'
      WHEN COALESCE(v.daily_vel, 0) > 0
           AND (ps.available_qty / v.daily_vel) < 7
        THEN 'critical'
      WHEN COALESCE(v.daily_vel, 0) > 0
           AND (ps.available_qty / v.daily_vel) < 31
        THEN 'low'
      WHEN COALESCE(v.daily_vel, 0) > 0
           AND (ps.available_qty / v.daily_vel) <= 90
        THEN 'ok'
      ELSE 'surplus'
    END                                                AS coverage_status
  FROM product_stock ps
  JOIN products p ON p.id = ps.product_id
  LEFT JOIN product_categories pc ON pc.id = p.category_id
  LEFT JOIN velocity_30d v ON v.product_id = ps.product_id
  LEFT JOIN last_out lo ON lo.product_id = ps.product_id
  ORDER BY
    CASE
      WHEN COALESCE(v.daily_vel, 0) <= 0
           AND (lo.last_out_at IS NULL OR lo.last_out_at < now() - INTERVAL '30 days')
        THEN 0  -- dead first
      WHEN COALESCE(v.daily_vel, 0) > 0
           AND (ps.available_qty / v.daily_vel) < 7
        THEN 1  -- critical
      ELSE 2
    END,
    ps.total_val DESC;
END;
$$;


-- ────────────────────────────────────────────────────────────────
-- PART 2: RPC — get_inventory_dead_stock_summary()
-- Returns JSONB summary of dead/surplus/critical counts and values
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_inventory_dead_stock_summary()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
  v_grand_total NUMERIC;
BEGIN
  IF NOT check_permission(auth.uid(), 'finance.view_costs') THEN
    RAISE EXCEPTION 'permission_denied: finance.view_costs required';
  END IF;

  -- Grand total for percentage calculation
  SELECT COALESCE(SUM(s.total_cost_value), 0)
  INTO v_grand_total
  FROM stock s
  JOIN warehouses w ON w.id = s.warehouse_id AND w.is_active = true
  WHERE s.quantity > 0;

  WITH product_stock AS (
    SELECT
      s.product_id,
      SUM(s.available_quantity) AS available_qty,
      SUM(s.total_cost_value)   AS total_val
    FROM stock s
    JOIN warehouses w ON w.id = s.warehouse_id AND w.is_active = true
    WHERE s.quantity > 0
    GROUP BY s.product_id
  ),
  velocity_30d AS (
    SELECT
      soi.product_id,
      SUM(soi.delivered_quantity - soi.returned_quantity) / 30.0 AS daily_vel
    FROM sales_order_items soi
    JOIN sales_orders so ON so.id = soi.order_id
    WHERE so.status IN ('delivered', 'completed')
      AND so.delivered_at >= (now() - INTERVAL '30 days')
    GROUP BY soi.product_id
  ),
  last_out AS (
    SELECT DISTINCT ON (sm.product_id)
      sm.product_id,
      sm.created_at AS last_out_at
    FROM stock_movements sm
    WHERE sm.type IN ('out', 'transfer_out')
    ORDER BY sm.product_id, sm.created_at DESC
  ),
  classified AS (
    SELECT
      ps.product_id,
      ps.available_qty,
      ps.total_val,
      COALESCE(v.daily_vel, 0) AS daily_vel,
      lo.last_out_at,
      -- days_since_last_out
      CASE WHEN lo.last_out_at IS NULL THEN 9999
           ELSE EXTRACT(DAY FROM (now() - lo.last_out_at))::INT
      END AS days_no_out,
      -- coverage
      CASE
        WHEN COALESCE(v.daily_vel, 0) <= 0 THEN 999
        ELSE ps.available_qty / v.daily_vel
      END AS doc,
      -- status (dead first)
      CASE
        WHEN COALESCE(v.daily_vel, 0) <= 0
             AND (lo.last_out_at IS NULL OR lo.last_out_at < now() - INTERVAL '30 days')
          THEN 'dead'
        WHEN COALESCE(v.daily_vel, 0) > 0 AND (ps.available_qty / v.daily_vel) < 7
          THEN 'critical'
        WHEN COALESCE(v.daily_vel, 0) > 0 AND (ps.available_qty / v.daily_vel) < 31
          THEN 'low'
        WHEN COALESCE(v.daily_vel, 0) > 0 AND (ps.available_qty / v.daily_vel) <= 90
          THEN 'ok'
        ELSE 'surplus'
      END AS status
    FROM product_stock ps
    LEFT JOIN velocity_30d v ON v.product_id = ps.product_id
    LEFT JOIN last_out lo ON lo.product_id = ps.product_id
  )
  SELECT jsonb_build_object(
    'dead_30', jsonb_build_object(
      'count', COUNT(*) FILTER (WHERE status = 'dead' AND days_no_out >= 30),
      'value', COALESCE(SUM(total_val) FILTER (WHERE status = 'dead' AND days_no_out >= 30), 0)
    ),
    'dead_60', jsonb_build_object(
      'count', COUNT(*) FILTER (WHERE status = 'dead' AND days_no_out >= 60),
      'value', COALESCE(SUM(total_val) FILTER (WHERE status = 'dead' AND days_no_out >= 60), 0)
    ),
    'dead_90', jsonb_build_object(
      'count', COUNT(*) FILTER (WHERE status = 'dead' AND days_no_out >= 90),
      'value', COALESCE(SUM(total_val) FILTER (WHERE status = 'dead' AND days_no_out >= 90), 0)
    ),
    'total_dead_value', COALESCE(SUM(total_val) FILTER (WHERE status = 'dead'), 0),
    'total_dead_pct', CASE
      WHEN v_grand_total > 0
      THEN ROUND(COALESCE(SUM(total_val) FILTER (WHERE status = 'dead'), 0) / v_grand_total * 100, 2)
      ELSE 0
    END,
    'surplus_count', COUNT(*) FILTER (WHERE status = 'surplus'),
    'surplus_value', COALESCE(SUM(total_val) FILTER (WHERE status = 'surplus'), 0),
    'critical_count', COUNT(*) FILTER (WHERE status = 'critical'),
    'low_count', COUNT(*) FILTER (WHERE status = 'low')
  )
  INTO v_result
  FROM classified;

  RETURN v_result;
END;
$$;


-- ────────────────────────────────────────────────────────────────
-- PART 3: RPC — get_inventory_abc_analysis()
-- Returns per-product ABC classification using Pareto cumulative
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_inventory_abc_analysis()
RETURNS TABLE (
  product_id       UUID,
  product_name     TEXT,
  product_sku      TEXT,
  category_name    TEXT,
  total_quantity   NUMERIC,
  total_value      NUMERIC,
  value_pct        NUMERIC,
  cumulative_pct   NUMERIC,
  abc_class        TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_grand_total NUMERIC;
BEGIN
  IF NOT check_permission(auth.uid(), 'finance.view_costs') THEN
    RAISE EXCEPTION 'permission_denied: finance.view_costs required';
  END IF;

  SELECT COALESCE(SUM(s.total_cost_value), 0)
  INTO v_grand_total
  FROM stock s
  JOIN warehouses w ON w.id = s.warehouse_id AND w.is_active = true
  WHERE s.quantity > 0;

  RETURN QUERY
  WITH product_stock AS (
    SELECT
      s.product_id,
      SUM(s.quantity)         AS total_qty,
      SUM(s.total_cost_value) AS total_val
    FROM stock s
    JOIN warehouses w ON w.id = s.warehouse_id AND w.is_active = true
    WHERE s.quantity > 0
    GROUP BY s.product_id
  ),
  ranked AS (
    SELECT
      ps.product_id,
      p.name::TEXT                                   AS product_name,
      p.sku::TEXT                                    AS product_sku,
      COALESCE(pc.name, 'بدون تصنيف')::TEXT         AS category_name,
      ps.total_qty                                   AS total_quantity,
      ps.total_val                                   AS total_value,
      CASE WHEN v_grand_total > 0
        THEN ROUND(ps.total_val / v_grand_total * 100, 2)
        ELSE 0
      END                                            AS value_pct,
      CASE WHEN v_grand_total > 0
        THEN ROUND(
          SUM(ps.total_val) OVER (ORDER BY ps.total_val DESC ROWS UNBOUNDED PRECEDING)
          / v_grand_total * 100, 2
        )
        ELSE 0
      END                                            AS cumulative_pct
    FROM product_stock ps
    JOIN products p ON p.id = ps.product_id
    LEFT JOIN product_categories pc ON pc.id = p.category_id
  )
  SELECT
    r.product_id,
    r.product_name,
    r.product_sku,
    r.category_name,
    r.total_quantity,
    r.total_value,
    r.value_pct,
    r.cumulative_pct,
    CASE
      WHEN r.cumulative_pct <= 80 THEN 'A'
      WHEN r.cumulative_pct <= 95 THEN 'B'
      ELSE 'C'
    END::TEXT AS abc_class
  FROM ranked r
  ORDER BY r.total_value DESC;
END;
$$;


-- ────────────────────────────────────────────────────────────────
-- PART 4: Grants
-- ────────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.get_inventory_movement_analysis() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_inventory_dead_stock_summary() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_inventory_abc_analysis() TO authenticated;
