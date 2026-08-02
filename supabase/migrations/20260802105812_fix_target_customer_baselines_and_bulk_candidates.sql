-- ============================================================
-- EDARA v2 — surgical correction for customer target baselines
--
-- Scope:
--   * Customer state and baselines are company-wide.
--   * Achievement remains attributable to the target employee scope.
--   * Category spread means NEW categories beyond a frozen baseline set.
--   * Operational sales/return tables remain read-only inputs.
-- ============================================================

ALTER TABLE public.target_customers
  ADD COLUMN IF NOT EXISTS baseline_category_ids UUID[];

COMMENT ON COLUMN public.target_customers.baseline_category_ids IS
  'Frozen product-category IDs bought in the complete month before a category-spread target.';

WITH frozen_baselines AS (
  SELECT
    tc.id AS target_customer_id,
    COALESCE(
      ARRAY_AGG(DISTINCT p.category_id ORDER BY p.category_id)
        FILTER (WHERE p.category_id IS NOT NULL),
      ARRAY[]::UUID[]
    ) AS category_ids
  FROM public.target_customers tc
  JOIN public.targets t ON t.id = tc.target_id AND t.type_code = 'category_spread'
  LEFT JOIN public.sales_orders so
    ON so.customer_id = tc.customer_id
   AND so.status IN ('delivered', 'completed')
   AND analytics.effective_sale_date(so.delivered_at, so.order_date)
       BETWEEN (date_trunc('month', t.period_start) - INTERVAL '1 month')::DATE
           AND (date_trunc('month', t.period_start) - INTERVAL '1 day')::DATE
  LEFT JOIN public.sales_order_items soi
    ON soi.order_id = so.id
   AND GREATEST(soi.delivered_quantity - COALESCE(soi.returned_quantity, 0), 0) > 0
  LEFT JOIN public.products p ON p.id = soi.product_id
  WHERE tc.baseline_category_ids IS NULL
  GROUP BY tc.id
)
UPDATE public.target_customers tc
SET baseline_category_ids = fb.category_ids,
    baseline_category_count = COALESCE(cardinality(fb.category_ids), 0)
FROM frozen_baselines fb
WHERE tc.id = fb.target_customer_id;

UPDATE public.target_types
SET description = 'عدد العملاء المحددين الذين اشتروا العدد المطلوب من تصنيفات جديدة لم تكن ضمن خط الشهر السابق'
WHERE code = 'category_spread';


