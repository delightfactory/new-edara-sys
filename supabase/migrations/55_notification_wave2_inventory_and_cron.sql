-- ═══════════════════════════════════════════════════════════════════════════
-- 55_notification_wave2_inventory_and_cron.sql
-- Wave 2 — Inventory Triggers + Cron Alert Jobs
--
-- SCOPE:
--   1. stock_transfers — new trigger: notify_on_stock_transfer_change()
--   2. stock_adjustments — new trigger: notify_on_stock_adjustment_change()
--   3. Cron job: check-low-stock-alerts (inventory.stock.low / .out)
--   4. Cron job: check-overdue-invoices (sales.invoice.overdue)
--
-- EVENT KEYS — all seeded status:
--   inventory.transfer.requested → seeded in 42_notification_system.sql L696 ✓
--   inventory.transfer.approved  → seeded in 52_notification_wave1a_events.sql ✓
--   inventory.transfer.completed → NOT YET SEEDED — added as part of this migration
--   inventory.adjustment.pending → seeded in 52_notification_wave1a_events.sql ✓
--   inventory.adjustment.approved → seeded in 52_notification_wave1a_events.sql ✓
--   inventory.stock.low          → seeded in 42_notification_system.sql L682 ✓
--   inventory.stock.out          → seeded in 42_notification_system.sql ✓
--   sales.invoice.overdue        → seeded in 42_notification_system.sql ✓
--
-- SCHEMA VERIFIED:
--   stock_transfers:
--     from_warehouse_id / to_warehouse_id → warehouses(id)
--     requested_by → profiles(id) NOT NULL
--     status CHECK IN ('pending','approved','in_transit','received','cancelled')
--     approved_by / received_by → profiles(id)
--   stock_adjustments:
--     warehouse_id → warehouses(id) NOT NULL
--     status CHECK IN ('draft','pending','approved','rejected')
--     created_by → profiles(id) NOT NULL
--     approved_by → profiles(id)
--   warehouse_managers:
--     warehouse_id + profile_id (UNIQUE) — profile_id = profiles.id directly
--     is_primary BOOLEAN — primary manager gets first priority
--   warehouses:
--     manager_id → profiles(id) — fallback manager
--   stock + products:
--     stock.available_quantity (GENERATED: quantity - reserved_quantity)
--     products.min_stock_level NUMERIC DEFAULT 0 (per 02_master_data.sql L116)
--   sales_orders:
--     due_date DATE — computed at delivery time (04_sales_system.sql L193)
--     status ENUM: 'confirmed','partially_delivered','delivered','completed','cancelled'
--     rep_id → profiles(id)
--     (credited/paid detection: paid_amount >= total_amount - returned_amount)
--
-- RECIPIENT MAPPING (all via direct lookup — not permission-based):
--   transfer.requested  → destination warehouse managers (warehouse_managers.profile_id
--                          WHERE warehouse_id = NEW.to_warehouse_id)
--                         + warehouses.manager_id fallback
--   transfer.approved   → NEW.requested_by
--   transfer.completed  → NEW.requested_by + source warehouse managers
--   adjustment.pending  → source warehouse managers (same warehouse_id lookup)
--   adjustment.approved → NEW.created_by
--   stock.low / .out    → warehouse managers for that warehouse (via cron function)
--                         + permission lookup 'inventory.management' / * wildcard
--   invoice.overdue     → sales_orders.rep_id + finance.ledger.read / * holders
--
-- NON-BLOCKING SAFETY:
--   ✅ AFTER triggers only
--   ✅ BEGIN..EXCEPTION WHEN OTHERS in every branch
--   ✅ SECURITY DEFINER + SET search_path = public
--   ✅ Cron functions: per-item BEGIN..EXCEPTION in inner loop
--
-- DUPLICATE/SPAM PREVENTION (cron):
--   Base strategy: notification_alert_state with UNIQUE(alert_key)
--   alert_key format: 'event_key::entity_id::warehouse_id'
--   Cooldown: 24h for stock, 72h for invoices
--   Auto-resolve: stock alerts resolve when available_quantity > min_stock_level
--   Invoice alerts: NO auto-resolve (rationale documented in section 4)
--
-- BASELINE COMPATIBILITY:
--   53b_fix_target_recalc_function_ambiguity.sql respected:
--     no calls to recalculate_targets_for_employee
-- ═══════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 0: Seed missing event key
-- inventory.transfer.completed was NOT seeded in any prior migration
-- ═══════════════════════════════════════════════════════════════════════════
INSERT INTO public.notification_event_types (
  event_key, label_ar, label_en,
  category, default_priority,
  title_template, body_template,
  icon, action_url_template
) VALUES
  ('inventory.transfer.completed',
   'اكتمل استلام التحويل', 'Transfer Completed',
   'inventory', 'medium',
   'تم استلام التحويل {{transfer_number}} بالكامل',
   'تحويل المخزون {{transfer_number}} تم استلامه في المخزن الوجهة وأُغلق',
   'package-check', '/inventory/transfers/{{transfer_id}}')
