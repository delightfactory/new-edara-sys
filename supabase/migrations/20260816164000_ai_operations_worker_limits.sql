-- ============================================================================
-- AI Operations Planner — Worker Resource Limits
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply until explicitly reviewed/approved.
-- Depends on: 20260816163504_ai_operations_foundation.sql
--
-- Adds only planner-local safety configuration. No operational schema touched.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '30s';

ALTER TABLE ai_ops.settings
  ADD COLUMN max_worker_context_bytes INTEGER NOT NULL DEFAULT 65536;

ALTER TABLE ai_ops.settings
  ADD CONSTRAINT ai_ops_settings_worker_context_bytes_range
  CHECK (max_worker_context_bytes BETWEEN 16384 AND 262144);

COMMENT ON COLUMN ai_ops.settings.max_worker_context_bytes IS
  'Hard serialized JSON budget for one reasoning context. Worker context fails closed instead of silently omitting frozen case evidence.';

RESET lock_timeout;
RESET statement_timeout;