CREATE OR REPLACE FUNCTION public.get_target_customer_candidates(
  p_type_code TEXT,
  p_scope TEXT,
  p_scope_id UUID,
  p_period_start DATE,
  p_dormancy_days INTEGER DEFAULT NULL,
  p_search TEXT DEFAULT NULL,
  p_customer_type TEXT DEFAULT NULL,
  p_governorate_id UUID DEFAULT NULL,
  p_city_id UUID DEFAULT NULL,
  p_area_id UUID DEFAULT NULL,
  p_employee_id UUID DEFAULT NULL,
  p_baseline_min NUMERIC DEFAULT NULL,
  p_baseline_max NUMERIC DEFAULT NULL,
  p_last_purchase_from DATE DEFAULT NULL,
  p_last_purchase_to DATE DEFAULT NULL,
  p_page INTEGER DEFAULT 1,
  p_page_size INTEGER DEFAULT 50
) RETURNS TABLE (
  customer_id UUID,
  customer_name TEXT,
  customer_code TEXT,
  customer_type TEXT,
  assigned_rep_id UUID,
  assigned_rep_name TEXT,
  governorate_name TEXT,
  city_name TEXT,
  area_name TEXT,
  last_purchase_date DATE,
  dormant_days INTEGER,
  baseline_value NUMERIC,
  baseline_category_count INTEGER,
  eligible BOOLEAN,
  eligibility_reason TEXT,
  total_count BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_branch UUID;
  v_allowed BOOLEAN := false;
  v_page INTEGER := GREATEST(COALESCE(p_page, 1), 1);
  v_page_size INTEGER := LEAST(GREATEST(COALESCE(p_page_size, 50), 1), 100);
  v_baseline_start DATE;
  v_baseline_end DATE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  IF p_type_code NOT IN ('upgrade_value', 'reactivation', 'category_spread') THEN
    RAISE EXCEPTION '[EDARA] نوع محور العملاء غير صالح';
  END IF;
  IF p_period_start IS NULL THEN RAISE EXCEPTION '[EDARA] بداية فترة الهدف مطلوبة'; END IF;
  IF p_scope NOT IN ('company', 'branch', 'department', 'individual')
    OR (p_scope = 'company' AND p_scope_id IS NOT NULL)
    OR (p_scope <> 'company' AND p_scope_id IS NULL) THEN
    RAISE EXCEPTION '[EDARA] نطاق الهدف غير صالح';
  END IF;
  IF p_type_code = 'reactivation' AND COALESCE(p_dormancy_days, 0) <= 0 THEN
    RAISE EXCEPTION '[EDARA] أيام الخمول يجب أن تكون أكبر من صفر';
  END IF;

  SELECT branch_id INTO v_caller_branch
  FROM public.hr_employees
  WHERE user_id = auth.uid()
  LIMIT 1;

  v_allowed := public.check_permission(auth.uid(), 'targets.read_all') OR (
    (public.check_permission(auth.uid(), 'targets.create')
      OR public.check_permission(auth.uid(), 'targets.assign'))
    AND CASE p_scope
      WHEN 'individual' THEN EXISTS (
        SELECT 1 FROM public.hr_employees
        WHERE id = p_scope_id AND branch_id = v_caller_branch AND status = 'active'
      )
      WHEN 'branch' THEN p_scope_id = v_caller_branch
      WHEN 'department' THEN EXISTS (
        SELECT 1 FROM public.hr_departments
        WHERE id = p_scope_id AND branch_id = v_caller_branch
      )
      ELSE false
    END
  );
  IF NOT v_allowed THEN RAISE EXCEPTION 'ليس لديك صلاحية قراءة مرشحي هذا النطاق'; END IF;

  v_baseline_start := (date_trunc('month', p_period_start) - INTERVAL '3 months')::DATE;
  v_baseline_end := (date_trunc('month', p_period_start) - INTERVAL '1 day')::DATE;

  RETURN QUERY
  WITH scoped_customers AS (
    SELECT
      c.id, c.name, c.code, c.type::TEXT AS customer_type,
      c.assigned_rep_id, rep.full_name AS assigned_rep_name,
      g.name AS governorate_name, ci.name AS city_name, a.name AS area_name
    FROM public.customers c
    LEFT JOIN public.profiles rep ON rep.id = c.assigned_rep_id
    LEFT JOIN public.governorates g ON g.id = c.governorate_id
    LEFT JOIN public.cities ci ON ci.id = c.city_id
    LEFT JOIN public.areas a ON a.id = c.area_id
    WHERE c.is_active = true
      AND (
        p_scope = 'company'
        OR EXISTS (
          SELECT 1
          FROM public.hr_employees owner_employee
          WHERE owner_employee.user_id = c.assigned_rep_id
            AND public.target_scope_matches_employee(p_scope, p_scope_id, owner_employee.id)
        )
      )
      AND (p_customer_type IS NULL OR c.type::TEXT = p_customer_type)
      AND (p_governorate_id IS NULL OR c.governorate_id = p_governorate_id)
      AND (p_city_id IS NULL OR c.city_id = p_city_id)
      AND (p_area_id IS NULL OR c.area_id = p_area_id)
      AND (p_employee_id IS NULL OR EXISTS (
        SELECT 1 FROM public.hr_employees filtered_employee
        WHERE filtered_employee.id = p_employee_id
          AND filtered_employee.user_id = c.assigned_rep_id
      ))
      AND (
        NULLIF(BTRIM(p_search), '') IS NULL
        OR NOT EXISTS (
          SELECT 1
          FROM regexp_split_to_table(BTRIM(p_search), E'\\s+') AS term
          WHERE CONCAT_WS(' ', c.name, c.code, c.phone, c.mobile)
            NOT ILIKE '%' || term || '%'
        )
      )
  ),
  sales_metrics AS (
    SELECT
      so.customer_id,
      MAX(analytics.effective_sale_date(so.delivered_at, so.order_date))
        FILTER (
          WHERE analytics.effective_sale_date(so.delivered_at, so.order_date) < p_period_start
            AND GREATEST(so.total_amount - COALESCE(so.returned_amount, 0), 0) > 0
        ) AS last_purchase_date,
      ROUND(
        COALESCE(SUM(GREATEST(so.total_amount - COALESCE(so.returned_amount, 0), 0))
          FILTER (
            WHERE analytics.effective_sale_date(so.delivered_at, so.order_date)
              BETWEEN v_baseline_start AND v_baseline_end
          ), 0) / 3.0,
        2
      ) AS baseline_value
    FROM public.sales_orders so
    JOIN scoped_customers sc ON sc.id = so.customer_id
    WHERE so.status IN ('delivered', 'completed')
    GROUP BY so.customer_id
  ),
  category_metrics AS (
    SELECT
      so.customer_id,
      COUNT(DISTINCT p.category_id)::INTEGER AS baseline_category_count
    FROM public.sales_orders so
    JOIN scoped_customers sc ON sc.id = so.customer_id
    JOIN public.sales_order_items soi ON soi.order_id = so.id
    JOIN public.products p ON p.id = soi.product_id
    WHERE so.status IN ('delivered', 'completed')
      AND analytics.effective_sale_date(so.delivered_at, so.order_date)
          BETWEEN (date_trunc('month', p_period_start) - INTERVAL '1 month')::DATE
              AND (date_trunc('month', p_period_start) - INTERVAL '1 day')::DATE
      AND GREATEST(soi.delivered_quantity - COALESCE(soi.returned_quantity, 0), 0) > 0
      AND p.category_id IS NOT NULL
    GROUP BY so.customer_id
  ),
  evaluated AS (
    SELECT
      sc.*,
      sm.last_purchase_date,
      CASE WHEN sm.last_purchase_date IS NULL THEN NULL
        ELSE (p_period_start - sm.last_purchase_date)::INTEGER END AS dormant_days,
      COALESCE(sm.baseline_value, 0)::NUMERIC AS baseline_value,
      COALESCE(cm.baseline_category_count, 0)::INTEGER AS baseline_category_count,
      CASE p_type_code
        WHEN 'upgrade_value' THEN COALESCE(sm.baseline_value, 0) > 0
        WHEN 'reactivation' THEN sm.last_purchase_date IS NOT NULL
          AND sm.last_purchase_date <= p_period_start - p_dormancy_days
        WHEN 'category_spread' THEN true
      END AS eligible,
      CASE
        WHEN p_type_code = 'upgrade_value' AND COALESCE(sm.baseline_value, 0) <= 0
          THEN 'baseline_missing'
        WHEN p_type_code = 'reactivation' AND sm.last_purchase_date IS NULL
          THEN 'no_purchase_history'
        WHEN p_type_code = 'reactivation'
          AND sm.last_purchase_date > p_period_start - p_dormancy_days
          THEN 'not_dormant'
        ELSE 'eligible'
      END AS eligibility_reason
    FROM scoped_customers sc
    LEFT JOIN sales_metrics sm ON sm.customer_id = sc.id
    LEFT JOIN category_metrics cm ON cm.customer_id = sc.id
  ),
  filtered AS (
    SELECT *
    FROM evaluated e
    WHERE e.eligible
      AND (p_baseline_min IS NULL OR (
        CASE WHEN p_type_code = 'category_spread'
          THEN e.baseline_category_count::NUMERIC ELSE e.baseline_value END
      ) >= p_baseline_min)
      AND (p_baseline_max IS NULL OR (
        CASE WHEN p_type_code = 'category_spread'
          THEN e.baseline_category_count::NUMERIC ELSE e.baseline_value END
      ) <= p_baseline_max)
      AND (p_last_purchase_from IS NULL OR e.last_purchase_date >= p_last_purchase_from)
      AND (p_last_purchase_to IS NULL OR e.last_purchase_date <= p_last_purchase_to)
  )
  SELECT
    f.id, f.name::TEXT, f.code::TEXT, f.customer_type,
    f.assigned_rep_id, f.assigned_rep_name::TEXT,
    f.governorate_name::TEXT, f.city_name::TEXT, f.area_name::TEXT,
    f.last_purchase_date, f.dormant_days, f.baseline_value,
    f.baseline_category_count, f.eligible, f.eligibility_reason,
    COUNT(*) OVER() AS total_count
  FROM filtered f
  ORDER BY f.name, f.id
  LIMIT v_page_size
  OFFSET (v_page - 1) * v_page_size;
END;
$$;

REVOKE ALL ON FUNCTION public.get_target_customer_candidates(
  TEXT, TEXT, UUID, DATE, INTEGER, TEXT, TEXT, UUID, UUID, UUID,
  UUID, NUMERIC, NUMERIC, DATE, DATE, INTEGER, INTEGER
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_target_customer_candidates(
  TEXT, TEXT, UUID, DATE, INTEGER, TEXT, TEXT, UUID, UUID, UUID,
  UUID, NUMERIC, NUMERIC, DATE, DATE, INTEGER, INTEGER
) TO authenticated;


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
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT
    c.customer_id, c.customer_name, c.customer_code,
    c.last_purchase_date, c.dormant_days
  FROM public.get_target_customer_candidates(
    p_type_code => 'reactivation',
    p_scope => p_scope,
    p_scope_id => p_scope_id,
    p_period_start => p_period_start,
    p_dormancy_days => p_dormancy_days,
    p_search => p_search,
    p_page => 1,
    p_page_size => LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100)
  ) c;
$$;

REVOKE ALL ON FUNCTION public.get_reactivation_target_candidates(
  TEXT, UUID, DATE, INTEGER, TEXT, INTEGER
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_reactivation_target_candidates(
  TEXT, UUID, DATE, INTEGER, TEXT, INTEGER
) TO authenticated;

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
             MAX(analytics.effective_sale_date(so.delivered_at, so.order_date)) AS last_sale
      FROM public.sales_orders so
      JOIN public.hr_employees he ON he.user_id = so.rep_id
      JOIN public.target_customers selected
        ON selected.target_id = p_target_id AND selected.customer_id = so.customer_id
      WHERE he.id = ANY(v_employee_ids)
        AND so.status IN ('delivered', 'completed')
        AND analytics.effective_sale_date(so.delivered_at, so.order_date)
            BETWEEN v_target.period_start AND v_end
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
        AND analytics.effective_sale_date(so.delivered_at, so.order_date)
            BETWEEN v_target.period_start AND v_end
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
             MAX(analytics.effective_sale_date(so.delivered_at, so.order_date)) AS last_sale
      FROM public.sales_orders so
      JOIN public.hr_employees he ON he.user_id = so.rep_id
      JOIN public.target_customers selected
        ON selected.target_id = p_target_id AND selected.customer_id = so.customer_id
      JOIN public.sales_order_items soi ON soi.order_id = so.id
      JOIN public.products p ON p.id = soi.product_id
      WHERE he.id = ANY(v_employee_ids)
        AND so.status IN ('delivered', 'completed')
        AND analytics.effective_sale_date(so.delivered_at, so.order_date)
            BETWEEN v_target.period_start AND v_end
        AND GREATEST(soi.delivered_quantity - COALESCE(soi.returned_quantity, 0), 0) > 0
        AND p.category_id IS NOT NULL
        AND NOT (
          p.category_id = ANY(COALESCE(selected.baseline_category_ids, ARRAY[]::UUID[]))
        )
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

REVOKE ALL ON FUNCTION public.target_customer_progress_rows(UUID, DATE)
  FROM PUBLIC, anon, authenticated;

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
  v_baseline_categories INTEGER; v_baseline_category_ids UUID[];
  v_baseline_start DATE; v_baseline_end DATE; v_last_purchase DATE;
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
    IF p_scope <> 'company' AND NOT EXISTS (
      SELECT 1
      FROM customers scoped_customer
      JOIN hr_employees owner_employee ON owner_employee.user_id = scoped_customer.assigned_rep_id
      WHERE scoped_customer.id = v_customer_id
        AND public.target_scope_matches_employee(p_scope, p_scope_id, owner_employee.id)
    ) THEN
      RAISE EXCEPTION '[EDARA] العميل [%] لا ينتمي إلى نطاق الهدف المحدد', v_customer_id;
    END IF;
    v_baseline := NULL; v_baseline_categories := NULL; v_baseline_category_ids := NULL;
    v_baseline_start := NULL; v_baseline_end := NULL;

    IF v_type_code = 'upgrade_value' THEN
      v_baseline_start := (date_trunc('month', v_start) - INTERVAL '3 months')::DATE;
      v_baseline_end := (date_trunc('month', v_start) - INTERVAL '1 day')::DATE;
      SELECT ROUND(COALESCE(SUM(GREATEST(so.total_amount - COALESCE(so.returned_amount, 0), 0)), 0) / 3.0, 2)
      INTO v_baseline
      FROM sales_orders so
      WHERE so.customer_id = v_customer_id
        AND so.status IN ('delivered', 'completed')
        AND analytics.effective_sale_date(so.delivered_at, so.order_date)
            BETWEEN v_baseline_start AND v_baseline_end;
      IF COALESCE(v_baseline, 0) <= 0 THEN
        RAISE EXCEPTION '[EDARA] العميل [%] لا يملك خط أساس موجباً في آخر 3 أشهر كاملة', v_customer_id;
      END IF;
    ELSIF v_type_code = 'reactivation' THEN
      SELECT MAX(analytics.effective_sale_date(so.delivered_at, so.order_date)) INTO v_last_purchase
      FROM sales_orders so
      WHERE so.customer_id = v_customer_id
        AND so.status IN ('delivered', 'completed')
        AND analytics.effective_sale_date(so.delivered_at, so.order_date) < v_start
        AND GREATEST(so.total_amount - COALESCE(so.returned_amount, 0), 0) > 0;
      IF v_last_purchase IS NULL OR v_last_purchase > v_start - p_dormancy_days THEN
        RAISE EXCEPTION '[EDARA] العميل [%] لا يحقق شرط الخمول عند بداية الهدف', v_customer_id;
      END IF;
      v_baseline_start := v_last_purchase; v_baseline_end := v_last_purchase;
    ELSIF v_type_code = 'category_spread' THEN
      v_baseline_start := (date_trunc('month', v_start) - INTERVAL '1 month')::DATE;
      v_baseline_end := (date_trunc('month', v_start) - INTERVAL '1 day')::DATE;
      SELECT COALESCE(
        ARRAY_AGG(DISTINCT p.category_id ORDER BY p.category_id)
          FILTER (WHERE p.category_id IS NOT NULL),
        ARRAY[]::UUID[]
      ) INTO v_baseline_category_ids
      FROM sales_orders so
      JOIN sales_order_items soi ON soi.order_id = so.id
      JOIN products p ON p.id = soi.product_id
      WHERE so.customer_id = v_customer_id
        AND so.status IN ('delivered', 'completed')
        AND analytics.effective_sale_date(so.delivered_at, so.order_date)
            BETWEEN v_baseline_start AND v_baseline_end
        AND GREATEST(soi.delivered_quantity - COALESCE(soi.returned_quantity, 0), 0) > 0
        AND p.category_id IS NOT NULL;
      v_baseline_categories := COALESCE(cardinality(v_baseline_category_ids), 0);
    ELSE
      v_baseline := NULLIF(v_customer->>'baseline_value', '')::NUMERIC;
      v_baseline_categories := NULLIF(v_customer->>'baseline_category_count', '')::INTEGER;
      v_baseline_start := NULLIF(v_customer->>'baseline_period_start', '')::DATE;
      v_baseline_end := NULLIF(v_customer->>'baseline_period_end', '')::DATE;
    END IF;

    INSERT INTO target_customers(target_id, customer_id, baseline_value, baseline_category_count,
      baseline_category_ids, baseline_period_start, baseline_period_end)
    VALUES (v_target_id, v_customer_id, v_baseline, v_baseline_categories,
      v_baseline_category_ids, v_baseline_start, v_baseline_end);
  END LOOP;

  IF p_auto_payout THEN UPDATE targets SET auto_payout = true, updated_at = now() WHERE id = v_target_id; END IF;
  IF CURRENT_DATE >= v_start THEN
    PERFORM recalculate_target_progress(v_target_id, LEAST(CURRENT_DATE, v_end));
  END IF;
  RETURN v_target_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_target_with_rewards(
  UUID, TEXT, TEXT, TEXT, UUID, TEXT, DATE, DATE, NUMERIC, NUMERIC, NUMERIC,
  UUID, UUID, UUID, UUID, UUID, INTEGER, JSONB, TEXT, TEXT, NUMERIC, TEXT,
  INTEGER, JSONB, JSONB, BOOLEAN, UUID
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_target_with_rewards(
  UUID, TEXT, TEXT, TEXT, UUID, TEXT, DATE, DATE, NUMERIC, NUMERIC, NUMERIC,
  UUID, UUID, UUID, UUID, UUID, INTEGER, JSONB, TEXT, TEXT, NUMERIC, TEXT,
  INTEGER, JSONB, JSONB, BOOLEAN, UUID
) TO authenticated;

COMMENT ON FUNCTION public.get_target_customer_candidates(
  TEXT, TEXT, UUID, DATE, INTEGER, TEXT, TEXT, UUID, UUID, UUID,
  UUID, NUMERIC, NUMERIC, DATE, DATE, INTEGER, INTEGER
) IS 'Read-only, filterable customer candidates with company-wide frozen baseline previews.';
