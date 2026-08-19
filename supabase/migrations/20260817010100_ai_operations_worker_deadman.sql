-- AI Operations — deterministic worker dead-man / recovery health alert.
--
-- This is intentionally operational-health only. It never creates business Work,
-- changes source entities, retries model calls, or impersonates a human. When the
-- external AI worker disappears, the database ledger remains authoritative and
-- management receives a bounded, deduplicated alert through the existing
-- notification system.
SET lock_timeout = '5s';
SET statement_timeout = '30s';

INSERT INTO public.notification_event_types(
  event_key,label_ar,label_en,category,default_priority,
  title_template,body_template,icon,action_url_template,is_active
) VALUES (
  'system.ai_operations.worker_health',
  'تعطل مخطط التشغيل الذكي',
  'AI Operations worker health',
  'alerts',
  'high',
  'تنبيه: تشغيل AI Operations يحتاج متابعة',
  'لم يكتمل تشغيل {{run_key}} في موعده. راجع حالة الـPlanner قبل الاعتماد على نتائج اليوم.',
  'triangle-alert',
  '/work/manage',
  true
)
ON CONFLICT(event_key) DO UPDATE SET
  label_ar=EXCLUDED.label_ar,
  label_en=EXCLUDED.label_en,
  category=EXCLUDED.category,
  default_priority=EXCLUDED.default_priority,
  title_template=EXCLUDED.title_template,
  body_template=EXCLUDED.body_template,
  icon=EXCLUDED.icon,
  action_url_template=EXCLUDED.action_url_template,
  is_active=true,
  updated_at=clock_timestamp();

