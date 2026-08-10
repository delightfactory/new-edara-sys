# بيئة EDARA المحلية الدائمة لاختبار قاعدة البيانات

هذه البيئة نسخة PostgreSQL/Supabase محلية دائمة ومعزولة لاختبار الميجريشن
والدوال والحسابات قبل تطبيقها على الإنتاج.

## العزل

- اسم الحاوية: `edara-staging-db`.
- مساحة البيانات الدائمة: `edara_staging_pgdata`.
- الاتصال متاح من نفس الجهاز فقط على `127.0.0.1:55432`.
- لا تستخدم رابطًا أو مفتاحًا من الإنتاج، ولا يستطيع Vercel الوصول إليها.
- بياناتها حساسة لأنها مستعادة من نسخة إنتاج؛ لا تُرفع ملفات النسخ إلى Git.

## الأوامر

من PowerShell داخل المشروع:

```powershell
.\tools\local-staging\status.ps1
.\tools\local-staging\start.ps1
.\tools\local-staging\stop.ps1
.\tools\local-staging\apply-migration.ps1 -MigrationFile .\supabase\migrations\<file>.sql
```

لإرجاع البيئة إلى نقطة أساس من أرشيف كامل، يجب تمرير إقرار صريح لأن العملية
تحذف قاعدة `postgres` داخل حاوية الاختبار فقط ثم تستعيدها:

```powershell
.\tools\local-staging\reset-from-backup.ps1 `
  -BackupFile D:\production-backups\new-edara-sys\<backup>\full_database.dump `
  -ConfirmReset
```

## نطاق الاستخدام

هذه البيئة الحالية مناسبة لاختبار:

- ملفات الميجريشن.
- دوال PostgreSQL وقيود البيانات وRLS.
- حسابات الحضور والرواتب والتدفقات المحاسبية داخل القاعدة.

اختبار الواجهة وSupabase Auth/REST/Realtime من المتصفح يحتاج تشغيل حزمة
Supabase المحلية الكاملة. لا يُستخدم اتصال PostgreSQL المباشر كبديل مضلل لذلك.
