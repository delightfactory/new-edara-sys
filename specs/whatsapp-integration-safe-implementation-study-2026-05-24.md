# دراسة تنفيذ آمن لربط EDARA مع NexusWA

تاريخ الدراسة: 2026-05-24  
النطاق: دراسة وتحليل وخطة تنفيذ آمن، بدون تعديل الوظائف الإنتاجية الحالية في EDARA.

---

## 1. الملخص التنفيذي

الربط بين EDARA ومشروع NexusWA ممكن فنيا، ومفيد تشغيليا، لكن يجب تنفيذه كطبقة تكامل خارجية اختيارية لا تتحكم في منطق EDARA الأساسي ولا توقف أي عملية إنتاجية عند فشل واتساب.

القرار المعماري الموصى به:

```text
EDARA business event
  -> notification/event catalogue
  -> whatsapp_outbox
  -> isolated Edge Function / Worker
  -> NexusWA REST API
  -> delivery log / webhook status update
```

المبدأ الحاكم:

> EDARA هو مصدر الحقيقة الوحيد. NexusWA قناة تواصل فقط. فشل القناة لا يفشل العملية التجارية.

بناء على مراجعة المشروعين:

- EDARA لديه نظام إشعارات مركزي جاهز وقابل للتوسعة.
- NexusWA لديه REST API لإرسال الرسائل، إدارة الجلسات، webhooks، وسجل رسائل مستقل.
- لا يجب ربط صفحات EDARA مباشرة بواتساب.
- لا يجب كشف مفاتيح NexusWA في المتصفح.
- لا يجب أن تؤثر رسائل واتساب على أوامر البيع، المالية، المخزون، HR، أو الموافقات.

التوصية التنفيذية:

1. المرحلة الأولى: إرسال إشعارات واتساب فقط، للمديرين/الموظفين داخليا، بدون عملاء، وبدون استقبال أوامر واردة.
2. المرحلة الثانية: رسائل عملاء محدودة Transactional مثل تأكيد طلب أو تذكير سداد.
3. المرحلة الثالثة: استقبال رسائل واردة وربطها بسجل العميل أو النشاط، بدون تنفيذ عمليات مالية أو مخزنية.
4. المرحلة الرابعة: أتمتة أكثر تقدما بعد إثبات الاستقرار.

التوصية للاستضافة:

- الأسهل والأقل تعقيدا: VPS صغير يعمل عليه Docker Compose.
- الأرخص المدفوع: DigitalOcean أو Hetzner حسب توافر الحساب والدعم.
- المجاني الممكن: Oracle Cloud Always Free، لكنه أقل سهولة وقد يواجه مشكلة توافر أو سعة.
- لا يوصى بـ Render/Railway كخيار أول لهذا المشروع لأن NexusWA يحتاج جلسات واتساب ثابتة وبيانات محلية/Redis/Postgres واستمرارية تشغيل.

---

## 2. الوضع الحالي بعد مراجعة المشروعين

### 2.1 EDARA

المشروع الحالي يعتمد على:

- React + Vite في الواجهة.
- Supabase كقاعدة وEdge Functions.
- نظام صلاحيات وRLS.
- نظام إشعارات مركزي.
- وحدات إنتاجية حساسة: Sales, Finance, Inventory, HR, Activities, Reports.

الملفات ذات الصلة:

- `supabase/migrations/42_notification_system.sql`
- `supabase/migrations/45_notification_webhooks.sql`
- `supabase/migrations/46_notification_full_coverage.sql`
- `supabase/functions/dispatch-notification/index.ts`
- `src/lib/notifications/event-registry.ts`
- `src/lib/notifications/types.ts`

الملاحظة المهمة:

نظام الإشعارات الحالي مصمم أصلا على مبدأ آمن: بعض الـ triggers تستخدم `AFTER`، وتغلف الإخفاقات بحيث لا تعطل العملية الأصلية. هذا النمط يجب الحفاظ عليه وتوسيعه.

### 2.2 NexusWA

مشروع NexusWA موجود خارج EDARA في:

- `C:\Users\HP\OneDrive\Desktop\whats`

مكوناته:

- Backend: Fastify + Prisma + PostgreSQL + Redis + Minio.
- Frontend: Next.js dashboard.
- WhatsApp engine: `@whiskeysockets/baileys`.
- تشغيل محلي عبر `start.ps1`.
- Docker Compose للخدمات الداعمة: PostgreSQL, Redis, Minio.

واجهات مهمة:

