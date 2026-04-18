-- 98_credit_customers_filtered.sql
-- مسار لجلب العملاء الائتمانيين مع الفلاتر المتقدمة، الترتيب، والـ KPIs بشكل منسق.

-- 1. الدالة الأولى: get_filtered_credit_customers
-- تقوم بجلب العملاء مع تطبيق الفلاتر والترتيب بشكل كامل داخل قاعدة البيانات، 
-- وتقوم بحساب متأخرات الفواتير (overdue) ونسب الاستخدام بدقة.
CREATE OR REPLACE FUNCTION public.get_filtered_credit_customers(
    p_search TEXT DEFAULT NULL,
    p_payment_terms TEXT DEFAULT NULL,
    p_rep_id UUID DEFAULT NULL,
    p_balance_state TEXT DEFAULT 'all',  -- 'all', 'with-balance-only', 'near-limit', 'exceeded', 'no-limit'
    p_current_balance_min NUMERIC DEFAULT NULL,
    p_current_balance_max NUMERIC DEFAULT NULL,
    p_credit_limit_min NUMERIC DEFAULT NULL,
    p_credit_limit_max NUMERIC DEFAULT NULL,
    p_sort_by TEXT DEFAULT 'name',       -- 'name', 'current_balance_desc', 'available_asc', 'utilization_desc', 'overdue_count_desc'
    p_limit INT DEFAULT 25,
    p_offset INT DEFAULT 0
) RETURNS TABLE (
    id UUID,
    code TEXT,
    name TEXT,
    payment_terms TEXT,
    credit_limit NUMERIC,
    credit_days INT,
    current_balance NUMERIC,
    is_active BOOLEAN,
    assigned_rep_id UUID,
    assigned_rep JSON,
    available_balance NUMERIC,
    utilization_pct NUMERIC,
    overdue_count INT,
    total_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT check_permission(auth.uid(), 'customers.read') AND NOT check_permission(auth.uid(), 'customers.read_all') THEN
        RAISE EXCEPTION 'Unauthorized: Requires customers.read or customers.read_all permission';
    END IF;

    RETURN QUERY
    WITH base_customers AS (
        SELECT 
            c.id, c.code, c.name, c.payment_terms, c.credit_limit, c.credit_days, c.current_balance, c.is_active, c.assigned_rep_id,
            CASE 
                WHEN c.assigned_rep_id IS NOT NULL THEN (
                    SELECT json_build_object('id', p.id, 'full_name', p.full_name) 
                    FROM profiles p WHERE p.id = c.assigned_rep_id
                )
                ELSE NULL
            END AS assigned_rep,
            GREATEST(0, (c.credit_limit - c.current_balance)) AS available_balance,
            CASE 
                WHEN c.credit_limit > 0 THEN (c.current_balance / c.credit_limit)
                ELSE 0 
            END AS utilization_pct,
            (SELECT COUNT(*)::INT
             FROM sales_orders so 
             WHERE so.customer_id = c.id 
               AND so.status IN ('delivered', 'partially_delivered')
               AND so.delivered_at IS NOT NULL
               AND (so.total_amount - so.paid_amount - so.returned_amount) > 0
               AND (CURRENT_DATE - so.delivered_at::date) > COALESCE(c.credit_days, 0)
            ) AS overdue_count
        FROM customers c
        WHERE c.payment_terms != 'cash'
          AND c.is_active = true
          AND (p_payment_terms IS NULL OR p_payment_terms = '' OR c.payment_terms = p_payment_terms)
          AND (p_rep_id IS NULL OR c.assigned_rep_id = p_rep_id)
          AND (p_search IS NULL OR p_search = '' OR c.name ILIKE '%' || p_search || '%' OR c.code ILIKE '%' || p_search || '%')
    ),
    filtered_customers AS (
        SELECT bc.*
        FROM base_customers bc
        WHERE 1=1
          -- Balance state filter
          AND (
               p_balance_state = 'all'
            OR (p_balance_state = 'with-balance-only' AND bc.current_balance > 0)
            OR (p_balance_state = 'near-limit' AND bc.credit_limit > 0 AND bc.utilization_pct >= 0.8 AND bc.utilization_pct <= 1)
            OR (p_balance_state = 'exceeded' AND bc.credit_limit > 0 AND bc.current_balance > bc.credit_limit)
            OR (p_balance_state = 'no-limit' AND bc.credit_limit = 0)
          )
          -- Range filters
          AND (p_current_balance_min IS NULL OR bc.current_balance >= p_current_balance_min)
          AND (p_current_balance_max IS NULL OR bc.current_balance <= p_current_balance_max)
          AND (p_credit_limit_min IS NULL OR bc.credit_limit >= p_credit_limit_min)
          AND (p_credit_limit_max IS NULL OR bc.credit_limit <= p_credit_limit_max)
    ),
    counted AS (
        SELECT COUNT(*) AS total_count FROM filtered_customers
    )
    SELECT 
        fc.id, fc.code, fc.name, fc.payment_terms, fc.credit_limit, fc.credit_days, fc.current_balance, fc.is_active, 
        fc.assigned_rep_id, fc.assigned_rep, fc.available_balance, fc.utilization_pct, fc.overdue_count,
        ct.total_count::BIGINT
    FROM filtered_customers fc
    CROSS JOIN counted ct
    ORDER BY
        CASE WHEN p_sort_by = 'name' THEN fc.name END ASC,
        CASE WHEN p_sort_by = 'current_balance_desc' THEN fc.current_balance END DESC,
        CASE WHEN p_sort_by = 'available_asc' THEN fc.available_balance END ASC,
        -- Utilization descending, treating no-limit (null/0) carefully
        CASE WHEN p_sort_by = 'utilization_desc' AND fc.credit_limit > 0 THEN fc.utilization_pct END DESC,
        CASE WHEN p_sort_by = 'utilization_desc' AND fc.credit_limit = 0 THEN 0 END DESC,
        CASE WHEN p_sort_by = 'overdue_count_desc' THEN fc.overdue_count END DESC,
        fc.name ASC  -- tie-breaker
    LIMIT COALESCE(p_limit, 25)
    OFFSET COALESCE(p_offset, 0);
END;
$$;


-- 2. الدالة الثانية: get_filtered_credit_kpis
-- لحساب الـ KPIs ديناميكياً بناءً على نفس الفلاتر المستخدمة في الدالة السابقة
CREATE OR REPLACE FUNCTION public.get_filtered_credit_kpis(
    p_search TEXT DEFAULT NULL,
    p_payment_terms TEXT DEFAULT NULL,
    p_rep_id UUID DEFAULT NULL,
    p_balance_state TEXT DEFAULT 'all',  -- 'all', 'with-balance-only', 'near-limit', 'exceeded', 'no-limit'
    p_current_balance_min NUMERIC DEFAULT NULL,
    p_current_balance_max NUMERIC DEFAULT NULL,
    p_credit_limit_min NUMERIC DEFAULT NULL,
    p_credit_limit_max NUMERIC DEFAULT NULL
) RETURNS TABLE (
    total_limit NUMERIC,
    total_used NUMERIC,
    total_available NUMERIC,
    count_exceeded INT,
    count_near_limit INT,
    total_credit_customers INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT check_permission(auth.uid(), 'customers.read') AND NOT check_permission(auth.uid(), 'customers.read_all') THEN
        RAISE EXCEPTION 'Unauthorized: Requires customers.read or customers.read_all permission';
    END IF;

    RETURN QUERY
    WITH base_customers AS (
        SELECT 
            c.id, c.credit_limit, c.current_balance, c.is_active,
            CASE 
                WHEN c.credit_limit > 0 THEN (c.current_balance / c.credit_limit)
                ELSE 0 
            END AS utilization_pct
        FROM customers c
        WHERE c.payment_terms != 'cash'
          AND c.is_active = true
          AND (p_payment_terms IS NULL OR p_payment_terms = '' OR c.payment_terms = p_payment_terms)
          AND (p_rep_id IS NULL OR c.assigned_rep_id = p_rep_id)
          AND (p_search IS NULL OR p_search = '' OR c.name ILIKE '%' || p_search || '%' OR c.code ILIKE '%' || p_search || '%')
    ),
    filtered_customers AS (
        SELECT bc.*
        FROM base_customers bc
        WHERE 1=1
          AND (
               p_balance_state = 'all'
            OR (p_balance_state = 'with-balance-only' AND bc.current_balance > 0)
            OR (p_balance_state = 'near-limit' AND bc.credit_limit > 0 AND bc.utilization_pct >= 0.8 AND bc.utilization_pct <= 1)
            OR (p_balance_state = 'exceeded' AND bc.credit_limit > 0 AND bc.current_balance > bc.credit_limit)
            OR (p_balance_state = 'no-limit' AND bc.credit_limit = 0)
          )
          AND (p_current_balance_min IS NULL OR bc.current_balance >= p_current_balance_min)
          AND (p_current_balance_max IS NULL OR bc.current_balance <= p_current_balance_max)
          AND (p_credit_limit_min IS NULL OR bc.credit_limit >= p_credit_limit_min)
          AND (p_credit_limit_max IS NULL OR bc.credit_limit <= p_credit_limit_max)
    )
    SELECT 
        COALESCE(SUM(fc.credit_limit) FILTER (WHERE fc.credit_limit > 0), 0) AS total_limit,
        COALESCE(SUM(fc.current_balance), 0) AS total_used,
        COALESCE(SUM(GREATEST(0, fc.credit_limit - fc.current_balance)) FILTER (WHERE fc.credit_limit > 0), 0) AS total_available,
        COUNT(*) FILTER (WHERE fc.credit_limit > 0 AND fc.current_balance > fc.credit_limit)::INT AS count_exceeded,
        COUNT(*) FILTER (WHERE fc.credit_limit > 0 AND fc.utilization_pct >= 0.8 AND fc.utilization_pct <= 1)::INT AS count_near_limit,
        COUNT(*)::INT AS total_credit_customers
    FROM filtered_customers fc;
END;
$$;

-- Protect RPCs by revoking access from public and anon, granting to authenticated
REVOKE EXECUTE ON FUNCTION public.get_filtered_credit_customers FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_filtered_credit_customers FROM anon;
GRANT EXECUTE ON FUNCTION public.get_filtered_credit_customers TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_filtered_credit_kpis FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_filtered_credit_kpis FROM anon;
GRANT EXECUTE ON FUNCTION public.get_filtered_credit_kpis TO authenticated;

