-- One-off production maintenance script
-- Purpose: remove only the four empty draft Renault Service Center orders created by mistake
--          on 2026-07-27, plus their creation notifications.
--
-- IMPORTANT
--   1. This is intentionally NOT a migration. Never add it to the migration chain.
--   2. It is safe-by-default: v_execute is FALSE. The first run is a dry run.
--   3. Review all PREFLIGHT notices, then change only v_execute to TRUE and run
--      the complete file exactly once in the NEW-EDARA-SYS production SQL editor.
--   4. Any changed order, unexpected dependency, or row-count mismatch aborts and
--      rolls back the complete transaction.
--   5. The valid completed order SO-20260727-0379 is explicitly excluded.

BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $maintenance$
DECLARE
  -- Safety switch. Change only this value after a successful dry run.
  v_execute CONSTANT BOOLEAN := FALSE;

  v_customer_id CONSTANT UUID := '42949a82-a4c4-4ec0-98fb-ac6f8370b957';
  v_creator_id  CONSTANT UUID := '9a158123-f511-4536-be8c-27d605741f5f';

  v_order_ids CONSTANT UUID[] := ARRAY[
    '98e5d655-998e-4855-b705-5be62e8fe07c'::UUID, -- SO-20260727-0375
    'd0c4b9e3-af9c-4680-a4fb-20c6be3f27ae'::UUID, -- SO-20260727-0376
    '22af7141-4441-4b81-9924-92729aff34a6'::UUID, -- SO-20260727-0377
    '97d7a918-6670-414a-b38c-03dce41a4d4b'::UUID  -- SO-20260727-0378
  ];
  v_order_numbers CONSTANT TEXT[] := ARRAY[
    'SO-20260727-0375',
    'SO-20260727-0376',
    'SO-20260727-0377',
    'SO-20260727-0378'
  ];

  -- The legitimate order is a guard only and is never deleted.
  v_valid_order_id     CONSTANT UUID := '2c459ff1-fe5a-4e13-9cdd-a3383377e0de';
  v_valid_order_number CONSTANT TEXT := 'SO-20260727-0379';

  v_count       BIGINT;
  v_known_count BIGINT;
  v_affected    BIGINT;
