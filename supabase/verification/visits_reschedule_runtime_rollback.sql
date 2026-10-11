\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE actor uuid; employee uuid; branch uuid; customer uuid; customer2 uuid; customer3 uuid; customer4 uuid; source_plan uuid:=gen_random_uuid(); source_item uuid:=gen_random_uuid(); target_plan uuid; target_item uuid; op uuid:=gen_random_uuid(); r jsonb; again jsonb; other_item uuid:=gen_random_uuid(); existing_item uuid:=gen_random_uuid(); duplicate_item uuid:=gen_random_uuid();
BEGIN
 SELECT id INTO actor FROM auth.users WHERE email='tester@edara.local';
 IF actor IS NULL THEN RAISE EXCEPTION 'isolated tester missing'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 SELECT id,branch_id INTO employee,branch FROM public.hr_employees ORDER BY id LIMIT 1;
 SELECT id INTO customer FROM public.customers ORDER BY id LIMIT 1; SELECT id INTO customer2 FROM public.customers ORDER BY id OFFSET 1 LIMIT 1; SELECT id INTO customer3 FROM public.customers ORDER BY id OFFSET 2 LIMIT 1; SELECT id INTO customer4 FROM public.customers ORDER BY id OFFSET 3 LIMIT 1;
 INSERT INTO public.visit_plans(id,employee_id,organizational_branch_id,plan_date,status,created_by) VALUES(source_plan,employee,branch,'2095-10-10','draft',actor);
 INSERT INTO public.visit_plan_items(id,plan_id,customer_id,sequence,planned_time,purpose_type) VALUES(source_item,source_plan,customer,1,'09:30','sales'),(other_item,source_plan,customer2,2,'10:00','sales'),(existing_item,source_plan,customer3,3,'11:00','sales'),(duplicate_item,source_plan,customer4,4,'12:00','sales');
 r:=public.confirm_visit_plan_atomic(gen_random_uuid(),source_plan);
 IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'source confirm failed %',r; END IF;
 r:=public.reschedule_visit_item_to_date_atomic(op,source_item,'2095-10-11','اختبار معزول',NULL,now(),'Africa/Cairo');
 IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'reschedule failed %',r; END IF;
 target_plan:=(r#>>'{data,target_plan_id}')::uuid;target_item:=(r#>>'{data,new_item_id}')::uuid;
 IF r#>>'{data,target_plan_status}' != 'draft' OR NOT (r#>>'{data,target_plan_created}')::boolean THEN RAISE EXCEPTION 'draft target metadata incorrect'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.visit_plans WHERE id=target_plan AND plan_date='2095-10-11' AND employee_id=employee AND status='draft') THEN RAISE EXCEPTION 'destination not persisted'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.visit_plan_items WHERE id=target_item AND plan_id=target_plan AND rescheduled_from_item_id=source_item AND planned_time='09:30' AND status='pending') THEN RAISE EXCEPTION 'replacement link/time missing'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.visit_plan_items WHERE id=source_item AND status='rescheduled' AND replacement_item_id=target_item AND reschedule_to='2095-10-11') THEN RAISE EXCEPTION 'source link missing'; END IF;
 again:=public.reschedule_visit_item_to_date_atomic(op,source_item,'2095-10-11','اختبار معزول',NULL,now(),'Africa/Cairo');
 -- client event timestamp must remain identical for idempotent input; now() fixed per transaction.
 IF NOT (again->>'ok')::boolean OR NOT (again->>'replayed')::boolean OR (SELECT count(*) FROM public.visit_plan_items WHERE plan_id=target_plan)<>1 THEN RAISE EXCEPTION 'idempotency failed %',again; END IF;
 INSERT INTO public.visit_plan_items(plan_id,customer_id,sequence) VALUES(target_plan,customer2,2); r:=public.reschedule_visit_item_to_date_atomic(gen_random_uuid(),other_item,'2095-10-11','اختبار تكرار','10:00',now(),'Africa/Cairo');
 IF (r->>'ok')::boolean OR r#>>'{error,code}'<>'TARGET_CUSTOMER_DUPLICATE' THEN RAISE EXCEPTION 'duplicate guard failed %',r; END IF;
 r:=public.reschedule_visit_item_to_date_atomic(gen_random_uuid(),existing_item,'2095-10-12','خطة قائمة','14:00',now(),'Africa/Cairo');
 IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'second destination failed %',r; END IF;
 target_plan:=(r#>>'{data,target_plan_id}')::uuid;
 r:=public.confirm_visit_plan_atomic(gen_random_uuid(),target_plan);
 IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'destination confirmation failed %',r; END IF;
 r:=public.reschedule_visit_item_to_date_atomic(gen_random_uuid(),duplicate_item,'2095-10-12','خطة معتمدة قائمة','15:00',now(),'Africa/Cairo'); IF NOT (r->>'ok')::boolean OR r#>>'{data,target_plan_status}'<>'confirmed' OR (r#>>'{data,target_plan_created}')::boolean OR (r#>>'{data,target_plan_id}')::uuid<>target_plan THEN RAISE EXCEPTION 'existing confirmed target failed %',r; END IF; -- Existing confirmed target, distinct customer to avoid legitimate duplicate guard.
 customer:=customer4;
 -- New source plan item inserted only in draft via a separate synthetic source plan.
 source_plan:=gen_random_uuid();source_item:=gen_random_uuid();
 INSERT INTO public.visit_plans(id,employee_id,organizational_branch_id,plan_date,status,created_by,plan_type) VALUES(source_plan,employee,branch,'2095-10-09','draft',actor,'weekly');
 INSERT INTO public.visit_plan_items(id,plan_id,customer_id,sequence) VALUES(source_item,source_plan,customer,1);
 r:=public.confirm_visit_plan_atomic(gen_random_uuid(),source_plan);
 IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'second source confirm failed %',r; END IF;
 -- Weekly targets must stay weekly: independent creation proves plan-type preservation.
 r:=public.reschedule_visit_item_to_date_atomic(gen_random_uuid(),source_item,'2095-10-13','نوع الخطة',NULL,now(),'Africa/Cairo');
 IF NOT (r->>'ok')::boolean OR NOT EXISTS(SELECT 1 FROM public.visit_plans WHERE id=(r#>>'{data,target_plan_id}')::uuid AND plan_type='weekly') THEN RAISE EXCEPTION 'plan type preservation failed %',r; END IF;
  BEGIN UPDATE public.visit_plans SET notes='must be blocked' WHERE id=source_plan; RAISE EXCEPTION 'closed note mutation unexpectedly allowed'; EXCEPTION WHEN raise_exception THEN IF SQLERRM='closed note mutation unexpectedly allowed' THEN RAISE; END IF; END;
 IF EXISTS(SELECT 1 FROM public.visit_plans WHERE id=source_plan AND notes='must be blocked') THEN RAISE EXCEPTION 'closed note persisted'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.visit_plans WHERE id=source_plan AND status='partial' AND rescheduled_count=1 AND closure_pct=100 AND completion_pct=0) THEN RAISE EXCEPTION 'last visit closure derived totals incorrect'; END IF;
 PERFORM private.recalculate_visit_plan_counts(source_plan);
 RAISE NOTICE 'PASS: real RPC destination/source persistence, linked replacement, date/employee/time/type preservation, draft requires confirmation, replay no duplicate, duplicate guard';
END $$;
ROLLBACK;
SELECT count(*) AS remaining_test_plans FROM public.visit_plans WHERE plan_date BETWEEN '2095-10-09' AND '2095-10-13';