- `GET /health`
- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/api-keys`
- `POST /api/v1/instances`
- `POST /api/v1/instances/:instanceId/connect`
- `GET /api/v1/instances/:instanceId/qr`
- `POST /api/v1/messages/send`
- `POST /api/v1/messages/send-bulk`
- `/docs` للتوثيق.

نموذج الإرسال الأساسي في NexusWA:

```json
{
  "instanceId": "uuid",
  "to": "201xxxxxxxxx",
  "type": "text",
  "content": {
    "body": "نص الرسالة"
  },
  "externalId": "edara-notification-id"
}
```

نقاط قوة NexusWA:

- API جاهز.
- API keys مخصصة للأنظمة الخارجية.
- يدعم أنواع رسائل متعددة.
- لديه سجل رسائل.
- لديه webhooks.
- لديه anti-ban service مبدئي.

نقاط ضعف NexusWA للإنتاج:

- يعتمد على WhatsApp Web/Baileys وليس WhatsApp Business Cloud API الرسمي.
- يحتاج جلسة واتساب مستقرة وملفات session ثابتة.
- يحتاج تشغيل دائم.
- يحتاج مراقبة للاتصال والـ QR.
- يحتاج حماية أقوى قبل فتحه للإنترنت.

---

## 3. المبدأ غير القابل للتفاوض: عدم المساس بإنتاج EDARA

أي تنفيذ يجب أن يلتزم بهذه القواعد:

1. لا تعديل في منطق تأكيد أوامر البيع.
2. لا تعديل في منطق القيود المحاسبية أو الخزائن.
3. لا تعديل في منطق المخزون أو التحويلات.
4. لا تعديل في منطق الرواتب أو الحضور.
5. لا تعديل في منطق RLS الحالي إلا لإضافة جداول تكامل جديدة.
6. لا استدعاء HTTP خارجي داخل transaction حرجة إذا كان سيؤثر على زمن أو نتيجة العملية.
7. لا جعل نجاح واتساب شرطا لنجاح أي عملية.
8. لا إرسال من الواجهة مباشرة.
9. لا تخزين أسرار NexusWA في frontend أو جداول مكشوفة للمستخدمين.
10. كل شيء قابل للإيقاف من إعداد واحد.

القاعدة العملية:

```text
Business operation succeeds first.
WhatsApp delivery happens later.
Failure is logged, never propagated to business logic.
```

---

## 4. النمط المعماري المقترح

### 4.1 لماذا Outbox؟

الـ Outbox هو طابور رسائل داخل EDARA. وظيفته فصل العملية التجارية عن قناة واتساب.

بدون Outbox:

```text
تأكيد طلب بيع -> استدعاء NexusWA -> إذا فشل NexusWA قد تتأثر العملية
```

مع Outbox:

```text
تأكيد طلب بيع -> تسجيل حدث/إشعار -> إضافة رسالة في outbox -> العملية تنتهي
Worker لاحق يرسل الرسالة -> يسجل النتيجة
```

هذا هو النمط الأكثر أمانا لبيئة إنتاجية.

### 4.2 مكونات التكامل

#### أ. جداول جديدة في EDARA

لا نعدل جداول الإنتاج الحالية. نضيف فقط:

1. `whatsapp_integration_settings`
2. `whatsapp_message_templates`
3. `whatsapp_outbox`
4. `whatsapp_delivery_attempts`
5. `whatsapp_inbound_messages` لاحقا
6. `whatsapp_contact_consent` لاحقا

#### ب. Edge Functions جديدة

1. `enqueue-whatsapp-message`
   - تستقبل طلب إرسال من النظام.
   - تتحقق من الصلاحيات والسياسات.
   - تضيف إلى outbox.

2. `process-whatsapp-outbox`
   - تقرأ الرسائل pending.
   - تتصل بـ NexusWA.
   - تحدث الحالة.
   - تعيد المحاولة حسب سياسة واضحة.

3. `nexuswa-webhook`
   - تستقبل أحداث NexusWA.
   - تتحقق من signature أو secret.
   - تحدث حالة الرسالة.
   - تحفظ الوارد لاحقا.

#### ج. إعدادات Secrets

تخزن في Supabase secrets أو بيئة السيرفر فقط:

- `NEXUSWA_BASE_URL`
- `NEXUSWA_API_KEY`
- `NEXUSWA_INSTANCE_ID`
- `NEXUSWA_WEBHOOK_SECRET`
- `WHATSAPP_INTEGRATION_ENABLED`

لا تخزن هذه القيم في React أو `.env` الخاص بالواجهة.

---

## 5. التصميم المقترح للجداول

### 5.1 جدول الإعدادات

```sql
CREATE TABLE public.whatsapp_integration_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  is_enabled boolean NOT NULL DEFAULT false,
  mode text NOT NULL DEFAULT 'internal_only'
    CHECK (mode IN ('internal_only', 'transactional_customers', 'full')),
  default_country_code text NOT NULL DEFAULT '20',
  daily_global_limit integer NOT NULL DEFAULT 100,
  hourly_global_limit integer NOT NULL DEFAULT 30,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
```

ملاحظة: لا نضع API key هنا. المفاتيح في secrets.

### 5.2 جدول القوالب

```sql
CREATE TABLE public.whatsapp_message_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL,
  audience text NOT NULL CHECK (audience IN ('employee', 'manager', 'customer', 'supplier')),
  language text NOT NULL DEFAULT 'ar',
  body_template text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  requires_consent boolean NOT NULL DEFAULT true,
  min_priority public.notification_priority NOT NULL DEFAULT 'medium',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (event_key, audience, language)
);
```

### 5.3 جدول outbox

```sql
CREATE TABLE public.whatsapp_outbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id uuid REFERENCES public.notifications(id) ON DELETE SET NULL,
  event_key text,
  recipient_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  recipient_entity_type text CHECK (recipient_entity_type IN ('profile', 'employee', 'customer', 'supplier', 'manual')),
  recipient_entity_id uuid,
  recipient_phone text NOT NULL,
  normalized_phone text NOT NULL,
  message_type text NOT NULL DEFAULT 'text',
  message_body text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}',
  external_id text UNIQUE,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'cancelled', 'skipped')),
  priority public.notification_priority NOT NULL DEFAULT 'medium',
  attempts integer NOT NULL DEFAULT 0,
  max_attempts integer NOT NULL DEFAULT 3,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  failed_at timestamptz,
  last_error_code text,
  last_error_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_whatsapp_outbox_pending
  ON public.whatsapp_outbox (status, next_attempt_at, priority);