BEGIN
  IF v_valid_order_id = ANY(v_order_ids)
     OR v_valid_order_number = ANY(v_order_numbers)
  THEN
    RAISE EXCEPTION 'ABORT: the valid completed order was included in the delete targets';
  END IF;

  -- Prevent concurrent copies of this exact maintenance operation.
  PERFORM pg_advisory_xact_lock(
    hashtextextended('maintenance:delete-empty-orders:renault-service-center:2026-07-27', 0)
  );

  -- Lock all four headers in deterministic order before validating them.
  PERFORM 1
  FROM public.sales_orders
  WHERE id = ANY(v_order_ids)
  ORDER BY id
  FOR UPDATE;

  -- Immutable identity/state snapshot. Any edit since review aborts the operation.
  SELECT COUNT(*)
  INTO v_count
  FROM public.sales_orders so
  JOIN (
    VALUES
      ('98e5d655-998e-4855-b705-5be62e8fe07c'::UUID, 'SO-20260727-0375'::TEXT,
       '2026-07-27 12:15:23.305781+00'::TIMESTAMPTZ,
       '2026-07-27 12:15:23.305781+00'::TIMESTAMPTZ, NULL::UUID),
      ('d0c4b9e3-af9c-4680-a4fb-20c6be3f27ae'::UUID, 'SO-20260727-0376'::TEXT,
       '2026-07-27 12:15:33.439614+00'::TIMESTAMPTZ,
       '2026-07-27 12:15:33.439614+00'::TIMESTAMPTZ, NULL::UUID),
      ('22af7141-4441-4b81-9924-92729aff34a6'::UUID, 'SO-20260727-0377'::TEXT,
       '2026-07-27 12:16:04.918513+00'::TIMESTAMPTZ,
       '2026-07-27 12:16:04.918513+00'::TIMESTAMPTZ, NULL::UUID),
      ('97d7a918-6670-414a-b38c-03dce41a4d4b'::UUID, 'SO-20260727-0378'::TEXT,
       '2026-07-27 12:16:20.852665+00'::TIMESTAMPTZ,
       '2026-07-27 12:16:20.852665+00'::TIMESTAMPTZ,
       NULL::UUID)
  ) AS expected(id, order_number, created_at, updated_at, warehouse_id)
    ON expected.id = so.id
   AND expected.order_number = so.order_number
   AND expected.created_at = so.created_at
   AND expected.updated_at = so.updated_at
   AND expected.warehouse_id IS NOT DISTINCT FROM so.warehouse_id
  WHERE so.status = 'draft'
    AND so.customer_id = v_customer_id
    AND so.rep_id = v_creator_id
    AND so.created_by_id = v_creator_id
    AND so.order_date = DATE '2026-07-27'
    AND so.total_amount = 0
    AND COALESCE(so.paid_amount, 0) = 0
    AND COALESCE(so.returned_amount, 0) = 0
    AND COALESCE(so.cash_amount, 0) = 0
    AND COALESCE(so.credit_amount, 0) = 0
    AND so.confirmed_at IS NULL
    AND so.delivered_at IS NULL
    AND so.payment_terms IS NULL
    AND so.payment_method IS NULL;

  IF v_count <> 4 THEN
    RAISE EXCEPTION
      'ABORT: only % of 4 targets still match the reviewed empty-draft snapshot',
      v_count;
  END IF;

  -- Prevent a reused/duplicated number or an unexpected target ID.
  SELECT COUNT(*), COUNT(*) FILTER (WHERE id = ANY(v_order_ids))
  INTO v_count, v_known_count
  FROM public.sales_orders
  WHERE order_number = ANY(v_order_numbers);

  IF v_count <> 4 OR v_known_count <> 4 THEN
    RAISE EXCEPTION
      'ABORT: target number mapping changed (number rows %, known IDs %)',
      v_count, v_known_count;
  END IF;

  -- Confirm the legitimate order still maps to its reviewed ID. Mutable business
  -- state is deliberately not constrained because it may evolve normally.
  SELECT COUNT(*)
  INTO v_count
  FROM public.sales_orders
  WHERE id = v_valid_order_id
    AND order_number = v_valid_order_number
    AND customer_id = v_customer_id;

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'ABORT: valid order SO-20260727-0379 identity changed';
  END IF;

  -- Direct relational children: all must be absent.
  SELECT
    (SELECT COUNT(*) FROM public.sales_order_items WHERE order_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.payment_receipts WHERE sales_order_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.sales_returns WHERE order_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.activities WHERE order_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.sales_order_due_date_history WHERE order_id = ANY(v_order_ids))
  INTO v_count;

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'ABORT: % direct order dependency row(s) found', v_count;
  END IF;

  -- Polymorphic operational/financial references: all must be absent. We check by
  -- UUID regardless of discriminator so a malformed historical reference also aborts.
  SELECT
    (SELECT COUNT(*) FROM public.stock_movements WHERE reference_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.customer_ledger WHERE source_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.journal_entries WHERE source_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.custody_transactions WHERE reference_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.vault_transactions WHERE reference_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.hr_commission_records WHERE source_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.notification_alert_state WHERE entity_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.price_list_assignments WHERE entity_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.supplier_ledger WHERE source_id = ANY(v_order_ids))
  INTO v_count;

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'ABORT: % unexpected operational/financial reference(s) found', v_count;
  END IF;

  -- The only reviewed side effect is five creation notifications per draft order.
  SELECT COUNT(*), COUNT(*) FILTER (
    WHERE entity_type = 'sales_order'
      AND event_key = 'sales.order.created'
      AND action_url = '/sales/orders/' || entity_id::TEXT
  )
  INTO v_count, v_known_count
  FROM public.notifications
  WHERE entity_id = ANY(v_order_ids);

  IF v_count <> 20 OR v_known_count <> 20 THEN
    RAISE EXCEPTION
      'ABORT: target notifications changed (total %, recognized creation rows %)',
      v_count, v_known_count;
  END IF;

  SELECT COUNT(*)
  INTO v_count
  FROM (
    SELECT entity_id
    FROM public.notifications
    WHERE entity_id = ANY(v_order_ids)
    GROUP BY entity_id
    HAVING COUNT(*) = 5
  ) AS five_per_order;

  IF v_count <> 4 THEN
    RAISE EXCEPTION 'ABORT: expected exactly five notifications for each target order';
  END IF;

  RAISE NOTICE 'PREFLIGHT OK: four exact empty drafts are locked and verified';
  RAISE NOTICE 'PREFLIGHT OK: zero stock, payment, ledger, journal, custody, vault, return, item, activity, commission, or due-date effects';
  RAISE NOTICE 'PREFLIGHT OK: exactly 20 recognized creation notifications will be removed';

  IF NOT v_execute THEN
    RAISE NOTICE 'DRY RUN ONLY: no rows were changed. Set v_execute := TRUE after review.';
    RETURN;
  END IF;

  -- Retain one non-operational audit snapshot per deleted order.
  INSERT INTO public.audit_logs (
    user_id, action, entity_type, entity_id, old_data, new_data, user_agent
  )
  SELECT
    NULL,
    'hard_delete_empty_wrong_sales_order',
    'sales_order_maintenance',
    so.id,
    jsonb_build_object(
      'sales_order', to_jsonb(so),
      'notifications', (
        SELECT COALESCE(jsonb_agg(to_jsonb(n) ORDER BY n.created_at, n.id), '[]'::JSONB)
        FROM public.notifications n
        WHERE n.entity_id = so.id
      )
    ),
    jsonb_build_object(
      'reason', 'Empty draft order created by mistake for Renault Service Center on 2026-07-27',
      'executed_at', clock_timestamp()
    ),
    'one-off SQL maintenance script'
  FROM public.sales_orders so
  WHERE so.id = ANY(v_order_ids);
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 4 THEN
    RAISE EXCEPTION 'ABORT: wrote % audit snapshots instead of 4', v_affected;
  END IF;

  -- notification_delivery_log children, if any, are removed by notification FK cascade.
  DELETE FROM public.notifications
  WHERE entity_id = ANY(v_order_ids)
    AND entity_type = 'sales_order'
    AND event_key = 'sales.order.created';
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 20 THEN
    RAISE EXCEPTION 'ABORT: deleted % notifications instead of 20', v_affected;
  END IF;

  DELETE FROM public.sales_orders
  WHERE id = ANY(v_order_ids)
    AND status = 'draft'
    AND total_amount = 0
    AND COALESCE(paid_amount, 0) = 0;
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 4 THEN
    RAISE EXCEPTION 'ABORT: deleted % order headers instead of 4', v_affected;
  END IF;

  -- Post-mutation invariants. Any failure rolls back audit + notifications + orders.
  SELECT
    (SELECT COUNT(*) FROM public.sales_orders WHERE id = ANY(v_order_ids) OR order_number = ANY(v_order_numbers))
    + (SELECT COUNT(*) FROM public.notifications WHERE entity_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.sales_order_items WHERE order_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.payment_receipts WHERE sales_order_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.sales_returns WHERE order_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.activities WHERE order_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.sales_order_due_date_history WHERE order_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.stock_movements WHERE reference_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.customer_ledger WHERE source_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.journal_entries WHERE source_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.custody_transactions WHERE reference_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.vault_transactions WHERE reference_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.hr_commission_records WHERE source_id = ANY(v_order_ids))
    + (SELECT COUNT(*) FROM public.notification_alert_state WHERE entity_id = ANY(v_order_ids))
  INTO v_count;

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'ABORT: % target operational row(s) remain after cleanup', v_count;
  END IF;

  SELECT COUNT(*)
  INTO v_count
  FROM public.audit_logs
  WHERE action = 'hard_delete_empty_wrong_sales_order'
    AND entity_type = 'sales_order_maintenance'
    AND entity_id = ANY(v_order_ids);

  IF v_count <> 4 THEN
    RAISE EXCEPTION 'ABORT: retained audit snapshot count is %, expected 4', v_count;
  END IF;

  SELECT COUNT(*)
  INTO v_count
  FROM public.sales_orders
  WHERE id = v_valid_order_id
    AND order_number = v_valid_order_number
    AND customer_id = v_customer_id;

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'ABORT: valid order guard failed after cleanup';
  END IF;

  RAISE NOTICE 'EXECUTION OK: four empty mistaken orders and 20 notifications were deleted';
  RAISE NOTICE 'EXECUTION OK: SO-20260727-0379 remains present and untouched';
