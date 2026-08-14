-- Work Management — notification integration, deduplicated operational scans and cron recovery jobs.
-- Reuses the existing notification catalogue/dispatcher/alert-state/pg_cron infrastructure.
SET lock_timeout='5s';
SET statement_timeout='60s';

-- ---------------------------------------------------------------------------
-- 1) Notification catalogue. Templates intentionally contain no Work title,
-- description, comments, reasons, intake payload or approval notes.
-- ---------------------------------------------------------------------------
INSERT INTO public.notification_event_types(
  event_key,label_ar,label_en,category,default_priority,
  title_template,body_template,icon,action_url_template
) VALUES
('work.assigned','إسناد عمل جديد','Work assigned','tasks','high',
 'مطلوب منك إجراء جديد','تم إسناد عنصر عمل رقم {{work_number}} إليك','clipboard-check','/work/{{work_id}}'),
('work.delegated','تم تفويض عنصر عمل','Work delegated','tasks','high',
 'تم إسناد المسؤولية التنفيذية إليك','أصبحت المسؤول الحالي عن عنصر العمل رقم {{work_number}}','user-round-check','/work/{{work_id}}'),
('work.ownership_transferred','نقل مسؤولية عنصر عمل','Work ownership transferred','tasks','high',
 'تم نقل مسؤولية عنصر عمل إليك','أصبحت المالك المسؤول عن عنصر العمل رقم {{work_number}}','shield-check','/work/{{work_id}}'),
('work.mentioned','إشارة في عنصر عمل','Mentioned in work','tasks','medium',
 'تمت الإشارة إليك','لديك إشارة جديدة في عنصر العمل رقم {{work_number}}','at-sign','/work/{{work_id}}'),
('work.follow_up_due','موعد متابعة','Work follow-up due','tasks','high',
 'حان موعد المتابعة','عنصر العمل رقم {{work_number}} يحتاج متابعة الآن','alarm-clock','/work/{{work_id}}'),
('work.due_soon','موعد استحقاق قريب','Work due soon','tasks','high',
 'موعد الاستحقاق يقترب','عنصر العمل رقم {{work_number}} يقترب من موعد الاستحقاق','clock-alert','/work/{{work_id}}'),
('work.overdue','عنصر عمل متأخر','Work overdue','tasks','critical',
 'تجاوز موعد الاستحقاق','عنصر العمل رقم {{work_number}} متأخر ويحتاج إجراء','triangle-alert','/work/{{work_id}}'),
('work.stale','عنصر عمل بلا تقدم','Work stale','tasks','high',
 'لا يوجد تقدم حديث','عنصر العمل رقم {{work_number}} لم يسجل نشاطاً تشغيلياً حديثاً','activity','/work/{{work_id}}'),
('work.blocked','عنصر عمل معطل','Work blocked','tasks','high',
 'يوجد عائق يمنع التقدم','عنصر العمل رقم {{work_number}} أصبح معطلاً','ban','/work/{{work_id}}'),
('work.unblocked','تم رفع العائق','Work unblocked','tasks','medium',
 'تم رفع العائق','عنصر العمل رقم {{work_number}} لم يعد معطلاً','circle-check','/work/{{work_id}}'),
('work.approval.requested','اعتماد مطلوب','Approval requested','tasks','high',
 'قرار اعتماد مطلوب منك','يوجد اعتماد معلق مرتبط بعنصر العمل رقم {{work_number}}','badge-check','/work/{{work_id}}'),
('work.approval.decided','تم اتخاذ قرار اعتماد','Approval decided','tasks','medium',
 'تم تحديث طلب اعتماد','تم اتخاذ قرار في اعتماد مرتبط بعنصر العمل رقم {{work_number}}','badge','/work/{{work_id}}'),
('work.approval.due','موعد اعتماد مستحق','Approval due','tasks','high',
 'اعتماد يحتاج قراراً','وصل اعتماد عنصر العمل رقم {{work_number}} إلى موعده المحدد','timer','/work/{{work_id}}'),
('work.escalated','تم تصعيد عنصر عمل','Work escalated','tasks','high',
 'تم تصعيد عنصر عمل إليك','عنصر العمل رقم {{work_number}} يحتاج متابعة تصعيدية','arrow-up-right','/work/{{work_id}}'),
