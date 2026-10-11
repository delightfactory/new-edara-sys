-- Isolated restored database only; runs real RPC/domain guards as postgres with synthetic claims.
-- This is not an RLS qualification. Every fixture and temporary employee link rolls back.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  actor uuid; employee uuid; branch uuid; customer uuid; customer2 uuid;
  plan uuid := gen_random_uuid(); item uuid := gen_random_uuid(); item2 uuid := gen_random_uuid();
  op uuid := gen_random_uuid(); result jsonb; replay jsonb;
BEGIN
  SELECT id INTO actor FROM auth.users WHERE email = 'tester@edara.local';
  IF actor IS NULL THEN RAISE EXCEPTION 'isolated tester missing'; END IF;
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', actor, 'role', 'authenticated')::text, true);
  SELECT e.id, e.branch_id INTO employee, branch FROM public.hr_employees e
  WHERE e.status = 'active' AND NOT EXISTS (
    SELECT 1 FROM public.visit_plans p JOIN public.visit_plan_items i ON i.plan_id = p.id
    WHERE p.employee_id = e.id AND i.status = 'in_progress'
  ) ORDER BY e.id LIMIT 1;
  IF employee IS NULL THEN RAISE EXCEPTION 'isolated fixture requires an employee without an open visit'; END IF;
  UPDATE public.hr_employees SET user_id = actor WHERE id = employee;
  SELECT id INTO customer FROM public.customers ORDER BY id LIMIT 1;
  SELECT id INTO customer2 FROM public.customers ORDER BY id OFFSET 1 LIMIT 1;
  INSERT INTO public.visit_plans(id, employee_id, organizational_branch_id, plan_date, status, created_by)
  VALUES(plan, employee, branch, '2095-11-20', 'draft', actor);
  INSERT INTO public.visit_plan_items(id, plan_id, customer_id, sequence)
  VALUES(item, plan, customer, 1), (item2, plan, customer2, 2);
  result := public.confirm_visit_plan_atomic(gen_random_uuid(), plan);
  IF NOT (result->>'ok')::boolean THEN RAISE EXCEPTION 'confirmation failed %', result; END IF;
  result := public.start_visit_item_atomic(op, item, NULL, NULL, NULL, now(), 'Africa/Cairo');
  IF NOT (result->>'ok')::boolean THEN RAISE EXCEPTION 'start failed %', result; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.visit_plan_items WHERE id=item AND status='in_progress' AND server_started_at IS NOT NULL AND gps_validation_status='no_coordinates')
  THEN RAISE EXCEPTION 'start not persisted with current missing-location policy'; END IF;
  replay := public.start_visit_item_atomic(op, item, NULL, NULL, NULL, now(), 'Africa/Cairo');
  IF NOT (replay->>'ok')::boolean OR NOT (replay->>'replayed')::boolean THEN RAISE EXCEPTION 'start replay failed %', replay; END IF;
  result := public.start_visit_item_atomic(gen_random_uuid(), item2, NULL, NULL, NULL, now(), 'Africa/Cairo');
  IF (result->>'ok')::boolean THEN RAISE EXCEPTION 'second simultaneous visit allowed'; END IF;
  IF (SELECT count(*) FROM public.visit_plan_items WHERE plan_id=plan AND status='in_progress') <> 1
  THEN RAISE EXCEPTION 'more than one active visit'; END IF;
  RAISE NOTICE 'PASS: start persisted, missing-location policy retained, replay idempotent, second active visit refused';
END $$;
ROLLBACK;