ON CONFLICT (event_key) DO NOTHING;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1: stock_transfers — notify_on_stock_transfer_change()
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Events covered:
--   INSERT status='pending'  → inventory.transfer.requested
--   UPDATE status→'approved' → inventory.transfer.approved
--   UPDATE status→'received' → inventory.transfer.completed
--
-- Recipient logic (direct lookup, NOT permission-based — matches inventory workflow):
--   requested: managers of the DESTINATION warehouse (to_warehouse_id)
--               → warehouse_managers WHERE warehouse_id = NEW.to_warehouse_id
--               + warehouses.manager_id as fallback if no warehouse_managers rows
--   approved:  NEW.requested_by (the person who created the transfer request)
--   completed: NEW.requested_by + managers of the SOURCE warehouse (from_warehouse_id)
--               (source needs to know goods left; requester needs confirmation)
--
-- No existing notification triggers on stock_transfers (verified by grep).
-- Existing BEFORE triggers: trg_transfer_auto_number (02_master_data.sql L456) — safe.

CREATE OR REPLACE FUNCTION public.notify_on_stock_transfer_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_recipient_ids  uuid[];
  v_transfer_num   text;
  v_from_wh_name   text;
  v_to_wh_name     text;
BEGIN
  BEGIN
    v_transfer_num := COALESCE(NEW.number, NEW.id::text);

    SELECT w.name INTO v_from_wh_name FROM warehouses w WHERE w.id = NEW.from_warehouse_id LIMIT 1;
    SELECT w.name INTO v_to_wh_name   FROM warehouses w WHERE w.id = NEW.to_warehouse_id   LIMIT 1;

    -- ─────────────────────────────────────────────────────────────
    -- INSERT status='pending' → inventory.transfer.requested
    -- Notify: destination warehouse managers
    -- ─────────────────────────────────────────────────────────────
    IF TG_OP = 'INSERT' AND NEW.status = 'pending' THEN
      -- Primary: warehouse_managers entries for to_warehouse_id
      -- Fallback: warehouses.manager_id (primary manager field)
      SELECT ARRAY(
        SELECT DISTINCT profile_id
        FROM warehouse_managers
        WHERE warehouse_id = NEW.to_warehouse_id
        UNION
        SELECT manager_id
        FROM warehouses
        WHERE id = NEW.to_warehouse_id
          AND manager_id IS NOT NULL
        LIMIT 10
      ) INTO v_recipient_ids;

      IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
        PERFORM public.call_dispatch_notification(
          'inventory.transfer.requested',
          v_recipient_ids,
          jsonb_build_object(
            'transfer_number', v_transfer_num,
            'from_warehouse',  COALESCE(v_from_wh_name, 'مخزن'),
            'to_warehouse',    COALESCE(v_to_wh_name, 'مخزن'),
            'transfer_id',     NEW.id::text
          ),
          'stock_transfer',
          NEW.id
        );
      END IF;

    -- ─────────────────────────────────────────────────────────────
    -- UPDATE status → 'approved' → inventory.transfer.approved
    -- Notify: the requester (who created the transfer)
    -- ─────────────────────────────────────────────────────────────
    ELSIF TG_OP = 'UPDATE'
      AND NEW.status = 'approved'
      AND OLD.status IS DISTINCT FROM 'approved'
      AND NEW.requested_by IS NOT NULL THEN

      PERFORM public.call_dispatch_notification(
        'inventory.transfer.approved',
        ARRAY[NEW.requested_by],
        jsonb_build_object(
          'transfer_number', v_transfer_num,
          'from_warehouse',  COALESCE(v_from_wh_name, 'مخزن'),
          'to_warehouse',    COALESCE(v_to_wh_name, 'مخزن'),
          'transfer_id',     NEW.id::text
        ),
        'stock_transfer',
        NEW.id
      );

    -- ─────────────────────────────────────────────────────────────
    -- UPDATE status → 'received' → inventory.transfer.completed
    -- Notify: requester + source warehouse managers
    -- ─────────────────────────────────────────────────────────────
    ELSIF TG_OP = 'UPDATE'
      AND NEW.status = 'received'
      AND OLD.status IS DISTINCT FROM 'received' THEN

      SELECT ARRAY(
        -- The requester needs to know their transfer is complete
        SELECT NEW.requested_by WHERE NEW.requested_by IS NOT NULL
        UNION
        -- Source warehouse managers need to know goods left their warehouse
        SELECT DISTINCT wm.profile_id
        FROM warehouse_managers wm
        WHERE wm.warehouse_id = NEW.from_warehouse_id
        UNION
        SELECT w.manager_id
        FROM warehouses w
        WHERE w.id = NEW.from_warehouse_id
          AND w.manager_id IS NOT NULL
        LIMIT 15
      ) INTO v_recipient_ids;

      IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
        PERFORM public.call_dispatch_notification(
          'inventory.transfer.completed',
          v_recipient_ids,
          jsonb_build_object(
            'transfer_number', v_transfer_num,
            'from_warehouse',  COALESCE(v_from_wh_name, 'مخزن'),
            'to_warehouse',    COALESCE(v_to_wh_name, 'مخزن'),
            'transfer_id',     NEW.id::text
          ),
          'stock_transfer',
          NEW.id
        );
      END IF;

    END IF;

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[notify_on_stock_transfer_change] non-critical: %', SQLERRM;
  END;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_stock_transfer_change ON public.stock_transfers;
