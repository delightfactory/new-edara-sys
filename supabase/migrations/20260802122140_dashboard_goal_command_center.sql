-- Dashboard goal command center
--
-- This migration deliberately does not alter sales, purchases, collections,
-- returns, payroll, or inventory records. It only completes the HR hierarchy,
-- adds read-only target visibility for members of the assigned scope, and
-- exposes a read-only contribution breakdown that mirrors the canonical target
-- calculator for axes which can be attributed to an employee without guessing.

-- The installation currently has one active branch. Resolve it from data (not
-- from a generated UUID), and fail closed if that invariant changes later.
DO $branch_assignment$
DECLARE
  v_main_branch UUID;
  v_active_branch_count INTEGER;
BEGIN
  SELECT COUNT(*), (ARRAY_AGG(id ORDER BY id))[1]
    INTO v_active_branch_count, v_main_branch
  FROM public.branches
  WHERE is_active = true;

  IF v_active_branch_count <> 1 OR v_main_branch IS NULL THEN
    RAISE EXCEPTION '[EDARA] Expected exactly one active branch; found %',
      v_active_branch_count;
  END IF;

  UPDATE public.hr_departments
  SET branch_id = v_main_branch,
      updated_at = now()
  WHERE branch_id IS NULL;

  UPDATE public.hr_employees
  SET branch_id = v_main_branch,
      updated_at = now()
  WHERE branch_id IS NULL;
END;
$branch_assignment$;

-- Scope membership is read-only. Existing manager/admin policies remain in
-- place and continue to control creation, editing, pausing, and deletion.
DROP POLICY IF EXISTS tgt_read_scope_members ON public.targets;
CREATE POLICY tgt_read_scope_members
ON public.targets
FOR SELECT
TO authenticated
USING (
  (SELECT auth.uid()) IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM public.hr_employees caller
    WHERE caller.user_id = (SELECT auth.uid())
      AND caller.status = 'active'
      AND (
        targets.scope = 'company'
        OR public.target_scope_matches_employee(
          targets.scope,
          targets.scope_id,
          caller.id
        )
      )
  )
);

DROP POLICY IF EXISTS tp_read_scope_members ON public.target_progress;
CREATE POLICY tp_read_scope_members
ON public.target_progress
FOR SELECT
TO authenticated
USING (
  (SELECT auth.uid()) IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM public.targets t
    JOIN public.hr_employees caller
      ON caller.user_id = (SELECT auth.uid())
     AND caller.status = 'active'
    WHERE t.id = target_progress.target_id
      AND (
        t.scope = 'company'
        OR public.target_scope_matches_employee(t.scope, t.scope_id, caller.id)
      )
  )
);

