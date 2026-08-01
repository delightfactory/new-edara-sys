-- ============================================================
-- EDARA v2 — dependable customer-based target axes
-- Applied after explicit review and production approval.
--
-- Scope:
--   * upgrade_value: 3 complete months average baseline, net sales.
--   * reactivation: verified dormant buyers, then minimum net sales.
--   * category_spread: customers reaching a required net category count.
--
-- Operational boundary:
--   This migration does not alter sales/purchase/collection/return tables,
--   functions, policies, or triggers. Those tables are read-only inputs.
-- ============================================================

-- Keep the type metadata aligned with the simple counting model.
UPDATE public.target_types
SET unit = 'count', auto_source = 'sales_orders', auto_calc_enabled = true,
    description = 'عدد العملاء المحددين الذين رفعوا صافي مشترياتهم عن متوسط آخر 3 أشهر كاملة بالنسبة المطلوبة'
WHERE code = 'upgrade_value';

UPDATE public.target_types
SET unit = 'count', auto_source = 'sales_orders', auto_calc_enabled = true,
    description = 'عدد العملاء الخاملين المحددين الذين عادوا للشراء بصافي قيمة لا تقل عن الحد المطلوب'
WHERE code = 'reactivation';

UPDATE public.target_types
SET unit = 'count', auto_source = 'sales_orders', auto_calc_enabled = true,
    description = 'عدد العملاء المحددين الذين اشتروا من العدد المطلوب من تصنيفات المنتجات بصافي كمية موجبة'
WHERE code = 'category_spread';