CREATE TRIGGER trg_notify_stock_transfer_change
  AFTER INSERT OR UPDATE OF status ON public.stock_transfers
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_stock_transfer_change();

REVOKE EXECUTE ON FUNCTION public.notify_on_stock_transfer_change() FROM authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2: stock_adjustments — notify_on_stock_adjustment_change()
-- ═══════════════════════════════════════════════════════════════════════════
--
-- [P1 FIX] Events covered via INSERT OR UPDATE:
--   INSERT status='pending'  → inventory.adjustment.pending
--     (create_stock_adjustment() in 02e L72-76 inserts directly with status='pending';
--      there is no draft→pending UPDATE in the standard workflow — INSERT must be covered)
--   UPDATE status → 'pending'  → inventory.adjustment.pending
--     (covers UI flows that first set status='draft' then submit='pending')
--   UPDATE status → 'approved' → inventory.adjustment.approved
--
-- Duplicate guard: TG_OP = 'INSERT' path uses NEW.status directly.
--   UPDATE path uses OLD.status IS DISTINCT FROM NEW.status guard.
--   No double-fire risk: INSERT fires only once at creation; UPDATE fires on transitions.
--
-- Recipient logic (DIRECT LOOKUP matching 02e_inventory_hardening.sql L148-156):
--   pending: warehouse managers for the adjustment's warehouse
--              → warehouse_managers WHERE warehouse_id = NEW.warehouse_id
--              + warehouses.manager_id fallback
--   approved: NEW.created_by (the staff who submitted the adjustment)
--
-- Existing BEFORE triggers: trg_adjustment_auto_number (02_master_data.sql L504) — safe.
-- No existing notification triggers on stock_adjustments (verified).

CREATE OR REPLACE FUNCTION public.notify_on_stock_adjustment_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_recipient_ids  uuid[];
  v_adj_num        text;
  v_wh_name        text;
