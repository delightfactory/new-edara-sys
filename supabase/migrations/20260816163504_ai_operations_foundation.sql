-- ============================================================================
-- AI Operations Planner — Foundation
--
-- Additive, isolated and disabled by default.
-- This migration MUST NOT change current operational behaviour.
--
-- Creates planner-local state only:
--   * settings / schedules
--   * durable planner runs
--   * immutable bounded snapshots
--   * persistent attention cases
--   * staged decisions
--   * governed operational context
--   * structured human feedback
--
-- Explicitly NOT included:
--   * no pg_cron jobs
--   * no ChatGPT/worker integration
--   * no source-table triggers
--   * no source-table indexes
--   * no Work/Sales/Customer/Inventory/HR schema changes
--   * no browser grants
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE SCHEMA ai_ops;

REVOKE ALL ON SCHEMA ai_ops FROM PUBLIC;
REVOKE ALL ON SCHEMA ai_ops FROM anon;
REVOKE ALL ON SCHEMA ai_ops FROM authenticated;

-- Keep future objects in this schema closed by default for the migration owner.
ALTER DEFAULT PRIVILEGES IN SCHEMA ai_ops REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA ai_ops REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA ai_ops REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- --------------------------------------------------------------------------
-- Safe global planner controls.
-- --------------------------------------------------------------------------
CREATE TABLE ai_ops.settings (
  singleton BOOLEAN PRIMARY KEY DEFAULT true,
  planner_enabled BOOLEAN NOT NULL DEFAULT false,
  shadow_mode BOOLEAN NOT NULL DEFAULT true,
  auto_commit_enabled BOOLEAN NOT NULL DEFAULT false,
  max_cases_per_snapshot INTEGER NOT NULL DEFAULT 30,
  max_actions_per_run INTEGER NOT NULL DEFAULT 3,
  planner_policy_version TEXT NOT NULL DEFAULT 'v1',
  tool_contract_version TEXT NOT NULL DEFAULT 'v1',
  state_version BIGINT NOT NULL DEFAULT 1,
  updated_by_user_id UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT ai_ops_settings_singleton_check CHECK (singleton),
  CONSTRAINT ai_ops_settings_case_budget_check
    CHECK (max_cases_per_snapshot BETWEEN 1 AND 100),
  CONSTRAINT ai_ops_settings_action_budget_check
    CHECK (max_actions_per_run BETWEEN 0 AND 20),
  CONSTRAINT ai_ops_settings_policy_version_not_blank
    CHECK (btrim(planner_policy_version) <> ''),
  CONSTRAINT ai_ops_settings_tool_version_not_blank
    CHECK (btrim(tool_contract_version) <> ''),
  CONSTRAINT ai_ops_settings_state_version_positive
    CHECK (state_version > 0),
  CONSTRAINT ai_ops_settings_auto_commit_safe_state
    CHECK (
      NOT auto_commit_enabled
      OR (planner_enabled = true AND shadow_mode = false)
    )
);

INSERT INTO ai_ops.settings(singleton) VALUES (true);

COMMENT ON TABLE ai_ops.settings IS
  'AI Operations global safety controls. Foundation defaults are disabled/shadow/no-auto-commit.';

-- --------------------------------------------------------------------------
-- Declarative run schedules. No scheduler/cron is installed by this migration.
-- --------------------------------------------------------------------------
CREATE TABLE ai_ops.run_schedules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(80) NOT NULL UNIQUE,
  run_type VARCHAR(80) NOT NULL,
  timezone TEXT NOT NULL DEFAULT 'Africa/Cairo',
  local_time TIME NOT NULL,
  weekdays SMALLINT[] NOT NULL,
  recovery_window_minutes INTEGER NOT NULL DEFAULT 180,
  enabled BOOLEAN NOT NULL DEFAULT false,
  settings JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_by_user_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT ai_ops_run_schedules_code_format
    CHECK (code ~ '^[a-z][a-z0-9_]{0,78}$'),
  CONSTRAINT ai_ops_run_schedules_type_format
    CHECK (run_type ~ '^[a-z][a-z0-9_]{0,78}$'),
  CONSTRAINT ai_ops_run_schedules_weekdays_nonempty
    CHECK (cardinality(weekdays) BETWEEN 1 AND 7),
  CONSTRAINT ai_ops_run_schedules_weekdays_range
    CHECK (weekdays <@ ARRAY[0,1,2,3,4,5,6]::SMALLINT[]),
  CONSTRAINT ai_ops_run_schedules_recovery_window
    CHECK (recovery_window_minutes BETWEEN 15 AND 10080),
  CONSTRAINT ai_ops_run_schedules_settings_object
    CHECK (jsonb_typeof(settings) = 'object')
);

