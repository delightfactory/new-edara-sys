-- ============================================================
-- 116: Customer advance credit auto-allocation
-- EDARA v2
--
-- Purpose
--   Safely consume confirmed, unallocated customer payment credits
--   against the customer's oldest delivered sales invoices.
--
-- Why this exists
--   allocate_payment_to_invoices() allocates at receipt-confirmation time.
--   If a receipt is confirmed before the sales-order debit appears in
--   customer_ledger, the receipt correctly remains as an unallocated credit.
--   Later, when the invoice debit is created, that old advance is not consumed.
--
-- Accounting guardrails
--   - Does NOT create vault/custody transactions.
--   - Does NOT create journal entries.
--   - Does NOT change payment_receipts.amount.
--   - Does NOT change sales order totals, items, stock, costs, or returns.
--   - The customer subledger net balance remains unchanged.
--   - Only reallocates existing confirmed payment_receipt credits.
--   - Only updates sales_orders.paid_amount/status to reflect the allocation.
--
-- Historical data
--   This migration does NOT run a historical backfill automatically.
--   Use preview_unallocated_customer_credit_allocation() first, then call
--   backfill_unallocated_customer_credits(...) explicitly after review.
-- ============================================================

-- The original unique source constraint was intentionally removed in
-- 04_sales_system.sql to allow one receipt to be split over multiple invoice
-- allocations. This migration deliberately does not drop/recreate constraints;
-- it expects the established ledger model and only adds safe helper indexes.

CREATE INDEX IF NOT EXISTS idx_customer_ledger_unallocated_receipt_credit
  ON public.customer_ledger (customer_id, created_at, id)
  WHERE type = 'credit'
    AND source_type = 'payment_receipt'
    AND allocated_to IS NULL;

CREATE INDEX IF NOT EXISTS idx_customer_ledger_sales_order_debit
  ON public.customer_ledger (customer_id, source_id, created_at, id)
  WHERE type = 'debit'
    AND source_type = 'sales_order';

