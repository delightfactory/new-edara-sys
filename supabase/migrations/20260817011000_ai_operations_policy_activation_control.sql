-- ============================================================================
-- AI Operations — policy activation control without mutable prompt content.
--
-- Policy text/methodology/hash/version remain immutable for replay. Management
-- of runtime policy availability may toggle only `enabled`; the global Planner
-- and Shadow switches remain separate controls in ai_ops.settings.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '30s';

DROP TRIGGER IF EXISTS trg_ai_ops_planner_policies_immutable ON ai_ops.planner_policies;

CREATE OR REPLACE FUNCTION ai_ops.guard_planner_policy_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION 'AI planner policy versions cannot be deleted';
  END IF;

  IF NEW.policy_version IS DISTINCT FROM OLD.policy_version
     OR NEW.prompt_version IS DISTINCT FROM OLD.prompt_version
     OR NEW.system_prompt IS DISTINCT FROM OLD.system_prompt
     OR NEW.methodology IS DISTINCT FROM OLD.methodology
     OR NEW.prompt_hash IS DISTINCT FROM OLD.prompt_hash
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'AI planner policy content is immutable; create a new prompt version';
  END IF;

  -- Only activation state and its audit timestamp may change in-place.
  NEW.updated_at:=clock_timestamp();
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.guard_planner_policy_mutation()
  FROM PUBLIC,anon,authenticated,service_role;

CREATE TRIGGER trg_ai_ops_planner_policies_guarded
  BEFORE UPDATE OR DELETE ON ai_ops.planner_policies
  FOR EACH ROW EXECUTE FUNCTION ai_ops.guard_planner_policy_mutation();

COMMENT ON FUNCTION ai_ops.guard_planner_policy_mutation() IS
  'Preserves exact versioned policy content for replay while allowing only the enabled activation flag to change in-place.';

RESET lock_timeout;
RESET statement_timeout;
