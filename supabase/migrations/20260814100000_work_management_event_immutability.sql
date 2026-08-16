-- Work Management — append-only timeline enforcement.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION private.work_reject_event_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'work_events is append-only';
END;
$$;

DROP TRIGGER IF EXISTS trg_work_events_immutable ON public.work_events;
CREATE TRIGGER trg_work_events_immutable
  BEFORE UPDATE OR DELETE ON public.work_events
  FOR EACH ROW EXECUTE FUNCTION private.work_reject_event_mutation();

REVOKE ALL ON FUNCTION private.work_reject_event_mutation()
  FROM PUBLIC, anon, authenticated, service_role;

RESET lock_timeout;
RESET statement_timeout;