BEGIN
  BEGIN
    v_adj_num := COALESCE(NEW.number, NEW.id::text);

    SELECT w.name INTO v_wh_name
    FROM warehouses w WHERE w.id = NEW.warehouse_id LIMIT 1;

    -- ─────────────────────────────────────────────────────────────
    -- INSERT status='pending' → inventory.adjustment.pending
    -- This is the PRIMARY path: create_stock_adjustment() inserts
    -- with status='pending' directly (02e_inventory_hardening.sql L72-76).
    -- ─────────────────────────────────────────────────────────────
    IF TG_OP = 'INSERT' AND NEW.status = 'pending' THEN
      SELECT ARRAY(
        SELECT DISTINCT wm.profile_id
        FROM warehouse_managers wm
        WHERE wm.warehouse_id = NEW.warehouse_id
        UNION
        SELECT w.manager_id
        FROM warehouses w
        WHERE w.id = NEW.warehouse_id
          AND w.manager_id IS NOT NULL
        LIMIT 10
      ) INTO v_recipient_ids;

      IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
        PERFORM public.call_dispatch_notification(
          'inventory.adjustment.pending',
          v_recipient_ids,
          jsonb_build_object(
            'adjustment_number', v_adj_num,
            'warehouse_name',    COALESCE(v_wh_name, 'مخزن'),
            'reason',            COALESCE(NEW.reason, '—'),
            'adjustment_id',     NEW.id::text
          ),
          'stock_adjustment',
          NEW.id
        );
      END IF;

    ELSIF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN

      -- ─────────────────────────────────────────────────────────────
      -- UPDATE status → 'pending' → inventory.adjustment.pending
      -- Covers UI flows that first create as 'draft' then submit.
      -- ─────────────────────────────────────────────────────────────
      IF NEW.status = 'pending' AND OLD.status IS DISTINCT FROM 'pending' THEN
        SELECT ARRAY(
          SELECT DISTINCT wm.profile_id
          FROM warehouse_managers wm
          WHERE wm.warehouse_id = NEW.warehouse_id
          UNION
          SELECT w.manager_id
          FROM warehouses w
          WHERE w.id = NEW.warehouse_id
            AND w.manager_id IS NOT NULL
          LIMIT 10
        ) INTO v_recipient_ids;

        IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
          PERFORM public.call_dispatch_notification(
            'inventory.adjustment.pending',
            v_recipient_ids,
            jsonb_build_object(
              'adjustment_number', v_adj_num,
              'warehouse_name',    COALESCE(v_wh_name, 'مخزن'),
              'reason',            COALESCE(NEW.reason, '—'),
              'adjustment_id',     NEW.id::text
            ),
            'stock_adjustment',
            NEW.id
          );
        END IF;

      -- ─────────────────────────────────────────────────────────────
      -- UPDATE status → 'approved' → inventory.adjustment.approved
      -- Notify: the staff who created the adjustment
      -- ─────────────────────────────────────────────────────────────
      ELSIF NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved' THEN
        IF NEW.created_by IS NOT NULL THEN
          PERFORM public.call_dispatch_notification(
            'inventory.adjustment.approved',
            ARRAY[NEW.created_by],
            jsonb_build_object(
              'adjustment_number', v_adj_num,
              'warehouse_name',    COALESCE(v_wh_name, 'مخزن'),
              'adjustment_id',     NEW.id::text
            ),
            'stock_adjustment',
            NEW.id
          );
        END IF;
      END IF;

    END IF; -- TG_OP

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[notify_on_stock_adjustment_change] non-critical: %', SQLERRM;
  END;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_stock_adjustment_change ON public.stock_adjustments;
CREATE TRIGGER trg_notify_stock_adjustment_change
  AFTER INSERT OR UPDATE OF status ON public.stock_adjustments
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_stock_adjustment_change();