-- Employee contribution breakdown for axes with exact employee attribution.
-- Customer upgrade/reactivation/category-spread axes intentionally return no
-- rows: assigning an achieved customer to one rep would be an accounting guess
-- when several reps contributed during the target period.
CREATE OR REPLACE FUNCTION public.get_target_employee_contributions(
  p_target_id UUID,
  p_snapshot_date DATE DEFAULT CURRENT_DATE
) RETURNS TABLE (
  employee_id UUID,
  employee_name TEXT,
  achieved_value NUMERIC,
  contribution_share_pct NUMERIC,
  target_share_pct NUMERIC,
  contribution_rank INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_target public.targets%ROWTYPE;
  v_caller public.hr_employees%ROWTYPE;
  v_calc_date DATE;
  v_visible BOOLEAN := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '[EDARA] Unauthorized';
  END IF;

  SELECT * INTO v_target
  FROM public.targets
  WHERE id = p_target_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION '[EDARA] Target not found';
  END IF;

  SELECT * INTO v_caller
  FROM public.hr_employees
  WHERE user_id = auth.uid()
    AND status = 'active'
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION '[EDARA] Active employee profile is required';
  END IF;

  -- Members may see collaboration inside their own department/branch target.
  -- Company-wide employee details remain restricted to read_all holders.
  v_visible :=
    public.check_permission(auth.uid(), 'targets.read_all')
    OR (
      v_target.scope <> 'company'
      AND public.target_scope_matches_employee(
        v_target.scope,
        v_target.scope_id,
        v_caller.id
      )
    )
    OR (
      public.check_permission(auth.uid(), 'targets.read_team')
      AND (
        (v_target.scope = 'branch' AND v_target.scope_id = v_caller.branch_id)
        OR (v_target.scope = 'department' AND EXISTS (
          SELECT 1
          FROM public.hr_departments d
          WHERE d.id = v_target.scope_id
            AND d.branch_id = v_caller.branch_id
        ))
        OR (v_target.scope = 'individual' AND EXISTS (
          SELECT 1
          FROM public.hr_employees e
          WHERE e.id = v_target.scope_id
            AND e.branch_id = v_caller.branch_id
        ))
      )
    );

  IF NOT v_visible THEN
    RAISE EXCEPTION '[EDARA] You cannot read contributions for this target';
  END IF;

  IF v_target.type_code NOT IN (
    'sales_value', 'collection', 'visits_count', 'calls_count',
    'new_customers', 'product_qty'
  ) THEN
    RETURN;
  END IF;

  v_calc_date := LEAST(
    GREATEST(COALESCE(p_snapshot_date, CURRENT_DATE), v_target.period_start),
    v_target.period_end
  );

  RETURN QUERY
  WITH members AS MATERIALIZED (
    SELECT e.id, e.full_name, e.user_id
    FROM public.hr_employees e
    WHERE e.status = 'active'
      AND public.target_scope_matches_employee(
        v_target.scope,
        v_target.scope_id,
        e.id
      )
  ), contribution_values AS (
    SELECT
      m.id,
      m.full_name,
      CASE v_target.type_code
        WHEN 'sales_value' THEN
          CASE
            WHEN v_target.product_id IS NOT NULL OR v_target.category_id IS NOT NULL THEN
              COALESCE((
                SELECT SUM(soi.line_total - COALESCE((
                  SELECT SUM(sri.line_total)
                  FROM public.sales_return_items sri
                  JOIN public.sales_returns sr ON sr.id = sri.return_id
                  WHERE sri.order_item_id = soi.id
                    AND sr.status = 'confirmed'
                ), 0))
                FROM public.sales_orders so
                JOIN public.sales_order_items soi ON soi.order_id = so.id
                JOIN public.customers c ON c.id = so.customer_id
                LEFT JOIN public.products p ON p.id = soi.product_id
                WHERE so.rep_id = m.user_id
                  AND so.status IN ('delivered', 'completed')
                  AND so.delivered_at::DATE BETWEEN v_target.period_start AND v_calc_date
                  AND (v_target.product_id IS NULL OR soi.product_id = v_target.product_id)
                  AND (v_target.category_id IS NULL OR p.category_id = v_target.category_id)
                  AND (v_target.governorate_id IS NULL OR c.governorate_id = v_target.governorate_id)
                  AND (v_target.city_id IS NULL OR c.city_id = v_target.city_id)
                  AND (v_target.area_id IS NULL OR c.area_id = v_target.area_id)
              ), 0)
            ELSE
              COALESCE((
                SELECT SUM(GREATEST(so.total_amount - COALESCE(so.returned_amount, 0), 0))
                FROM public.sales_orders so
                JOIN public.customers c ON c.id = so.customer_id
                WHERE so.rep_id = m.user_id
                  AND so.status IN ('delivered', 'completed')
                  AND so.delivered_at::DATE BETWEEN v_target.period_start AND v_calc_date
                  AND (v_target.governorate_id IS NULL OR c.governorate_id = v_target.governorate_id)
                  AND (v_target.city_id IS NULL OR c.city_id = v_target.city_id)
                  AND (v_target.area_id IS NULL OR c.area_id = v_target.area_id)
              ), 0)
          END
        WHEN 'collection' THEN
          -- Keep the employee rows additive. The canonical helper applies
          -- GREATEST(..., 0) to the whole team; calling it once per employee
          -- would apply that floor too early and could overstate the sum.
          (
            WITH relevant_returns AS (
              SELECT sr.total_amount, so.id AS sales_order_id
              FROM public.sales_returns sr
              JOIN public.sales_orders so ON so.id = sr.order_id
              WHERE sr.status = 'confirmed'
                AND so.delivered_at::DATE
                  BETWEEN v_target.period_start AND v_calc_date
                AND (
                  so.payment_terms = 'cash'
                  OR COALESCE(so.credit_amount, 0) = 0
                )
            ), relevant_orders AS (
              SELECT DISTINCT rr.sales_order_id
              FROM relevant_returns rr
            ), employee_receipts_by_order AS (
              SELECT pr.sales_order_id, SUM(pr.amount) AS amount
              FROM public.payment_receipts pr
              JOIN relevant_orders ro ON ro.sales_order_id = pr.sales_order_id
              WHERE pr.collected_by = m.user_id
                AND pr.status = 'confirmed'
              GROUP BY pr.sales_order_id
            ), all_receipts_by_order AS (
              SELECT pr.sales_order_id, SUM(pr.amount) AS amount
              FROM public.payment_receipts pr
              JOIN relevant_orders ro ON ro.sales_order_id = pr.sales_order_id
              WHERE pr.status = 'confirmed'
              GROUP BY pr.sales_order_id
            ), allocated_returns AS (
              SELECT SUM(
                rr.total_amount * employee_receipts.amount
                / NULLIF(all_receipts.amount, 0)
              ) AS amount
              FROM relevant_returns rr
              JOIN employee_receipts_by_order employee_receipts
                ON employee_receipts.sales_order_id = rr.sales_order_id
               AND employee_receipts.amount > 0
              JOIN all_receipts_by_order all_receipts
                ON all_receipts.sales_order_id = rr.sales_order_id
               AND all_receipts.amount > 0
            )
            SELECT
              COALESCE((
                SELECT SUM(pr.amount)
                FROM public.payment_receipts pr
                WHERE pr.collected_by = m.user_id
                  AND pr.status = 'confirmed'
                  AND pr.created_at::DATE
                    BETWEEN v_target.period_start AND v_calc_date
              ), 0)
              - COALESCE((SELECT ar.amount FROM allocated_returns ar), 0)
          )
        WHEN 'visits_count' THEN
          (SELECT COUNT(*)::NUMERIC
           FROM public.activities a
           JOIN public.activity_types at_ ON at_.id = a.type_id
           WHERE a.employee_id = m.id
             AND at_.category = 'visit'
             AND a.activity_date BETWEEN v_target.period_start AND v_calc_date
             AND a.deleted_at IS NULL)
        WHEN 'calls_count' THEN
          (SELECT COUNT(*)::NUMERIC
           FROM public.activities a
           JOIN public.activity_types at_ ON at_.id = a.type_id
           WHERE a.employee_id = m.id
             AND at_.category = 'call'
             AND a.activity_date BETWEEN v_target.period_start AND v_calc_date
             AND a.deleted_at IS NULL)
        WHEN 'new_customers' THEN
          (SELECT COUNT(*)::NUMERIC
           FROM public.customers c
           WHERE c.assigned_rep_id = m.user_id
             AND c.created_at::DATE BETWEEN v_target.period_start AND v_calc_date
             AND c.is_active = true)
        WHEN 'product_qty' THEN
          COALESCE((
            SELECT SUM(GREATEST(
              soi.delivered_quantity - COALESCE(soi.returned_quantity, 0), 0
            ))
            FROM public.sales_order_items soi
            JOIN public.sales_orders so ON so.id = soi.order_id
            WHERE so.rep_id = m.user_id
              AND so.status IN ('delivered', 'completed')
              AND so.delivered_at::DATE BETWEEN v_target.period_start AND v_calc_date
              AND (v_target.product_id IS NULL OR soi.product_id = v_target.product_id)
              AND (v_target.category_id IS NULL OR soi.product_id IN (
                SELECT p.id FROM public.products p
                WHERE p.category_id = v_target.category_id
              ))
          ), 0)
        ELSE 0
      END::NUMERIC AS achieved
    FROM members m
  ), normalized_values AS (
    SELECT
      cv.id,
      cv.full_name,
      CASE
        WHEN v_target.type_code = 'collection'
          AND SUM(cv.achieved) OVER () <= 0
          THEN 0::NUMERIC
        ELSE cv.achieved
      END AS achieved
    FROM contribution_values cv
  ), totals AS (
    SELECT COALESCE(SUM(cv.achieved), 0) AS total_achieved
    FROM normalized_values cv
  )
  SELECT
    cv.id,
    cv.full_name::TEXT,
    cv.achieved,
    CASE WHEN totals.total_achieved = 0 THEN 0
      ELSE ROUND(cv.achieved / totals.total_achieved * 100, 2)
    END,
    CASE WHEN v_target.target_value = 0 THEN 0
      ELSE ROUND(cv.achieved / v_target.target_value * 100, 2)
    END,
    ROW_NUMBER() OVER (ORDER BY cv.achieved DESC, cv.full_name)::INTEGER
  FROM normalized_values cv
  CROSS JOIN totals
  ORDER BY cv.achieved DESC, cv.full_name;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_target_employee_contributions(UUID, DATE)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_target_employee_contributions(UUID, DATE)
  TO authenticated;