('work.dependency.resolved','تم حل اعتماد بين الأعمال','Dependency resolved','tasks','medium',
 'تم حل اعتماد مؤثر','تم حل اعتماد مرتبط بعنصر العمل رقم {{work_number}}','git-merge','/work/{{work_id}}'),
('work.request.triage_due','طلب يحتاج فرزاً','Request triage due','tasks','high',
 'طلب في قائمة الانتظار يحتاج إجراء','وصل الطلب رقم {{work_number}} إلى موعد الفرز','inbox','/work/{{work_id}}'),
('work.recurrence.generated','تم إنشاء عمل دوري','Recurring work generated','tasks','medium',
 'تم إنشاء دورة عمل جديدة','تم إنشاء عنصر العمل الدوري رقم {{work_number}}','repeat','/work/{{work_id}}'),
('work.recurrence.overlap','تداخل في عمل دوري','Recurring work overlap','tasks','high',
 'تم تسجيل دورة متداخلة','الدورة الجديدة تداخلت مع عمل سابق ما زال مفتوحاً','repeat-2','/work')
ON CONFLICT(event_key) DO UPDATE SET
  label_ar=EXCLUDED.label_ar,label_en=EXCLUDED.label_en,
  category=EXCLUDED.category,default_priority=EXCLUDED.default_priority,
  title_template=EXCLUDED.title_template,body_template=EXCLUDED.body_template,
  icon=EXCLUDED.icon,action_url_template=EXCLUDED.action_url_template,
  is_active=true,updated_at=now();