REVOKE EXECUTE ON FUNCTION public.notify_on_stock_adjustment_change() FROM authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3: Cron Function — check_low_stock_alerts()
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Runs periodically to detect low/out-of-stock conditions and notify managers.
--
-- DEDUPE STRATEGY (notification_alert_state):
--   alert_key = 'inventory.stock.low::<product_id>::<warehouse_id>'
--             or 'inventory.stock.out::<product_id>::<warehouse_id>'
--   A new alert row is inserted when condition first detected → last_sent_at set.
--   Cooldown: 24h — no repeat notification within 24h of last_sent.
--   Auto-resolve: when stock recovers (available_quantity > min_stock_level),
--                 resolved_at is SET on the matching alert_key.
--                 If stock drops again later, the alert_key row is found with
--                 resolved_at set → treated as new occurrence → resolved_at cleared
--                 and a fresh notification fires.
--
-- LOW STOCK THRESHOLD: products.min_stock_level (02_master_data.sql L116)
--   Only products with min_stock_level > 0 are tracked.
--   out = available_quantity <= 0
--   low = 0 < available_quantity <= min_stock_level (and product not already 'out')
--
-- RECIPIENT: warehouse managers (direct lookup) + inventory.management permission holders
--   Combined: gives both operational managers and inventory supervisors awareness.
--
-- IDEMPOTENCY: Safe to run multiple times — INSERT ON CONFLICT + cooldown guard.

CREATE OR REPLACE FUNCTION public.check_low_stock_alerts()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item         RECORD;
  v_alert_key    TEXT;
  v_event_key    TEXT;
  v_state        RECORD;
  v_now          TIMESTAMPTZ := now();
  v_alert_count  INTEGER := 0;
  v_resolve_count INTEGER := 0;
  v_recipient_ids uuid[];
  v_perm_holders  uuid[];
