-- ============================================================================
-- 21g: إضافة outcome_type = 'visited' لدعم تنفيذ الزيارات
--
-- عند إنهاء زيارة من وضع التنفيذ، يتم إنشاء سجل activity بـ outcome = 'visited'
-- هذا القيد (CHECK) في 21_mvp لا يتضمنها، لذلك نضيفها هنا
-- ============================================================================

-- 1) إسقاط القيد القديم وإعادة إنشائه مع 'visited'
ALTER TABLE public.activities
  DROP CONSTRAINT IF EXISTS activities_outcome_type_check;

ALTER TABLE public.activities
  ADD CONSTRAINT activities_outcome_type_check
  CHECK (outcome_type IN (
    'visited',
    'order_placed',
    'collection',
    'followup_scheduled',
    'refused',
    'closed',
    'promotion',
    'exploratory',
    'info_only',
    'agreed_order',
    'promised_payment',
    'followup_visit',
    'not_interested',
    'no_answer',
    'busy',
    'callback_scheduled'
  ));