CREATE OR REPLACE FUNCTION ai_ops.scan_worker_health(
  p_now TIMESTAMPTZ DEFAULT clock_timestamp(),
  p_pending_grace_minutes INTEGER DEFAULT 20,
  p_notification_cooldown_minutes INTEGER DEFAULT 180
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_settings ai_ops.settings%ROWTYPE;
  v_run RECORD;
  v_recipient RECORD;
  v_materialized JSONB;
  v_stale_count INTEGER:=0;
  v_alert_count INTEGER:=0;
  v_recipient_count INTEGER:=0;
  v_reason TEXT;
BEGIN
  IF p_pending_grace_minutes NOT BETWEEN 5 AND 240 THEN
    RAISE EXCEPTION 'pending grace must be between 5 and 240 minutes';
  END IF;
  IF p_notification_cooldown_minutes NOT BETWEEN 30 AND 1440 THEN
    RAISE EXCEPTION 'notification cooldown must be between 30 and 1440 minutes';
  END IF;

  SELECT * INTO v_settings FROM ai_ops.settings WHERE singleton=true;
  IF NOT FOUND OR NOT v_settings.planner_enabled THEN
    RETURN jsonb_build_object(
      'checked',true,'planner_enabled',false,'stale_runs',0,
      'alerts_created',0,'management_recipients',0
    );
  END IF;

  -- If every external worker is down, the DB still materializes the run that
  -- should have happened, so absence cannot silently look like “nothing due”.
  v_materialized:=ai_ops.materialize_due_runs(p_now);

  SELECT COUNT(*)::INTEGER INTO v_recipient_count
  FROM public.profiles p
  WHERE private.work_actor_is_active(p.id)
    AND COALESCE(public.check_permission(p.id,'work.policies.manage'),false);

  FOR v_run IN
    SELECT
      r.id,r.run_key,r.run_type,r.business_date,r.scheduled_for,r.status,
      r.checkpoint,r.attempt_no,r.claimed_by,r.lease_expires_at,r.heartbeat_at,
      r.error_class,r.error_message,r.updated_at,
      s.recovery_window_minutes
    FROM ai_ops.planner_runs r
    LEFT JOIN ai_ops.run_schedules s ON s.id=r.schedule_id
    WHERE r.status IN ('pending','claimed','reasoning','failed','abandoned','committing')
      AND r.scheduled_for <= p_now
      AND r.scheduled_for >= p_now - (
        COALESCE(s.recovery_window_minutes,180) * interval '1 minute'
      )
      AND (
        (r.status='pending'
          AND r.scheduled_for <= p_now-(p_pending_grace_minutes*interval '1 minute'))
        OR (r.status IN ('claimed','reasoning')
          AND r.lease_expires_at IS NOT NULL AND r.lease_expires_at<=p_now)
        OR r.status IN ('failed','abandoned')
        OR (r.status='committing'
          AND r.updated_at<=p_now-(p_pending_grace_minutes*interval '1 minute'))
      )
    ORDER BY r.scheduled_for,r.id
  LOOP
    v_stale_count:=v_stale_count+1;
    v_reason:=CASE
      WHEN v_run.status='pending' THEN 'due_run_not_claimed'
      WHEN v_run.status IN ('claimed','reasoning') THEN 'worker_lease_expired'
      WHEN v_run.status='committing' THEN 'commit_lifecycle_stalled'
      WHEN v_run.status='failed' THEN 'worker_run_failed'
      ELSE 'worker_run_abandoned'
    END;

    FOR v_recipient IN
      SELECT p.id AS user_id
      FROM public.profiles p
      WHERE private.work_actor_is_active(p.id)
        AND COALESCE(public.check_permission(p.id,'work.policies.manage'),false)
      ORDER BY p.id
    LOOP
      IF NOT EXISTS (
        SELECT 1
        FROM public.notifications n
        WHERE n.user_id=v_recipient.user_id
          AND n.event_key='system.ai_operations.worker_health'
          AND n.entity_type='ai_ops_run'
          AND n.entity_id=v_run.id
          AND n.created_at>=p_now-(p_notification_cooldown_minutes*interval '1 minute')
          AND NOT n.is_archived
      ) THEN
        INSERT INTO public.notifications(
          user_id,event_key,title,body,category,priority,icon,action_url,
          entity_type,entity_id,metadata,expires_at
        ) VALUES (
          v_recipient.user_id,
          'system.ai_operations.worker_health',
          'تنبيه: تشغيل AI Operations يحتاج متابعة',
          format(
            'تشغيل %s لم يكتمل في موعده. الحالة: %s — checkpoint: %s. راجع الـPlanner قبل الاعتماد على نتائج اليوم.',
            v_run.run_key,v_run.status,v_run.checkpoint
          ),
          'alerts','high','triangle-alert','/work/manage',
          'ai_ops_run',v_run.id,
          jsonb_build_object(
            'ai_ops_health_alert',true,
            'health_reason',v_reason,
            'run_key',v_run.run_key,
            'run_type',v_run.run_type,
            'business_date',v_run.business_date,
            'scheduled_for',v_run.scheduled_for,
            'run_status',v_run.status,
            'checkpoint',v_run.checkpoint,
            'attempt_no',v_run.attempt_no,
            'lease_expires_at',v_run.lease_expires_at,
            'heartbeat_at',v_run.heartbeat_at,
            'error_class',v_run.error_class,
            'management_only',true,
            'employee_performance_signal',false
          ),
          p_now+interval '7 days'
        );
        v_alert_count:=v_alert_count+1;
      END IF;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object(
    'checked',true,
    'planner_enabled',true,
    'materialized_due_runs',COALESCE((v_materialized->>'materialized')::INTEGER,0),
    'stale_runs',v_stale_count,
    'management_recipients',v_recipient_count,
    'alerts_created',v_alert_count,
    'operational_mutation_performed',false
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.scan_worker_health(TIMESTAMPTZ,INTEGER,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.ai_ops_worker_scan_health()
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT ai_ops.scan_worker_health(clock_timestamp(),20,180);
$$;
REVOKE ALL ON FUNCTION public.ai_ops_worker_scan_health()
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ai_ops_worker_scan_health() TO service_role;

-- Production already uses pg_cron. Keep fresh/local database installs portable:
-- install the health scanner everywhere, schedule it only where pg_cron exists.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron')
     AND to_regclass('cron.job') IS NOT NULL THEN
    BEGIN
      PERFORM cron.unschedule('ai-operations-worker-deadman');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    PERFORM cron.schedule(
      'ai-operations-worker-deadman',
      '*/15 * * * *',
      'SELECT ai_ops.scan_worker_health(clock_timestamp(),20,180);'
    );
    RAISE NOTICE '[ai_ops] worker dead-man scheduled every 15 minutes';
  ELSE
    RAISE NOTICE '[ai_ops] pg_cron unavailable — dead-man function installed but not scheduled';
  END IF;
END $$;

COMMENT ON FUNCTION ai_ops.scan_worker_health(TIMESTAMPTZ,INTEGER,INTEGER) IS
  'Deterministic AI worker dead-man: materializes due runs, detects unclaimed/expired/failed/stalled runs and emits cooldown-deduped management health notifications only.';
COMMENT ON FUNCTION public.ai_ops_worker_scan_health() IS
  'Service-role health scan wrapper. External workers may call it, while pg_cron remains the independent dead-man when workers are unavailable.';

RESET lock_timeout;
RESET statement_timeout;