BEGIN

  -- ── Step 1: Build reusable permission-holder list ──────────────────────
  -- Once per run — not per product (performance)
  -- [P2 FIX] Using 'inventory.read_all' — verified in constants.ts L75 and seeded
  --          in 02_master_data.sql. 'inventory.management' was NOT in schema.
  --          Wildcard * catches super_admin / ceo as fallback.
  SELECT ARRAY(
    SELECT DISTINCT ur.user_id
    FROM user_roles ur
    JOIN role_permissions rp ON rp.role_id = ur.role_id
    WHERE rp.permission IN ('inventory.read_all', '*')
      AND ur.is_active = true
    LIMIT 20
  ) INTO v_perm_holders;

  -- ── Step 2: Auto-resolve alerts where stock has recovered ─────────────
  -- For each active (unresolved) stock alert, check if stock is now healthy.
  -- If yes: set resolved_at so we don't keep it as "active".
  FOR v_state IN
    SELECT nas.alert_key, nas.entity_id, nas.event_key,
           nas.id AS state_id
    FROM notification_alert_state nas
    WHERE nas.event_key IN ('inventory.stock.low', 'inventory.stock.out')
      AND nas.resolved_at IS NULL
  LOOP
    BEGIN
      -- entity_id is the stock row id for these alerts
      IF NOT EXISTS (
        SELECT 1
        FROM stock s
        JOIN products p ON p.id = s.product_id
        WHERE s.id = v_state.entity_id
          AND p.min_stock_level > 0
          AND s.available_quantity <= p.min_stock_level
      ) THEN
        -- Stock is healthy again → mark resolved
        UPDATE notification_alert_state
        SET resolved_at = v_now
        WHERE id = v_state.state_id;
        v_resolve_count := v_resolve_count + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '[check_low_stock_alerts] resolve loop error: %', SQLERRM;
    END;
  END LOOP;

  -- ── Step 3: Detect current low/out conditions ──────────────────────────
  FOR v_item IN
    SELECT
      s.id             AS stock_id,
      s.warehouse_id,
      s.product_id,
      s.available_quantity,
      p.min_stock_level,
      p.name           AS product_name,
      w.name           AS warehouse_name
    FROM stock s
    JOIN products p ON p.id = s.product_id
    JOIN warehouses w ON w.id = s.warehouse_id
    WHERE p.min_stock_level > 0                        -- only tracked products
      AND s.available_quantity <= p.min_stock_level    -- below threshold
    ORDER BY s.available_quantity ASC
    LIMIT 100  -- cap per run to avoid runaway
  LOOP
    BEGIN
      -- Classify: out vs low
      IF v_item.available_quantity <= 0 THEN
        v_event_key := 'inventory.stock.out';
      ELSE
        v_event_key := 'inventory.stock.low';
      END IF;

      v_alert_key := v_event_key || '::' || v_item.product_id::text
                     || '::' || v_item.warehouse_id::text;

      -- ── Check dedupe state ─────────────────────────────────────────────
      SELECT * INTO v_state
      FROM notification_alert_state
      WHERE alert_key = v_alert_key;

      IF FOUND THEN
        -- Alert exists
        IF v_state.resolved_at IS NOT NULL THEN
          -- Was resolved but condition returned → reopen
          UPDATE notification_alert_state
          SET resolved_at  = NULL,
              send_count   = send_count + 1,
              last_sent_at = v_now
          WHERE alert_key = v_alert_key;
          -- Fall through to send notification
        ELSIF (v_now - v_state.last_sent_at) < (v_state.cooldown_hours * INTERVAL '1 hour') THEN
          -- Within cooldown window → skip (no spam)
          CONTINUE;
        ELSE
          -- Cooldown expired → send reminder and update timestamp
          UPDATE notification_alert_state
          SET send_count   = send_count + 1,
              last_sent_at = v_now
          WHERE alert_key = v_alert_key;
          -- Fall through to send notification
        END IF;
      ELSE
        -- First occurrence → create alert state
        INSERT INTO notification_alert_state (
          alert_key, event_key, entity_type, entity_id,
          last_sent_at, resolved_at, send_count, cooldown_hours
        ) VALUES (
          v_alert_key, v_event_key, 'stock', v_item.stock_id,
          v_now, NULL, 1, 24
        );
        -- Fall through to send notification
      END IF;

      -- ── Build recipient list: warehouse managers + perm holders ──────
      SELECT ARRAY(
        -- Warehouse managers for this specific warehouse
        SELECT DISTINCT wm.profile_id
        FROM warehouse_managers wm
        WHERE wm.warehouse_id = v_item.warehouse_id
        UNION
        -- Warehouses primary manager_id
        SELECT w.manager_id
        FROM warehouses w
        WHERE w.id = v_item.warehouse_id AND w.manager_id IS NOT NULL
        UNION
        -- Global inventory permission holders
        SELECT UNNEST(v_perm_holders)
        LIMIT 20
      ) INTO v_recipient_ids;

      IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
        PERFORM public.call_dispatch_notification(
          v_event_key,
          v_recipient_ids,
          jsonb_build_object(
            'product_name',      v_item.product_name,
            'warehouse_name',    v_item.warehouse_name,
            'available_qty',     v_item.available_quantity::text,
            'min_stock_level',   v_item.min_stock_level::text,
            'stock_id',          v_item.stock_id::text
          ),
          'stock',
          v_item.stock_id
        );
        v_alert_count := v_alert_count + 1;
      END IF;

    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '[check_low_stock_alerts] item % error: %',
                    v_item.stock_id, SQLERRM;
    END;
  END LOOP;

  RAISE NOTICE '[check_low_stock_alerts] alerts sent: %, resolved: %',
               v_alert_count, v_resolve_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_low_stock_alerts() TO service_role;
REVOKE EXECUTE ON FUNCTION public.check_low_stock_alerts() FROM authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 4: Cron Function — check_overdue_invoices()
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Detects sales orders with credit payment terms that are past their due_date
-- and have unpaid balances. Notifies rep + finance team.
--
-- OVERDUE DEFINITION:
--   sales_orders WHERE:
--     payment_terms = 'credit' (or 'mixed' with remaining balance)
--     AND due_date IS NOT NULL AND due_date < CURRENT_DATE
--     AND status NOT IN ('cancelled', 'completed')
--     AND paid_amount < (total_amount - returned_amount)  ← outstanding balance
--
-- DEDUPE STRATEGY:
--   alert_key = 'sales.invoice.overdue::<order_id>'
--   Cooldown: 72h (3 days) — credit collections are not urgent enough for daily spam
--
-- AUTO-RESOLVE: NO
--   Rationale: There is no safe place in the DB to hook "invoice became non-overdue"
--   without a complex trigger chain or RPC interception. The paid_amount update
--   happens inside allocate_payment_to_invoices() (08_payment_receipts_refactor.sql)
--   and sales_order status can change via deliver_sales_order() or confirm_payment_receipt().
--   Adding a resolve trigger here would require touching Wave 1B business logic silently.
--   DECISION: alerts expire naturally when order reaches 'completed'/'cancelled'
--             (excluded from the query above). Manual resolution is required for
--             partial payments unless a future Wave adds explicit resolve logic.
--
-- RECIPIENT:
--   sales_orders.rep_id (the sales representative responsible for collection)
--   + permission holders: finance.ledger.read / * (finance team oversight)
--   (wildcard * included per project pattern from migration 50)