-- ---------------------------------------------------------------------------
-- 2) Recipient filter. Even generic notifications are sent only to active users
-- who can currently see the Work Item. A notification never grants visibility.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.work_filter_notification_recipients(
  p_work_item_id UUID,
  p_candidates UUID[],
  p_exclude_user_id UUID DEFAULT NULL
) RETURNS UUID[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT COALESCE(array_agg(x.user_id ORDER BY x.user_id),ARRAY[]::UUID[])
  FROM (
    SELECT DISTINCT c.user_id
    FROM unnest(COALESCE(p_candidates,ARRAY[]::UUID[])) AS c(user_id)
    JOIN public.work_items w ON w.id=p_work_item_id
    WHERE c.user_id IS NOT NULL
      AND c.user_id IS DISTINCT FROM p_exclude_user_id
      AND private.work_actor_is_active(c.user_id)
      AND private.work_user_can_view_row(
        c.user_id,w.id,w.visibility,w.creator_user_id,w.requester_user_id,
        w.accountable_owner_user_id,w.current_assignee_user_id,w.branch_id,w.owning_department_id
      )
  ) x;
$$;
REVOKE ALL ON FUNCTION private.work_filter_notification_recipients(UUID,UUID[],UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.work_dispatch_generic_notification(
  p_event_key TEXT,
  p_work_item_id UUID,
  p_candidates UUID[],
  p_exclude_user_id UUID DEFAULT NULL,
  p_extra JSONB DEFAULT '{}'::JSONB
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_recipients UUID[];
  v_work_number BIGINT;
BEGIN
  SELECT w.work_number INTO v_work_number FROM public.work_items w WHERE w.id=p_work_item_id;
  IF v_work_number IS NULL THEN RETURN 0; END IF;
  v_recipients:=private.work_filter_notification_recipients(p_work_item_id,p_candidates,p_exclude_user_id);
  IF cardinality(v_recipients)=0 THEN RETURN 0; END IF;
  PERFORM public.call_dispatch_notification(
    p_event_key,v_recipients,
    jsonb_build_object('work_id',p_work_item_id::TEXT,'work_number',v_work_number::TEXT)
      || COALESCE(p_extra,'{}'::JSONB),
    'work_item',p_work_item_id
  );
  RETURN cardinality(v_recipients);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '[work_dispatch_generic_notification] non-critical %: %',p_event_key,SQLERRM;
  RETURN 0;
END;
$$;
REVOKE ALL ON FUNCTION private.work_dispatch_generic_notification(TEXT,UUID,UUID[],UUID,JSONB)
  FROM PUBLIC,anon,authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 3) One integration trigger from the immutable Work timeline.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.work_notify_from_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_item public.work_items%ROWTYPE;
  v_candidates UUID[]:=ARRAY[]::UUID[];
  v_uuid UUID;
  v_approval_request_id UUID;
  v_comment_id UUID;
BEGIN
  BEGIN
    SELECT * INTO v_item FROM public.work_items WHERE id=NEW.work_item_id;
    IF NOT FOUND THEN RETURN NEW; END IF;

    CASE NEW.event_type
      WHEN 'work.activated' THEN
        v_candidates:=ARRAY[v_item.current_assignee_user_id];
        PERFORM private.work_dispatch_generic_notification('work.assigned',v_item.id,v_candidates,NEW.actor_user_id);

      WHEN 'work.workflow_step.activated' THEN
        v_candidates:=ARRAY[v_item.current_assignee_user_id];
        PERFORM private.work_dispatch_generic_notification('work.assigned',v_item.id,v_candidates,NULL);

      WHEN 'work.recurrence.generated' THEN
        v_candidates:=ARRAY[v_item.current_assignee_user_id,v_item.accountable_owner_user_id];
        PERFORM private.work_dispatch_generic_notification('work.recurrence.generated',v_item.id,v_candidates,NULL);

      WHEN 'work.delegated' THEN
        BEGIN v_uuid:=(NEW.payload->>'to_assignee_user_id')::UUID; EXCEPTION WHEN OTHERS THEN v_uuid:=NULL; END;
        PERFORM private.work_dispatch_generic_notification('work.delegated',v_item.id,ARRAY[v_uuid],NEW.actor_user_id);

      WHEN 'work.ownership_transferred' THEN
        BEGIN v_uuid:=(NEW.payload->>'to_owner_user_id')::UUID; EXCEPTION WHEN OTHERS THEN v_uuid:=NULL; END;
        PERFORM private.work_dispatch_generic_notification('work.ownership_transferred',v_item.id,ARRAY[v_uuid],NEW.actor_user_id);

      WHEN 'work.comment_added' THEN
        BEGIN v_comment_id:=(NEW.payload->>'comment_id')::UUID; EXCEPTION WHEN OTHERS THEN v_comment_id:=NULL; END;
        SELECT COALESCE(array_agg(m.mentioned_user_id),ARRAY[]::UUID[]) INTO v_candidates
        FROM public.work_mentions m WHERE m.comment_id=v_comment_id AND m.work_item_id=v_item.id;
        PERFORM private.work_dispatch_generic_notification('work.mentioned',v_item.id,v_candidates,NEW.actor_user_id);
        UPDATE public.work_mentions SET notified_at=COALESCE(notified_at,clock_timestamp())
        WHERE comment_id=v_comment_id AND work_item_id=v_item.id;

      WHEN 'work.progress_updated' THEN
        BEGIN v_comment_id:=(NEW.payload->>'comment_id')::UUID; EXCEPTION WHEN OTHERS THEN v_comment_id:=NULL; END;
        SELECT COALESCE(array_agg(m.mentioned_user_id),ARRAY[]::UUID[]) INTO v_candidates
        FROM public.work_mentions m WHERE m.comment_id=v_comment_id AND m.work_item_id=v_item.id;
        PERFORM private.work_dispatch_generic_notification('work.mentioned',v_item.id,v_candidates,NEW.actor_user_id);
        UPDATE public.work_mentions SET notified_at=COALESCE(notified_at,clock_timestamp())
        WHERE comment_id=v_comment_id AND work_item_id=v_item.id;

      WHEN 'work.approval.requested' THEN
        BEGIN v_approval_request_id:=(NEW.payload->>'approval_request_id')::UUID; EXCEPTION WHEN OTHERS THEN v_approval_request_id:=NULL; END;
        SELECT COALESCE(array_agg(DISTINCT a.effective_approver_user_id),ARRAY[]::UUID[]) INTO v_candidates
        FROM public.work_approval_assignments a
        JOIN public.work_approval_stage_instances s ON s.id=a.stage_instance_id
        WHERE s.approval_request_id=v_approval_request_id AND s.status='pending' AND a.status='pending';
        PERFORM private.work_dispatch_generic_notification('work.approval.requested',v_item.id,v_candidates,NEW.actor_user_id);

      WHEN 'work.approval.decision' THEN
        BEGIN v_approval_request_id:=(NEW.payload->>'approval_request_id')::UUID; EXCEPTION WHEN OTHERS THEN v_approval_request_id:=NULL; END;
        SELECT ARRAY[r.requested_by_user_id,v_item.accountable_owner_user_id] INTO v_candidates
        FROM public.work_approval_requests r WHERE r.id=v_approval_request_id;
        PERFORM private.work_dispatch_generic_notification('work.approval.decided',v_item.id,v_candidates,NEW.actor_user_id);

      WHEN 'work.escalated' THEN
        BEGIN v_uuid:=(NEW.payload->>'target_user_id')::UUID; EXCEPTION WHEN OTHERS THEN v_uuid:=NULL; END;
        PERFORM private.work_dispatch_generic_notification(
          'work.escalated',v_item.id,ARRAY[v_uuid,v_item.accountable_owner_user_id],NEW.actor_user_id
        );

      WHEN 'work.dependency_resolved' THEN
        PERFORM private.work_dispatch_generic_notification(
          'work.dependency.resolved',v_item.id,
          ARRAY[v_item.current_assignee_user_id,v_item.accountable_owner_user_id],NEW.actor_user_id
        );
      ELSE
        NULL;
    END CASE;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[work_notify_from_event] non-critical event %: %',NEW.event_type,SQLERRM;
  END;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.work_notify_from_event() FROM PUBLIC,anon,authenticated,service_role;
DROP TRIGGER IF EXISTS trg_work_notify_from_event ON public.work_events;
CREATE TRIGGER trg_work_notify_from_event
  AFTER INSERT ON public.work_events
  FOR EACH ROW EXECUTE FUNCTION private.work_notify_from_event();

-- ---------------------------------------------------------------------------
-- 4) Concurrency-safe alert claim on the existing notification_alert_state.
-- Returns true only for a first occurrence, a reopened alert, or an expired cooldown.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.work_claim_notification_alert(
  p_alert_key TEXT,
  p_event_key TEXT,
  p_entity_id UUID,
  p_cooldown_hours INTEGER,
  p_now TIMESTAMPTZ DEFAULT now()
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE v_id UUID;
BEGIN
  INSERT INTO public.notification_alert_state(
    alert_key,event_key,entity_type,entity_id,last_sent_at,resolved_at,send_count,cooldown_hours
  ) VALUES(
    p_alert_key,p_event_key,'work_item',p_entity_id,p_now,NULL,1,GREATEST(p_cooldown_hours,1)
  )
  ON CONFLICT(alert_key) DO UPDATE
  SET event_key=EXCLUDED.event_key,
      entity_type='work_item',entity_id=EXCLUDED.entity_id,
      last_sent_at=EXCLUDED.last_sent_at,resolved_at=NULL,
      send_count=public.notification_alert_state.send_count+1,
      cooldown_hours=EXCLUDED.cooldown_hours
  WHERE public.notification_alert_state.resolved_at IS NOT NULL
     OR public.notification_alert_state.last_sent_at
        <= p_now-make_interval(hours=>GREATEST(p_cooldown_hours,1))
  RETURNING id INTO v_id;
  RETURN v_id IS NOT NULL;
END;
$$;
REVOKE ALL ON FUNCTION private.work_claim_notification_alert(TEXT,TEXT,UUID,INTEGER,TIMESTAMPTZ)
  FROM PUBLIC,anon,authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 5) Operational scanner. It does not mutate lifecycle status and never creates
-- automatic manager escalations. It only emits deduplicated reminders/overlays.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.work_scan_operational_alerts(
  p_now TIMESTAMPTZ DEFAULT now(),
  p_limit INTEGER DEFAULT 200
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_settings public.work_operational_settings%ROWTYPE;
  v_flag RECORD;
  v_key TEXT;
  v_candidates UUID[];
  v_sent INTEGER:=0;
  v_unblocked INTEGER:=0;
  v_triage RECORD;
  v_approval RECORD;
  v_overlap RECORD;
BEGIN
  SELECT * INTO v_settings FROM public.work_operational_settings WHERE singleton=true;
  p_limit:=LEAST(GREATEST(COALESCE(p_limit,200),1),1000);

  -- Resolve obsolete/cleared alerts first. Timestamp-bound keys also resolve after
  -- due/follow-up dates change, so a new date can generate a fresh alert.
  UPDATE public.notification_alert_state nas
  SET resolved_at=p_now
  FROM public.work_operational_flags f
  WHERE nas.entity_type='work_item' AND nas.entity_id=f.work_item_id AND nas.resolved_at IS NULL
    AND nas.event_key='work.due_soon'
    AND (NOT f.is_due_soon OR f.due_at IS NULL OR nas.alert_key<>'work.due_soon::'||f.work_item_id::TEXT||'::'||extract(epoch from f.due_at)::BIGINT::TEXT);
  UPDATE public.notification_alert_state nas
  SET resolved_at=p_now
  FROM public.work_operational_flags f
  WHERE nas.entity_type='work_item' AND nas.entity_id=f.work_item_id AND nas.resolved_at IS NULL
    AND nas.event_key='work.overdue'
    AND (NOT f.is_overdue OR f.due_at IS NULL OR nas.alert_key<>'work.overdue::'||f.work_item_id::TEXT||'::'||extract(epoch from f.due_at)::BIGINT::TEXT);
  UPDATE public.notification_alert_state nas
  SET resolved_at=p_now
  FROM public.work_operational_flags f
  WHERE nas.entity_type='work_item' AND nas.entity_id=f.work_item_id AND nas.resolved_at IS NULL
    AND nas.event_key='work.follow_up_due'
    AND (NOT f.is_follow_up_due OR f.next_action_at IS NULL OR nas.alert_key<>'work.follow_up_due::'||f.work_item_id::TEXT||'::'||extract(epoch from f.next_action_at)::BIGINT::TEXT);
  UPDATE public.notification_alert_state nas
  SET resolved_at=p_now
  FROM public.work_operational_flags f
  WHERE nas.entity_type='work_item' AND nas.entity_id=f.work_item_id AND nas.resolved_at IS NULL
    AND nas.event_key='work.stale' AND NOT f.is_stale;

  -- Blocked -> unblocked is a useful transition notification; resolve after dispatch.
  FOR v_flag IN
    SELECT f.*
    FROM public.work_operational_flags f
    JOIN public.notification_alert_state nas
      ON nas.entity_type='work_item' AND nas.entity_id=f.work_item_id
     AND nas.event_key='work.blocked' AND nas.resolved_at IS NULL
    WHERE NOT f.is_blocked
    ORDER BY f.work_number
    LIMIT p_limit
  LOOP
    SELECT ARRAY[f.current_assignee_user_id,f.accountable_owner_user_id] INTO v_candidates
    FROM public.work_operational_flags f WHERE f.work_item_id=v_flag.work_item_id;
    v_unblocked:=v_unblocked+private.work_dispatch_generic_notification(
      'work.unblocked',v_flag.work_item_id,v_candidates,NULL
    );
    UPDATE public.notification_alert_state
    SET resolved_at=p_now
    WHERE entity_type='work_item' AND entity_id=v_flag.work_item_id
      AND event_key='work.blocked' AND resolved_at IS NULL;
  END LOOP;

  FOR v_flag IN
    SELECT * FROM public.work_operational_flags
    WHERE is_due_soon OR is_overdue OR is_follow_up_due OR is_stale OR is_blocked
    ORDER BY COALESCE(due_at,next_action_at,p_now),work_number
    LIMIT p_limit
  LOOP
    v_candidates:=ARRAY[v_flag.current_assignee_user_id,v_flag.accountable_owner_user_id];

    IF v_flag.is_due_soon AND NOT v_flag.is_overdue AND v_flag.due_at IS NOT NULL THEN
      v_key:='work.due_soon::'||v_flag.work_item_id::TEXT||'::'||extract(epoch from v_flag.due_at)::BIGINT::TEXT;
      IF private.work_claim_notification_alert(v_key,'work.due_soon',v_flag.work_item_id,v_settings.due_alert_cooldown_hours,p_now) THEN
        v_sent:=v_sent+private.work_dispatch_generic_notification('work.due_soon',v_flag.work_item_id,v_candidates,NULL);
      END IF;
    END IF;

    IF v_flag.is_overdue AND v_flag.due_at IS NOT NULL THEN
      v_key:='work.overdue::'||v_flag.work_item_id::TEXT||'::'||extract(epoch from v_flag.due_at)::BIGINT::TEXT;
      IF private.work_claim_notification_alert(v_key,'work.overdue',v_flag.work_item_id,v_settings.due_alert_cooldown_hours,p_now) THEN
        v_sent:=v_sent+private.work_dispatch_generic_notification('work.overdue',v_flag.work_item_id,v_candidates,NULL);
      END IF;
    END IF;

    IF v_flag.is_follow_up_due AND v_flag.next_action_at IS NOT NULL THEN
      v_key:='work.follow_up_due::'||v_flag.work_item_id::TEXT||'::'||extract(epoch from v_flag.next_action_at)::BIGINT::TEXT;
      IF private.work_claim_notification_alert(v_key,'work.follow_up_due',v_flag.work_item_id,v_settings.follow_up_alert_cooldown_hours,p_now) THEN
        v_sent:=v_sent+private.work_dispatch_generic_notification('work.follow_up_due',v_flag.work_item_id,v_candidates,NULL);
      END IF;
    END IF;

    IF v_flag.is_stale THEN
      v_key:='work.stale::'||v_flag.work_item_id::TEXT;
      IF private.work_claim_notification_alert(v_key,'work.stale',v_flag.work_item_id,v_settings.stale_alert_cooldown_hours,p_now) THEN
        v_sent:=v_sent+private.work_dispatch_generic_notification('work.stale',v_flag.work_item_id,v_candidates,NULL);
      END IF;
    END IF;

    IF v_flag.is_blocked THEN
      v_key:='work.blocked::'||v_flag.work_item_id::TEXT;
      IF private.work_claim_notification_alert(v_key,'work.blocked',v_flag.work_item_id,v_settings.blocked_alert_cooldown_hours,p_now) THEN
        v_sent:=v_sent+private.work_dispatch_generic_notification('work.blocked',v_flag.work_item_id,v_candidates,NULL);
      END IF;
    END IF;
  END LOOP;

  -- Request triage SLA is separate from Work due/follow-up.
  FOR v_triage IN
    SELECT r.work_item_id,r.queue_id,r.triage_due_at,w.work_number
    FROM public.work_requests r
    JOIN public.work_items w ON w.id=r.work_item_id
    WHERE r.triaged_at IS NULL AND r.triage_due_at<=p_now
      AND w.status NOT IN ('done','cancelled')
    ORDER BY r.triage_due_at
    LIMIT p_limit
  LOOP
    SELECT COALESCE(array_agg(DISTINCT u.user_id),ARRAY[]::UUID[]) INTO v_candidates
    FROM (
      SELECT q.manager_user_id AS user_id FROM public.work_queues q WHERE q.id=v_triage.queue_id AND q.is_active=true
      UNION ALL
      SELECT m.user_id FROM public.work_queue_members m
      WHERE m.queue_id=v_triage.queue_id
        AND m.active_from<=p_now AND (m.active_until IS NULL OR m.active_until>p_now)
        AND (m.can_triage OR m.member_role IN ('triager','manager'))
    ) u
    WHERE private.work_actor_is_active(u.user_id)
      AND COALESCE(public.check_permission(u.user_id,'work.requests.triage'),false);
    v_key:='work.request.triage_due::'||v_triage.work_item_id::TEXT||'::'||extract(epoch from v_triage.triage_due_at)::BIGINT::TEXT;
    IF private.work_claim_notification_alert(v_key,'work.request.triage_due',v_triage.work_item_id,v_settings.due_alert_cooldown_hours,p_now) THEN
      v_sent:=v_sent+private.work_dispatch_generic_notification('work.request.triage_due',v_triage.work_item_id,v_candidates,NULL);
    END IF;
  END LOOP;

  -- Approval deadline reminder. This is notification only; no automatic manager escalation.
  FOR v_approval IN
    SELECT a.id AS assignment_id,a.effective_approver_user_id,r.work_item_id,s.due_at
    FROM public.work_approval_assignments a
    JOIN public.work_approval_stage_instances s ON s.id=a.stage_instance_id
    JOIN public.work_approval_requests r ON r.id=s.approval_request_id
    WHERE a.status='pending' AND s.status='pending' AND r.status='pending'
      AND s.due_at IS NOT NULL AND s.due_at<=p_now
    ORDER BY s.due_at,a.id
    LIMIT p_limit
  LOOP
    v_key:='work.approval.due::'||v_approval.assignment_id::TEXT||'::'||extract(epoch from v_approval.due_at)::BIGINT::TEXT;
    IF private.work_claim_notification_alert(v_key,'work.approval.due',v_approval.work_item_id,v_settings.due_alert_cooldown_hours,p_now) THEN
      v_sent:=v_sent+private.work_dispatch_generic_notification(
        'work.approval.due',v_approval.work_item_id,ARRAY[v_approval.effective_approver_user_id],NULL
      );
    END IF;
  END LOOP;

  -- Recurrence overlaps are retained as compliance records and get one deduped alert.
  FOR v_overlap IN
    SELECT o.id AS occurrence_id,o.overlap_work_item_id,d.created_by_user_id
    FROM public.work_recurrence_occurrences o
    JOIN public.work_recurrence_definitions d ON d.id=o.recurrence_definition_id
    WHERE o.status='overlap'
    ORDER BY o.scheduled_for DESC
    LIMIT p_limit
  LOOP
    IF v_overlap.overlap_work_item_id IS NOT NULL THEN
      v_key:='work.recurrence.overlap::'||v_overlap.occurrence_id::TEXT;
      IF private.work_claim_notification_alert(v_key,'work.recurrence.overlap',v_overlap.overlap_work_item_id,8760,p_now) THEN
        v_sent:=v_sent+private.work_dispatch_generic_notification(
          'work.recurrence.overlap',v_overlap.overlap_work_item_id,ARRAY[v_overlap.created_by_user_id],NULL
        );
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('sent_recipient_count',v_sent,'unblocked_recipient_count',v_unblocked);
END;
$$;
REVOKE ALL ON FUNCTION private.work_scan_operational_alerts(TIMESTAMPTZ,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 6) Workflow recovery activator. Normal commands advance synchronously; this
-- cron-safe sweep only repairs progress if an external completion changed state
-- between executions. SKIP LOCKED keeps concurrent workers independent.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.work_advance_running_workflows(p_limit INTEGER DEFAULT 100)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_run RECORD;
  v_count INTEGER:=0;
  v_failed INTEGER:=0;
BEGIN
  p_limit:=LEAST(GREATEST(COALESCE(p_limit,100),1),500);
  FOR v_run IN
    SELECT r.id
    FROM public.work_workflow_runs r
    WHERE r.status='running'
    ORDER BY r.started_at,r.id
    FOR UPDATE SKIP LOCKED
    LIMIT p_limit
  LOOP
    BEGIN
      PERFORM private.work_advance_workflow_run(v_run.id);
      v_count:=v_count+1;
    EXCEPTION WHEN OTHERS THEN
      v_failed:=v_failed+1;
      RAISE WARNING '[work_advance_running_workflows] run %: %',v_run.id,SQLERRM;
    END;
  END LOOP;
  RETURN jsonb_build_object('processed',v_count,'failed',v_failed);
END;
$$;
REVOKE ALL ON FUNCTION private.work_advance_running_workflows(INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 7) pg_cron jobs. These are migration definitions only until release gate.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS(SELECT 1 FROM cron.job WHERE jobname='work-operational-alerts') THEN
    PERFORM cron.unschedule('work-operational-alerts');
  END IF;
  IF EXISTS(SELECT 1 FROM cron.job WHERE jobname='work-recurrence-generator') THEN
    PERFORM cron.unschedule('work-recurrence-generator');
  END IF;
  IF EXISTS(SELECT 1 FROM cron.job WHERE jobname='work-workflow-activator') THEN
    PERFORM cron.unschedule('work-workflow-activator');
  END IF;
END $$;

SELECT cron.schedule(
  'work-operational-alerts','*/15 * * * *',
  $$ SELECT private.work_scan_operational_alerts(clock_timestamp(),200); $$
);
SELECT cron.schedule(
  'work-recurrence-generator','*/5 * * * *',
  $$ SELECT private.work_generate_due_recurrences(clock_timestamp(),200); $$
);
SELECT cron.schedule(
  'work-workflow-activator','*/5 * * * *',
  $$ SELECT private.work_advance_running_workflows(100); $$
);

RESET lock_timeout;
RESET statement_timeout;