CREATE INDEX idx_whatsapp_outbox_entity
  ON public.whatsapp_outbox (recipient_entity_type, recipient_entity_id);
```

### 5.4 جدول محاولات الإرسال

```sql
CREATE TABLE public.whatsapp_delivery_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  outbox_id uuid NOT NULL REFERENCES public.whatsapp_outbox(id) ON DELETE CASCADE,
  attempt_number integer NOT NULL,
  request_payload jsonb NOT NULL DEFAULT '{}',
  response_status integer,
  response_body jsonb,
  success boolean NOT NULL DEFAULT false,
  error_code text,
  error_message text,
  processed_at timestamptz NOT NULL DEFAULT now()
);
```

### 5.5 جدول الموافقة/الاشتراك لاحقا

```sql
CREATE TABLE public.whatsapp_contact_consent (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type text NOT NULL CHECK (entity_type IN ('customer', 'supplier', 'employee')),
  entity_id uuid NOT NULL,
  phone text NOT NULL,
  normalized_phone text NOT NULL,
  consent_status text NOT NULL DEFAULT 'unknown'
    CHECK (consent_status IN ('unknown', 'opted_in', 'opted_out')),
  consent_source text,
  consent_at timestamptz,
  opted_out_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (entity_type, entity_id, normalized_phone)
);
```

---

## 6. عدم تعديل enum الحالي كمرحلة أولى

في EDARA يوجد enum:

```ts
type NotificationDeliveryChannel = 'in_app' | 'push' | 'email'
```

ويوجد enum في DB:

```sql
notification_delivery_channel = in_app, push, email
```

تعديل enum في Postgres ممكن لكنه حساس في الإنتاج. لذلك في المرحلة الأولى لا نضيف `whatsapp` إلى enum الحالي. الأفضل:

- نستخدم جداول واتساب منفصلة.
- نترك نظام notification_delivery_log كما هو.
- نربط `whatsapp_outbox.notification_id` بالإشعار.

بعد استقرار المرحلة الأولى يمكن التفكير في إضافة channel جديدة، لكن ليس ضروريا.

---

## 7. تدفق العمل المقترح

### 7.1 إرسال إشعار داخلي إلى موظف

```text
حدث HR/Finance/Sales يحدث في EDARA
  -> trigger أو service يستدعي dispatch-notification
  -> dispatch-notification ينشئ in-app notification
  -> إذا واتساب مفعّل لهذا الحدث والمستلم لديه رقم
  -> enqueue-whatsapp-message يضيف إلى whatsapp_outbox
  -> worker يرسل عبر NexusWA
  -> يسجل sent/failed
```

### 7.2 إرسال رسالة إلى عميل

```text
أمر بيع تم تأكيده
  -> EDARA ينجز التأكيد بالكامل
  -> event مستقل بعد التأكيد
  -> تحقق من سياسة القالب والموافقة
  -> إضافة outbox
  -> إرسال لاحق
```

لا يتم إرسال رسائل عملاء في البداية إلا في أحداث قليلة ومصرح بها.

### 7.3 استقبال رسالة واردة

مرحلة لاحقة فقط:

```text
رسالة واردة إلى NexusWA
  -> NexusWA webhook
  -> EDARA nexuswa-webhook
  -> حفظ في whatsapp_inbound_messages
  -> محاولة ربط بالعميل عبر normalized_phone
  -> عرض في نشاط/Customer 360