-- ------------------------------------------------------------
-- Read-only preview.
-- Shows the theoretical FIFO allocation plan without touching data.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.preview_unallocated_customer_credit_allocation(
  p_customer_id UUID DEFAULT NULL
)
RETURNS TABLE (
  customer_id UUID,
  customer_code TEXT,
  customer_name TEXT,
  receipt_id UUID,
  receipt_number TEXT,
  credit_ledger_id UUID,
  original_unallocated_credit NUMERIC,
  order_id UUID,
  order_number TEXT,
  order_date DATE,
  current_invoice_remaining NUMERIC,
  proposed_allocation_amount NUMERIC,
  invoice_remaining_after_proposed_allocation NUMERIC
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  WITH unallocated_credits AS (
    SELECT
      cl.id AS credit_ledger_id,
      pr.id AS receipt_id,
      pr.number AS receipt_number,
      pr.customer_id,
      c.code AS customer_code,
      c.name AS customer_name,
      cl.amount AS credit_amount,
      cl.created_at AS credit_created_at,
      COALESCE(
        SUM(cl.amount) OVER (
          PARTITION BY pr.customer_id
          ORDER BY cl.created_at, cl.id
          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ),
        0
      ) AS credit_start,
      SUM(cl.amount) OVER (
        PARTITION BY pr.customer_id
        ORDER BY cl.created_at, cl.id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) AS credit_end
    FROM public.customer_ledger cl
    JOIN public.payment_receipts pr
      ON pr.id = cl.source_id
     AND cl.source_type = 'payment_receipt'
     AND pr.status = 'confirmed'
    JOIN public.customers c ON c.id = pr.customer_id
    WHERE cl.type = 'credit'
      AND cl.allocated_to IS NULL
      AND cl.amount > 0
      AND (p_customer_id IS NULL OR pr.customer_id = p_customer_id)
      AND (
        auth.uid() IS NULL
        OR public.check_permission(auth.uid(), 'finance.payments.confirm')
      )
  ),
  open_debits AS (
    SELECT
      debit.id AS debit_ledger_id,
      so.id AS order_id,
      so.order_number,
      so.customer_id,
      so.order_date,
      COALESCE(so.delivered_at, so.created_at) AS delivered_sort_at,
      debit.created_at AS debit_created_at,
      LEAST(
        GREATEST(
          COALESCE(debit.amount, 0)
          - COALESCE((
            SELECT SUM(cr.amount)
            FROM public.customer_ledger cr
            WHERE cr.type = 'credit'
              AND cr.allocated_to = debit.id
          ), 0),
          0
        ),
        GREATEST(
          COALESCE(so.total_amount, 0)
          - COALESCE(so.paid_amount, 0)
          - COALESCE(so.returned_amount, 0),
          0
        )
      ) AS debit_remaining
    FROM public.sales_orders so
    JOIN public.customer_ledger debit
      ON debit.source_type = 'sales_order'
     AND debit.source_id = so.id
     AND debit.type = 'debit'
    WHERE so.status::text = 'delivered'
      AND (p_customer_id IS NULL OR so.customer_id = p_customer_id)
      AND (
        auth.uid() IS NULL
        OR public.check_permission(auth.uid(), 'finance.payments.confirm')
      )
  ),
  open_debits_with_windows AS (
    SELECT
      od.*,
      COALESCE(
        SUM(od.debit_remaining) OVER (
          PARTITION BY od.customer_id
          ORDER BY od.order_date, od.delivered_sort_at, od.debit_created_at, od.debit_ledger_id
          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ),
        0
      ) AS debit_start,
      SUM(od.debit_remaining) OVER (
        PARTITION BY od.customer_id
        ORDER BY od.order_date, od.delivered_sort_at, od.debit_created_at, od.debit_ledger_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) AS debit_end
    FROM open_debits od
    WHERE od.debit_remaining > 0
  )
  SELECT
    uc.customer_id,
    uc.customer_code,
    uc.customer_name,
    uc.receipt_id,
    uc.receipt_number,
    uc.credit_ledger_id,
    ROUND(uc.credit_amount::numeric, 2) AS original_unallocated_credit,
    od.order_id,
    od.order_number,
    od.order_date,
    ROUND(od.debit_remaining::numeric, 2) AS current_invoice_remaining,
    ROUND(
      GREATEST(
        LEAST(uc.credit_end, od.debit_end)
        - GREATEST(uc.credit_start, od.debit_start),
        0
      )::numeric,
      2
    ) AS proposed_allocation_amount,
    ROUND(
      (
        od.debit_remaining
        - GREATEST(
            LEAST(uc.credit_end, od.debit_end)
            - GREATEST(uc.credit_start, od.debit_start),
            0
          )
      )::numeric,
      2
    ) AS invoice_remaining_after_proposed_allocation
  FROM unallocated_credits uc
  JOIN open_debits_with_windows od
    ON od.customer_id = uc.customer_id
  WHERE GREATEST(
    LEAST(uc.credit_end, od.debit_end)
    - GREATEST(uc.credit_start, od.debit_start),
    0
  ) > 0
  ORDER BY
    uc.customer_code,
    od.order_date,
    od.delivered_sort_at,
    od.debit_created_at,
    uc.credit_created_at;
$$;

-- ------------------------------------------------------------
-- Internal allocator.
-- It is intentionally not granted to application roles directly.
-- Trigger/backfill wrappers call it.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._allocate_unallocated_customer_credits(
  p_customer_id UUID,
  p_actor_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_credit RECORD;
  v_debit RECORD;
  v_credit_remaining NUMERIC;
  v_alloc_amount NUMERIC;
  v_current_outstanding NUMERIC;
  v_first_slice BOOLEAN;
  v_rows JSONB := '[]'::JSONB;
  v_updated_order RECORD;
BEGIN
  IF p_customer_id IS NULL THEN
    RETURN v_rows;
  END IF;

  -- Serialize allocation per customer. This prevents double consumption of
  -- the same advance if two invoices/receipts are processed at the same time.
  PERFORM pg_advisory_xact_lock(
    hashtext('customer_advance_credit_allocation'),
    hashtext(p_customer_id::text)
  );

  -- Lock the customer row as an additional, readable coordination point.
  PERFORM 1
  FROM public.customers
  WHERE id = p_customer_id
  FOR UPDATE;

  FOR v_credit IN
    SELECT
      cl.id,
      cl.customer_id,
      cl.amount,
      cl.source_type,
      cl.source_id,
      cl.description,
      cl.created_by,
      cl.created_at,
      pr.number AS receipt_number
    FROM public.customer_ledger cl
    JOIN public.payment_receipts pr
      ON pr.id = cl.source_id
     AND cl.source_type = 'payment_receipt'
     AND pr.status = 'confirmed'
    WHERE cl.customer_id = p_customer_id
      AND cl.type = 'credit'
      AND cl.allocated_to IS NULL
      AND cl.amount > 0
    ORDER BY cl.created_at, cl.id
    FOR UPDATE OF cl
  LOOP
    v_credit_remaining := ROUND(v_credit.amount, 2);
    v_first_slice := true;

    FOR v_debit IN
      SELECT
        debit.id AS debit_ledger_id,
        so.id AS order_id,
        so.order_number,
        so.order_date,
        LEAST(
          GREATEST(
            COALESCE(debit.amount, 0)
            - COALESCE((
              SELECT SUM(cr.amount)
              FROM public.customer_ledger cr
              WHERE cr.type = 'credit'
                AND cr.allocated_to = debit.id
            ), 0),
            0
          ),
          GREATEST(
            COALESCE(so.total_amount, 0)
            - COALESCE(so.paid_amount, 0)
            - COALESCE(so.returned_amount, 0),
            0
          )
        ) AS outstanding
      FROM public.customer_ledger debit
      JOIN public.sales_orders so
        ON so.id = debit.source_id
       AND debit.source_type = 'sales_order'
      WHERE debit.customer_id = p_customer_id
        AND debit.type = 'debit'
        AND so.status::text = 'delivered'
      ORDER BY
        so.order_date,
        COALESCE(so.delivered_at, so.created_at),
        debit.created_at,
        debit.id
      FOR UPDATE OF debit, so
    LOOP
      EXIT WHEN v_credit_remaining <= 0;

      -- Recalculate immediately before allocation. This protects mixed orders
      -- that may have more than one debit row and protects concurrent changes
      -- already serialized by the customer advisory lock.
      SELECT LEAST(
        GREATEST(
          COALESCE(debit.amount, 0)
          - COALESCE((
            SELECT SUM(cr.amount)
            FROM public.customer_ledger cr
            WHERE cr.type = 'credit'
              AND cr.allocated_to = debit.id
          ), 0),
          0
        ),
        GREATEST(
          COALESCE(so.total_amount, 0)
          - COALESCE(so.paid_amount, 0)
          - COALESCE(so.returned_amount, 0),
          0
        )
      )
      INTO v_current_outstanding
      FROM public.customer_ledger debit
      JOIN public.sales_orders so
        ON so.id = debit.source_id
       AND debit.source_type = 'sales_order'
      WHERE debit.id = v_debit.debit_ledger_id
        AND debit.customer_id = p_customer_id
        AND debit.type = 'debit'
        AND so.status::text = 'delivered'
      FOR UPDATE OF debit, so;

      CONTINUE WHEN COALESCE(v_current_outstanding, 0) <= 0;

      v_alloc_amount := ROUND(LEAST(v_credit_remaining, v_current_outstanding), 2);
      CONTINUE WHEN v_alloc_amount <= 0;

      IF v_first_slice THEN
        -- Reuse the original unallocated row for the first slice. If the
        -- original credit must be split, the remaining slices/remainder are
        -- inserted below with the same receipt source.
        UPDATE public.customer_ledger
        SET amount = v_alloc_amount,
            allocated_to = v_debit.debit_ledger_id,
            description = 'تخصيص رصيد مقدم من إيصال '
              || COALESCE(v_credit.receipt_number, v_credit.source_id::text)
              || ' على فاتورة #' || v_debit.order_number
        WHERE id = v_credit.id;

        v_first_slice := false;
      ELSE
        INSERT INTO public.customer_ledger (
          customer_id,
          type,
          amount,
          source_type,
          source_id,
          allocated_to,
          description,
          created_by,
          created_at
        ) VALUES (
          p_customer_id,
          'credit',
          v_alloc_amount,
          v_credit.source_type,
          v_credit.source_id,
          v_debit.debit_ledger_id,
          'تخصيص رصيد مقدم من إيصال '
            || COALESCE(v_credit.receipt_number, v_credit.source_id::text)
            || ' على فاتورة #' || v_debit.order_number,
          COALESCE(p_actor_id, v_credit.created_by),
          v_credit.created_at
        );
      END IF;

      UPDATE public.sales_orders
      SET paid_amount = ROUND(COALESCE(paid_amount, 0) + v_alloc_amount, 2),
          status = CASE
            WHEN (
              COALESCE(paid_amount, 0)
              + v_alloc_amount
              + COALESCE(returned_amount, 0)
            ) >= COALESCE(total_amount, 0) - 0.005
            THEN 'completed'::sales_order_status
            ELSE status
          END
      WHERE id = v_debit.order_id
        AND status::text = 'delivered'
        AND GREATEST(
          COALESCE(total_amount, 0)
          - COALESCE(paid_amount, 0)
          - COALESCE(returned_amount, 0),
          0
        ) + 0.005 >= v_alloc_amount
      RETURNING
        id,
        order_number,
        paid_amount,
        returned_amount,
        total_amount,
        status::text AS status
      INTO v_updated_order;

      IF NOT FOUND THEN
        RAISE EXCEPTION
          'Advance allocation failed: order % no longer has enough open balance',
          v_debit.order_number;
      END IF;

      v_credit_remaining := ROUND(v_credit_remaining - v_alloc_amount, 2);

      v_rows := v_rows || jsonb_build_object(
        'customer_id', p_customer_id,
        'receipt_id', v_credit.source_id,
        'receipt_number', v_credit.receipt_number,
        'allocated_to_order_id', v_updated_order.id,
        'allocated_to_order_number', v_updated_order.order_number,
        'allocated_amount', v_alloc_amount,
        'order_paid_amount_after', v_updated_order.paid_amount,
        'order_status_after', v_updated_order.status,
        'credit_remaining_after', v_credit_remaining
      );
    END LOOP;

    -- If the original credit row was used for an allocated slice and there is
    -- still unused credit, recreate the unused balance as a new unallocated
    -- row tied to the same receipt. This preserves the source total exactly.
    IF NOT v_first_slice AND v_credit_remaining > 0 THEN
      INSERT INTO public.customer_ledger (
        customer_id,
        type,
        amount,
        source_type,
        source_id,
        description,
        created_by,
        created_at
      ) VALUES (
        p_customer_id,
        'credit',
        v_credit_remaining,
        v_credit.source_type,
        v_credit.source_id,
        COALESCE(v_credit.description, 'دفعة مقدمة / رصيد زائد'),
        COALESCE(p_actor_id, v_credit.created_by),
        v_credit.created_at
      );
    END IF;
  END LOOP;

  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public._allocate_unallocated_customer_credits(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._allocate_unallocated_customer_credits(UUID, UUID) FROM authenticated;

-- ------------------------------------------------------------
-- Explicit historical backfill wrapper.
-- Not called automatically by this migration.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.backfill_unallocated_customer_credits(
  p_user_id UUID DEFAULT NULL,
  p_customer_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer RECORD;
  v_result JSONB;
  v_all JSONB := '[]'::JSONB;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    IF p_user_id IS NULL OR p_user_id <> auth.uid() THEN
      RAISE EXCEPTION 'Unauthorized: User ID mismatch';
    END IF;

    IF NOT public.check_permission(p_user_id, 'finance.payments.confirm') THEN
      RAISE EXCEPTION 'لا تملك صلاحية تنفيذ تسوية أرصدة العملاء المقدمة';
    END IF;
  END IF;

  FOR v_customer IN
    SELECT DISTINCT customer_id
    FROM public.preview_unallocated_customer_credit_allocation(p_customer_id)
    ORDER BY customer_id
  LOOP
    v_result := public._allocate_unallocated_customer_credits(
      v_customer.customer_id,
      p_user_id
    );

    IF jsonb_array_length(v_result) > 0 THEN
      v_all := v_all || v_result;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'allocated_count', jsonb_array_length(v_all),
    'allocations', v_all
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.preview_unallocated_customer_credit_allocation(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.backfill_unallocated_customer_credits(UUID, UUID) TO authenticated;

-- ------------------------------------------------------------
-- Future protection.
-- When a sales order becomes delivered, its debit ledger already exists in
-- the current delivery flow. At that moment old unallocated receipt credits
-- can be safely consumed.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_allocate_unallocated_customer_credits_after_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.customer_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.status::text = 'delivered'
     AND OLD.status IS DISTINCT FROM NEW.status THEN
    PERFORM public._allocate_unallocated_customer_credits(
      NEW.customer_id,
      -- sales_orders stores the creator as created_by_id, not created_by.
      COALESCE(NEW.delivered_by, NEW.created_by_id)
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sales_orders_allocate_unallocated_customer_credits
  ON public.sales_orders;

CREATE TRIGGER trg_sales_orders_allocate_unallocated_customer_credits
  AFTER UPDATE OF status ON public.sales_orders
  FOR EACH ROW
  WHEN (
    NEW.status::text = 'delivered'
    AND OLD.status IS DISTINCT FROM NEW.status
  )
  EXECUTE FUNCTION public.trg_allocate_unallocated_customer_credits_after_delivery();

COMMENT ON FUNCTION public.preview_unallocated_customer_credit_allocation(UUID)
  IS 'Read-only preview for confirmed unallocated payment_receipt credits that can be FIFO-allocated to delivered sales invoices.';

COMMENT ON FUNCTION public.backfill_unallocated_customer_credits(UUID, UUID)
  IS 'Explicit historical backfill for customer advance credits. Not run automatically by migration 116.';

COMMENT ON FUNCTION public._allocate_unallocated_customer_credits(UUID, UUID)
  IS 'Internal allocator used by migration 116 trigger/backfill. Reallocates existing confirmed receipt credits without changing net customer balance.';
