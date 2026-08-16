-- Work Management — operational flags, thresholds and explicit escalation overlay.
-- Lifecycle status remains canonical; blocked/overdue/stale/at-risk/escalated are overlays only.
SET lock_timeout='5s';
SET statement_timeout='60s';

CREATE TABLE public.work_operational_settings (
  singleton BOOLEAN PRIMARY KEY DEFAULT true CHECK (singleton=true),
  due_soon_hours INTEGER NOT NULL DEFAULT 24,
  stale_after_hours INTEGER NOT NULL DEFAULT 72,
  due_alert_cooldown_hours INTEGER NOT NULL DEFAULT 24,
  follow_up_alert_cooldown_hours INTEGER NOT NULL DEFAULT 12,
  stale_alert_cooldown_hours INTEGER NOT NULL DEFAULT 24,
  blocked_alert_cooldown_hours INTEGER NOT NULL DEFAULT 24,
  manager_escalation_enabled BOOLEAN NOT NULL DEFAULT false,
  hierarchy_validated_at TIMESTAMPTZ,
  hierarchy_validated_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  state_version BIGINT NOT NULL DEFAULT 1,
  updated_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_operational_settings_due_soon_positive CHECK (due_soon_hours>0),
  CONSTRAINT work_operational_settings_stale_positive CHECK (stale_after_hours>0),
  CONSTRAINT work_operational_settings_cooldowns_positive CHECK (
    due_alert_cooldown_hours>0 AND follow_up_alert_cooldown_hours>0
    AND stale_alert_cooldown_hours>0 AND blocked_alert_cooldown_hours>0
  ),
  CONSTRAINT work_operational_settings_version_positive CHECK (state_version>0),
  CONSTRAINT work_operational_settings_hierarchy_pair CHECK (
    (hierarchy_validated_at IS NULL AND hierarchy_validated_by_user_id IS NULL)
    OR (hierarchy_validated_at IS NOT NULL AND hierarchy_validated_by_user_id IS NOT NULL)
  ),
  CONSTRAINT work_operational_settings_escalation_gate CHECK (
    manager_escalation_enabled=false OR hierarchy_validated_at IS NOT NULL
  )
);

INSERT INTO public.work_operational_settings(singleton)
VALUES(true)
ON CONFLICT(singleton) DO NOTHING;

ALTER TABLE public.work_operational_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.work_operational_settings FROM anon,authenticated;
GRANT SELECT ON TABLE public.work_operational_settings TO authenticated;
CREATE POLICY work_operational_settings_select
ON public.work_operational_settings FOR SELECT TO authenticated
USING (private.work_actor_is_active((select auth.uid())));

CREATE TABLE public.work_escalations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_item_id UUID NOT NULL REFERENCES public.work_items(id) ON DELETE CASCADE,
  escalated_by_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  target_user_id UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  reason TEXT NOT NULL,
  escalated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ,
  resolved_by_user_id UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  resolution_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_escalations_reason_not_blank CHECK (btrim(reason)<>''),
  CONSTRAINT work_escalations_resolution_order CHECK (resolved_at IS NULL OR resolved_at>=escalated_at),
  CONSTRAINT work_escalations_resolution_pair CHECK (
    (resolved_at IS NULL AND resolved_by_user_id IS NULL)
    OR (resolved_at IS NOT NULL AND resolved_by_user_id IS NOT NULL)
  )
);
CREATE UNIQUE INDEX work_escalations_one_active_per_item
  ON public.work_escalations(work_item_id) WHERE resolved_at IS NULL;
CREATE INDEX idx_work_escalations_target_active
  ON public.work_escalations(target_user_id,escalated_at DESC) WHERE resolved_at IS NULL;

ALTER TABLE public.work_escalations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.work_escalations FROM anon,authenticated;
GRANT SELECT ON TABLE public.work_escalations TO authenticated;
CREATE POLICY work_escalations_select
ON public.work_escalations FOR SELECT TO authenticated
USING (private.work_current_user_can_view_item(work_item_id));