-- Internal calculation source shared by the target total and detail screen.
-- It deliberately has no authenticated grant; the public wrapper below
-- performs target visibility checks.
CREATE OR REPLACE FUNCTION public.target_customer_progress_rows(
  p_target_id UUID,
  p_snapshot_date DATE DEFAULT CURRENT_DATE
) RETURNS TABLE (
  target_id UUID,
  customer_id UUID,
  customer_name TEXT,
  customer_code TEXT,
  baseline_value NUMERIC,
  baseline_category_count INTEGER,
  required_value NUMERIC,
  achieved_value NUMERIC,
  achieved_category_count INTEGER,
  last_purchase_date DATE,
  is_achieved BOOLEAN,
  status_reason TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target public.targets%ROWTYPE;
  v_end DATE;
  v_growth NUMERIC;
  v_min_reactivation NUMERIC;
  v_required_categories INTEGER;
  v_employee_ids UUID[];
BEGIN
  SELECT * INTO v_target FROM public.targets WHERE id = p_target_id;
  IF NOT FOUND THEN RETURN; END IF;

  v_end := LEAST(GREATEST(COALESCE(p_snapshot_date, CURRENT_DATE), v_target.period_start), v_target.period_end);

  CASE v_target.scope
    WHEN 'individual' THEN v_employee_ids := ARRAY[v_target.scope_id];
    WHEN 'branch' THEN
      SELECT COALESCE(ARRAY_AGG(he.id), ARRAY[]::UUID[]) INTO v_employee_ids
      FROM public.hr_employees he WHERE he.branch_id = v_target.scope_id AND he.status = 'active';
    WHEN 'department' THEN
      SELECT COALESCE(ARRAY_AGG(he.id), ARRAY[]::UUID[]) INTO v_employee_ids
      FROM public.hr_employees he WHERE he.department_id = v_target.scope_id AND he.status = 'active';
    WHEN 'company' THEN
      SELECT COALESCE(ARRAY_AGG(he.id), ARRAY[]::UUID[]) INTO v_employee_ids
      FROM public.hr_employees he WHERE he.status = 'active';
    ELSE v_employee_ids := ARRAY[]::UUID[];
  END CASE;

  IF v_target.type_code = 'upgrade_value' THEN
    v_growth := COALESCE((v_target.filter_criteria->>'growth_pct')::NUMERIC, 0);
    RETURN QUERY
    WITH sales AS (
      SELECT so.customer_id,
             SUM(GREATEST(so.total_amount - COALESCE(so.returned_amount, 0), 0))::NUMERIC AS net_sales,
             MAX(so.delivered_at::DATE) AS last_sale
      FROM public.sales_orders so
      JOIN public.hr_employees he ON he.user_id = so.rep_id
      JOIN public.target_customers selected
        ON selected.target_id = p_target_id AND selected.customer_id = so.customer_id
      WHERE he.id = ANY(v_employee_ids)
        AND so.status IN ('delivered', 'completed')
        AND so.delivered_at >= v_target.period_start::TIMESTAMPTZ
        AND so.delivered_at < (v_end + 1)::TIMESTAMPTZ
      GROUP BY so.customer_id
    )
    SELECT
      tc.target_id, tc.customer_id, c.name::TEXT, c.code::TEXT,
      tc.baseline_value, tc.baseline_category_count,
      ROUND(COALESCE(tc.baseline_value, 0) * (1 + v_growth / 100.0), 2),
      COALESCE(s.net_sales, 0), NULL::INTEGER, s.last_sale,
      COALESCE(tc.baseline_value, 0) > 0
        AND COALESCE(s.net_sales, 0) >= COALESCE(tc.baseline_value, 0) * (1 + v_growth / 100.0),
      CASE
        WHEN COALESCE(tc.baseline_value, 0) <= 0 THEN 'baseline_missing'
        WHEN COALESCE(s.net_sales, 0) >= tc.baseline_value * (1 + v_growth / 100.0) THEN 'achieved'
        WHEN COALESCE(s.net_sales, 0) = 0 THEN 'no_sales_yet'
        ELSE 'in_progress'
      END
    FROM public.target_customers tc
    JOIN public.customers c ON c.id = tc.customer_id
    LEFT JOIN sales s ON s.customer_id = tc.customer_id
    WHERE tc.target_id = p_target_id
    ORDER BY c.name;

  ELSIF v_target.type_code = 'reactivation' THEN
    v_min_reactivation := COALESCE((v_target.filter_criteria->>'min_reactivation_value')::NUMERIC, 0);
    RETURN QUERY
    WITH sales AS (
      SELECT so.customer_id,
             SUM(GREATEST(so.total_amount - COALESCE(so.returned_amount, 0), 0))::NUMERIC AS net_sales
      FROM public.sales_orders so
      JOIN public.hr_employees he ON he.user_id = so.rep_id
      JOIN public.target_customers selected
        ON selected.target_id = p_target_id AND selected.customer_id = so.customer_id
      WHERE he.id = ANY(v_employee_ids)
        AND so.status IN ('delivered', 'completed')
        AND so.delivered_at >= v_target.period_start::TIMESTAMPTZ
        AND so.delivered_at < (v_end + 1)::TIMESTAMPTZ
      GROUP BY so.customer_id
    )
    SELECT
      tc.target_id, tc.customer_id, c.name::TEXT, c.code::TEXT,
      tc.baseline_value, tc.baseline_category_count,
      v_min_reactivation, COALESCE(s.net_sales, 0), NULL::INTEGER,
      tc.baseline_period_end,
      COALESCE(s.net_sales, 0) >= v_min_reactivation,
      CASE
        WHEN tc.baseline_period_end IS NULL THEN 'dormancy_not_verified'
        WHEN COALESCE(s.net_sales, 0) >= v_min_reactivation THEN 'achieved'
        WHEN COALESCE(s.net_sales, 0) = 0 THEN 'not_reactivated_yet'
        ELSE 'below_minimum_value'
      END
    FROM public.target_customers tc
    JOIN public.customers c ON c.id = tc.customer_id
    LEFT JOIN sales s ON s.customer_id = tc.customer_id
    WHERE tc.target_id = p_target_id
    ORDER BY c.name;

  ELSIF v_target.type_code = 'category_spread' THEN
    v_required_categories := COALESCE((v_target.filter_criteria->>'required_category_count')::INTEGER, 0);
    RETURN QUERY
    WITH category_sales AS (
      SELECT so.customer_id,
             COUNT(DISTINCT p.category_id)::INTEGER AS category_count,
             MAX(so.delivered_at::DATE) AS last_sale
      FROM public.sales_orders so
      JOIN public.hr_employees he ON he.user_id = so.rep_id
      JOIN public.target_customers selected
        ON selected.target_id = p_target_id AND selected.customer_id = so.customer_id
      JOIN public.sales_order_items soi ON soi.order_id = so.id
      JOIN public.products p ON p.id = soi.product_id
      WHERE he.id = ANY(v_employee_ids)
        AND so.status IN ('delivered', 'completed')
        AND so.delivered_at >= v_target.period_start::TIMESTAMPTZ
        AND so.delivered_at < (v_end + 1)::TIMESTAMPTZ
        AND GREATEST(soi.delivered_quantity - COALESCE(soi.returned_quantity, 0), 0) > 0
        AND p.category_id IS NOT NULL
      GROUP BY so.customer_id
    )
    SELECT
      tc.target_id, tc.customer_id, c.name::TEXT, c.code::TEXT,
      tc.baseline_value, tc.baseline_category_count,
      v_required_categories::NUMERIC, COALESCE(s.category_count, 0)::NUMERIC,
      COALESCE(s.category_count, 0)::INTEGER, s.last_sale,
      COALESCE(s.category_count, 0) >= v_required_categories,
      CASE
        WHEN v_required_categories <= 0 THEN 'required_count_missing'
        WHEN COALESCE(s.category_count, 0) >= v_required_categories THEN 'achieved'
        WHEN COALESCE(s.category_count, 0) = 0 THEN 'no_categories_yet'
        ELSE 'in_progress'
      END
    FROM public.target_customers tc
    JOIN public.customers c ON c.id = tc.customer_id
    LEFT JOIN category_sales s ON s.customer_id = tc.customer_id
    WHERE tc.target_id = p_target_id
    ORDER BY c.name;
  END IF;
END;
$$;

-- One accounting source for net collections. Returns are allocated once per
-- order, proportionally to each collector's confirmed-receipt share.
CREATE OR REPLACE FUNCTION public.target_collection_net_value(
  p_employee_ids UUID[],
  p_period_start DATE,
  p_period_end DATE
) RETURNS NUMERIC
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH relevant_returns AS (
    SELECT sr.total_amount, so.id AS sales_order_id
    FROM public.sales_returns sr
    JOIN public.sales_orders so ON so.id = sr.order_id
    WHERE sr.status = 'confirmed'
      AND so.delivered_at::DATE BETWEEN p_period_start AND p_period_end
      AND (so.payment_terms = 'cash' OR COALESCE(so.credit_amount, 0) = 0)
  ), relevant_orders AS (
    SELECT DISTINCT sales_order_id FROM relevant_returns
  ), scoped_receipts AS (
    SELECT pr.sales_order_id, SUM(pr.amount) AS amount
    FROM public.payment_receipts pr
    JOIN public.hr_employees he ON he.user_id = pr.collected_by
    JOIN relevant_orders ro ON ro.sales_order_id = pr.sales_order_id
    WHERE he.id = ANY(COALESCE(p_employee_ids, ARRAY[]::UUID[]))
      AND pr.status = 'confirmed'
    GROUP BY pr.sales_order_id
  ), all_receipts AS (
    SELECT pr.sales_order_id, SUM(pr.amount) AS amount
    FROM public.payment_receipts pr
    JOIN relevant_orders ro ON ro.sales_order_id = pr.sales_order_id
    WHERE pr.status = 'confirmed'
    GROUP BY pr.sales_order_id
  ), allocated_returns AS (
    SELECT SUM(sr.total_amount * scoped.amount / NULLIF(all_r.amount, 0)) AS amount
    FROM relevant_returns sr
    JOIN scoped_receipts scoped ON scoped.sales_order_id = sr.sales_order_id AND scoped.amount > 0
    JOIN all_receipts all_r ON all_r.sales_order_id = sr.sales_order_id AND all_r.amount > 0
  )
  SELECT GREATEST(
    COALESCE((
      SELECT SUM(pr.amount)
      FROM public.payment_receipts pr
      JOIN public.hr_employees he ON he.user_id = pr.collected_by
      WHERE he.id = ANY(COALESCE(p_employee_ids, ARRAY[]::UUID[]))
        AND pr.status = 'confirmed'
        AND pr.created_at::DATE BETWEEN p_period_start AND p_period_end
    ), 0) - COALESCE((SELECT amount FROM allocated_returns), 0),
    0
  );
$$;

REVOKE ALL ON FUNCTION public.target_collection_net_value(UUID[], DATE, DATE) FROM PUBLIC, anon, authenticated;

-- Keep percentage-reward pools aligned with the canonical progress calculator.
-- The sales branch is unchanged; only collection delegates to the deduplicated
-- accounting helper above.
CREATE OR REPLACE FUNCTION public.calc_target_pool_value(
  p_target_id UUID,
  p_employee_id UUID,
  p_period_start DATE,
  p_period_end DATE
) RETURNS NUMERIC
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_target public.targets%ROWTYPE;
  v_pool NUMERIC := 0;
BEGIN
  SELECT * INTO v_target FROM public.targets WHERE id = p_target_id;
  IF NOT FOUND OR v_target.reward_pool_basis IS NULL THEN RETURN 0; END IF;

  CASE v_target.reward_pool_basis
    WHEN 'sales_value' THEN
      IF EXISTS (SELECT 1 FROM public.target_customers WHERE target_id = p_target_id) THEN
        IF v_target.product_id IS NOT NULL OR v_target.category_id IS NOT NULL THEN
          SELECT COALESCE(SUM(soi.line_total - COALESCE((
            SELECT SUM(sri.line_total)
            FROM public.sales_return_items sri
            JOIN public.sales_returns sr ON sr.id = sri.return_id
            WHERE sri.order_item_id = soi.id AND sr.status = 'confirmed'
          ), 0)), 0) INTO v_pool
          FROM public.target_customers tc
          JOIN public.sales_orders so ON so.customer_id = tc.customer_id
          JOIN public.hr_employees he ON he.user_id = so.rep_id
          JOIN public.sales_order_items soi ON soi.order_id = so.id
          LEFT JOIN public.products p ON p.id = soi.product_id
          WHERE tc.target_id = p_target_id AND he.id = p_employee_id
            AND so.status IN ('delivered', 'completed')
            AND so.delivered_at::DATE BETWEEN p_period_start AND p_period_end
            AND (v_target.product_id IS NULL OR soi.product_id = v_target.product_id)
            AND (v_target.category_id IS NULL OR p.category_id = v_target.category_id);
        ELSE
          SELECT COALESCE(SUM(GREATEST(so.total_amount - COALESCE(so.returned_amount, 0), 0)), 0)
          INTO v_pool
          FROM public.target_customers tc
          JOIN public.sales_orders so ON so.customer_id = tc.customer_id
          JOIN public.hr_employees he ON he.user_id = so.rep_id
          WHERE tc.target_id = p_target_id AND he.id = p_employee_id
            AND so.status IN ('delivered', 'completed')
            AND so.delivered_at::DATE BETWEEN p_period_start AND p_period_end;
        END IF;
      ELSIF v_target.product_id IS NOT NULL OR v_target.category_id IS NOT NULL THEN
        SELECT COALESCE(SUM(soi.line_total - COALESCE((
          SELECT SUM(sri.line_total)
          FROM public.sales_return_items sri
          JOIN public.sales_returns sr ON sr.id = sri.return_id
          WHERE sri.order_item_id = soi.id AND sr.status = 'confirmed'
        ), 0)), 0) INTO v_pool
        FROM public.sales_orders so
        JOIN public.hr_employees he ON he.user_id = so.rep_id
        JOIN public.sales_order_items soi ON soi.order_id = so.id
        JOIN public.customers c ON c.id = so.customer_id
        LEFT JOIN public.products p ON p.id = soi.product_id
        WHERE he.id = p_employee_id AND so.status IN ('delivered', 'completed')
          AND so.delivered_at::DATE BETWEEN p_period_start AND p_period_end
          AND (v_target.product_id IS NULL OR soi.product_id = v_target.product_id)
          AND (v_target.category_id IS NULL OR p.category_id = v_target.category_id)
          AND (v_target.governorate_id IS NULL OR c.governorate_id = v_target.governorate_id)
          AND (v_target.city_id IS NULL OR c.city_id = v_target.city_id)
          AND (v_target.area_id IS NULL OR c.area_id = v_target.area_id);
      ELSE
        SELECT COALESCE(SUM(GREATEST(so.total_amount - COALESCE(so.returned_amount, 0), 0)), 0)
        INTO v_pool
        FROM public.sales_orders so
        JOIN public.hr_employees he ON he.user_id = so.rep_id
        JOIN public.customers c ON c.id = so.customer_id
        WHERE he.id = p_employee_id AND so.status IN ('delivered', 'completed')
          AND so.delivered_at::DATE BETWEEN p_period_start AND p_period_end
          AND (v_target.governorate_id IS NULL OR c.governorate_id = v_target.governorate_id)
          AND (v_target.city_id IS NULL OR c.city_id = v_target.city_id)
          AND (v_target.area_id IS NULL OR c.area_id = v_target.area_id);
      END IF;
    WHEN 'collection_value' THEN
      v_pool := public.target_collection_net_value(
        ARRAY[p_employee_id], p_period_start, p_period_end
      );
    ELSE
      v_pool := 0;
  END CASE;

  RETURN GREATEST(v_pool, 0);
END;
$$;

REVOKE ALL ON FUNCTION public.target_customer_progress_rows(UUID, DATE) FROM PUBLIC, anon, authenticated;

-- Preserve the existing target visibility rules and add only the missing
-- department-in-branch path for team readers. Separate permissive policies
-- avoid rewriting or weakening the established individual/branch policies.
DROP POLICY IF EXISTS tgt_read_department_team ON public.targets;
CREATE POLICY tgt_read_department_team ON public.targets
  FOR SELECT TO authenticated
  USING (
    (SELECT public.check_permission((SELECT auth.uid()), 'targets.read_team'))
    AND scope = 'department'
    AND EXISTS (
      SELECT 1
      FROM public.hr_departments d
      JOIN public.hr_employees caller ON caller.branch_id = d.branch_id
      WHERE d.id = targets.scope_id
        AND caller.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS tp_read_department_team ON public.target_progress;
CREATE POLICY tp_read_department_team ON public.target_progress
  FOR SELECT TO authenticated
  USING (
    (SELECT public.check_permission((SELECT auth.uid()), 'targets.read_team'))
    AND EXISTS (
      SELECT 1
      FROM public.targets t
      JOIN public.hr_departments d ON d.id = t.scope_id
      JOIN public.hr_employees caller ON caller.branch_id = d.branch_id
      WHERE t.id = target_progress.target_id
        AND t.scope = 'department'
        AND caller.user_id = (SELECT auth.uid())
    )
  );

-- Read-only detail endpoint. Visibility mirrors the existing targets SELECT policy.
CREATE OR REPLACE FUNCTION public.get_target_customer_progress(
  p_target_id UUID,
  p_snapshot_date DATE DEFAULT CURRENT_DATE
) RETURNS TABLE (
  target_id UUID,
  customer_id UUID,
  customer_name TEXT,
  customer_code TEXT,
  baseline_value NUMERIC,
  baseline_category_count INTEGER,
  required_value NUMERIC,
  achieved_value NUMERIC,
  achieved_category_count INTEGER,
  last_purchase_date DATE,
  is_achieved BOOLEAN,
  status_reason TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target public.targets%ROWTYPE;
  v_caller_branch UUID;
  v_visible BOOLEAN := false;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  SELECT * INTO v_target FROM public.targets WHERE id = p_target_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'الهدف غير موجود'; END IF;

  SELECT branch_id INTO v_caller_branch
  FROM public.hr_employees WHERE user_id = auth.uid() LIMIT 1;

  v_visible :=
    (v_target.scope = 'individual' AND EXISTS (
      SELECT 1 FROM public.hr_employees WHERE id = v_target.scope_id AND user_id = auth.uid()
    ))
    OR (public.check_permission(auth.uid(), 'targets.read_team') AND (
      (v_target.scope = 'branch' AND v_target.scope_id = v_caller_branch)
      OR (v_target.scope = 'department' AND EXISTS (
        SELECT 1 FROM public.hr_departments
        WHERE id = v_target.scope_id AND branch_id = v_caller_branch
      ))
      OR (v_target.scope = 'individual' AND EXISTS (
        SELECT 1 FROM public.hr_employees WHERE id = v_target.scope_id AND branch_id = v_caller_branch
      ))
    ))
    OR public.check_permission(auth.uid(), 'targets.read_all');

  IF NOT v_visible THEN RAISE EXCEPTION 'ليس لديك صلاحية قراءة تفاصيل هذا الهدف'; END IF;
  RETURN QUERY SELECT * FROM public.target_customer_progress_rows(p_target_id, p_snapshot_date);
END;
$$;

REVOKE ALL ON FUNCTION public.get_target_customer_progress(UUID, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_target_customer_progress(UUID, DATE) TO authenticated;

-- Read-only eligible customer search for reactivation target creation.
CREATE OR REPLACE FUNCTION public.get_reactivation_target_candidates(
  p_scope TEXT,
  p_scope_id UUID,
  p_period_start DATE,
  p_dormancy_days INTEGER,
  p_search TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50
) RETURNS TABLE (
  customer_id UUID,
  customer_name TEXT,
  customer_code TEXT,
  last_purchase_date DATE,
  dormant_days INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_branch UUID;
  v_allowed BOOLEAN := false;
  v_employee_ids UUID[];
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  IF p_period_start IS NULL OR COALESCE(p_dormancy_days, 0) <= 0 THEN RETURN; END IF;

  SELECT branch_id INTO v_caller_branch
  FROM public.hr_employees WHERE user_id = auth.uid() LIMIT 1;

  v_allowed := public.check_permission(auth.uid(), 'targets.read_all') OR (
    (public.check_permission(auth.uid(), 'targets.create') OR public.check_permission(auth.uid(), 'targets.assign'))
    AND CASE p_scope
      WHEN 'individual' THEN EXISTS (
        SELECT 1 FROM public.hr_employees WHERE id = p_scope_id AND branch_id = v_caller_branch
      )
      WHEN 'branch' THEN p_scope_id = v_caller_branch
      WHEN 'department' THEN EXISTS (
        SELECT 1 FROM public.hr_departments WHERE id = p_scope_id AND branch_id = v_caller_branch
      )
      ELSE false
    END
  );
  IF NOT v_allowed THEN RAISE EXCEPTION 'ليس لديك صلاحية قراءة مرشحي هذا النطاق'; END IF;

  SELECT COALESCE(ARRAY_AGG(he.id), ARRAY[]::UUID[]) INTO v_employee_ids
  FROM public.hr_employees he
  WHERE public.target_scope_matches_employee(p_scope, p_scope_id, he.id);

  RETURN QUERY
  WITH history AS (
    SELECT so.customer_id, MAX(so.delivered_at::DATE) AS last_purchase
    FROM public.sales_orders so
    JOIN public.hr_employees he ON he.user_id = so.rep_id
    WHERE he.id = ANY(v_employee_ids)
      AND so.status IN ('delivered', 'completed')
      AND so.delivered_at < p_period_start::TIMESTAMPTZ
      AND GREATEST(so.total_amount - COALESCE(so.returned_amount, 0), 0) > 0
    GROUP BY so.customer_id
  )
  SELECT c.id, c.name::TEXT, c.code::TEXT, h.last_purchase,
         (p_period_start - h.last_purchase)::INTEGER
  FROM public.customers c
  JOIN history h ON h.customer_id = c.id
  WHERE c.is_active = true
    AND h.last_purchase <= p_period_start - p_dormancy_days
    AND (NULLIF(BTRIM(p_search), '') IS NULL
      OR c.name ILIKE '%' || BTRIM(p_search) || '%'
      OR c.code ILIKE '%' || BTRIM(p_search) || '%')
  ORDER BY h.last_purchase DESC, c.name
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
END;
$$;

REVOKE ALL ON FUNCTION public.get_reactivation_target_candidates(TEXT, UUID, DATE, INTEGER, TEXT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_reactivation_target_candidates(TEXT, UUID, DATE, INTEGER, TEXT, INTEGER) TO authenticated;

-- Canonical calculator. Existing axes remain byte-for-byte equivalent in
-- accounting meaning; only the three customer axes delegate to the rows above.
CREATE OR REPLACE FUNCTION public.recalculate_target_progress(
  p_target_id UUID,
  p_snapshot_date DATE DEFAULT CURRENT_DATE,
  p_force_recalc BOOLEAN DEFAULT FALSE
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_target public.targets%ROWTYPE;
  v_achieved NUMERIC := 0;
  v_trend VARCHAR(20);
  v_days_elapsed NUMERIC;
  v_total_days NUMERIC;
  v_expected_pct NUMERIC;
  v_pct NUMERIC;
  v_employee_ids UUID[];
  v_best_tier public.target_reward_tiers%ROWTYPE;
  v_expected_rwd NUMERIC := 0;
  v_calc_date DATE;
  v_caller_branch UUID;
  v_visible BOOLEAN := false;
BEGIN
  SELECT * INTO v_target FROM public.targets
  WHERE id = p_target_id AND (p_force_recalc OR (is_active = true AND is_paused = false));
  IF NOT FOUND THEN RETURN; END IF;

  -- Direct RPC calls must obey the same visibility boundary as target reads.
  -- Internal cron/payroll calls have no auth.uid() and remain available to the
  -- privileged function owner after EXECUTE is revoked from public roles.
  IF auth.uid() IS NOT NULL THEN
    SELECT branch_id INTO v_caller_branch
    FROM public.hr_employees WHERE user_id = auth.uid() LIMIT 1;

    v_visible :=
      (v_target.scope = 'individual' AND EXISTS (
        SELECT 1 FROM public.hr_employees WHERE id = v_target.scope_id AND user_id = auth.uid()
      ))
      OR (public.check_permission(auth.uid(), 'targets.read_team') AND (
        (v_target.scope = 'branch' AND v_target.scope_id = v_caller_branch)
        OR (v_target.scope = 'department' AND EXISTS (
          SELECT 1 FROM public.hr_departments
          WHERE id = v_target.scope_id AND branch_id = v_caller_branch
        ))
        OR (v_target.scope = 'individual' AND EXISTS (
          SELECT 1 FROM public.hr_employees WHERE id = v_target.scope_id AND branch_id = v_caller_branch
        ))
      ))
      OR public.check_permission(auth.uid(), 'targets.read_all');

    IF NOT v_visible THEN RAISE EXCEPTION 'ليس لديك صلاحية إعادة حساب هذا الهدف'; END IF;
  END IF;

  -- Every axis and the stored snapshot use one date bounded by the target
  -- period, preventing late manual edits from counting post-period activity.
  v_calc_date := LEAST(
    GREATEST(COALESCE(p_snapshot_date, CURRENT_DATE), v_target.period_start),
    v_target.period_end
  );

  CASE v_target.scope
    WHEN 'individual' THEN v_employee_ids := ARRAY[v_target.scope_id];
    WHEN 'branch' THEN SELECT ARRAY_AGG(id) INTO v_employee_ids FROM hr_employees WHERE branch_id = v_target.scope_id AND status = 'active';
    WHEN 'department' THEN SELECT ARRAY_AGG(id) INTO v_employee_ids FROM hr_employees WHERE department_id = v_target.scope_id AND status = 'active';
    WHEN 'company' THEN SELECT ARRAY_AGG(id) INTO v_employee_ids FROM hr_employees WHERE status = 'active';
    ELSE v_employee_ids := ARRAY[]::UUID[];
  END CASE;
  IF v_employee_ids IS NULL THEN v_employee_ids := ARRAY[]::UUID[]; END IF;

  CASE v_target.type_code
    WHEN 'sales_value' THEN
      IF v_target.product_id IS NOT NULL OR v_target.category_id IS NOT NULL THEN
        SELECT COALESCE(SUM(soi.line_total - COALESCE((
          SELECT SUM(sri.line_total) FROM sales_return_items sri
          JOIN sales_returns sr ON sr.id = sri.return_id
          WHERE sri.order_item_id = soi.id AND sr.status = 'confirmed'
        ), 0)), 0) INTO v_achieved
        FROM sales_orders so
        JOIN hr_employees he ON he.user_id = so.rep_id
        JOIN sales_order_items soi ON soi.order_id = so.id
        JOIN customers c ON c.id = so.customer_id
        LEFT JOIN products p ON p.id = soi.product_id
        WHERE he.id = ANY(v_employee_ids)
          AND so.status IN ('delivered','completed')
          AND so.delivered_at::DATE BETWEEN v_target.period_start AND v_calc_date
          AND (v_target.product_id IS NULL OR soi.product_id = v_target.product_id)
          AND (v_target.category_id IS NULL OR p.category_id = v_target.category_id)
          AND (v_target.governorate_id IS NULL OR c.governorate_id = v_target.governorate_id)
          AND (v_target.city_id IS NULL OR c.city_id = v_target.city_id)
          AND (v_target.area_id IS NULL OR c.area_id = v_target.area_id);
      ELSE
        SELECT COALESCE(SUM(GREATEST(so.total_amount - COALESCE(so.returned_amount, 0), 0)), 0) INTO v_achieved
        FROM sales_orders so JOIN hr_employees he ON he.user_id = so.rep_id
        JOIN customers c ON c.id = so.customer_id
        WHERE he.id = ANY(v_employee_ids) AND so.status IN ('delivered','completed')
          AND so.delivered_at::DATE BETWEEN v_target.period_start AND v_calc_date
          AND (v_target.governorate_id IS NULL OR c.governorate_id = v_target.governorate_id)
          AND (v_target.city_id IS NULL OR c.city_id = v_target.city_id)
          AND (v_target.area_id IS NULL OR c.area_id = v_target.area_id);
      END IF;
    WHEN 'collection' THEN
      v_achieved := public.target_collection_net_value(
        v_employee_ids, v_target.period_start, v_calc_date
      );
    WHEN 'visits_count' THEN
      SELECT COUNT(*) INTO v_achieved FROM activities a JOIN activity_types at_ ON at_.id = a.type_id
      WHERE a.employee_id = ANY(v_employee_ids) AND at_.category = 'visit'
        AND a.activity_date BETWEEN v_target.period_start AND v_calc_date AND a.deleted_at IS NULL;
    WHEN 'calls_count' THEN
      SELECT COUNT(*) INTO v_achieved FROM activities a JOIN activity_types at_ ON at_.id = a.type_id
      WHERE a.employee_id = ANY(v_employee_ids) AND at_.category = 'call'
        AND a.activity_date BETWEEN v_target.period_start AND v_calc_date AND a.deleted_at IS NULL;
    WHEN 'new_customers' THEN
      SELECT COUNT(*) INTO v_achieved FROM customers c
      WHERE c.assigned_rep_id IN (SELECT user_id FROM hr_employees WHERE id = ANY(v_employee_ids))
        AND c.created_at::DATE BETWEEN v_target.period_start AND v_calc_date AND c.is_active = true;
    WHEN 'product_qty' THEN
      SELECT COALESCE(SUM(GREATEST(soi.delivered_quantity - COALESCE(soi.returned_quantity, 0), 0)), 0) INTO v_achieved
      FROM sales_order_items soi JOIN sales_orders so ON so.id = soi.order_id
      JOIN hr_employees he ON he.user_id = so.rep_id
      WHERE he.id = ANY(v_employee_ids) AND so.status IN ('delivered','completed')
        AND so.delivered_at::DATE BETWEEN v_target.period_start AND v_calc_date
        AND (v_target.product_id IS NULL OR soi.product_id = v_target.product_id)
        AND (v_target.category_id IS NULL OR soi.product_id IN (SELECT id FROM products WHERE category_id = v_target.category_id));
    WHEN 'upgrade_value' THEN
      SELECT COUNT(*) INTO v_achieved
      FROM public.target_customer_progress_rows(p_target_id, v_calc_date) r
      WHERE r.is_achieved;
    WHEN 'reactivation' THEN
      SELECT COUNT(*) INTO v_achieved
      FROM public.target_customer_progress_rows(p_target_id, v_calc_date) r
      WHERE r.is_achieved;
    WHEN 'category_spread' THEN
      SELECT COUNT(*) INTO v_achieved
      FROM public.target_customer_progress_rows(p_target_id, v_calc_date) r
      WHERE r.is_achieved;
    ELSE v_achieved := 0;
  END CASE;

  v_pct := CASE WHEN v_target.target_value = 0 THEN 0 ELSE ROUND(v_achieved / v_target.target_value * 100, 2) END;
  v_days_elapsed := v_calc_date - v_target.period_start + 1;
  v_total_days := v_target.period_end - v_target.period_start + 1;
  v_expected_pct := ROUND(v_days_elapsed / GREATEST(v_total_days, 1) * 100, 2);
  v_trend := CASE
    WHEN v_achieved >= COALESCE(v_target.stretch_value, v_target.target_value * 1.2) THEN 'exceeded'
    WHEN v_achieved >= v_target.target_value THEN 'achieved'
    WHEN v_pct < v_expected_pct - 20 THEN 'behind'
    WHEN v_pct < v_expected_pct - 10 THEN 'at_risk'
    ELSE 'on_track' END;

  IF v_target.reward_type IS NOT NULL AND v_target.auto_payout = true THEN
    SELECT * INTO v_best_tier FROM target_reward_tiers
    WHERE target_id = p_target_id AND threshold_pct <= v_pct ORDER BY threshold_pct DESC LIMIT 1;
    IF FOUND AND v_target.reward_type = 'fixed' THEN
      v_expected_rwd := ROUND(COALESCE(v_target.reward_base_value, 0) * v_best_tier.reward_pct / 100.0, 2);
    END IF;
  END IF;

  INSERT INTO target_progress(target_id, snapshot_date, achieved_value, achievement_pct, trend, last_calc_at, calc_details)
  VALUES (p_target_id, v_calc_date, v_achieved, v_pct, v_trend, now(), jsonb_build_object(
    'expected_reward', v_expected_rwd, 'tier_label', v_best_tier.label,
    'days_elapsed', v_days_elapsed, 'total_days', v_total_days, 'expected_pct', v_expected_pct
  ))
  ON CONFLICT (target_id, snapshot_date) DO UPDATE SET
    achieved_value = EXCLUDED.achieved_value, achievement_pct = EXCLUDED.achievement_pct,
    trend = EXCLUDED.trend, last_calc_at = EXCLUDED.last_calc_at, calc_details = EXCLUDED.calc_details;
END;
$$;

REVOKE ALL ON FUNCTION public.recalculate_target_progress(UUID, DATE, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.recalculate_target_progress(UUID, DATE, BOOLEAN) TO authenticated;

-- Creation stays atomic, keeps its exact canonical signature, and computes all
-- baselines server-side so UI values can never drift from calculation values.
CREATE OR REPLACE FUNCTION public.create_target_with_rewards(
  p_type_id UUID, p_name TEXT, p_description TEXT DEFAULT NULL,
  p_scope TEXT DEFAULT 'individual', p_scope_id UUID DEFAULT NULL,
  p_period TEXT DEFAULT 'monthly', p_period_start DATE DEFAULT NULL, p_period_end DATE DEFAULT NULL,
  p_target_value NUMERIC DEFAULT 0, p_min_value NUMERIC DEFAULT NULL, p_stretch_value NUMERIC DEFAULT NULL,
  p_product_id UUID DEFAULT NULL, p_category_id UUID DEFAULT NULL,
  p_governorate_id UUID DEFAULT NULL, p_city_id UUID DEFAULT NULL, p_area_id UUID DEFAULT NULL,
  p_dormancy_days INTEGER DEFAULT NULL, p_filter_criteria JSONB DEFAULT '{}', p_notes TEXT DEFAULT NULL,
  p_reward_type TEXT DEFAULT NULL, p_reward_base_value NUMERIC DEFAULT NULL,
  p_reward_pool_basis TEXT DEFAULT NULL, p_payout_month_offset INTEGER DEFAULT 0,
  p_tiers JSONB DEFAULT '[]', p_customers JSONB DEFAULT '[]',
  p_auto_payout BOOLEAN DEFAULT false, p_user_id UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_target_id UUID; v_type_code TEXT; v_type_cat TEXT; v_tier JSONB; v_customer JSONB;
  v_seq INTEGER := 0; v_caller_id UUID; v_caller_branch_id UUID;
  v_has_read_all BOOLEAN; v_scope_allowed BOOLEAN := false;
  v_start DATE; v_end DATE; v_customer_id UUID; v_baseline NUMERIC;
  v_baseline_categories INTEGER; v_baseline_start DATE; v_baseline_end DATE; v_last_purchase DATE;
  v_customer_count INTEGER; v_growth NUMERIC; v_required_categories INTEGER; v_min_reactivation NUMERIC;
  v_employee_ids UUID[];
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  IF p_user_id IS NOT NULL AND p_user_id <> v_caller_id THEN RAISE EXCEPTION 'Unauthorized'; END IF;

  IF NOT (check_permission(v_caller_id, 'targets.create') OR check_permission(v_caller_id, 'targets.assign')) THEN
    RAISE EXCEPTION 'ليس لديك صلاحية إنشاء الأهداف';
  END IF;

  v_has_read_all := check_permission(v_caller_id, 'targets.read_all');
  IF NOT v_has_read_all THEN
    SELECT branch_id INTO v_caller_branch_id FROM hr_employees WHERE user_id = v_caller_id LIMIT 1;
    v_scope_allowed := CASE p_scope
      WHEN 'individual' THEN EXISTS (SELECT 1 FROM hr_employees WHERE id = p_scope_id AND branch_id = v_caller_branch_id)
      WHEN 'branch' THEN p_scope_id = v_caller_branch_id
      WHEN 'department' THEN EXISTS (SELECT 1 FROM hr_departments WHERE id = p_scope_id AND branch_id = v_caller_branch_id)
      ELSE false END;
    IF NOT v_scope_allowed THEN RAISE EXCEPTION '[EDARA] لا يمكنك إنشاء أهداف خارج نطاق فرعك'; END IF;
  END IF;

  SELECT code, category INTO v_type_code, v_type_cat FROM target_types WHERE id = p_type_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'نوع الهدف غير موجود'; END IF;

  IF p_scope NOT IN ('company', 'branch', 'department', 'individual')
    OR (p_scope = 'company' AND p_scope_id IS NOT NULL)
    OR (p_scope <> 'company' AND p_scope_id IS NULL) THEN
    RAISE EXCEPTION '[EDARA] نطاق الهدف غير صالح أو لا يطابق المعرّف المحدد';
  END IF;
  IF COALESCE(p_target_value, 0) <= 0 THEN
    RAISE EXCEPTION '[EDARA] القيمة المستهدفة يجب أن تكون أكبر من صفر';
  END IF;
  IF p_min_value IS NOT NULL AND (p_min_value <= 0 OR p_min_value > p_target_value) THEN
    RAISE EXCEPTION '[EDARA] الحد الأدنى يجب أن يكون موجباً وألا يتجاوز الهدف';
  END IF;
  IF p_stretch_value IS NOT NULL AND p_stretch_value < p_target_value THEN
    RAISE EXCEPTION '[EDARA] هدف التمدد يجب ألا يقل عن القيمة المستهدفة';
  END IF;
  IF p_product_id IS NOT NULL AND p_category_id IS NOT NULL THEN
    RAISE EXCEPTION '[EDARA] اختر منتجاً أو تصنيفاً، وليس الاثنين معاً';
  END IF;
  IF v_type_code = 'product_qty' AND p_product_id IS NULL AND p_category_id IS NULL THEN
    RAISE EXCEPTION '[EDARA] هدف كمية المنتج يتطلب منتجاً محدداً أو تصنيفاً';
  END IF;
  IF v_type_code NOT IN ('sales_value', 'product_qty')
    AND (p_product_id IS NOT NULL OR p_category_id IS NOT NULL) THEN
    RAISE EXCEPTION '[EDARA] فلتر المنتج أو التصنيف غير مدعوم لهذا النوع من الأهداف';
  END IF;
  IF v_type_code <> 'sales_value'
    AND (p_governorate_id IS NOT NULL OR p_city_id IS NOT NULL OR p_area_id IS NOT NULL) THEN
    RAISE EXCEPTION '[EDARA] الفلتر الجغرافي مدعوم لهدف المبيعات فقط';
  END IF;
  IF p_city_id IS NOT NULL AND p_governorate_id IS NULL THEN
    RAISE EXCEPTION '[EDARA] اختيار المدينة يتطلب اختيار المحافظة أولاً';
  END IF;
  IF p_area_id IS NOT NULL AND p_city_id IS NULL THEN
    RAISE EXCEPTION '[EDARA] اختيار المنطقة يتطلب اختيار المدينة أولاً';
  END IF;
  IF NOT is_valid_reward_config(v_type_cat, v_type_code, p_reward_type, p_reward_pool_basis) THEN
    RAISE EXCEPTION '[EDARA] تركيبة المكافأة غير صالحة للهدف من نوع [%]', v_type_code;
  END IF;
  IF p_reward_type IS NULL AND (
    p_reward_base_value IS NOT NULL
    OR p_reward_pool_basis IS NOT NULL
    OR p_auto_payout
    OR jsonb_array_length(COALESCE(p_tiers, '[]')) > 0
  ) THEN
    RAISE EXCEPTION '[EDARA] لا يمكن إرسال قيمة أو شرائح أو صرف تلقائي بدون نوع مكافأة';
  END IF;
  IF COALESCE(p_payout_month_offset, -1) < 0 THEN
    RAISE EXCEPTION '[EDARA] تأخير الصرف غير صالح';
  END IF;

  v_start := COALESCE(p_period_start, date_trunc('month', CURRENT_DATE)::DATE);
  v_end := COALESCE(p_period_end, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::DATE);
  IF v_start > v_end THEN RAISE EXCEPTION '[EDARA] بداية فترة الهدف بعد نهايتها'; END IF;

  IF v_type_code IN ('upgrade_value', 'reactivation', 'category_spread') THEN
    IF p_period <> 'monthly' THEN RAISE EXCEPTION '[EDARA] هذا النوع متاح شهرياً فقط في النسخة الحالية'; END IF;
    IF v_start <> date_trunc('month', v_start)::DATE
      OR v_end <> (date_trunc('month', v_start) + INTERVAL '1 month - 1 day')::DATE THEN
      RAISE EXCEPTION '[EDARA] محاور العملاء تتطلب شهراً تقويمياً كاملاً من أول يوم إلى آخر يوم';
    END IF;
    v_customer_count := jsonb_array_length(COALESCE(p_customers, '[]'));
    IF v_customer_count = 0 THEN RAISE EXCEPTION '[EDARA] يجب تحديد عميل واحد على الأقل'; END IF;
    IF p_target_value <= 0 OR p_target_value <> TRUNC(p_target_value) OR p_target_value > v_customer_count THEN
      RAISE EXCEPTION '[EDARA] القيمة المستهدفة يجب أن تكون عدداً صحيحاً لا يتجاوز عدد العملاء المحددين';
    END IF;
    IF EXISTS (
      SELECT 1 FROM jsonb_array_elements(COALESCE(p_customers, '[]')) x
      GROUP BY x->>'customer_id' HAVING COUNT(*) > 1
    ) THEN RAISE EXCEPTION '[EDARA] قائمة العملاء تحتوي على تكرار'; END IF;
    SELECT COALESCE(ARRAY_AGG(he.id), ARRAY[]::UUID[]) INTO v_employee_ids
    FROM public.hr_employees he
    WHERE public.target_scope_matches_employee(p_scope, p_scope_id, he.id);
    IF array_length(v_employee_ids, 1) IS NULL THEN
      RAISE EXCEPTION '[EDARA] نطاق الهدف لا يحتوي على موظفين نشطين';
    END IF;
  END IF;

  IF v_type_code = 'upgrade_value' THEN
    v_growth := NULLIF(p_filter_criteria->>'growth_pct', '')::NUMERIC;
    IF COALESCE(v_growth, 0) <= 0 THEN RAISE EXCEPTION '[EDARA] نسبة النمو يجب أن تكون أكبر من صفر'; END IF;
  ELSIF v_type_code = 'reactivation' THEN
    v_min_reactivation := NULLIF(p_filter_criteria->>'min_reactivation_value', '')::NUMERIC;
    IF COALESCE(p_dormancy_days, 0) <= 0 THEN RAISE EXCEPTION '[EDARA] أيام الخمول يجب أن تكون أكبر من صفر'; END IF;
    IF COALESCE(v_min_reactivation, 0) <= 0 THEN RAISE EXCEPTION '[EDARA] حد إعادة التنشيط يجب أن يكون أكبر من صفر'; END IF;
    IF p_auto_payout THEN
      RAISE EXCEPTION '[EDARA] الصرف التلقائي غير متاح حالياً لهدف إعادة التنشيط حتى تغطية المرتجعات المتأخرة';
    END IF;
  ELSIF v_type_code = 'category_spread' THEN
    v_required_categories := NULLIF(p_filter_criteria->>'required_category_count', '')::INTEGER;
    IF COALESCE(v_required_categories, 0) <= 0 THEN RAISE EXCEPTION '[EDARA] عدد التصنيفات المطلوب يجب أن يكون أكبر من صفر'; END IF;
  END IF;

  IF p_auto_payout AND (p_reward_type IS NULL OR COALESCE(p_reward_base_value, 0) <= 0
    OR jsonb_array_length(COALESCE(p_tiers, '[]')) = 0) THEN
    RAISE EXCEPTION '[EDARA] الصرف التلقائي يتطلب نوع وقيمة مكافأة وشريحة واحدة على الأقل';
  END IF;
  IF p_auto_payout AND p_scope <> 'individual' THEN
    RAISE EXCEPTION '[EDARA] الصرف التلقائي متاح للأهداف الفردية فقط';
  END IF;

  -- Individual overlap is the only ambiguous attribution case in this release.
  IF v_type_code IN ('upgrade_value', 'reactivation', 'category_spread') AND p_scope = 'individual' AND EXISTS (
    SELECT 1 FROM targets t
    JOIN target_customers tc ON tc.target_id = t.id
    JOIN jsonb_array_elements(COALESCE(p_customers, '[]')) x ON (x->>'customer_id')::UUID = tc.customer_id
    WHERE t.type_code = v_type_code AND t.scope = 'individual' AND t.scope_id = p_scope_id
      AND t.is_active = true AND daterange(t.period_start, t.period_end, '[]') && daterange(v_start, v_end, '[]')
  ) THEN RAISE EXCEPTION '[EDARA] أحد العملاء موجود بالفعل في هدف فردي متداخل من نفس النوع'; END IF;

  INSERT INTO targets(type_id, name, description, scope, scope_id, period, period_start, period_end,
    target_value, min_value, stretch_value, product_id, category_id, governorate_id, city_id, area_id,
    dormancy_days, filter_criteria, notes, reward_type, reward_base_value, reward_pool_basis,
    payout_month_offset, auto_payout, assigned_by, is_active, is_paused)
  VALUES (p_type_id, p_name, p_description, p_scope, p_scope_id, p_period, v_start, v_end,
    p_target_value, p_min_value, p_stretch_value,
    CASE WHEN v_type_code IN ('upgrade_value', 'reactivation', 'category_spread') THEN NULL ELSE p_product_id END,
    CASE WHEN v_type_code IN ('upgrade_value', 'reactivation', 'category_spread') THEN NULL ELSE p_category_id END,
    CASE WHEN v_type_code IN ('upgrade_value', 'reactivation', 'category_spread') THEN NULL ELSE p_governorate_id END,
    CASE WHEN v_type_code IN ('upgrade_value', 'reactivation', 'category_spread') THEN NULL ELSE p_city_id END,
    CASE WHEN v_type_code IN ('upgrade_value', 'reactivation', 'category_spread') THEN NULL ELSE p_area_id END,
    CASE WHEN v_type_code = 'reactivation' THEN p_dormancy_days ELSE NULL END,
    CASE v_type_code
      WHEN 'upgrade_value' THEN jsonb_build_object('growth_pct', v_growth)
      WHEN 'reactivation' THEN jsonb_build_object('min_reactivation_value', v_min_reactivation)
      WHEN 'category_spread' THEN jsonb_build_object('required_category_count', v_required_categories)
      ELSE COALESCE(p_filter_criteria, '{}')
    END,
    p_notes,
    p_reward_type, p_reward_base_value, p_reward_pool_basis, COALESCE(p_payout_month_offset, 0),
    false, v_caller_id, true, false)
  RETURNING id INTO v_target_id;

  FOR v_tier IN SELECT * FROM jsonb_array_elements(COALESCE(p_tiers, '[]')) LOOP
    v_seq := v_seq + 1;
    INSERT INTO target_reward_tiers(target_id, sequence, threshold_pct, reward_pct, label)
    VALUES (v_target_id, COALESCE((v_tier->>'sequence')::INTEGER, v_seq),
      (v_tier->>'threshold_pct')::NUMERIC, (v_tier->>'reward_pct')::NUMERIC, v_tier->>'label');
  END LOOP;

  FOR v_customer IN SELECT * FROM jsonb_array_elements(COALESCE(p_customers, '[]')) LOOP
    v_customer_id := (v_customer->>'customer_id')::UUID;
    IF NOT EXISTS (SELECT 1 FROM customers WHERE id = v_customer_id AND is_active = true) THEN
      RAISE EXCEPTION '[EDARA] عميل مستهدف غير موجود أو غير نشط';
    END IF;
    v_baseline := NULL; v_baseline_categories := NULL;
    v_baseline_start := NULL; v_baseline_end := NULL;

    IF v_type_code = 'upgrade_value' THEN
      v_baseline_start := (date_trunc('month', v_start) - INTERVAL '3 months')::DATE;
      v_baseline_end := (date_trunc('month', v_start) - INTERVAL '1 day')::DATE;
      SELECT ROUND(COALESCE(SUM(GREATEST(so.total_amount - COALESCE(so.returned_amount, 0), 0)), 0) / 3.0, 2)
      INTO v_baseline
      FROM sales_orders so JOIN hr_employees he ON he.user_id = so.rep_id
      WHERE so.customer_id = v_customer_id
        AND he.id = ANY(v_employee_ids)
        AND so.status IN ('delivered', 'completed')
        AND so.delivered_at >= v_baseline_start::TIMESTAMPTZ
        AND so.delivered_at < (v_baseline_end + 1)::TIMESTAMPTZ;
      IF COALESCE(v_baseline, 0) <= 0 THEN
        RAISE EXCEPTION '[EDARA] العميل [%] لا يملك خط أساس موجباً في آخر 3 أشهر كاملة', v_customer_id;
      END IF;
    ELSIF v_type_code = 'reactivation' THEN
      SELECT MAX(so.delivered_at::DATE) INTO v_last_purchase
      FROM sales_orders so JOIN hr_employees he ON he.user_id = so.rep_id
      WHERE so.customer_id = v_customer_id
        AND he.id = ANY(v_employee_ids)
        AND so.status IN ('delivered', 'completed') AND so.delivered_at < v_start::TIMESTAMPTZ
        AND GREATEST(so.total_amount - COALESCE(so.returned_amount, 0), 0) > 0;
      IF v_last_purchase IS NULL OR v_last_purchase > v_start - p_dormancy_days THEN
        RAISE EXCEPTION '[EDARA] العميل [%] لا يحقق شرط الخمول عند بداية الهدف', v_customer_id;
      END IF;
      v_baseline_start := v_last_purchase; v_baseline_end := v_last_purchase;
    ELSIF v_type_code = 'category_spread' THEN
      v_baseline_start := (date_trunc('month', v_start) - INTERVAL '1 month')::DATE;
      v_baseline_end := (date_trunc('month', v_start) - INTERVAL '1 day')::DATE;
      SELECT COUNT(DISTINCT p.category_id)::INTEGER INTO v_baseline_categories
      FROM sales_orders so JOIN hr_employees he ON he.user_id = so.rep_id
      JOIN sales_order_items soi ON soi.order_id = so.id JOIN products p ON p.id = soi.product_id
      WHERE so.customer_id = v_customer_id
        AND he.id = ANY(v_employee_ids)
        AND so.status IN ('delivered', 'completed')
        AND so.delivered_at >= v_baseline_start::TIMESTAMPTZ
        AND so.delivered_at < (v_baseline_end + 1)::TIMESTAMPTZ
        AND GREATEST(soi.delivered_quantity - COALESCE(soi.returned_quantity, 0), 0) > 0
        AND p.category_id IS NOT NULL;
    ELSE
      v_baseline := NULLIF(v_customer->>'baseline_value', '')::NUMERIC;
      v_baseline_categories := NULLIF(v_customer->>'baseline_category_count', '')::INTEGER;
      v_baseline_start := NULLIF(v_customer->>'baseline_period_start', '')::DATE;
      v_baseline_end := NULLIF(v_customer->>'baseline_period_end', '')::DATE;
    END IF;

    INSERT INTO target_customers(target_id, customer_id, baseline_value, baseline_category_count,
      baseline_period_start, baseline_period_end)
    VALUES (v_target_id, v_customer_id, v_baseline, v_baseline_categories, v_baseline_start, v_baseline_end);
  END LOOP;

  IF p_auto_payout THEN UPDATE targets SET auto_payout = true, updated_at = now() WHERE id = v_target_id; END IF;
  IF CURRENT_DATE >= v_start THEN
    PERFORM recalculate_target_progress(v_target_id, LEAST(CURRENT_DATE, v_end));
  END IF;
  RETURN v_target_id;
END;
$$;

-- Atomic target adjustment. All requested fields are validated against the
-- final state, updated once, audited once per changed field, and recalculated once.
CREATE OR REPLACE FUNCTION public.adjust_target_fields(
  p_target_id UUID,
  p_changes JSONB,
  p_reason TEXT,
  p_user_id UUID DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_target public.targets%ROWTYPE;
  v_updated public.targets%ROWTYPE;
  v_type_code TEXT;
  v_type_category TEXT;
  v_new_target NUMERIC;
  v_new_min NUMERIC;
  v_new_stretch NUMERIC;
  v_new_period_end DATE;
  v_new_reward_type TEXT;
  v_new_reward_base NUMERIC;
  v_new_reward_basis TEXT;
  v_new_auto_payout BOOLEAN;
  v_new_payout_offset INTEGER;
  v_new_filter JSONB;
  v_customer_count INTEGER;
  v_growth NUMERIC;
  v_min_reactivation NUMERIC;
  v_required_categories INTEGER;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  IF p_user_id IS NOT NULL AND p_user_id <> v_caller THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  IF NOT public.check_permission(v_caller, 'targets.update') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية تعديل الأهداف';
  END IF;
  IF NULLIF(BTRIM(p_reason), '') IS NULL THEN RAISE EXCEPTION 'يجب إدخال سبب التعديل'; END IF;
  IF p_changes IS NULL OR jsonb_typeof(p_changes) <> 'object' THEN
    RAISE EXCEPTION '[EDARA] تعديلات الهدف يجب أن تكون كائناً صالحاً';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_object_keys(p_changes) key
    WHERE key NOT IN (
      'target_value', 'min_value', 'stretch_value', 'period_end',
      'is_paused', 'is_active', 'filter_criteria', 'reward_base_value',
      'auto_payout', 'payout_month_offset', 'reward_type', 'reward_pool_basis'
    )
  ) THEN RAISE EXCEPTION '[EDARA] حقل غير مسموح بتعديله'; END IF;

  SELECT * INTO v_target FROM public.targets WHERE id = p_target_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'الهدف غير موجود'; END IF;

  SELECT tt.code, tt.category INTO v_type_code, v_type_category
  FROM public.target_types tt WHERE tt.id = v_target.type_id;

  IF EXISTS (
    SELECT 1 FROM public.target_reward_payouts
    WHERE target_id = p_target_id AND status = 'committed'
  ) AND p_changes ?| ARRAY[
    'target_value', 'min_value', 'stretch_value', 'period_end', 'filter_criteria',
    'reward_type', 'reward_base_value', 'reward_pool_basis', 'payout_month_offset'
  ] THEN
    RAISE EXCEPTION '[EDARA] الأساس التاريخي مُقفل بعد تثبيت مكافأة؛ أنشئ هدفاً جديداً للفترة القادمة';
  END IF;

  v_new_target := CASE WHEN p_changes ? 'target_value' THEN (p_changes->>'target_value')::NUMERIC ELSE v_target.target_value END;
  v_new_min := CASE WHEN p_changes ? 'min_value' THEN (p_changes->>'min_value')::NUMERIC ELSE v_target.min_value END;
  v_new_stretch := CASE WHEN p_changes ? 'stretch_value' THEN (p_changes->>'stretch_value')::NUMERIC ELSE v_target.stretch_value END;
  v_new_period_end := CASE WHEN p_changes ? 'period_end' THEN (p_changes->>'period_end')::DATE ELSE v_target.period_end END;
  v_new_filter := CASE WHEN p_changes ? 'filter_criteria' THEN p_changes->'filter_criteria' ELSE v_target.filter_criteria END;
  v_new_reward_type := CASE WHEN p_changes ? 'reward_type' THEN NULLIF(p_changes->>'reward_type', '') ELSE v_target.reward_type END;
  v_new_reward_base := CASE WHEN p_changes ? 'reward_base_value' THEN (p_changes->>'reward_base_value')::NUMERIC ELSE v_target.reward_base_value END;
  v_new_reward_basis := CASE WHEN p_changes ? 'reward_pool_basis' THEN NULLIF(p_changes->>'reward_pool_basis', '') ELSE v_target.reward_pool_basis END;
  v_new_auto_payout := CASE WHEN p_changes ? 'auto_payout' THEN (p_changes->>'auto_payout')::BOOLEAN ELSE v_target.auto_payout END;
  v_new_payout_offset := CASE WHEN p_changes ? 'payout_month_offset' THEN (p_changes->>'payout_month_offset')::INTEGER ELSE v_target.payout_month_offset END;

  IF v_new_reward_type IS NULL THEN
    v_new_reward_base := NULL;
    v_new_reward_basis := NULL;
    v_new_auto_payout := false;
  ELSIF v_new_reward_type = 'fixed' THEN
    v_new_reward_basis := NULL;
  END IF;

  IF COALESCE(v_new_target, 0) <= 0 THEN RAISE EXCEPTION '[EDARA] القيمة المستهدفة يجب أن تكون أكبر من صفر'; END IF;
  IF v_new_min IS NOT NULL AND (v_new_min <= 0 OR v_new_min > v_new_target) THEN
    RAISE EXCEPTION '[EDARA] الحد الأدنى يجب أن يكون موجباً وألا يتجاوز الهدف';
  END IF;
  IF v_new_stretch IS NOT NULL AND v_new_stretch < v_new_target THEN
    RAISE EXCEPTION '[EDARA] هدف التمدد يجب ألا يقل عن القيمة المستهدفة';
  END IF;
  IF v_new_period_end IS NULL OR v_new_period_end < v_target.period_start THEN
    RAISE EXCEPTION '[EDARA] نهاية الفترة لا يمكن أن تسبق بدايتها';
  END IF;
  IF v_new_filter IS NULL OR jsonb_typeof(v_new_filter) <> 'object' THEN
    RAISE EXCEPTION '[EDARA] فلاتر الهدف غير صالحة';
  END IF;

  IF v_type_code IN ('upgrade_value', 'reactivation', 'category_spread') THEN
    SELECT COUNT(*) INTO v_customer_count
    FROM public.target_customers
    WHERE target_id = p_target_id;

    IF v_new_target <> TRUNC(v_new_target) OR v_new_target > v_customer_count THEN
      RAISE EXCEPTION '[EDARA] القيمة المستهدفة يجب أن تكون عدداً صحيحاً لا يتجاوز عدد العملاء المحددين';
    END IF;
    IF v_target.period <> 'monthly'
      OR v_target.period_start <> date_trunc('month', v_target.period_start)::DATE
      OR v_new_period_end <> (date_trunc('month', v_target.period_start) + INTERVAL '1 month - 1 day')::DATE THEN
      RAISE EXCEPTION '[EDARA] محاور العملاء تتطلب شهراً تقويمياً كاملاً من أول يوم إلى آخر يوم';
    END IF;

    IF v_type_code = 'upgrade_value' THEN
      v_growth := NULLIF(v_new_filter->>'growth_pct', '')::NUMERIC;
      IF COALESCE(v_growth, 0) <= 0 THEN
        RAISE EXCEPTION '[EDARA] نسبة النمو يجب أن تكون أكبر من صفر';
      END IF;
    ELSIF v_type_code = 'reactivation' THEN
      v_min_reactivation := NULLIF(v_new_filter->>'min_reactivation_value', '')::NUMERIC;
      IF COALESCE(v_min_reactivation, 0) <= 0 THEN
        RAISE EXCEPTION '[EDARA] حد إعادة التنشيط يجب أن يكون أكبر من صفر';
      END IF;
    ELSE
      v_required_categories := NULLIF(v_new_filter->>'required_category_count', '')::INTEGER;
      IF COALESCE(v_required_categories, 0) <= 0 THEN
        RAISE EXCEPTION '[EDARA] عدد التصنيفات المطلوب يجب أن يكون أكبر من صفر';
      END IF;
    END IF;
  END IF;

  IF NOT public.is_valid_reward_config(v_type_category, v_type_code, v_new_reward_type, v_new_reward_basis) THEN
    RAISE EXCEPTION '[EDARA] تركيبة المكافأة غير صالحة لهذا النوع من الأهداف';
  END IF;
  IF v_new_reward_type IS NOT NULL AND COALESCE(v_new_reward_base, 0) <= 0 THEN
    RAISE EXCEPTION '[EDARA] قيمة المكافأة يجب أن تكون أكبر من صفر';
  END IF;
  IF COALESCE(v_new_payout_offset, -1) < 0 THEN RAISE EXCEPTION '[EDARA] تأخير الصرف غير صالح'; END IF;
  IF v_new_auto_payout THEN
    IF v_target.scope <> 'individual' THEN RAISE EXCEPTION '[EDARA] الصرف التلقائي متاح للأهداف الفردية فقط'; END IF;
    IF v_type_code = 'reactivation' THEN RAISE EXCEPTION '[EDARA] الصرف التلقائي غير متاح لإعادة التنشيط حالياً'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.target_reward_tiers WHERE target_id = p_target_id) THEN
      RAISE EXCEPTION '[EDARA] الصرف التلقائي يتطلب شريحة مكافأة واحدة على الأقل';
    END IF;
  END IF;

  UPDATE public.targets SET
    target_value = v_new_target,
    min_value = v_new_min,
    stretch_value = v_new_stretch,
    period_end = v_new_period_end,
    is_paused = CASE WHEN p_changes ? 'is_paused' THEN (p_changes->>'is_paused')::BOOLEAN ELSE is_paused END,
    is_active = CASE WHEN p_changes ? 'is_active' THEN (p_changes->>'is_active')::BOOLEAN ELSE is_active END,
    filter_criteria = v_new_filter,
    reward_type = v_new_reward_type,
    reward_base_value = v_new_reward_base,
    reward_pool_basis = v_new_reward_basis,
    auto_payout = v_new_auto_payout,
    payout_month_offset = v_new_payout_offset,
    paused_at = CASE
      WHEN p_changes ? 'is_paused' AND (p_changes->>'is_paused')::BOOLEAN THEN now()
      WHEN p_changes ? 'is_paused' THEN NULL
      ELSE paused_at
    END,
    updated_at = now()
  WHERE id = p_target_id
  RETURNING * INTO v_updated;

  INSERT INTO public.target_adjustments(
    target_id, field_changed, old_value, new_value, reason, adjusted_by
  )
  SELECT p_target_id, changed.field_name, changed.old_value, changed.new_value, BTRIM(p_reason), v_caller
  FROM (VALUES
    ('target_value', v_target.target_value::TEXT, v_updated.target_value::TEXT),
    ('min_value', v_target.min_value::TEXT, v_updated.min_value::TEXT),
    ('stretch_value', v_target.stretch_value::TEXT, v_updated.stretch_value::TEXT),
    ('period_end', v_target.period_end::TEXT, v_updated.period_end::TEXT),
    ('is_paused', v_target.is_paused::TEXT, v_updated.is_paused::TEXT),
    ('is_active', v_target.is_active::TEXT, v_updated.is_active::TEXT),
    ('filter_criteria', v_target.filter_criteria::TEXT, v_updated.filter_criteria::TEXT),
    ('reward_type', v_target.reward_type::TEXT, v_updated.reward_type::TEXT),
    ('reward_base_value', v_target.reward_base_value::TEXT, v_updated.reward_base_value::TEXT),
    ('reward_pool_basis', v_target.reward_pool_basis::TEXT, v_updated.reward_pool_basis::TEXT),
    ('auto_payout', v_target.auto_payout::TEXT, v_updated.auto_payout::TEXT),
    ('payout_month_offset', v_target.payout_month_offset::TEXT, v_updated.payout_month_offset::TEXT)
  ) AS changed(field_name, old_value, new_value)
  WHERE changed.old_value IS DISTINCT FROM changed.new_value;

  IF v_target.reward_type IS DISTINCT FROM v_updated.reward_type
    OR v_target.reward_base_value IS DISTINCT FROM v_updated.reward_base_value
    OR v_target.reward_pool_basis IS DISTINCT FROM v_updated.reward_pool_basis
    OR v_target.auto_payout IS DISTINCT FROM v_updated.auto_payout
    OR v_target.payout_month_offset IS DISTINCT FROM v_updated.payout_month_offset THEN
    DELETE FROM public.target_reward_payouts
    WHERE target_id = p_target_id AND status = 'pending';
  END IF;

  PERFORM public.recalculate_target_progress(p_target_id, CURRENT_DATE);
END;
$$;

-- Compatibility path for the existing single-field UI. It delegates to the
-- same atomic implementation and therefore cannot bypass final-state checks.
CREATE OR REPLACE FUNCTION public.adjust_target(
  p_target_id UUID,
  p_field TEXT,
  p_new_value TEXT,
  p_reason TEXT,
  p_user_id UUID DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public.adjust_target_fields(
    p_target_id,
    CASE
      WHEN p_new_value IS NULL OR LOWER(BTRIM(p_new_value)) = 'null'
        THEN jsonb_build_object(p_field, NULL)
      WHEN p_field = 'filter_criteria'
        THEN jsonb_build_object(p_field, p_new_value::JSONB)
      ELSE jsonb_build_object(p_field, p_new_value)
    END,
    p_reason,
    p_user_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.adjust_target_fields(UUID, JSONB, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.adjust_target_fields(UUID, JSONB, TEXT, UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.adjust_target(UUID, TEXT, TEXT, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.adjust_target(UUID, TEXT, TEXT, TEXT, UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.calc_target_pool_value(UUID, UUID, DATE, DATE) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_target_with_rewards(UUID, TEXT, TEXT, TEXT, UUID, TEXT, DATE, DATE, NUMERIC, NUMERIC, NUMERIC, UUID, UUID, UUID, UUID, UUID, INTEGER, JSONB, TEXT, TEXT, NUMERIC, TEXT, INTEGER, JSONB, JSONB, BOOLEAN, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_target_with_rewards(UUID, TEXT, TEXT, TEXT, UUID, TEXT, DATE, DATE, NUMERIC, NUMERIC, NUMERIC, UUID, UUID, UUID, UUID, UUID, INTEGER, JSONB, TEXT, TEXT, NUMERIC, TEXT, INTEGER, JSONB, JSONB, BOOLEAN, UUID) TO authenticated;

-- Scheduled and trigger-only recalculation entry points stay available to their
-- owners, pg_cron and table triggers, but are not callable through the Data API.
REVOKE ALL ON FUNCTION public.recalculate_all_active_targets(DATE) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.recalculate_targets_for_employee(UUID, TEXT[], DATE, DATE) FROM PUBLIC, anon, authenticated;

-- Preserve the existing payout implementation verbatim and put the permission
-- boundary in a small wrapper. approve_payroll_run remains compatible because
-- it resolves the same public signature and payroll approvers are allowed.
ALTER FUNCTION public.prepare_target_reward_payouts(UUID)
  RENAME TO prepare_target_reward_payouts_internal;
REVOKE ALL ON FUNCTION public.prepare_target_reward_payouts_internal(UUID) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.prepare_target_reward_payouts(p_period_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller UUID := auth.uid();
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  IF NOT (
    public.check_permission(v_caller, 'hr.payroll.read')
    OR public.check_permission(v_caller, 'hr.payroll.approve')
    OR public.check_permission(v_caller, 'targets.read_all')
  ) THEN
    RAISE EXCEPTION '[EDARA] ليس لديك صلاحية تجهيز مكافآت الأهداف للرواتب';
  END IF;

  RETURN public.prepare_target_reward_payouts_internal(p_period_id);
END;
$$;

REVOKE ALL ON FUNCTION public.prepare_target_reward_payouts(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prepare_target_reward_payouts(UUID) TO authenticated;

COMMENT ON FUNCTION public.get_target_customer_progress(UUID, DATE) IS
  'Read-only per-customer tracking for upgrade, reactivation, and category-spread targets.';
COMMENT ON FUNCTION public.get_reactivation_target_candidates(TEXT, UUID, DATE, INTEGER, TEXT, INTEGER) IS
  'Read-only dormant buyer candidates, attributed by delivered sales order rep and target scope.';
