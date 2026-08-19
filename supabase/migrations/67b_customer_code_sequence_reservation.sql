-- ============================================================
-- Reserve the legacy explicit customer-code range before seed 68.
--
-- Migration 68 imports customers with explicit CUS-xxxxx codes up to
-- CUS-01657 and also imports legacy rows without a code. Those no-code
-- rows use trg_customer_auto_code -> customer_code_seq. On a fresh
-- database the sequence otherwise starts at 1 and can collide with an
-- explicit legacy code later in the same seed, or worse reuse a code
-- that belongs to another imported customer.
--
-- This migration keeps the existing generator semantics intact and only
-- advances the sequence beyond both:
--   1) the highest CUS-numeric code already present, and
--   2) the explicit range reserved by 68_seed_customers.sql (1..1657).
--
-- It is idempotent and safe on databases whose sequence/customer codes
-- are already ahead of the legacy reserved range.
-- ============================================================

DO $$
DECLARE
  v_existing_max bigint := 0;
  v_sequence_last bigint := 0;
  v_reserved_seed_max constant bigint := 1657;
  v_target bigint;
BEGIN
  IF to_regclass('public.customers') IS NULL
     OR to_regclass('public.customer_code_seq') IS NULL THEN
    RAISE EXCEPTION 'customers/customer_code_seq must exist before reserving legacy customer codes';
  END IF;

  SELECT COALESCE(
           MAX(substring(code FROM '^CUS-([0-9]+)$')::bigint),
           0
         )
    INTO v_existing_max
    FROM public.customers
   WHERE code ~ '^CUS-[0-9]+$';

  SELECT last_value
    INTO v_sequence_last
    FROM public.customer_code_seq;

  v_target := GREATEST(v_existing_max, v_sequence_last, v_reserved_seed_max);

  PERFORM setval('public.customer_code_seq'::regclass, v_target, true);
END;
$$;