COMMENT ON TABLE ai_ops.run_schedules IS
  'Planner schedule definitions only. Expected-run generation is added in a later reliability migration.';

-- --------------------------------------------------------------------------
-- Durable execution ledger. This is the authority for whether a planning run
-- existed/completed; an external AI worker is only a claimant/processor.
-- --------------------------------------------------------------------------
CREATE TABLE ai_ops.planner_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_key TEXT NOT NULL UNIQUE,
  schedule_id UUID REFERENCES ai_ops.run_schedules(id) ON DELETE SET NULL,
  run_type VARCHAR(80) NOT NULL,
  business_date DATE NOT NULL,
  scheduled_for TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  attempt_no INTEGER NOT NULL DEFAULT 0,
  claimed_by TEXT,
  lease_expires_at TIMESTAMPTZ,
  heartbeat_at TIMESTAMPTZ,
  checkpoint TEXT NOT NULL DEFAULT 'created',
  planner_policy_version TEXT NOT NULL,
  tool_contract_version TEXT NOT NULL,
  prompt_hash TEXT,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  cases_seen INTEGER NOT NULL DEFAULT 0,
  cases_investigated INTEGER NOT NULL DEFAULT 0,
  decisions_count INTEGER NOT NULL DEFAULT 0,
  work_created_count INTEGER NOT NULL DEFAULT 0,
  error_class TEXT,
  error_message TEXT,
  result_summary JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT ai_ops_planner_runs_key_not_blank CHECK (btrim(run_key) <> ''),
  CONSTRAINT ai_ops_planner_runs_type_format
    CHECK (run_type ~ '^[a-z][a-z0-9_]{0,78}$'),
  CONSTRAINT ai_ops_planner_runs_status_check CHECK (
    status IN (
      'pending','claimed','reasoning','staged','committing',
      'completed','partial','failed','abandoned'
    )
  ),
  CONSTRAINT ai_ops_planner_runs_attempt_nonnegative CHECK (attempt_no >= 0),
  CONSTRAINT ai_ops_planner_runs_counts_nonnegative CHECK (
    cases_seen >= 0
    AND cases_investigated >= 0
    AND decisions_count >= 0
    AND work_created_count >= 0
  ),
  CONSTRAINT ai_ops_planner_runs_result_object
    CHECK (jsonb_typeof(result_summary) = 'object'),
  CONSTRAINT ai_ops_planner_runs_completion_order CHECK (
    completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at
  )
);

CREATE INDEX idx_ai_ops_runs_due
  ON ai_ops.planner_runs(status, scheduled_for)
  WHERE status IN ('pending','claimed','reasoning','staged','committing');

CREATE INDEX idx_ai_ops_runs_business_date
  ON ai_ops.planner_runs(business_date DESC, scheduled_for DESC);

COMMENT ON TABLE ai_ops.planner_runs IS
  'Durable planner execution ledger with leases/checkpoints for retry and recovery.';

-- --------------------------------------------------------------------------
-- Immutable bounded input presented to a planner run.
-- --------------------------------------------------------------------------
CREATE TABLE ai_ops.snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id UUID NOT NULL UNIQUE
    REFERENCES ai_ops.planner_runs(id) ON DELETE RESTRICT,
  payload_version TEXT NOT NULL,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  data_as_of TIMESTAMPTZ NOT NULL,
  snapshot_status TEXT NOT NULL DEFAULT 'ready',
  trust JSONB NOT NULL DEFAULT '{}'::JSONB,
  company_pulse JSONB NOT NULL DEFAULT '{}'::JSONB,
  coverage JSONB NOT NULL DEFAULT '{}'::JSONB,
  payload JSONB NOT NULL DEFAULT '{}'::JSONB,
  payload_bytes INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT ai_ops_snapshots_payload_version_not_blank
    CHECK (btrim(payload_version) <> ''),
  CONSTRAINT ai_ops_snapshots_status_check
    CHECK (snapshot_status IN ('ready','partial','blocked')),
  CONSTRAINT ai_ops_snapshots_json_objects CHECK (
    jsonb_typeof(trust) = 'object'
    AND jsonb_typeof(company_pulse) = 'object'
    AND jsonb_typeof(coverage) = 'object'
    AND jsonb_typeof(payload) = 'object'
  ),
  CONSTRAINT ai_ops_snapshots_payload_bytes_nonnegative
    CHECK (payload_bytes IS NULL OR payload_bytes >= 0)
);

