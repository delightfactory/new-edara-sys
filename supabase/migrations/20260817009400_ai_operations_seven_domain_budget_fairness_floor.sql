-- ============================================================================
-- AI Operations Planner — Seven-Domain Case-Budget Fairness Floor
--
-- DESIGN-TIME MIGRATION ONLY.
-- A deterministic round-robin allocator is only starvation-free for one run
-- when the hard snapshot budget can offer at least one slot to every required
-- domain that has demand. The planner now has seven required domains, while the
-- historical settings constraint still allowed budgets as low as one.
--
-- Keep the existing reviewed nested snapshot builders and global hard cap, but
-- make the seven-domain invariant explicit: the canonical snapshot budget may
-- never be lower than the required-domain count.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

-- Bring any design/test database created before the seventh domain forward
-- before tightening the check constraint.
UPDATE ai_ops.settings
SET max_cases_per_snapshot = GREATEST(
      max_cases_per_snapshot,
      cardinality(ai_ops.required_operational_domains())
    ),
    updated_at = clock_timestamp()
WHERE singleton = true
  AND max_cases_per_snapshot < cardinality(ai_ops.required_operational_domains());

ALTER TABLE ai_ops.settings
  DROP CONSTRAINT ai_ops_settings_case_budget_check;

ALTER TABLE ai_ops.settings
  ADD CONSTRAINT ai_ops_settings_case_budget_check
  CHECK (max_cases_per_snapshot BETWEEN 7 AND 100);

ALTER FUNCTION ai_ops.build_operational_snapshot(UUID,INTEGER)
  RENAME TO build_operational_snapshot_pre_seven_domain_fairness_floor_v1;
REVOKE ALL ON FUNCTION ai_ops.build_operational_snapshot_pre_seven_domain_fairness_floor_v1(UUID,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.build_operational_snapshot(
  p_run_id UUID,
  p_case_limit INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_settings ai_ops.settings%ROWTYPE;
  v_required_domains TEXT[];
  v_required_domain_count INTEGER;
  v_effective_limit INTEGER;
BEGIN
  SELECT * INTO v_settings
  FROM ai_ops.settings
  WHERE singleton=true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI Operations settings are not initialized';
  END IF;

  v_required_domains:=ai_ops.required_operational_domains();
  v_required_domain_count:=cardinality(v_required_domains);

  IF v_required_domain_count IS NULL OR v_required_domain_count<=0 THEN
    RAISE EXCEPTION 'AI Operations required-domain registry is empty';
  END IF;

  IF v_settings.max_cases_per_snapshot<v_required_domain_count THEN
    RAISE EXCEPTION
      'AI Operations case budget % is below required-domain fairness floor %',
      v_settings.max_cases_per_snapshot,v_required_domain_count;
  END IF;

  -- Caller hints may reduce context size, but never below the number of required
  -- domains. The preserved seven-domain builder still owns the actual hard cap,
  -- exact demand calculation, immutable capture markers and round-robin split.
  v_effective_limit:=LEAST(
    v_settings.max_cases_per_snapshot,
    GREATEST(
      COALESCE(p_case_limit,v_settings.max_cases_per_snapshot),
      v_required_domain_count
    )
  );

  RETURN ai_ops.build_operational_snapshot_pre_seven_domain_fairness_floor_v1(
    p_run_id,v_effective_limit
  );
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.build_operational_snapshot(UUID,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON CONSTRAINT ai_ops_settings_case_budget_check ON ai_ops.settings IS
  'Seven-domain planner invariant: the global snapshot case budget reserves capacity for at least one case per required domain before round-robin spill.';
COMMENT ON FUNCTION ai_ops.build_operational_snapshot(UUID,INTEGER) IS
  'Canonical seven-domain snapshot builder with a starvation-safe fairness floor equal to required_operational_domains cardinality; delegates bounded capture to the preserved seven-domain implementation.';

RESET lock_timeout;
RESET statement_timeout;
