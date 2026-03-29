-- ============================================================
-- Migration 19d: HR Permissions Fix
-- إضافة الصلاحيات الناقصة في جدول role_permissions
-- 
-- المشكلة: الكود يستخدم صلاحيات HR لم تُضَف أبداً لـ role_permissions:
--   hr.employees.edit, hr.attendance.checkin, hr.attendance.edit
--   hr.leaves.request, hr.leaves.approve, hr.advances.create
--   hr.advances.approve, hr.permissions.approve, hr.commissions.create
--   hr.attendance.create (مستخدمة في RLS لكن غير موجودة في roles)
--
-- آمن: يستخدم ON CONFLICT DO NOTHING — لا يُعدِّل أي شيء موجود
--      لا يُعيد تعريف أي RLS أو function أو trigger
-- ============================================================

-- ──────────────────────────────────────────────────────────────
-- 1. hr_manager — مدير الموارد البشرية
--    يجب أن يمتلك كامل صلاحيات HR:
--    - تعديل الموظفين (كان ينقصه employees.edit)
--    - تسجيل الحضور وتعديله (كانت تنقصه attendance.checkin, edit, create)
--    - اعتماد الإجازات والأذونات (كانت تنقصه leaves.approve, permissions.approve)
--    - طلب الإجازات على نفسه (leaves.request)
--    - إنشاء السلف واعتمادها (advances.create, approve)
--    - إدارة العمولات (commissions.create)
-- ──────────────────────────────────────────────────────────────
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm
FROM roles r
CROSS JOIN (VALUES
  ('hr.employees.edit'),        -- تعديل بيانات الموظف
  ('hr.employees.update'),      -- مرادف للتعديل (مستخدم في RLS)
  ('hr.employees.delete'),      -- حذف الموظف (مستخدم في RLS)
  ('hr.attendance.checkin'),    -- تسجيل الحضور
  ('hr.attendance.create'),     -- إنشاء سجل حضور (مستخدم في RLS)
  ('hr.attendance.edit'),       -- تعديل يدوي للحضور
  ('hr.attendance.approve'),    -- اعتماد تعديل الحضور (مستخدم في RLS)
  ('hr.leaves.read'),           -- قراءة الإجازات (مستخدم في RLS)
  ('hr.leaves.create'),         -- إنشاء طلب إجازة (مستخدم في RLS)
  ('hr.leaves.request'),        -- طلب إجازة (مستخدم في الكود)
  ('hr.leaves.approve'),        -- اعتماد طلبات الإجازة
  ('hr.advances.read'),         -- قراءة السلف (مستخدم في RLS)
  ('hr.advances.create'),       -- إنشاء طلب سلفة
  ('hr.advances.approve'),      -- اعتماد وصرف السلف
  ('hr.permissions.approve'),   -- اعتماد أذونات الانصراف
  ('hr.commissions.create'),    -- إنشاء أهداف العمولات
  ('hr.reports.view'),          -- تقارير HR
  ('hr.settings.update')        -- تعديل إعدادات HR (مستخدم في RLS)
) AS p(perm)
WHERE r.name = 'hr_manager'
ON CONFLICT DO NOTHING;

-- ──────────────────────────────────────────────────────────────
-- 2. ceo — المدير التنفيذي
--    يرى كل شيء في HR + يعتمد الإجازات والسلف
-- ──────────────────────────────────────────────────────────────
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm
FROM roles r
CROSS JOIN (VALUES
  ('hr.leaves.read'),
  ('hr.leaves.approve'),
  ('hr.advances.read'),
  ('hr.advances.approve'),
  ('hr.attendance.read'),
  ('hr.reports.view')
) AS p(perm)
WHERE r.name = 'ceo'
ON CONFLICT DO NOTHING;