CREATE INDEX idx_ai_ops_snapshots_generated
  ON ai_ops.snapshots(generated_at DESC);

COMMENT ON TABLE ai_ops.snapshots IS
  'Immutable bounded evidence presented to an AI planner run; never a raw operational dump.';

-- --------------------------------------------------------------------------
-- Persistent attention cases. A stable case_key survives across planner runs.
-- Business entity references are intentionally soft typed references.
-- --------------------------------------------------------------------------
CREATE TABLE ai_ops.cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_key TEXT NOT NULL UNIQUE,
  first_snapshot_id UUID NOT NULL
    REFERENCES ai_ops.snapshots(id) ON DELETE RESTRICT,
  last_snapshot_id UUID NOT NULL
    REFERENCES ai_ops.snapshots(id) ON DELETE RESTRICT,
  domain VARCHAR(80) NOT NULL,
  case_type VARCHAR(100) NOT NULL,
  entity_type VARCHAR(80),
  entity_id UUID,
  attention_class TEXT NOT NULL DEFAULT 'exception',
  severity TEXT NOT NULL DEFAULT 'medium',
  first_seen_at TIMESTAMPTZ NOT NULL,
  last_seen_at TIMESTAMPTZ NOT NULL,
  source_as_of TIMESTAMPTZ NOT NULL,
  facts JSONB NOT NULL DEFAULT '{}'::JSONB,
  responsibility_evidence JSONB NOT NULL DEFAULT '{}'::JSONB,
  trust JSONB NOT NULL DEFAULT '{}'::JSONB,
  status TEXT NOT NULL DEFAULT 'open',
  suppressed_until TIMESTAMPTZ,
  resolved_at TIMESTAMPTZ,
  state_version BIGINT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT ai_ops_cases_key_not_blank CHECK (btrim(case_key) <> ''),
  CONSTRAINT ai_ops_cases_domain_format
    CHECK (domain ~ '^[a-z][a-z0-9_]{0,78}$'),
  CONSTRAINT ai_ops_cases_type_format
    CHECK (case_type ~ '^[a-z][a-z0-9_]{0,98}$'),
  CONSTRAINT ai_ops_cases_entity_pair CHECK (
    (entity_type IS NULL AND entity_id IS NULL)
    OR (entity_type IS NOT NULL AND entity_id IS NOT NULL)
  ),
  CONSTRAINT ai_ops_cases_attention_class_check
    CHECK (attention_class IN ('exception','opportunity','integrity','continuity')),
  CONSTRAINT ai_ops_cases_severity_check
    CHECK (severity IN ('low','medium','high','critical')),
  CONSTRAINT ai_ops_cases_status_check
    CHECK (status IN ('open','monitored','actioned','resolved','suppressed','expired')),
  CONSTRAINT ai_ops_cases_seen_order CHECK (last_seen_at >= first_seen_at),
  CONSTRAINT ai_ops_cases_json_objects CHECK (
    jsonb_typeof(facts) = 'object'
    AND jsonb_typeof(responsibility_evidence) = 'object'
    AND jsonb_typeof(trust) = 'object'
  ),
  CONSTRAINT ai_ops_cases_state_version_positive CHECK (state_version > 0)
);

CREATE INDEX idx_ai_ops_cases_attention
  ON ai_ops.cases(status, severity, domain, last_seen_at DESC);

CREATE INDEX idx_ai_ops_cases_entity
  ON ai_ops.cases(entity_type, entity_id, status)
  WHERE entity_id IS NOT NULL;

COMMENT ON TABLE ai_ops.cases IS
  'Persistent material attention candidates. A case is not a task and may correctly end in no action.';

