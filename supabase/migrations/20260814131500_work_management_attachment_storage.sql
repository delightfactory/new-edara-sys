-- Work Management — private attachment bucket, path-bound Storage RLS and metadata removal.
SET lock_timeout='5s';
SET statement_timeout='60s';

-- Bucket is deliberately private. The Storage API owns object lifecycle; SQL only
-- defines bucket configuration and RLS policies.
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES(
  'work-attachments','work-attachments',false,26214400,
  ARRAY[
    'image/jpeg','image/png','image/webp','application/pdf','text/plain','text/csv',
    'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  ]::TEXT[]
)
ON CONFLICT(id) DO UPDATE SET
  name=EXCLUDED.name,
  public=false,
  file_size_limit=EXCLUDED.file_size_limit,
  allowed_mime_types=EXCLUDED.allowed_mime_types;

-- Parse only the canonical path work/{work_item_uuid}/... and fail closed.
CREATE OR REPLACE FUNCTION private.work_storage_item_id(p_name TEXT)
RETURNS UUID
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_folders TEXT[];
  v_id UUID;
BEGIN
  IF p_name IS NULL OR p_name='' THEN RETURN NULL; END IF;
  v_folders:=storage.foldername(p_name);
  IF cardinality(v_folders)<2 OR v_folders[1]<>'work' THEN RETURN NULL; END IF;
  BEGIN
    v_id:=v_folders[2]::UUID;
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION private.work_storage_item_id(TEXT)
  FROM PUBLIC,anon,authenticated,service_role;

-- Current-user wrapper only. It does not accept an arbitrary user id and therefore
-- cannot be abused as a permission oracle from the client.
CREATE OR REPLACE FUNCTION private.work_current_user_can_attach_item(p_work_item_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT p_work_item_id IS NOT NULL
    AND private.work_actor_is_active(auth.uid())
    AND (
      private.work_actor_can_update_item(auth.uid(),p_work_item_id)
      OR private.work_actor_can_comment_item(auth.uid(),p_work_item_id)
    );
$$;
REVOKE ALL ON FUNCTION private.work_current_user_can_attach_item(UUID)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private.work_current_user_can_attach_item(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION private.work_storage_item_id(TEXT) TO authenticated;

DROP POLICY IF EXISTS work_attachments_storage_select ON storage.objects;
CREATE POLICY work_attachments_storage_select
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id='work-attachments'
  AND private.work_storage_item_id(name) IS NOT NULL
  AND private.work_current_user_can_view_item(private.work_storage_item_id(name))
  AND EXISTS (
    SELECT 1
    FROM public.work_attachments a
    WHERE a.storage_bucket='work-attachments'
      AND a.storage_path=name
      AND a.work_item_id=private.work_storage_item_id(name)
      AND a.removed_at IS NULL
  )
);

DROP POLICY IF EXISTS work_attachments_storage_insert ON storage.objects;
CREATE POLICY work_attachments_storage_insert
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id='work-attachments'
  AND private.work_storage_item_id(name) IS NOT NULL
  AND private.work_current_user_can_attach_item(private.work_storage_item_id(name))
);

-- Upsert/replacement is limited to the original uploader and to an active metadata
-- row. Managers/collaborators may add new files but cannot silently overwrite
-- somebody else's object.
DROP POLICY IF EXISTS work_attachments_storage_update ON storage.objects;
CREATE POLICY work_attachments_storage_update
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id='work-attachments'
  AND owner_id=(select auth.uid())::TEXT
  AND private.work_storage_item_id(name) IS NOT NULL
  AND private.work_current_user_can_attach_item(private.work_storage_item_id(name))
  AND EXISTS (
    SELECT 1 FROM public.work_attachments a
    WHERE a.storage_bucket='work-attachments' AND a.storage_path=name AND a.removed_at IS NULL
  )
)
WITH CHECK (
  bucket_id='work-attachments'
  AND owner_id=(select auth.uid())::TEXT
  AND private.work_storage_item_id(name) IS NOT NULL
  AND private.work_current_user_can_attach_item(private.work_storage_item_id(name))
  AND EXISTS (
    SELECT 1 FROM public.work_attachments a
    WHERE a.storage_bucket='work-attachments' AND a.storage_path=name AND a.removed_at IS NULL
  )
);

