-- Work Management — Migration C1a: private idempotency operation ledger.
SET lock_timeout = '5s';
SET statement_timeout = '60s';
CREATE SCHEMA IF NOT EXISTS private;

CREATE TABLE private.work_operation_requests (
  operation_id UUID PRIMARY KEY,
  actor_user_id UUID NOT NULL,
  operation_name VARCHAR(100) NOT NULL,
  request_hash VARCHAR(64) NOT NULL,
  subject_id UUID,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  result_json JSONB,
  error_code VARCHAR(50),
  failure_stage VARCHAR(100),
  error_detail TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT work_operation_requests_status_check
    CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  CONSTRAINT work_operation_requests_name_not_blank
    CHECK (btrim(operation_name) <> ''),
  CONSTRAINT work_operation_requests_hash_shape_check
    CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT work_operation_requests_result_object_check
    CHECK (result_json IS NULL OR jsonb_typeof(result_json) = 'object')
);

CREATE INDEX idx_work_operation_requests_actor_created
  ON private.work_operation_requests(actor_user_id, created_at DESC);
CREATE INDEX idx_work_operation_requests_subject_created
  ON private.work_operation_requests(subject_id, created_at DESC)
  WHERE subject_id IS NOT NULL;
CREATE INDEX idx_work_operation_requests_status_updated
  ON private.work_operation_requests(status, updated_at)
  WHERE status IN ('pending', 'processing');

REVOKE ALL ON TABLE private.work_operation_requests
  FROM PUBLIC, anon, authenticated, service_role;

RESET lock_timeout;
RESET statement_timeout;