-- --------------------------------------------------------------------------
-- Planner dispositions. Store concise rationale/evidence, never hidden chain
-- of thought. Operational Work reference remains soft to preserve isolation.
-- --------------------------------------------------------------------------
CREATE TABLE ai_ops.decisions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id UUID NOT NULL REFERENCES ai_ops.planner_runs(id) ON DELETE RESTRICT,
  case_id UUID NOT NULL REFERENCES ai_ops.cases(id) ON DELETE RESTRICT,
  revision INTEGER NOT NULL DEFAULT 1,
  decision_type TEXT NOT NULL,
  business_impact TEXT,
  urgency TEXT,
  confidence NUMERIC(5,4),
  evidence_completeness NUMERIC(5,4),
  reversibility TEXT,
  estimated_effort TEXT,
  recommended_owner_user_id UUID,
  recommended_assignee_user_id UUID,
  responsibility_basis JSONB NOT NULL DEFAULT '{}'::JSONB,
  concise_rationale TEXT NOT NULL,
  expected_outcome TEXT,
  success_signal JSONB NOT NULL DEFAULT '{}'::JSONB,
  review_after TIMESTAMPTZ,
  validation_status TEXT NOT NULL DEFAULT 'pending',
  validation_detail JSONB NOT NULL DEFAULT '{}'::JSONB,
  commit_status TEXT NOT NULL DEFAULT 'not_requested',
  work_item_id UUID,
  idempotency_key TEXT,
  management_only_metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
  employee_safe_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT ai_ops_decisions_revision_positive CHECK (revision > 0),
  CONSTRAINT ai_ops_decisions_type_check CHECK (
    decision_type IN ('IGNORE','MONITOR','INVESTIGATE','INFORM','CREATE_WORK','ESCALATE')
  ),
  CONSTRAINT ai_ops_decisions_confidence_range CHECK (
    confidence IS NULL OR confidence BETWEEN 0 AND 1
  ),
  CONSTRAINT ai_ops_decisions_evidence_range CHECK (
    evidence_completeness IS NULL OR evidence_completeness BETWEEN 0 AND 1
  ),
  CONSTRAINT ai_ops_decisions_rationale_not_blank
    CHECK (btrim(concise_rationale) <> ''),
  CONSTRAINT ai_ops_decisions_validation_check CHECK (
    validation_status IN ('pending','valid','rejected','stale','conflict')
  ),
  CONSTRAINT ai_ops_decisions_commit_check CHECK (
    commit_status IN ('not_requested','staged','committed','rejected','failed','skipped')
  ),
  CONSTRAINT ai_ops_decisions_json_objects CHECK (
    jsonb_typeof(responsibility_basis) = 'object'
    AND jsonb_typeof(success_signal) = 'object'
    AND jsonb_typeof(validation_detail) = 'object'
    AND jsonb_typeof(management_only_metadata) = 'object'
  ),
  CONSTRAINT ai_ops_decisions_run_case_revision_uniq
    UNIQUE (run_id, case_id, revision),
  CONSTRAINT ai_ops_decisions_idempotency_uniq UNIQUE (idempotency_key)
);

CREATE INDEX idx_ai_ops_decisions_run
  ON ai_ops.decisions(run_id, created_at);

CREATE INDEX idx_ai_ops_decisions_case
  ON ai_ops.decisions(case_id, created_at DESC);

CREATE INDEX idx_ai_ops_decisions_validation_commit
  ON ai_ops.decisions(validation_status, commit_status, decision_type);

COMMENT ON TABLE ai_ops.decisions IS
  'Explainable planner dispositions and validation/commit state; no hidden chain-of-thought is persisted.';

