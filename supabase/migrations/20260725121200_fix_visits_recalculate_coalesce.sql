BEGIN;

-- Forward-only repair for private.recalculate_visit_plan_counts(uuid).
-- COALESCE is SQL syntax and cannot be schema-qualified as pg_catalog.coalesce().
DO $$
DECLARE
  v_oid          OID;
  v_definition   TEXT;
  v_owner        OID;
  v_acl          ACLITEM[];
  v_is_definer   BOOLEAN;
  v_config       TEXT[];
  v_bad_count    INTEGER;
BEGIN
  SELECT p.oid, p.proowner, p.proacl, p.prosecdef, p.proconfig
  INTO v_oid, v_owner, v_acl, v_is_definer, v_config
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'private'
    AND p.proname = 'recalculate_visit_plan_counts'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_plan_id uuid';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'private.recalculate_visit_plan_counts(uuid) was not found';
  END IF;

  IF NOT v_is_definer OR v_config IS NULL OR NOT ('search_path=pg_catalog' = ANY(v_config)) THEN
    RAISE EXCEPTION 'private.recalculate_visit_plan_counts(uuid) has unexpected security properties';
  END IF;

  SELECT (
    pg_catalog.length(p.prosrc)
    - pg_catalog.length(pg_catalog.replace(p.prosrc, 'pg_catalog.coalesce(', ''))
  ) / pg_catalog.length('pg_catalog.coalesce(')
  INTO v_bad_count
  FROM pg_catalog.pg_proc p
  WHERE p.oid = v_oid;

  IF v_bad_count = 0 THEN
    IF EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc p
      WHERE p.oid = v_oid
        AND p.prosrc ILIKE '%COALESCE(completed_at, pg_catalog.clock_timestamp())%'
    ) THEN
      RETURN;
    END IF;
    RAISE EXCEPTION 'expected pg_catalog.coalesce() defect was not found and the corrected expression is absent';
  END IF;

  IF v_bad_count <> 1 THEN
    RAISE EXCEPTION 'unexpected pg_catalog.coalesce() occurrence count: %', v_bad_count;
  END IF;

  SELECT pg_catalog.pg_get_functiondef(v_oid) INTO v_definition;
  v_definition := pg_catalog.replace(v_definition, 'pg_catalog.coalesce(', 'COALESCE(');
  EXECUTE v_definition;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc p
    WHERE p.oid = v_oid
      AND (
        p.prosrc ILIKE '%pg_catalog.coalesce(%'
        OR p.prosrc NOT ILIKE '%COALESCE(completed_at, pg_catalog.clock_timestamp())%'
        OR p.proowner IS DISTINCT FROM v_owner
        OR p.proacl IS DISTINCT FROM v_acl
        OR p.prosecdef IS DISTINCT FROM v_is_definer
        OR p.proconfig IS DISTINCT FROM v_config
      )
  ) THEN
    RAISE EXCEPTION 'recalculate_visit_plan_counts repair verification failed';
  END IF;
END;
$$;

COMMIT;
