-- Work Management — final collaboration closure: entity links + realtime publication.
-- Keeps cross-domain links as references only; a Work link never grants entity access.
SET lock_timeout='5s';
SET statement_timeout='60s';

CREATE OR REPLACE FUNCTION private.work_link_entity_table(p_entity_type TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT CASE lower(trim(p_entity_type))
    WHEN 'customer' THEN 'public.customers'
    WHEN 'sales_order' THEN 'public.sales_orders'
    WHEN 'payment_receipt' THEN 'public.payment_receipts'
    WHEN 'supplier' THEN 'public.suppliers'
    WHEN 'purchase_invoice' THEN 'public.purchase_invoices'
    WHEN 'product' THEN 'public.products'
    WHEN 'warehouse' THEN 'public.warehouses'
    WHEN 'employee' THEN 'public.hr_employees'
    WHEN 'activity' THEN 'public.activities'
    WHEN 'target' THEN 'public.targets'
    ELSE NULL
  END;
$$;
REVOKE ALL ON FUNCTION private.work_link_entity_table(TEXT) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.work_link_entity_exists(p_entity_type TEXT,p_entity_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_table TEXT:=private.work_link_entity_table(p_entity_type);
  v_exists BOOLEAN:=false;
BEGIN
  IF v_table IS NULL OR p_entity_id IS NULL THEN RETURN false; END IF;
  IF to_regclass(v_table) IS NULL THEN RETURN false; END IF;
  EXECUTE format('SELECT EXISTS(SELECT 1 FROM %s WHERE id=$1)',v_table) INTO v_exists USING p_entity_id;
  RETURN COALESCE(v_exists,false);
END;
$$;
REVOKE ALL ON FUNCTION private.work_link_entity_exists(TEXT,UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.work_add_link(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_entity_type TEXT,
  p_entity_id UUID,
  p_relation_type TEXT DEFAULT 'relates_to',
  p_label TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_link public.work_links%ROWTYPE;
  v_entity_type TEXT:=lower(trim(p_entity_type));
  v_relation_type TEXT:=lower(trim(COALESCE(p_relation_type,'relates_to')));
  v_label TEXT:=NULLIF(trim(p_label),'');
  v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_add_link',
    jsonb_build_object('work_item_id',p_work_item_id,'expected_version',p_expected_version,'entity_type',v_entity_type,'entity_id',p_entity_id,'relation_type',v_relation_type,'label',v_label),
    p_work_item_id
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_add_link','NOT_FOUND','المهمة غير موجودة',p_work_item_id); END IF;
  IF v_item.state_version<>p_expected_version THEN RETURN private.work_command_error(p_operation_id,'work_add_link','VERSION_CONFLICT','تم تعديل المهمة بواسطة مستخدم آخر',p_work_item_id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor,p_work_item_id) THEN RETURN private.work_command_error(p_operation_id,'work_add_link','FORBIDDEN','غير مصرح بإدارة روابط هذه المهمة',p_work_item_id); END IF;
  IF v_item.status IN ('done','cancelled') THEN RETURN private.work_command_error(p_operation_id,'work_add_link','TERMINAL_ITEM','لا يمكن تعديل الروابط بعد إغلاق المهمة',p_work_item_id); END IF;
  IF private.work_link_entity_table(v_entity_type) IS NULL THEN RETURN private.work_command_error(p_operation_id,'work_add_link','UNSUPPORTED_ENTITY_TYPE','نوع الكيان غير مدعوم',p_work_item_id); END IF;
  IF NOT private.work_link_entity_exists(v_entity_type,p_entity_id) THEN RETURN private.work_command_error(p_operation_id,'work_add_link','ENTITY_NOT_FOUND','الكيان المرتبط غير موجود',p_work_item_id); END IF;
  IF v_relation_type !~ '^[a-z][a-z0-9_]{0,62}$' THEN RETURN private.work_command_error(p_operation_id,'work_add_link','INVALID_RELATION_TYPE','نوع العلاقة غير صالح',p_work_item_id); END IF;
  IF length(COALESCE(v_label,''))>250 THEN RETURN private.work_command_error(p_operation_id,'work_add_link','LABEL_TOO_LONG','وصف الرابط أطول من المسموح',p_work_item_id); END IF;
  IF EXISTS(SELECT 1 FROM public.work_links WHERE work_item_id=p_work_item_id AND entity_type=v_entity_type AND entity_id=p_entity_id AND relation_type=v_relation_type) THEN
    RETURN private.work_command_error(p_operation_id,'work_add_link','ALREADY_LINKED','هذا الكيان مرتبط بالمهمة بالفعل',p_work_item_id);
  END IF;

  INSERT INTO public.work_links(work_item_id,entity_type,entity_id,relation_type,label,created_by_user_id)
  VALUES(p_work_item_id,v_entity_type,p_entity_id,v_relation_type,v_label,v_actor)
  RETURNING * INTO v_link;
  UPDATE public.work_items SET state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
  WHERE id=p_work_item_id RETURNING * INTO v_item;
  PERFORM private.work_append_user_event(p_work_item_id,'work.link_added',v_actor,p_operation_id,v_item.status,v_item.status,
    jsonb_build_object('link_id',v_link.id,'entity_type',v_entity_type,'entity_id',p_entity_id,'relation_type',v_relation_type,'label',v_label));
  v_result:=jsonb_build_object('work_item_id',p_work_item_id,'link_id',v_link.id,'status',v_item.status,'state_version',v_item.state_version);
  RETURN private.work_command_success(p_operation_id,'work_add_link',p_work_item_id,v_result);
END;
$$;

CREATE OR REPLACE FUNCTION public.work_remove_link(
  p_operation_id UUID,
  p_link_id UUID,
  p_expected_version BIGINT,
  p_reason TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_link public.work_links%ROWTYPE;
  v_result JSONB;
BEGIN
  SELECT * INTO v_link FROM public.work_links WHERE id=p_link_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'operation_id',p_operation_id,'operation','work_remove_link','replayed',false,'error',jsonb_build_object('code','NOT_FOUND','message','الرابط غير موجود')); END IF;
  v_prepare:=private.work_prepare_operation(p_operation_id,v_actor,'work_remove_link',jsonb_build_object('link_id',p_link_id,'expected_version',p_expected_version,'reason',p_reason),v_link.work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id=v_link.work_item_id FOR UPDATE;
  SELECT * INTO v_link FROM public.work_links WHERE id=p_link_id FOR UPDATE;
  IF v_item.state_version<>p_expected_version THEN RETURN private.work_command_error(p_operation_id,'work_remove_link','VERSION_CONFLICT','تم تعديل المهمة بواسطة مستخدم آخر',v_item.id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor,v_item.id) THEN RETURN private.work_command_error(p_operation_id,'work_remove_link','FORBIDDEN','غير مصرح بإدارة روابط هذه المهمة',v_item.id); END IF;
  IF v_item.status IN ('done','cancelled') THEN RETURN private.work_command_error(p_operation_id,'work_remove_link','TERMINAL_ITEM','لا يمكن تعديل الروابط بعد إغلاق المهمة',v_item.id); END IF;

  DELETE FROM public.work_links WHERE id=p_link_id;
  UPDATE public.work_items SET state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
  WHERE id=v_item.id RETURNING * INTO v_item;
  PERFORM private.work_append_user_event(v_item.id,'work.link_removed',v_actor,p_operation_id,v_item.status,v_item.status,
    jsonb_build_object('link_id',p_link_id,'entity_type',v_link.entity_type,'entity_id',v_link.entity_id,'relation_type',v_link.relation_type,'reason',p_reason));
  v_result:=jsonb_build_object('work_item_id',v_item.id,'link_id',p_link_id,'status',v_item.status,'state_version',v_item.state_version);
  RETURN private.work_command_success(p_operation_id,'work_remove_link',v_item.id,v_result);
END;
$$;

REVOKE ALL ON FUNCTION public.work_add_link(UUID,UUID,BIGINT,TEXT,UUID,TEXT,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_remove_link(UUID,UUID,BIGINT,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.work_add_link(UUID,UUID,BIGINT,TEXT,UUID,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_remove_link(UUID,UUID,BIGINT,TEXT) TO authenticated;

-- Realtime is additive and RLS remains authoritative. Add only user-facing runtime tables.
DO $$
DECLARE v_table TEXT;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['work_items','work_events','work_comments','work_checklist_items','work_attachments','work_links','work_dependencies'] LOOP
    IF NOT EXISTS(
      SELECT 1 FROM pg_publication_tables
      WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename=v_table
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I',v_table);
    END IF;
  END LOOP;
END;
$$;

RESET lock_timeout;
RESET statement_timeout;