-- --------------------------------------------------------------------------
-- Structured human/system context that transactional records cannot express.
-- --------------------------------------------------------------------------
CREATE TABLE ai_ops.operational_context (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_type VARCHAR(80) NOT NULL,
  subject_id UUID NOT NULL,
  context_type VARCHAR(100) NOT NULL,
  context_payload JSONB NOT NULL DEFAULT '{}'::JSONB,
  owner_user_id UUID,
  source_type TEXT NOT NULL DEFAULT 'human',
  confidence_class TEXT NOT NULL DEFAULT 'explicit_human',
  lifecycle_type TEXT NOT NULL DEFAULT 'valid_until',
  valid_from TIMESTAMPTZ NOT NULL DEFAULT now(),
  valid_until TIMESTAMPTZ,
  review_on DATE,
  status TEXT NOT NULL DEFAULT 'active',
  visibility TEXT NOT NULL DEFAULT 'management',
  created_by_user_id UUID,
  approved_by_user_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT ai_ops_context_subject_type_format
    CHECK (subject_type ~ '^[a-z][a-z0-9_]{0,78}$'),
  CONSTRAINT ai_ops_context_type_format
    CHECK (context_type ~ '^[a-z][a-z0-9_]{0,98}$'),
  CONSTRAINT ai_ops_context_payload_object
    CHECK (jsonb_typeof(context_payload) = 'object'),
  CONSTRAINT ai_ops_context_source_check
    CHECK (source_type IN ('human','system','ai_proposed')),
  CONSTRAINT ai_ops_context_confidence_check CHECK (
    confidence_class IN (
      'hard_policy','approved_human','explicit_human',
      'system_record','system_inference','ai_inference'
    )
  ),
  CONSTRAINT ai_ops_context_lifecycle_check
    CHECK (lifecycle_type IN ('permanent','valid_until','review_on','one_time')),
  CONSTRAINT ai_ops_context_status_check
    CHECK (status IN ('active','expired','revoked','consumed')),
  CONSTRAINT ai_ops_context_visibility_check
    CHECK (visibility IN ('management','restricted','standard')),
  CONSTRAINT ai_ops_context_valid_until_required CHECK (
    lifecycle_type <> 'valid_until' OR valid_until IS NOT NULL
  ),
  CONSTRAINT ai_ops_context_review_on_required CHECK (
    lifecycle_type <> 'review_on' OR review_on IS NOT NULL
  ),
  CONSTRAINT ai_ops_context_validity_order CHECK (
    valid_until IS NULL OR valid_until > valid_from
  )
);

CREATE INDEX idx_ai_ops_context_subject_active
  ON ai_ops.operational_context(subject_type, subject_id, status, valid_until);

CREATE INDEX idx_ai_ops_context_review
  ON ai_ops.operational_context(status, review_on)
  WHERE review_on IS NOT NULL;

COMMENT ON TABLE ai_ops.operational_context IS
  'Governed non-transactional business context with explicit ownership, confidence and expiry/review semantics.';

-- --------------------------------------------------------------------------
-- Human review feedback; explicitly not an employee-performance record.
-- --------------------------------------------------------------------------
CREATE TABLE ai_ops.decision_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  decision_id UUID NOT NULL REFERENCES ai_ops.decisions(id) ON DELETE RESTRICT,
  feedback_reason TEXT NOT NULL,
  feedback_note TEXT,
  actor_user_id UUID,
  metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT ai_ops_feedback_reason_check CHECK (
    feedback_reason IN (
      'accepted','already_handled','wrong_owner','wrong_timing','missing_context',
      'not_actionable','lower_value_than_other_work','superseded_by_human_decision',
      'data_incorrect','other'
    )
  ),
  CONSTRAINT ai_ops_feedback_metadata_object
    CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE INDEX idx_ai_ops_feedback_decision
  ON ai_ops.decision_feedback(decision_id, created_at DESC);

COMMENT ON TABLE ai_ops.decision_feedback IS
  'Structured planner-quality feedback; never a hidden employee score or disciplinary record.';

-- --------------------------------------------------------------------------
-- Snapshot immutability. This is planner-local and has no source-table effect.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ai_ops.reject_snapshot_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'ai_ops snapshots are immutable';
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.reject_snapshot_mutation() FROM PUBLIC;
REVOKE ALL ON FUNCTION ai_ops.reject_snapshot_mutation() FROM anon;
REVOKE ALL ON FUNCTION ai_ops.reject_snapshot_mutation() FROM authenticated;

CREATE TRIGGER trg_ai_ops_snapshots_immutable
  BEFORE UPDATE OR DELETE ON ai_ops.snapshots
  FOR EACH ROW EXECUTE FUNCTION ai_ops.reject_snapshot_mutation();

-- --------------------------------------------------------------------------
-- Defense in depth. The schema is not intended for direct browser access.
-- No policies are installed in foundation; future UI uses permission-gated
-- public RPCs rather than direct table mutation.
-- --------------------------------------------------------------------------
ALTER TABLE ai_ops.settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_ops.run_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_ops.planner_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_ops.snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_ops.cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_ops.decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_ops.operational_context ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_ops.decision_feedback ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON ALL TABLES IN SCHEMA ai_ops FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA ai_ops FROM anon;
REVOKE ALL ON ALL TABLES IN SCHEMA ai_ops FROM authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA ai_ops FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA ai_ops FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA ai_ops FROM authenticated;

RESET lock_timeout;
RESET statement_timeout;