CREATE OR REPLACE FUNCTION public.check_overdue_invoices()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order        RECORD;
  v_alert_key    TEXT;
  v_state        RECORD;
  v_now          TIMESTAMPTZ := now();
  v_today        DATE        := CURRENT_DATE;
  v_alert_count  INTEGER     := 0;
  v_finance_ids  uuid[];
  v_recipient_ids uuid[];
BEGIN

  -- ── Step 1: Build finance team recipient list once per run ─────────────
  SELECT ARRAY(
    SELECT DISTINCT ur.user_id
    FROM user_roles ur
    JOIN role_permissions rp ON rp.role_id = ur.role_id
    WHERE rp.permission IN ('finance.ledger.read', '*')
      AND ur.is_active = true
    LIMIT 15
  ) INTO v_finance_ids;

  -- ── Step 2: Scan overdue credit orders ────────────────────────────────
  FOR v_order IN
    SELECT
      so.id,
      so.order_number,
      so.rep_id,
      so.due_date,
      so.total_amount,
      so.paid_amount,
      so.returned_amount,
      (so.total_amount - COALESCE(so.returned_amount, 0) - COALESCE(so.paid_amount, 0)) AS outstanding,
      COALESCE(c.name, 'عميل') AS customer_name
    FROM sales_orders so
    LEFT JOIN customers c ON c.id = so.customer_id
    WHERE so.payment_terms IN ('credit', 'mixed')
      AND so.due_date IS NOT NULL
      AND so.due_date < v_today
      AND so.status NOT IN ('cancelled', 'completed')
      AND (so.total_amount - COALESCE(so.returned_amount, 0) - COALESCE(so.paid_amount, 0)) > 0
    ORDER BY so.due_date ASC
    LIMIT 100
  LOOP
    BEGIN
      v_alert_key := 'sales.invoice.overdue::' || v_order.id::text;

      -- ── Check dedupe state ─────────────────────────────────────────────
      SELECT * INTO v_state
      FROM notification_alert_state
      WHERE alert_key = v_alert_key;

      IF FOUND THEN
        IF v_state.resolved_at IS NOT NULL THEN
          -- Re-overdue (edge case): reopen
          UPDATE notification_alert_state
          SET resolved_at  = NULL,
              send_count   = send_count + 1,
              last_sent_at = v_now
          WHERE alert_key = v_alert_key;
        ELSIF (v_now - v_state.last_sent_at) < (v_state.cooldown_hours * INTERVAL '1 hour') THEN
          CONTINUE; -- Within 72h cooldown — skip
        ELSE
          -- Cooldown expired → send reminder
          UPDATE notification_alert_state
          SET send_count   = send_count + 1,
              last_sent_at = v_now
          WHERE alert_key = v_alert_key;
        END IF;
      ELSE
        -- First occurrence
        INSERT INTO notification_alert_state (
          alert_key, event_key, entity_type, entity_id,
          last_sent_at, resolved_at, send_count, cooldown_hours
        ) VALUES (
          v_alert_key, 'sales.invoice.overdue', 'sales_order', v_order.id,
          v_now, NULL, 1, 72
        );
      END IF;

      -- ── Build recipient list ─────────────────────────────────────────
      SELECT ARRAY(
        SELECT v_order.rep_id WHERE v_order.rep_id IS NOT NULL
        UNION
        SELECT UNNEST(v_finance_ids)
        LIMIT 20
      ) INTO v_recipient_ids;

      IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
        PERFORM public.call_dispatch_notification(
          'sales.invoice.overdue',
          v_recipient_ids,
          jsonb_build_object(
            'order_number',   v_order.order_number,
            'customer_name',  v_order.customer_name,
            'due_date',       to_char(v_order.due_date, 'YYYY-MM-DD'),
            'outstanding',    to_char(v_order.outstanding, 'FM999,999,999.00') || ' ج.م',
            'order_id',       v_order.id::text
          ),
          'sales_order',
          v_order.id
        );
        v_alert_count := v_alert_count + 1;
      END IF;

    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '[check_overdue_invoices] order % error: %',
                    v_order.id, SQLERRM;
    END;
  END LOOP;

  RAISE NOTICE '[check_overdue_invoices] alerts sent: %', v_alert_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_overdue_invoices() TO service_role;
