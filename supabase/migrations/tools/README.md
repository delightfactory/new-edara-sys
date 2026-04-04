# أدوات توليد Migration أمان RLS

## الفلسفة

**مصدر الحقيقة = قاعدة البيانات الحية، لا ملفات migrations التاريخية.**

بدلاً من تحليل 96 ملف migration والبحث عن "آخر سياسة فعالة"،  
نستخرج السياسات **كما هي مطبّقة الآن** من `pg_policies`  
ثم نُحوّل **فقط ما يحتاج تحويلاً** دون المساس بأي منطق صلاحيات.

---

## الخطوات (بالترتيب)

### الخطوة 1 — استخراج snapshot من قاعدة البيانات

1. افتح **Supabase Dashboard** → **SQL Editor**
2. انسخ محتوى ملف `01_extract_policies.sql` وشغّله
3. ستظهر نتيجة تحتوي عمود `policies_snapshot` بقيمة JSON واحدة كبيرة
4. انسخ قيمة JSON كاملة (ابدأ من `[` وانته بـ `]`)
5. احفظها في ملف جديد: `supabase/migrations/tools/policies_snapshot.json`

> ⚠️ هذا الاستعلام **قراءة فقط** — لا يُغيّر أي شيء في قاعدة البيانات.

---

### الخطوة 2 — تشغيل مولّد الـ Migration

```powershell
cd c:\Users\HP\OneDrive\Desktop\new-edara-sys
node supabase/migrations/tools/02_generate_rls_migration.js
```

سيُنتج ملفين في مجلد `tools/output/`:

| الملف | المحتوى |
|-------|---------|
| `66_rls_initplan_safe.sql` | Migration جاهز للتطبيق |
| `policies_diff_report.md` | تقرير مقارنة قبل/بعد لكل سياسة |

---

### الخطوة 3 — مراجعة التقرير قبل التطبيق

افتح `tools/output/policies_diff_report.md` وتحقق من:

- [ ] أسماء الصلاحيات **لم تتغير** (مثلاً `finance.expenses.read` بقي كما هو)
- [ ] المنطق الشرطي (AND/OR) **لم يتغير**
- [ ] سياسات `service_role` ظهرت في قسم "مستثناة"
- [ ] عدد السياسات المُحوَّلة معقول (يجب أن يكون أكثر من 200)

---

### الخطوة 4 — تطبيق Migration 64 أولاً (ANALYZE)

قبل أي تغيير في RLS، طبّق migration الآمن تماماً:

```sql
-- في Supabase SQL Editor
-- انسخ محتوى 64_performance_analyze_refresh.sql وشغّله
```

---

### الخطوة 5 — تطبيق migration الجديد

بعد مراجعة التقرير والتأكد من صحته:

```sql
-- في Supabase SQL Editor
-- انسخ محتوى tools/output/66_rls_initplan_safe.sql وشغّله
```

أو عبر Supabase CLI:
```bash
supabase db push
```

---

## ضمانات الأمان

| الضمان | الآلية |
|--------|--------|
| لا تغيير في أسماء الصلاحيات | المولّد يستخدم regex فقط على `auth.uid()` لا على أسماء الصلاحيات |
| سياسات service_role محمية | تُستثنى تلقائياً من أي تحويل |
| سياسات anon محمية | تُستثنى تلقائياً |
| Transaction آمنة | الملف المُولَّد يحتوي `BEGIN;` / `COMMIT;` صريحاً |
| المصدر هو الحالة الحية | pg_policies = ما هو مطبّق فعلاً، لا تاريخ migrations |

---

## قواعد التحويل (فقط هذه)

```
auth.uid()                          →  (SELECT auth.uid())
check_permission(auth.uid(), 'X')   →  (SELECT check_permission((SELECT auth.uid()), 'X'))
```

لا يُغيَّر أي شيء آخر: لا أسماء صلاحيات، لا منطق AND/OR، لا WITH CHECK، لا roles.
