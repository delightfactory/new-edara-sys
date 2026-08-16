-- ============================================================================
-- Work Management — Migration A3: align DB status values with approved model.
-- Approved core states:
--   draft, open, in_progress, waiting, pending_approval, done, cancelled
-- Blocked/Overdue/Stale/At-Risk/Escalated are operational flags, not statuses.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE TYPE public.work_item_status_v2 AS ENUM (
  'draft',
  'open',
  'in_progress',
  'waiting',
  'pending_approval',
  'done',
  'cancelled'
);

ALTER TABLE public.work_items
  ALTER COLUMN status DROP DEFAULT;

ALTER TABLE public.work_items
  ALTER COLUMN status TYPE public.work_item_status_v2
  USING (
    CASE status::TEXT
      WHEN 'waiting_internal' THEN 'waiting'
      WHEN 'waiting_external' THEN 'waiting'
      WHEN 'blocked' THEN 'open'
      ELSE status::TEXT
    END
  )::public.work_item_status_v2;

ALTER TABLE public.work_events
  ALTER COLUMN from_status TYPE public.work_item_status_v2
  USING (
    CASE from_status::TEXT
      WHEN 'waiting_internal' THEN 'waiting'
      WHEN 'waiting_external' THEN 'waiting'
      WHEN 'blocked' THEN 'open'
      ELSE from_status::TEXT
    END
  )::public.work_item_status_v2,
  ALTER COLUMN to_status TYPE public.work_item_status_v2
  USING (
    CASE to_status::TEXT
      WHEN 'waiting_internal' THEN 'waiting'
      WHEN 'waiting_external' THEN 'waiting'
      WHEN 'blocked' THEN 'open'
      ELSE to_status::TEXT
    END
  )::public.work_item_status_v2;

DROP TYPE public.work_item_status;
ALTER TYPE public.work_item_status_v2 RENAME TO work_item_status;

ALTER TABLE public.work_items
  ALTER COLUMN status SET DEFAULT 'draft'::public.work_item_status;

COMMENT ON TYPE public.work_item_status IS
  'Canonical lifecycle only. Operational flags such as blocked/overdue/stale are computed separately.';

RESET lock_timeout;
RESET statement_timeout;