-- ──────────────────────────────────────────────────────────────
-- 3. branch_manager — مدير الفرع
--    يحتاج: اعتماد إجازات موظفي فرعه + اعتماد سلفهم
--    + قراءة السلف + اعتماد الأذونات
-- ──────────────────────────────────────────────────────────────
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm
FROM roles r
CROSS JOIN (VALUES
  ('hr.leaves.read'),
  ('hr.leaves.approve'),        -- اعتماد طلبات الإجازة
  ('hr.advances.read'),
  ('hr.advances.approve'),      -- اعتماد السلف (pending_supervisor → pending_hr)
  ('hr.permissions.approve'),   -- اعتماد أذونات الانصراف
  ('hr.attendance.checkin'),    -- تسجيل حضوره الخاص
  ('hr.leaves.request'),        -- طلب إجازة لنفسه
  ('hr.advances.create')        -- طلب سلفة لنفسه
) AS p(perm)
WHERE r.name = 'branch_manager'
ON CONFLICT DO NOTHING;

-- ──────────────────────────────────────────────────────────────
-- 4. accountant — المحاسب
--    يحتاج: اعتماد وصرف السلف (من migration 19c disburse_employee_advance)
--    + قراءة السلف للمراجعة المالية
-- ──────────────────────────────────────────────────────────────
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm
FROM roles r
CROSS JOIN (VALUES
  ('hr.advances.read'),         -- قراءة السلف للمراجعة
  ('hr.advances.approve'),      -- صرف السلف (يستدعي disburse_employee_advance)
  ('finance.payments.create')   -- مطلوب لصرف السلفة عبر الخزنة (موجود مسبقاً)
) AS p(perm)
WHERE r.name = 'accountant'
ON CONFLICT DO NOTHING;

-- ──────────────────────────────────────────────────────────────
-- 5. sales_rep — مندوب المبيعات
--    الموظف الميداني: يسجل حضوره + يطلب إجازة + يطلب سلفة
-- ──────────────────────────────────────────────────────────────
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm
FROM roles r
CROSS JOIN (VALUES
  ('hr.attendance.checkin'),    -- تسجيل الحضور GPS
  ('hr.attendance.create'),     -- إنشاء سجل الحضور (مستخدم في RLS)
  ('hr.leaves.request'),        -- طلب إجازة
  ('hr.leaves.create'),         -- إنشاء طلب إجازة (مستخدم في RLS)
  ('hr.leaves.read'),           -- رؤية طلباته
  ('hr.advances.create'),       -- طلب سلفة
  ('hr.advances.read')          -- رؤية سلفه
) AS p(perm)
WHERE r.name = 'sales_rep'
ON CONFLICT DO NOTHING;

-- ──────────────────────────────────────────────────────────────
-- 6. warehouse_keeper — أمين المخزن
--    نفس الموظف الميداني: حضور + إجازة + سلفة
-- ──────────────────────────────────────────────────────────────
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm
FROM roles r
CROSS JOIN (VALUES
  ('hr.attendance.checkin'),
  ('hr.attendance.create'),
  ('hr.leaves.request'),
  ('hr.leaves.create'),
  ('hr.leaves.read'),
  ('hr.advances.create'),
  ('hr.advances.read')
) AS p(perm)
WHERE r.name = 'warehouse_keeper'
ON CONFLICT DO NOTHING;

-- ──────────────────────────────────────────────────────────────
-- 7. sales_supervisor — مشرف المبيعات
--    يطلب إجازة/سلفة لنفسه + يعتمد إجازات فريقه + يسجل حضوره
-- ──────────────────────────────────────────────────────────────
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm
FROM roles r
CROSS JOIN (VALUES
  ('hr.attendance.checkin'),
  ('hr.attendance.create'),
  ('hr.leaves.request'),
  ('hr.leaves.create'),
  ('hr.leaves.read'),
  ('hr.leaves.approve'),        -- اعتماد إجازات فريقه
  ('hr.advances.create'),
  ('hr.advances.read'),
  ('hr.advances.approve'),      -- اعتماد السلف (pending_supervisor)
  ('hr.permissions.approve')    -- اعتماد أذونات الانصراف
) AS p(perm)
WHERE r.name = 'sales_supervisor'
ON CONFLICT DO NOTHING;

-- ──────────────────────────────────────────────────────────────
-- تحقق: طباعة عدد الصلاحيات الجديدة المُضافة
-- ──────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM role_permissions rp
  JOIN roles r ON r.id = rp.role_id
  WHERE rp.permission LIKE 'hr.%'
    AND r.name != 'super_admin';
    
  RAISE NOTICE '✅ Migration 19d: إجمالي صلاحيات HR في role_permissions = %', v_count;
END;
$$;