END;
$maintenance$;

COMMIT;

-- Read-only result summary.
SELECT
  CASE
    WHEN (SELECT COUNT(*) FROM public.sales_orders
          WHERE id = ANY(ARRAY[
            '98e5d655-998e-4855-b705-5be62e8fe07c'::UUID,
            'd0c4b9e3-af9c-4680-a4fb-20c6be3f27ae'::UUID,
            '22af7141-4441-4b81-9924-92729aff34a6'::UUID,
            '97d7a918-6670-414a-b38c-03dce41a4d4b'::UUID
          ])) = 4
      THEN 'dry_run_not_deleted'
    WHEN (SELECT COUNT(*) FROM public.sales_orders
          WHERE id = ANY(ARRAY[
            '98e5d655-998e-4855-b705-5be62e8fe07c'::UUID,
            'd0c4b9e3-af9c-4680-a4fb-20c6be3f27ae'::UUID,
            '22af7141-4441-4b81-9924-92729aff34a6'::UUID,
            '97d7a918-6670-414a-b38c-03dce41a4d4b'::UUID
          ])) = 0
      THEN 'deleted_and_verified'
    ELSE 'unexpected_partial_state'
  END AS operation_state,
  (SELECT COUNT(*) FROM public.sales_orders
   WHERE id = '2c459ff1-fe5a-4e13-9cdd-a3383377e0de'::UUID
     AND order_number = 'SO-20260727-0379') AS valid_order_rows,
  (SELECT COUNT(*) FROM public.audit_logs
   WHERE action = 'hard_delete_empty_wrong_sales_order'
     AND entity_type = 'sales_order_maintenance'
     AND entity_id = ANY(ARRAY[
       '98e5d655-998e-4855-b705-5be62e8fe07c'::UUID,
       'd0c4b9e3-af9c-4680-a4fb-20c6be3f27ae'::UUID,
       '22af7141-4441-4b81-9924-92729aff34a6'::UUID,
       '97d7a918-6670-414a-b38c-03dce41a4d4b'::UUID
     ])) AS retained_audit_rows;
