BEGIN;

-- Forward-only repair for visit state-machine triggers invoked from RPCs whose
-- search_path is intentionally restricted to pg_catalog.
DO $repair$
DECLARE
  v_target             RECORD;
  v_oid                OID;
  v_definition         TEXT;
  v_owner              OID;
  v_acl                ACLITEM[];
  v_is_definer         BOOLEAN;
  v_config             TEXT[];
  v_unqualified_count  INTEGER;
  v_qualified_count    INTEGER;
BEGIN
  FOR v_target IN
    SELECT *
    FROM (VALUES
      ('trg_visit_plans_state_machine'::TEXT, 3),
      ('trg_visit_plan_items_state_machine'::TEXT, 1)
    ) AS targets(function_name, expected_count)
  LOOP
    SELECT p.oid, p.proowner, p.proacl, p.prosecdef, p.proconfig
    INTO v_oid, v_owner, v_acl, v_is_definer, v_config
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'private'
      AND p.proname = v_target.function_name
      AND pg_catalog.pg_get_function_identity_arguments(p.oid) = '';

    IF NOT FOUND THEN
      RAISE EXCEPTION 'private.%() was not found', v_target.function_name;
    END IF;

    SELECT
      (
        pg_catalog.length(p.prosrc)
        - pg_catalog.length(pg_catalog.replace(p.prosrc, '(SELECT check_permission(', ''))
      ) / pg_catalog.length('(SELECT check_permission('),
      (
        pg_catalog.length(p.prosrc)
        - pg_catalog.length(pg_catalog.replace(p.prosrc, '(SELECT public.check_permission(', ''))
      ) / pg_catalog.length('(SELECT public.check_permission(')
    INTO v_unqualified_count, v_qualified_count
    FROM pg_catalog.pg_proc p
    WHERE p.oid = v_oid;

    IF v_unqualified_count = 0 THEN
      IF v_qualified_count = v_target.expected_count THEN
        CONTINUE;
      END IF;
      RAISE EXCEPTION 'private.%() has an unexpected permission-call shape', v_target.function_name;
    END IF;

    IF v_unqualified_count <> v_target.expected_count OR v_qualified_count <> 0 THEN
      RAISE EXCEPTION 'private.%() has unexpected permission-call counts: unqualified=%, qualified=%',
        v_target.function_name, v_unqualified_count, v_qualified_count;
    END IF;

    SELECT pg_catalog.pg_get_functiondef(v_oid) INTO v_definition;
    v_definition := pg_catalog.replace(
      v_definition,
      '(SELECT check_permission(',
      '(SELECT public.check_permission('
    );
    EXECUTE v_definition;

    IF EXISTS (
      SELECT 1
      FROM pg_catalog.pg_proc p
      WHERE p.oid = v_oid
        AND (
          p.prosrc LIKE '%(SELECT check_permission(%'
          OR (
            (
              pg_catalog.length(p.prosrc)
              - pg_catalog.length(pg_catalog.replace(p.prosrc, '(SELECT public.check_permission(', ''))
            ) / pg_catalog.length('(SELECT public.check_permission(')
          ) <> v_target.expected_count
          OR p.proowner IS DISTINCT FROM v_owner
          OR p.proacl IS DISTINCT FROM v_acl
          OR p.prosecdef IS DISTINCT FROM v_is_definer
          OR p.proconfig IS DISTINCT FROM v_config
        )
    ) THEN
      RAISE EXCEPTION 'private.%() repair verification failed', v_target.function_name;
    END IF;
  END LOOP;
END;
$repair$;

COMMIT;