```

لا يتم تنفيذ أي أمر وارد مثل "اعتمد" أو "الغ طلب" في المراحل الأولى.

---

## 8. سياسة اختيار الأحداث

### 8.1 المرحلة الأولى: داخلي فقط

الأحداث الآمنة:

- `hr.leave.requested`
- `hr.leave.approved`
- `hr.leave.rejected`
- `hr.advance.requested`
- `hr.advance.approved`
- `hr.advance.rejected`
- `finance.expense.submitted`
- `finance.expense.approved`
- `finance.expense.rejected`
- `inventory.stock.low`
- `inventory.stock.out`
- `inventory.transfer.requested`
- `sales.order.confirmed` للمدير/المندوب فقط، وليس العميل.
- `purchase.invoice.received`
- `purchase.invoice.billed`

لا ترسل تفاصيل حساسة كاملة. الرسالة تكون مختصرة:

```text
إشعار من EDARA:
طلب صرف جديد يحتاج مراجعتك.
افتح النظام لمراجعة التفاصيل.
```

### 8.2 المرحلة الثانية: عملاء بشكل محدود

أحداث مقترحة:

- تأكيد أمر بيع.
- إشعار بتجهيز/تسليم.
- تذكير سداد.
- إيصال دفع.
- إعادة تنشيط عميل خامد.

الشروط:

- رقم العميل موجود وصالح.
- الرسالة ليست spam.
- وجود opt-out.
- معدل إرسال محدود.
- لا إرسال جماعي كبير في البداية.

### 8.3 المرحلة الثالثة: الموردون

- إشعار بتحويل مستحق.
- طلب مستند ناقص.
- تأكيد استلام.

### 8.4 المرحلة الرابعة: الوارد والـ CRM

- حفظ المحادثات.
- ربط الرسائل بالعميل.
- إنشاء activity يدوي أو مقترح.
- تصنيف الرسائل.

لا ينفذ النظام أوامر تشغيلية تلقائيا إلا بعد تصميم منفصل للموافقات.

---

## 9. سياسة الخصوصية والبيانات

### 9.1 بيانات لا ترسل عبر واتساب في البداية

- صافي الراتب بالكامل.
- تفاصيل قيود محاسبية.
- أرصدة خزائن.
- كشوف تفصيلية.
- بيانات دخول.
- كلمات مرور.
- روابط مباشرة بدون صلاحية.
- بيانات عملاء آخرين.

### 9.2 بيانات مسموحة بحذر

- رقم الطلب.
- اسم العميل.
- حالة الطلب.
- مبلغ عام إذا كان موجها للعميل نفسه.
- تذكير سداد مختصر.
- تنبيه إداري داخلي بدون تفاصيل حساسة.

### 9.3 الروابط

أي رابط داخل الرسالة يجب أن يفتح EDARA ويتطلب تسجيل دخول. لا نعتمد على سرية الرابط.

---

## 10. سياسة أرقام الهاتف

يجب بناء دالة موحدة لتطبيع أرقام مصر:

أمثلة:

- `01012345678` -> `201012345678`
- `+201012345678` -> `201012345678`
- `00201012345678` -> `201012345678`

قواعد:

- إزالة المسافات والرموز.
- رفض الرقم إذا كان أقل من 10 أو أكبر من 15 رقم.
- تخزين الأصل والتطبيع.
- عدم الإرسال لرقم غير صالح.

---

## 11. سياسة Rate Limit

حتى مع وجود anti-ban داخل NexusWA، يجب أن يكون EDARA لديه حده الخاص.

مقترح البداية:

- داخلي: 30 رسالة/ساعة، 100 رسالة/يوم.
- عملاء: 20 رسالة/ساعة، 100 رسالة/يوم في أول أسبوع.
- إرسال جماعي: معطل في البداية.
- تذكيرات السداد: batch صغير، مثلا 10 رسائل كل 10 دقائق.

لا تعتمد فقط على NexusWA لأن EDARA يجب أن يعرف مسبقا هل سيولد ضغطا كبيرا.

---

## 12. سياسة إعادة المحاولة

حالات مؤقتة:

- timeout
- 5xx
- NexusWA offline
- instance disconnected

إعادة المحاولة:

```text
attempt 1: immediately
attempt 2: after 5 minutes
attempt 3: after 30 minutes
then failed
```

حالات نهائية لا يعاد إرسالها:

- رقم غير صالح.
- blacklisted.
- القالب غير مفعل.
- لا توجد موافقة.
- integration disabled.

---

## 13. خطة حماية NexusWA قبل النشر

قبل فتح NexusWA للإنترنت:

1. تغيير كل الأسرار في `.env`.
2. عدم استخدام القيم الافتراضية مثل `nexuswa_secret`.
3. تفعيل HTTPS.
4. وضع firewall يسمح فقط:
   - منفذ 443 عام.
   - منفذ SSH من IP موثوق.
   - PostgreSQL/Redis/Minio غير مكشوفة للإنترنت.
5. عدم نشر Swagger علنا أو حمايته.
6. حماية dashboard بكلمة مرور قوية.
7. تفعيل CORS فقط لمجالات محددة.
8. عمل backups للـ PostgreSQL وملفات `wa-sessions`.
9. health check دائم.
10. مراقبة disconnect للرقم.

---

## 14. النشر والاستضافة

### 14.1 متطلبات NexusWA الدنيا

لبيئة صغيرة:

- 1 vCPU كحد أدنى.
- 1 GB RAM قد يعمل بصعوبة.
- 2 GB RAM أفضل.
- 20-40 GB disk.
- Docker + Docker Compose.
- Public HTTPS endpoint.
- persistent storage للـ PostgreSQL وRedis وMinio وwa-sessions.

الأفضل:

- 2 GB RAM.
- Ubuntu LTS.
- Docker Compose.
- Caddy أو Nginx Proxy Manager لإصدار HTTPS بسهولة.

### 14.2 خيار 1: VPS واحد مدفوع صغير - موصى به

المزايا:

- أسهل في الفهم.
- كل شيء في مكان واحد.
- مناسب لـ Docker Compose.
- لا يوجد تعقيد خدمات متعددة.
- يمكن أخذ backup من مجلد واحد.

العيوب:

- يحتاج إعداد أول مرة.
- يحتاج متابعة تحديثات وأمان بسيطة.

مناسب لك إذا كنت تريد أقل تعقيد مستقبلي.

#### DigitalOcean

حسب صفحة DigitalOcean الرسمية، Basic Droplets تبدأ من 4 دولار شهريا، وخيار 1GB RAM بسعر 6 دولار شهريا، وخيار 2GB بسعر 12 دولار شهريا. صفحة الوثائق تذكر أيضا أن Droplets تحاسب بالثانية من 2026 وأن الـ Droplet المطفأ يظل محجوزا وتستمر محاسبته.  
المصدر: https://www.digitalocean.com/pricing/droplets و https://docs.digitalocean.com/products/droplets/details/pricing/

تقييم:

- أسهل من Oracle.
- واجهة واضحة.
- تكلفة متوقعة.
- أوصي بـ 2GB RAM إن أمكن.

#### Hetzner

Hetzner عادة منخفض التكلفة جدا، لكن الأسعار تغيرت في 2026 حسب مستندات Hetzner الرسمية الخاصة بتعديل الأسعار، وصفحة الوثائق تذكر أن أسعار Cloud تختلف حسب نوع السيرفر ولا تشمل public IP في بعض الحالات، وتوجه لصفحة cloud الحالية.  
المصدر: https://docs.hetzner.com/cloud/servers/overview و https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/

تقييم:

- ممتاز من ناحية السعر مقابل الموارد.
- قد يكون أقل سهولة من DigitalOcean للمبتدئ.
- جيد جدا إذا كان الحساب متاحا والدفع مناسب.

### 14.3 خيار 2: Oracle Always Free - مجاني لكن ليس الأسهل

Oracle تذكر رسميا أن Always Free يشمل موارد Compute، منها Ampere A1 بحدود شهرية تعادل 4 OCPUs و24GB RAM، و200GB Block Volume، لكن هناك ملاحظة مهمة: قد تظهر مشكلة `out of host capacity`، كما أن Oracle قد تسترد instances الخاملة إذا كانت مؤشرات الاستخدام منخفضة 7 أيام.  
المصدر: https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm

المزايا:

- يمكن أن يكون مجانيا فعلا.
- الموارد قوية مقارنة باحتياج NexusWA.
- مناسب إذا نجح إنشاء instance.

العيوب:

- التسجيل والتفعيل قد يكونان مزعجين.
- السعة غير مضمونة دائما.
- يحتاج فهم firewall وVCN أكثر.
- احتمال reclaim للـ idle instances.
- معمارية ARM قد تحتاج التأكد من توافق Docker images.

التقييم:

- خيار جيد إذا قبلت التعقيد الأولي.
- ليس الخيار الأول إذا كان الهدف "سلاسة وسهولة".

### 14.4 خيار 3: Railway

Railway حسب وثائقه يستخدم اشتراك + استخدام موارد، والخطة Hobby بسعر 5 دولار شهريا، مع احتساب الاشتراك ضمن الاستخدام. كما أن Railway يبني من Dockerfile أو Railpack ويدعم النشر من GitHub.  
المصدر: https://docs.railway.com/pricing و https://docs.railway.com/deployments/reference

المزايا:

- تجربة نشر سهلة.
- يدعم قواعد وRedis كخدمات.
- جيد للتجارب.

العيوب:

- التكلفة قد تزيد حسب RAM/CPU/storage/egress.
- عدة خدمات تعني فاتورة غير واضحة للمبتدئ.
- جلسة واتساب وملفات session تحتاج persistent volume.

التقييم:

- مناسب للتجربة، ليس الخيار الأول للإنتاج منخفض التكلفة.

### 14.5 خيار 4: Render

Render يدعم Docker، ويدعم web services، ويذكر في وثائقه أن filesystem افتراضي ephemeral وأن البيانات التي يكتبها التطبيق تضيع مع deploy إلا إذا استخدمت datastore أو persistent disk.  
المصدر: https://render.com/docs/docker و https://render.com/docs/deploys/

المزايا:

- سهل نسبيا.
- Docker support جيد.
- auto-deploy من GitHub.

العيوب:

- persistent session مهم جدا لـ WhatsApp.
- الخطة المجانية قد لا تناسب خدمة تحتاج تشغيل دائم.
- تحتاج Datastore/Persistent disk.

التقييم:

- ليس الخيار الأول لـ NexusWA بسبب طبيعة الجلسات والتخزين.

### 14.6 خيار 5: Cloudflare Tunnel إلى جهاز محلي

الفكرة: تشغيل NexusWA على جهاز داخل الشركة، وربطه بـ Cloudflare Tunnel.

المزايا:

- تكلفة منخفضة جدا.
- لا تنقل sessions إلى سحابة.
- مناسب للتجربة.

العيوب:

- الجهاز يجب أن يعمل دائما.
- انقطاع كهرباء أو إنترنت يوقف الخدمة.
- ليس Production grade إلا مع UPS وإنترنت مستقر.

التقييم:

- جيد كمرحلة تجريبية أو طوارئ.
- ليس الأفضل إذا أردت خادم دائم.

---

## 15. توصية الاستضافة النهائية

### التوصية العملية الأولى

VPS واحد 2GB RAM مع Docker Compose.

ترتيب الخيارات:

1. DigitalOcean 2GB إذا كانت السهولة أهم من أقل سعر.
2. Hetzner 2GB/4GB إذا كان السعر أهم وتقبل إعدادا أكثر قليلا.
3. Oracle Always Free إذا أردت محاولة مجانية وتقبل تعقيد التسجيل والتوافر.
4. Railway/Render للتجربة فقط.

### لماذا VPS؟

لأن NexusWA ليس مجرد API stateless. هو يحتاج:

- جلسة WhatsApp مستمرة.
- ملفات `wa-sessions`.
- PostgreSQL.
- Redis.
- Minio أو بديل تخزين.
- logs.
- تحكم في restart.

VPS + Docker Compose هو أبسط شكل يجمع كل ذلك.

---

## 16. تصميم نشر مبسط على VPS

### 16.1 شكل الخادم

```text
Ubuntu VPS
  /opt/nexuswa
    docker-compose.yml
    backend/
    frontend/
    data/
      postgres/
      redis/
      minio/
      wa-sessions/
    backups/

  Caddy/Nginx
    api.your-domain.com -> backend:3000
    wa.your-domain.com  -> frontend:3001
