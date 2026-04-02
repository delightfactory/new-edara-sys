-- ═══════════════════════════════════════════════════════════════════
-- 🔔 اختبار Push Notifications — Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════════
-- الهدف: إرسال إشعار Push تجريبي لكل المستخدمين المشتركين
-- المتطلب: يجب أن يكون المستخدم قد فعّل Push من إعدادات الإشعارات
-- ═══════════════════════════════════════════════════════════════════


-- ── خطوة 0 (اختيارية): تحقق من المشتركين في Push ─────────────────
-- شغّل هذا أولاً للتأكد أن هناك اشتراكات نشطة
SELECT
  u.email,
  ps.device_name,
  ps.browser,
  ps.device_type,
  ps.is_active,
  ps.created_at
FROM public.push_subscriptions ps
JOIN auth.users u ON u.id = ps.user_id
WHERE ps.is_active = true
ORDER BY ps.created_at DESC;


-- ════════════════════════════════════════════════════════════════════
-- ── خطوة 1: إرسال إشعار لمستخدم واحد بعينه (للاختبار الأولي) ─────
-- ════════════════════════════════════════════════════════════════════
-- استبدل  YOUR_USER_UUID  بـ UUID المستخدم الذي فعّل Push
-- يمكنك الحصول عليه من نتيجة الاستعلام أعلاه أو من:
--   Supabase Dashboard → Authentication → Users

DO $$
DECLARE
  v_url        text := current_setting('app.settings.supabase_url', true);
  v_service_key text := current_setting('app.settings.service_role_key', true);
  v_user_id    uuid := 'YOUR_USER_UUID';   -- ← ضع UUID المستخدم هنا
  v_response   json;
BEGIN
  SELECT content::json INTO v_response
  FROM net.http_post(
    url     := v_url || '/functions/v1/dispatch-notification',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body    := jsonb_build_object(
      'event_key', 'system.announcement',        -- event_key موجود في notification_event_types
      'user_ids',  jsonb_build_array(v_user_id::text),
      'variables', jsonb_build_object(
        'message', '🎉 اختبار Push Notifications — النظام يعمل بشكل صحيح!'
      )
    )
  );

  RAISE NOTICE 'Response: %', v_response;
END $$;


-- ════════════════════════════════════════════════════════════════════
-- ── خطوة 2: إرسال لكل المستخدمين المشتركين دفعة واحدة ────────────
-- ════════════════════════════════════════════════════════════════════
-- ملاحظة: Edge Function تقبل حتى 100 مستخدم لكل استدعاء
-- إذا كان عدد المستخدمين > 100، استخدم خطوة 3 (batched)

DO $$
DECLARE
  v_url         text;
  v_service_key text;
  v_user_ids    jsonb;
  v_response    json;
BEGIN
  -- اقرأ الإعدادات من Vault أو متغيرات البيئة
  v_url         := current_setting('app.settings.supabase_url',    true);
  v_service_key := current_setting('app.settings.service_role_key', true);

  -- اجمع كل المستخدمين النشطين الذين فعّلوا Push
  SELECT jsonb_agg(DISTINCT ps.user_id::text)
  INTO v_user_ids
  FROM public.push_subscriptions ps
  WHERE ps.is_active = true;

  IF v_user_ids IS NULL OR jsonb_array_length(v_user_ids) = 0 THEN
    RAISE NOTICE 'لا يوجد مستخدمون مشتركون في Push حتى الآن';
    RETURN;
  END IF;

  RAISE NOTICE 'سيتم الإرسال لـ % مستخدم', jsonb_array_length(v_user_ids);

  SELECT content::json INTO v_response
  FROM net.http_post(
    url     := v_url || '/functions/v1/dispatch-notification',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body    := jsonb_build_object(
      'event_key', 'system.announcement',
      'user_ids',  v_user_ids,
      'variables', jsonb_build_object(
        'message', '🔔 اختبار شامل — Push Notifications تعمل بنجاح!'
      )
    )
  );

  RAISE NOTICE 'نتيجة الإرسال: %', v_response;
END $$;


-- ════════════════════════════════════════════════════════════════════
-- ── خطوة 3: إذا لم تكن app.settings مضبوطة — استخدم هذا البديل ──
-- ════════════════════════════════════════════════════════════════════
-- في Supabase Dashboard → Settings → API → انسخ Project URL و service_role key

DO $$
DECLARE
  v_url         text := 'https://XXXXXXXXXX.supabase.co';    -- ← ضع Project URL
  v_service_key text := 'eyJhbGci...YOUR_SERVICE_ROLE_KEY'; -- ← ضع service_role key
  v_user_ids    jsonb;
  v_response    json;
BEGIN
  SELECT jsonb_agg(DISTINCT ps.user_id::text)
  INTO v_user_ids
  FROM public.push_subscriptions ps
  WHERE ps.is_active = true;

  IF v_user_ids IS NULL OR jsonb_array_length(v_user_ids) = 0 THEN
    RAISE NOTICE '❌ لا يوجد مستخدمون مشتركون في Push — تأكد من تفعيل Push في إعدادات الإشعارات أولاً';
    RETURN;
  END IF;

  RAISE NOTICE '✅ إرسال لـ % مستخدم...', jsonb_array_length(v_user_ids);

  SELECT content::json INTO v_response
  FROM net.http_post(
    url     := v_url || '/functions/v1/dispatch-notification',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body    := jsonb_build_object(
      'event_key', 'system.announcement',
      'user_ids',  v_user_ids,
      'variables', jsonb_build_object(
        'message', '🔔 اختبار Push Notifications — يعمل بنجاح!'
      )
    )
  );

  RAISE NOTICE '📬 النتيجة: %', v_response;
END $$;


-- ════════════════════════════════════════════════════════════════════
-- ── تحقق من event_keys المتاحة إذا فشل event_key أعلاه ───────────
-- ════════════════════════════════════════════════════════════════════
SELECT event_key, label_ar, category, default_priority
FROM public.notification_event_types
WHERE is_active = true
ORDER BY category, event_key;