CREATE OR REPLACE FUNCTION private.work_manager_escalation_ready()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT COALESCE((
    SELECT s.manager_escalation_enabled
       AND s.hierarchy_validated_at IS NOT NULL
       AND private.work_actor_is_active(s.hierarchy_validated_by_user_id)
    FROM public.work_operational_settings s
    WHERE s.singleton=true
  ),false);
$$;

REVOKE ALL ON FUNCTION private.work_manager_escalation_ready()
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.work_update_operational_settings(
  p_operation_id UUID,
  p_expected_version BIGINT,
  p_due_soon_hours INTEGER DEFAULT NULL,
  p_stale_after_hours INTEGER DEFAULT NULL,
  p_due_alert_cooldown_hours INTEGER DEFAULT NULL,
  p_follow_up_alert_cooldown_hours INTEGER DEFAULT NULL,
  p_stale_alert_cooldown_hours INTEGER DEFAULT NULL,
  p_blocked_alert_cooldown_hours INTEGER DEFAULT NULL,
  p_validate_hierarchy BOOLEAN DEFAULT false,
  p_manager_escalation_enabled BOOLEAN DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_settings public.work_operational_settings%ROWTYPE;
  v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_update_operational_settings',
    jsonb_build_object(
      'expected_version',p_expected_version,'due_soon_hours',p_due_soon_hours,
      'stale_after_hours',p_stale_after_hours,'due_alert_cooldown_hours',p_due_alert_cooldown_hours,
      'follow_up_alert_cooldown_hours',p_follow_up_alert_cooldown_hours,
      'stale_alert_cooldown_hours',p_stale_alert_cooldown_hours,
      'blocked_alert_cooldown_hours',p_blocked_alert_cooldown_hours,
      'validate_hierarchy',p_validate_hierarchy,'manager_escalation_enabled',p_manager_escalation_enabled
    ),NULL
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  IF NOT private.work_actor_is_active(v_actor)
     OR NOT COALESCE(public.check_permission(v_actor,'work.policies.manage'),false) THEN
    RETURN private.work_command_error(p_operation_id,'work_update_operational_settings','FORBIDDEN','غير مصرح بإدارة إعدادات التشغيل');
  END IF;

  SELECT * INTO v_settings FROM public.work_operational_settings WHERE singleton=true FOR UPDATE;
  IF v_settings.state_version<>p_expected_version THEN
    RETURN private.work_command_error(p_operation_id,'work_update_operational_settings','VERSION_CONFLICT','تم تعديل إعدادات التشغيل بواسطة مستخدم آخر');
  END IF;
  IF COALESCE(p_due_soon_hours,v_settings.due_soon_hours)<=0
     OR COALESCE(p_stale_after_hours,v_settings.stale_after_hours)<=0
     OR COALESCE(p_due_alert_cooldown_hours,v_settings.due_alert_cooldown_hours)<=0
     OR COALESCE(p_follow_up_alert_cooldown_hours,v_settings.follow_up_alert_cooldown_hours)<=0
     OR COALESCE(p_stale_alert_cooldown_hours,v_settings.stale_alert_cooldown_hours)<=0
     OR COALESCE(p_blocked_alert_cooldown_hours,v_settings.blocked_alert_cooldown_hours)<=0 THEN
    RETURN private.work_command_error(p_operation_id,'work_update_operational_settings','VALIDATION_ERROR','قيم مدد التشغيل يجب أن تكون موجبة');
  END IF;
  IF COALESCE(p_manager_escalation_enabled,v_settings.manager_escalation_enabled)
     AND NOT (p_validate_hierarchy OR v_settings.hierarchy_validated_at IS NOT NULL) THEN
    RETURN private.work_command_error(p_operation_id,'work_update_operational_settings','HIERARCHY_NOT_VALIDATED','لا يمكن تفعيل التصعيد الإداري التلقائي قبل اعتماد الهيكل التنظيمي');
  END IF;

  UPDATE public.work_operational_settings
  SET due_soon_hours=COALESCE(p_due_soon_hours,due_soon_hours),
      stale_after_hours=COALESCE(p_stale_after_hours,stale_after_hours),
      due_alert_cooldown_hours=COALESCE(p_due_alert_cooldown_hours,due_alert_cooldown_hours),
      follow_up_alert_cooldown_hours=COALESCE(p_follow_up_alert_cooldown_hours,follow_up_alert_cooldown_hours),
      stale_alert_cooldown_hours=COALESCE(p_stale_alert_cooldown_hours,stale_alert_cooldown_hours),
      blocked_alert_cooldown_hours=COALESCE(p_blocked_alert_cooldown_hours,blocked_alert_cooldown_hours),
      hierarchy_validated_at=CASE WHEN p_validate_hierarchy THEN clock_timestamp() ELSE hierarchy_validated_at END,
      hierarchy_validated_by_user_id=CASE WHEN p_validate_hierarchy THEN v_actor ELSE hierarchy_validated_by_user_id END,
      manager_escalation_enabled=COALESCE(p_manager_escalation_enabled,manager_escalation_enabled),
      state_version=state_version+1,updated_by_user_id=v_actor,updated_at=clock_timestamp()
  WHERE singleton=true
  RETURNING * INTO v_settings;

  v_result:=jsonb_build_object(
    'state_version',v_settings.state_version,'due_soon_hours',v_settings.due_soon_hours,
    'stale_after_hours',v_settings.stale_after_hours,
    'manager_escalation_enabled',v_settings.manager_escalation_enabled,
    'hierarchy_validated_at',v_settings.hierarchy_validated_at
  );
  RETURN private.work_command_success(p_operation_id,'work_update_operational_settings',NULL,v_result);
END;
$$;

CREATE OR REPLACE FUNCTION public.work_escalate(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_reason TEXT,
  p_target_user_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_escalation public.work_escalations%ROWTYPE;
  v_target UUID;
  v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_escalate',
    jsonb_build_object('work_item_id',p_work_item_id,'expected_version',p_expected_version,'reason',p_reason,'target_user_id',p_target_user_id),
    p_work_item_id
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_escalate','NOT_FOUND','المهمة غير موجودة',p_work_item_id); END IF;
  IF v_item.state_version<>p_expected_version THEN RETURN private.work_command_error(p_operation_id,'work_escalate','VERSION_CONFLICT','تم تعديل المهمة بواسطة مستخدم آخر',p_work_item_id); END IF;
  IF v_item.status IN ('done','cancelled') THEN RETURN private.work_command_error(p_operation_id,'work_escalate','INVALID_STATE','لا يمكن تصعيد مهمة منتهية',p_work_item_id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor,p_work_item_id) THEN RETURN private.work_command_error(p_operation_id,'work_escalate','FORBIDDEN','غير مصرح بتصعيد المهمة',p_work_item_id); END IF;
  IF p_reason IS NULL OR btrim(p_reason)='' THEN RETURN private.work_command_error(p_operation_id,'work_escalate','REASON_REQUIRED','سبب التصعيد مطلوب',p_work_item_id); END IF;
  IF EXISTS(SELECT 1 FROM public.work_escalations e WHERE e.work_item_id=p_work_item_id AND e.resolved_at IS NULL) THEN
    RETURN private.work_command_error(p_operation_id,'work_escalate','ALREADY_ESCALATED','المهمة مصعدة بالفعل',p_work_item_id);
  END IF;

  v_target:=COALESCE(p_target_user_id,v_item.accountable_owner_user_id);
  IF v_target IS NOT NULL THEN
    IF NOT private.work_actor_is_active(v_target) THEN
      RETURN private.work_command_error(p_operation_id,'work_escalate','TARGET_UNAVAILABLE','مستخدم التصعيد غير نشط',p_work_item_id);
    END IF;
    IF NOT private.work_user_can_view_row(
      v_target,v_item.id,v_item.visibility,v_item.creator_user_id,v_item.requester_user_id,
      v_item.accountable_owner_user_id,v_item.current_assignee_user_id,v_item.branch_id,v_item.owning_department_id
    ) THEN
      RETURN private.work_command_error(p_operation_id,'work_escalate','TARGET_VISIBILITY_DENIED','مستخدم التصعيد لا يملك حق رؤية المهمة',p_work_item_id);
    END IF;
  END IF;

  INSERT INTO public.work_escalations(work_item_id,escalated_by_user_id,target_user_id,reason)
  VALUES(p_work_item_id,v_actor,v_target,p_reason)
  RETURNING * INTO v_escalation;
  UPDATE public.work_items
  SET state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
  WHERE id=p_work_item_id RETURNING * INTO v_item;
  PERFORM private.work_append_user_event(
    v_item.id,'work.escalated',v_actor,p_operation_id,v_item.status,v_item.status,
    jsonb_build_object('escalation_id',v_escalation.id,'target_user_id',v_target,'reason',p_reason)
  );
  v_result:=jsonb_build_object('work_item_id',v_item.id,'escalation_id',v_escalation.id,'target_user_id',v_target,'state_version',v_item.state_version);
  RETURN private.work_command_success(p_operation_id,'work_escalate',v_item.id,v_result);
END;
$$;

CREATE OR REPLACE FUNCTION public.work_resolve_escalation(
  p_operation_id UUID,
  p_escalation_id UUID,
  p_expected_version BIGINT,
  p_resolution_note TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_escalation public.work_escalations%ROWTYPE;
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_result JSONB;
BEGIN
  SELECT * INTO v_escalation FROM public.work_escalations WHERE id=p_escalation_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error',jsonb_build_object('code','NOT_FOUND','message','التصعيد غير موجود')); END IF;
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_resolve_escalation',
    jsonb_build_object('escalation_id',p_escalation_id,'expected_version',p_expected_version,'resolution_note',p_resolution_note),
    v_escalation.work_item_id
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  SELECT * INTO v_item FROM public.work_items WHERE id=v_escalation.work_item_id FOR UPDATE;
  SELECT * INTO v_escalation FROM public.work_escalations WHERE id=p_escalation_id FOR UPDATE;
  IF v_item.state_version<>p_expected_version THEN RETURN private.work_command_error(p_operation_id,'work_resolve_escalation','VERSION_CONFLICT','تم تعديل المهمة بواسطة مستخدم آخر',v_item.id); END IF;
  IF v_escalation.resolved_at IS NOT NULL THEN RETURN private.work_command_error(p_operation_id,'work_resolve_escalation','ALREADY_RESOLVED','تم إنهاء التصعيد بالفعل',v_item.id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor,v_item.id)
     AND v_escalation.target_user_id IS DISTINCT FROM v_actor THEN
    RETURN private.work_command_error(p_operation_id,'work_resolve_escalation','FORBIDDEN','غير مصرح بإنهاء التصعيد',v_item.id);
  END IF;

  UPDATE public.work_escalations
  SET resolved_at=clock_timestamp(),resolved_by_user_id=v_actor,resolution_note=p_resolution_note
  WHERE id=p_escalation_id RETURNING * INTO v_escalation;
  UPDATE public.work_items
  SET state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
  WHERE id=v_item.id RETURNING * INTO v_item;
  PERFORM private.work_append_user_event(
    v_item.id,'work.escalation_resolved',v_actor,p_operation_id,v_item.status,v_item.status,
    jsonb_build_object('escalation_id',v_escalation.id,'resolution_note',p_resolution_note)
  );
  v_result:=jsonb_build_object('work_item_id',v_item.id,'escalation_id',v_escalation.id,'state_version',v_item.state_version);
  RETURN private.work_command_success(p_operation_id,'work_resolve_escalation',v_item.id,v_result);
END;
$$;

REVOKE ALL ON FUNCTION public.work_update_operational_settings(UUID,BIGINT,INTEGER,INTEGER,INTEGER,INTEGER,INTEGER,INTEGER,BOOLEAN,BOOLEAN)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_escalate(UUID,UUID,BIGINT,TEXT,UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_resolve_escalation(UUID,UUID,BIGINT,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.work_update_operational_settings(UUID,BIGINT,INTEGER,INTEGER,INTEGER,INTEGER,INTEGER,INTEGER,BOOLEAN,BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_escalate(UUID,UUID,BIGINT,TEXT,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_resolve_escalation(UUID,UUID,BIGINT,TEXT) TO authenticated;

CREATE OR REPLACE VIEW public.work_operational_flags
WITH (security_invoker=true)
AS
WITH settings AS (
  SELECT * FROM public.work_operational_settings WHERE singleton=true
), base AS (
  SELECT
    w.*,
    s.due_soon_hours,
    s.stale_after_hours,
    (w.status IN ('open','in_progress','waiting','pending_approval')) AS is_active,
    EXISTS(
      SELECT 1
      FROM public.work_dependencies d
      JOIN public.work_items blocker ON blocker.id=d.blocker_work_item_id
      WHERE d.blocked_work_item_id=w.id
        AND d.resolved_at IS NULL
        AND d.dependency_strength='hard'
        AND blocker.status<>'done'
    ) OR EXISTS(
      SELECT 1 FROM public.work_items child
      WHERE child.parent_work_item_id=w.id
        AND child.blocks_parent_completion=true
        AND child.status NOT IN ('done','cancelled')
    ) AS is_blocked,
    EXISTS(
      SELECT 1 FROM public.work_escalations e
      WHERE e.work_item_id=w.id AND e.resolved_at IS NULL
    ) AS is_escalated
  FROM public.work_items w
  CROSS JOIN settings s
)
SELECT
  b.id AS work_item_id,
  b.work_number,
  b.status,
  b.priority,
  b.visibility,
  b.current_assignee_user_id,
  b.accountable_owner_user_id,
  b.due_at,
  b.next_action_at,
  b.last_meaningful_activity_at,
  b.is_blocked,
  (b.is_active AND b.due_at IS NOT NULL AND b.due_at<clock_timestamp()) AS is_overdue,
  (
    b.status IN ('open','in_progress','pending_approval')
    AND COALESCE(b.last_meaningful_activity_at,b.activated_at,b.created_at)
        < clock_timestamp()-make_interval(hours=>b.stale_after_hours)
  ) AS is_stale,
  b.is_escalated,
  (
    b.is_active AND b.due_at IS NOT NULL
    AND b.due_at>=clock_timestamp()
    AND b.due_at<=clock_timestamp()+make_interval(hours=>b.due_soon_hours)
  ) AS is_due_soon,
  (
    b.status='waiting' AND b.next_action_at IS NOT NULL AND b.next_action_at<=clock_timestamp()
  ) AS is_follow_up_due,
  (
    b.is_active
    AND NOT (b.due_at IS NOT NULL AND b.due_at<clock_timestamp())
    AND (
      (b.due_at IS NOT NULL
       AND b.due_at<=clock_timestamp()+make_interval(hours=>b.due_soon_hours)
       AND (b.is_blocked OR (
         b.status IN ('open','in_progress','pending_approval')
         AND COALESCE(b.last_meaningful_activity_at,b.activated_at,b.created_at)
             < clock_timestamp()-make_interval(hours=>b.stale_after_hours)
       )))
      OR (b.status='waiting' AND b.next_action_at IS NOT NULL AND b.next_action_at<=clock_timestamp())
    )
  ) AS is_at_risk
FROM base b;

GRANT SELECT ON public.work_operational_flags TO authenticated;

RESET lock_timeout;
RESET statement_timeout;