```

### 16.2 الخدمات

- `nexuswa-backend`
- `nexuswa-frontend`
- `postgres`
- `redis`
- `minio`
- `caddy` أو `nginx-proxy-manager`

### 16.3 المنافذ

المكشوف للعالم:

- 80/443 فقط.

غير مكشوف:

- 3000
- 3001
- 5432
- 6379
- 9000
- 9001

### 16.4 HTTPS

الأبسط:

- استخدام Caddy لأنه يصدر شهادات HTTPS تلقائيا.

مثال Caddyfile:

```text
api.example.com {
  reverse_proxy nexuswa-backend:3000
}

wa.example.com {
  reverse_proxy nexuswa-frontend:3001
}
```

---

## 17. تعديلات مطلوبة على NexusWA قبل الإنتاج

### 17.1 Dockerfile

المشروع الحالي لديه Docker Compose للخدمات الداعمة فقط. نحتاج إضافة:

- Dockerfile للـ backend.
- Dockerfile للـ frontend.
- docker-compose.prod.yml.
- `.dockerignore`.

### 17.2 Health check

Backend لديه `/health`. يجب استخدامه في compose.

### 17.3 تخزين sessions

يجب تثبيت `backend/wa-sessions` كـ volume دائم.

### 17.4 حماية Swagger

في الإنتاج:

- إما تعطيل `/docs`.
- أو حمايته basic auth / IP allowlist.

### 17.5 تشديد CORS

لا يكون:

```text
*
```

يكون فقط:

```text
https://wa.example.com
https://edara.example.com
```

### 17.6 Webhook signature

NexusWA يرسل HMAC في webhooks. EDARA يجب أن يتحقق منه.

---

## 18. تعديلات مطلوبة على EDARA

كلها إضافية:

### 18.1 Migration جديدة

مثلا:

```text
supabase/migrations/121_whatsapp_integration_foundation.sql
```

تضيف الجداول فقط.

### 18.2 Edge Functions

```text
supabase/functions/enqueue-whatsapp-message/index.ts
supabase/functions/process-whatsapp-outbox/index.ts
supabase/functions/nexuswa-webhook/index.ts
```

### 18.3 UI لاحق

صفحة إعدادات صغيرة:

- تفعيل/تعطيل.
- اختبار الاتصال.
- عرض حالة NexusWA.
- عرض آخر رسائل فاشلة.
- إدارة القوالب.

لكن في أول تنفيذ يمكن تأجيل UI والاكتفاء بإعدادات DB/secrets لتقليل المخاطر.

---

## 19. خطة تنفيذ آمنة على مراحل

### المرحلة 0: تحضير بدون تشغيل

الهدف: لا تأثير على الإنتاج.

الأعمال:

- إنشاء وثيقة التصميم.
- تحديد events المسموحة.
- تحديد القوالب.
- تحديد أرقام اختبار.
- تجهيز NexusWA staging.

معيار النجاح:

- لا يوجد أي تغيير في EDARA production.

### المرحلة 1: بنية EDARA معطلة افتراضيا

الأعمال:

- إضافة جداول outbox/templates/settings.
- إضافة RLS.
- إضافة Edge Functions.
- `is_enabled = false`.

معيار النجاح:

- build/test ناجح.
- لا يتم إرسال أي رسالة.
- لا تظهر أخطاء في العمليات الحالية.

### المرحلة 2: إرسال يدوي لاختبار رقم واحد

الأعمال:

- تفعيل فقط لمستخدم اختبار.
- إرسال رسالة اختبار يدوية.
- التأكد من logging.

معيار النجاح:

- الرسالة تصل.
- الفشل يسجل ولا يكسر أي شيء.

### المرحلة 3: حدث داخلي واحد

اختيار حدث منخفض المخاطر:

- `hr.leave.requested` أو `finance.expense.submitted`.

الأعمال:

- إرسال داخلي لمدير واحد.
- مراقبة 3-7 أيام.

معيار النجاح:

- لا تأثير على أداء EDARA.
- لا رسائل مكررة.
- لا تسريب بيانات.

### المرحلة 4: توسيع داخلي محدود

إضافة:

- HR approvals.
- Finance approvals.
- Inventory low stock.

معيار النجاح:

- أقل من 1% فشل غير مفهوم.
- إمكانية إيقاف فورية.

### المرحلة 5: عملاء Transactional

إضافة:

- تأكيد طلب بيع.
- إيصال دفع.
- تذكير سداد محدود.

معيار النجاح:

- opt-out يعمل.
- لا إرسال جماعي.
- لا شكاوى.

### المرحلة 6: وارد واتساب

إضافة:

- حفظ incoming messages.
- ربط بالعميل.
- عرض في Customer Detail أو Activities.

بدون:

- إنشاء عمليات تلقائية.
- اعتماد مالي.
- تغيير حالة طلب.

---

## 20. خطة الاختبار

### 20.1 اختبارات قاعدة البيانات

- إنشاء outbox row صالح.
- رفض رقم غير صالح.
- رفض event غير مفعل.
- RLS يمنع قراءة outbox لغير المصرح.
- retry count يعمل.
- status transitions صحيحة.

### 20.2 اختبارات Edge Function

- NexusWA online.
- NexusWA offline.
- API key خطأ.
- timeout.
- response 400.
- response 500.
- duplicate externalId.

### 20.3 اختبارات إنتاجية EDARA

لكل عملية:

- تأكيد أمر بيع.
- اعتماد مصروف.
- طلب إجازة.
- تحويل مخزني.

يجب التأكد:

- العملية تنجح حتى لو واتساب معطل.
- زمن العملية لا يزيد بشكل ملحوظ.
- لا rollback بسبب واتساب.

### 20.4 اختبارات عدم التكرار

- نفس الحدث لا يرسل مرتين.
- `external_id` فريد.
- retries لا تنشئ رسائل مكررة إذا NexusWA استقبل الطلب وحدث timeout.

### 20.5 اختبارات إيقاف فوري

- ضبط `is_enabled=false`.
- التأكد أن outbox لا يعالج.
- العمليات الأساسية مستمرة.

---

## 21. خطة rollback

لأن التنفيذ additive، rollback سهل:

### إيقاف فوري

```sql
UPDATE public.whatsapp_integration_settings
SET is_enabled = false;
```

### إيقاف worker

- تعطيل cron الخاص بـ `process-whatsapp-outbox`.
- إزالة secret مؤقتا.

### لا حاجة للتراجع عن جداول

الجداول لا تؤثر على النظام.

### إذا ظهر أثر غير متوقع

1. تعطيل integration.
2. إيقاف NexusWA.
3. مراجعة logs.
4. لا نلمس جداول EDARA الأساسية.

---

## 22. خطة مراقبة وتشغيل

لوحة مراقبة مطلوبة لاحقا:

- حالة NexusWA health.
- حالة instance connected/disconnected.
- عدد pending.
- عدد failed آخر 24 ساعة.
- آخر خطأ.
- عدد الرسائل اليومية.
- تحذير عند الاقتراب من الحد.

تنبيهات:

- NexusWA down.
- WhatsApp disconnected.
- failed rate > 10%.
- pending > 100.
- no successful send for 30 minutes.

---

## 23. سياسة النسخ الاحتياطي

### 23.1 NexusWA

نسخ يومي:

- PostgreSQL dump.
- `wa-sessions`.
- Minio data إذا تستخدم media.
- `.env` مشفر أو محفوظ في password manager.

احتفاظ:

- يومي 7 أيام.
- أسبوعي 4 أسابيع.

### 23.2 EDARA

لا تتغير سياسة EDARA الأساسية. فقط يمكن إضافة outbox إلى النسخ المعتاد.

---

## 24. مقارنة NexusWA مع WhatsApp Cloud API الرسمي

### NexusWA/Baileys

المزايا:

- تكلفة رسائل مباشرة شبه صفرية.
- لا يحتاج موافقة Meta templates.
- سريع للبدء.
- مناسب للإشعارات الداخلية والمنخفضة الحجم.

العيوب:

- غير رسمي.
- خطر disconnect أو ban.
- يحتاج إدارة session.
- لا يصلح لحملات كبيرة.

### WhatsApp Business Platform الرسمي

Meta تذكر أن منصة WhatsApp Business لديها فئات رسائل مثل marketing, utility, authentication, service، والتسعير يعتمد على المنصة وفئات الرسائل.  
المصدر: https://whatsappbusiness.com/products/platform-pricing

المزايا:

- رسمي.
- أفضل للإنتاج واسع النطاق.
- webhooks رسمية.
- أقل خطر حظر إذا التزمت السياسات.

العيوب:

- تكلفة.
- إعدادات Meta Business.
- قوالب وموافقات.
- تعقيد أكبر.

التوصية:

- ابدأ بـ NexusWA للرسائل الداخلية والتجريب المحدود.
- إذا أصبحت الرسائل جزءا حرجا مع العملاء أو حجمها زاد، خطط للهجرة إلى Cloud API الرسمي.

---

## 25. قائمة الوظائف ذات القيمة التجارية

### 25.1 Sales

- تأكيد أمر بيع للعميل.
- إشعار المندوب بتأكيد/رفض/تأخير.
- رابط معاينة أمر البيع.
- تنبيه العملاء المتأخرين.
- إشعار إعادة جدولة أو تسليم.

### 25.2 Credit and Collections

- تذكير سداد قبل الاستحقاق.
- تذكير بعد الاستحقاق.
- إشعار داخلي للمدير بتجاوز حد الائتمان.
- قوائم متابعة يومية للمندوب.

### 25.3 Finance

- طلب اعتماد مصروف.
- نتيجة اعتماد/رفض.
- تنبيهات قيود أو خزائن تحتاج مراجعة.
- إشعار دفع مورد.

### 25.4 Inventory

- نفاد مخزون.
- انخفاض مخزون.
- طلب تحويل.
- تأكيد استلام/شحن.

### 25.5 HR

- طلب إجازة.
- نتيجة الإجازة.
- طلب سلفة.
- نتيجة السلفة.
- تنبيه غياب/تأخير.
- إشعار جاهزية الراتب بدون تفاصيل حساسة.

### 25.6 Procurement

- استلام فاتورة شراء.
- اعتماد مالي.
- طلب مستندات من مورد.

### 25.7 Activities

- خطة زيارات يومية.
- تنبيه زيارة فائتة.
- متابعة عميل خامد.
- ربط رسالة واردة بنشاط.

---

## 26. خطة نشر مبسطة مقترحة للمستخدم غير الخبير

### اليوم 1: تجهيز الخادم

1. إنشاء VPS 2GB RAM.
2. اختيار Ubuntu LTS.
3. ربط domain فرعي:
   - `api-wa.company.com`
   - `wa.company.com`
4. تثبيت Docker.
5. تثبيت Caddy.

### اليوم 2: نشر NexusWA

1. رفع المشروع إلى GitHub private repo.
2. نسخ المشروع على السيرفر.
3. إنشاء `.env.production`.
4. تشغيل `docker compose`.
5. فتح dashboard.
6. إنشاء tenant/admin.
7. إنشاء instance.
8. مسح QR.
9. إرسال رسالة اختبار.

### اليوم 3: تأمين ومراقبة

1. Firewall.
2. HTTPS.
3. Backup script.
4. Health check.
5. تعطيل أو حماية Swagger.

### اليوم 4: ربط EDARA staging

1. إضافة secrets.
2. تفعيل outbox في staging.
3. تجربة رقم واحد.
4. اختبار فشل NexusWA.

### بعد أسبوع مراقبة

تفعيل production لمستخدمين داخليين محدودين.

---

## 27. قائمة تحقق قبل أي تنفيذ إنتاجي

- [ ] نسخة احتياطية حديثة من EDARA.
- [ ] لا يوجد تعديل في منطق الجداول الأساسية.
- [ ] كل migrations الجديدة additive.
- [ ] integration disabled by default.
- [ ] أسرار NexusWA في secrets فقط.
- [ ] NexusWA يعمل خلف HTTPS.
- [ ] PostgreSQL/Redis غير مكشوفين.
- [ ] رقم واتساب مخصص للشركة وليس رقم شخصي مهم.
- [ ] اختبار فشل NexusWA.
- [ ] اختبار إيقاف التكامل.
- [ ] اختبار عدم التكرار.
- [ ] تحديد القوالب المسموحة.
- [ ] تحديد الأحداث المسموحة.
- [ ] تحديد المسؤول عن QR/session.
- [ ] تحديد سياسة backup.

---

## 28. قرار Go / No-Go

### Go إذا:

- NexusWA مستقر 7 أيام في staging.
- الإرسال اليدوي يعمل.
- outbox لا يؤثر على العمليات.
- rollback مجرب.
- logs واضحة.
- المسؤولون موافقون على سياسات الخصوصية.

### No-Go إذا:

- NexusWA يحتاج QR متكرر.
- لا يوجد backup.
- لا يوجد HTTPS.
- لا توجد طريقة إيقاف فوري.
- الرسائل قد تحتوي بيانات حساسة.
- لا توجد سياسات rate limit.

---

## 29. الخلاصة النهائية

الربط آمن إذا نفذ كـ outbox اختياري معزول. لا يجب دمج واتساب داخل منطق EDARA الأساسي، ولا يجب أن يملك NexusWA أي قدرة على تغيير بيانات EDARA في المراحل الأولى.

أفضل مسار:

1. نشر NexusWA على VPS بسيط.
2. تأمينه وتشغيله أسبوعا كتجربة.
3. إضافة outbox في EDARA وهو معطل.
4. تفعيل رقم اختبار.
5. تفعيل أحداث داخلية محدودة.
6. التوسع تدريجيا.

بهذه الطريقة نحقق الاستفادة من واتساب بدون تعريض نظام إدارة الشركة لأي خلل تشغيلي.

---

## 30. المصادر المستخدمة في دراسة الاستضافة

- Oracle Always Free Resources: https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm
- DigitalOcean Droplet Pricing: https://www.digitalocean.com/pricing/droplets
- DigitalOcean Droplet Pricing Documentation: https://docs.digitalocean.com/products/droplets/details/pricing/
- Railway Pricing Documentation: https://docs.railway.com/pricing
- Railway Deployments Documentation: https://docs.railway.com/deployments/reference
- Render Docker Documentation: https://render.com/docs/docker
- Render Deploys Documentation: https://render.com/docs/deploys/
- Hetzner Cloud Servers Overview: https://docs.hetzner.com/cloud/servers/overview
- Hetzner Price Adjustment: https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/
- WhatsApp Business Platform Pricing: https://whatsappbusiness.com/products/platform-pricing