-- Physical cleanup is allowed to the original uploader even after metadata is
-- soft-removed, so a failed cleanup can be retried without reopening the record.
DROP POLICY IF EXISTS work_attachments_storage_delete ON storage.objects;
CREATE POLICY work_attachments_storage_delete
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id='work-attachments'
  AND owner_id=(select auth.uid())::TEXT
  AND private.work_storage_item_id(name) IS NOT NULL
  AND private.work_current_user_can_attach_item(private.work_storage_item_id(name))
);

-- Metadata is retained for audit but can be marked removed only through this command.
CREATE OR REPLACE FUNCTION public.work_remove_attachment_metadata(
  p_operation_id UUID,
  p_attachment_id UUID,
  p_expected_version BIGINT,
  p_reason TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_attachment public.work_attachments%ROWTYPE;
  v_item public.work_items%ROWTYPE;
  v_prepare JSONB;
  v_result JSONB;
BEGIN
  SELECT * INTO v_attachment FROM public.work_attachments WHERE id=p_attachment_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'operation_id',p_operation_id,'operation','work_remove_attachment_metadata','replayed',false,
      'error',jsonb_build_object('code','NOT_FOUND','message','المرفق غير موجود'));
  END IF;
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_remove_attachment_metadata',
    jsonb_build_object('attachment_id',p_attachment_id,'expected_version',p_expected_version,'reason',p_reason),
    v_attachment.work_item_id
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id=v_attachment.work_item_id FOR UPDATE;
  SELECT * INTO v_attachment FROM public.work_attachments WHERE id=p_attachment_id FOR UPDATE;
  IF v_item.state_version<>p_expected_version THEN
    RETURN private.work_command_error(p_operation_id,'work_remove_attachment_metadata','VERSION_CONFLICT','تم تعديل المهمة بواسطة مستخدم آخر',v_item.id);
  END IF;
  IF v_attachment.removed_at IS NOT NULL THEN
    RETURN private.work_command_error(p_operation_id,'work_remove_attachment_metadata','ALREADY_REMOVED','تم حذف المرفق من المهمة بالفعل',v_item.id);
  END IF;
  IF NOT private.work_actor_can_update_item(v_actor,v_item.id)
     AND NOT (v_attachment.uploaded_by_user_id=v_actor AND private.work_actor_can_comment_item(v_actor,v_item.id)) THEN
    RETURN private.work_command_error(p_operation_id,'work_remove_attachment_metadata','FORBIDDEN','غير مصرح بحذف هذا المرفق',v_item.id);
  END IF;

  UPDATE public.work_attachments
  SET removed_at=clock_timestamp(),removed_by_user_id=v_actor
  WHERE id=p_attachment_id
  RETURNING * INTO v_attachment;
  UPDATE public.work_items
  SET state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
  WHERE id=v_item.id
  RETURNING * INTO v_item;
  PERFORM private.work_append_user_event(
    v_item.id,'work.attachment_removed',v_actor,p_operation_id,v_item.status,v_item.status,
    jsonb_build_object('attachment_id',p_attachment_id,'reason',p_reason)
  );
  v_result:=jsonb_build_object(
    'work_item_id',v_item.id,'attachment_id',p_attachment_id,
    'storage_bucket',v_attachment.storage_bucket,'storage_path',v_attachment.storage_path,
    'state_version',v_item.state_version,'removed_at',v_attachment.removed_at
  );
  RETURN private.work_command_success(p_operation_id,'work_remove_attachment_metadata',v_item.id,v_result);
END;
$$;
REVOKE ALL ON FUNCTION public.work_remove_attachment_metadata(UUID,UUID,BIGINT,TEXT)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.work_remove_attachment_metadata(UUID,UUID,BIGINT,TEXT) TO authenticated;

RESET lock_timeout;
RESET statement_timeout;