REVOKE EXECUTE ON FUNCTION public.check_overdue_invoices() FROM authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 5: Cron Job Scheduling
-- ═══════════════════════════════════════════════════════════════════════════
-- Pattern: unschedule→schedule (idempotent, matches migration 46 pattern)

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'check-low-stock-alerts') THEN
    PERFORM cron.unschedule('check-low-stock-alerts');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'check-overdue-invoices') THEN
    PERFORM cron.unschedule('check-overdue-invoices');
  END IF;
END $$;

-- Every 4 hours — stock levels can change frequently; daily may miss shifts
SELECT cron.schedule(
  'check-low-stock-alerts',
  '0 */4 * * *',
  $$ SELECT public.check_low_stock_alerts(); $$
);

-- Daily at 07:00 UTC (≈ 09:00 Cairo) — morning collections briefing
SELECT cron.schedule(
  'check-overdue-invoices',
  '0 7 * * *',
  $$ SELECT public.check_overdue_invoices(); $$
);


-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_fn_count  INTEGER;
  v_trg_count INTEGER;
  v_cron_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_fn_count
  FROM pg_proc
  WHERE proname IN (
    'notify_on_stock_transfer_change',
    'notify_on_stock_adjustment_change',
    'check_low_stock_alerts',
    'check_overdue_invoices'
  );

  SELECT COUNT(*) INTO v_trg_count
  FROM information_schema.triggers
  WHERE trigger_name IN (
    'trg_notify_stock_transfer_change',
    'trg_notify_stock_adjustment_change'
  );

  SELECT COUNT(*) INTO v_cron_count
  FROM cron.job
  WHERE jobname IN ('check-low-stock-alerts', 'check-overdue-invoices');

  RAISE NOTICE '══════════════════════════════════════════════════════════';
  RAISE NOTICE '[55_notification_wave2] VERIFICATION RESULT:';
  RAISE NOTICE '  Functions registered:  % / 4', v_fn_count;
  RAISE NOTICE '  Triggers registered:   % / 2', v_trg_count;
  RAISE NOTICE '  Cron jobs registered:  % / 2', v_cron_count;

  RAISE NOTICE '  inventory.transfer.completed event: %',
    CASE WHEN EXISTS (SELECT 1 FROM notification_event_types WHERE event_key = 'inventory.transfer.completed')
    THEN '✅ seeded' ELSE '❌ MISSING' END;

  -- Verify no Wave 1 triggers damaged
  RAISE NOTICE '  trg_notify_stock_transfer_change: %',
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name = 'trg_notify_stock_transfer_change')
    THEN '✅ created' ELSE '❌ MISSING' END;

  RAISE NOTICE '  trg_notify_stock_adjustment_change: %',
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name = 'trg_notify_stock_adjustment_change')
    THEN '✅ created' ELSE '❌ MISSING' END;

  RAISE NOTICE '  check-low-stock-alerts cron: %',
    CASE WHEN EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'check-low-stock-alerts')
    THEN '✅ scheduled' ELSE '❌ MISSING' END;

  RAISE NOTICE '  check-overdue-invoices cron: %',
    CASE WHEN EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'check-overdue-invoices')
    THEN '✅ scheduled' ELSE '❌ MISSING' END;

  IF v_fn_count = 4 AND v_trg_count = 2 AND v_cron_count = 2 THEN
    RAISE NOTICE '  ✅ Wave 2 complete';
  ELSE
    RAISE WARNING '[55_wave2] ⚠️  Expected 4 fn / 2 triggers / 2 crons — check above';
  END IF;
  RAISE NOTICE '══════════════════════════════════════════════════════════';
END $$;
