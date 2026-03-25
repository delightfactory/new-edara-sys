-- ==========================================
-- EDARA v2 — Migration 01: Foundation
-- Auth + Roles + Permissions + RLS + Audit
-- Idempotent: safe to run multiple times
-- ==========================================

-- ========== EXTENSIONS ==========
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ========== ENUMS ==========
DO $$ BEGIN
  CREATE TYPE user_status AS ENUM ('active', 'inactive', 'suspended');
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;

-- ========== HELPER FUNCTION ==========
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

-- ==========================================
-- TABLE: profiles (extends auth.users)
-- ==========================================
CREATE TABLE IF NOT EXISTS public.profiles (
  id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name     TEXT NOT NULL,
  email         TEXT,
  phone         TEXT,
  avatar_url    TEXT,
  status        user_status NOT NULL DEFAULT 'active',
  last_login_at TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_profiles_status ON profiles(status);

DROP TRIGGER IF EXISTS trg_profiles_updated_at ON profiles;
CREATE TRIGGER trg_profiles_updated_at
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
    NEW.email
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_on_auth_user_created ON auth.users;
CREATE TRIGGER trg_on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ==========================================
-- TABLE: roles
-- ==========================================
CREATE TABLE IF NOT EXISTS public.roles (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL UNIQUE,
  name_ar     TEXT NOT NULL,
  description TEXT,
  is_system   BOOLEAN NOT NULL DEFAULT false,
  color       TEXT DEFAULT '#6b7280',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ==========================================
-- TABLE: role_permissions
-- ==========================================
CREATE TABLE IF NOT EXISTS public.role_permissions (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role_id    UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  permission TEXT NOT NULL,
  UNIQUE(role_id, permission)
);
CREATE INDEX IF NOT EXISTS idx_role_perms_role ON role_permissions(role_id);
CREATE INDEX IF NOT EXISTS idx_role_perms_perm ON role_permissions(permission);

-- ==========================================
-- TABLE: user_roles
-- ==========================================
CREATE TABLE IF NOT EXISTS public.user_roles (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role_id     UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  branch_id   UUID NULL,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  assigned_by UUID REFERENCES auth.users(id),
  assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, role_id)
);
CREATE INDEX IF NOT EXISTS idx_user_roles_user   ON user_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_role   ON user_roles(role_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_active ON user_roles(user_id, is_active);

-- ==========================================
-- TABLE: user_permission_overrides
-- ==========================================
CREATE TABLE IF NOT EXISTS public.user_permission_overrides (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  permission  TEXT NOT NULL,
  granted     BOOLEAN NOT NULL,
  granted_by  UUID NOT NULL REFERENCES auth.users(id),
  reason      TEXT,
  expires_at  TIMESTAMPTZ NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, permission)
);
CREATE INDEX IF NOT EXISTS idx_overrides_user ON user_permission_overrides(user_id);

-- ==========================================
-- TABLE: company_settings
-- ==========================================
CREATE TABLE IF NOT EXISTS public.company_settings (
  key         TEXT PRIMARY KEY,
  value       TEXT NOT NULL,
  type        TEXT NOT NULL DEFAULT 'text'
                CHECK (type IN ('text','number','boolean','json')),
  description TEXT,
  category    TEXT NOT NULL DEFAULT 'general',
  is_public   BOOLEAN NOT NULL DEFAULT false,
  updated_by  UUID REFERENCES auth.users(id),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ==========================================
-- TABLE: feature_flags
-- ==========================================
CREATE TABLE IF NOT EXISTS public.feature_flags (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key         TEXT NOT NULL UNIQUE,
  is_enabled  BOOLEAN NOT NULL DEFAULT true,
  description TEXT,
  updated_by  UUID REFERENCES auth.users(id),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ==========================================
-- TABLE: audit_logs
-- ==========================================
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID REFERENCES auth.users(id),
  action      TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id   UUID,
  old_data    JSONB,
  new_data    JSONB,
  ip_address  TEXT,
  user_agent  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_user   ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_date   ON audit_logs(created_at DESC);

-- ==========================================
-- FUNCTION: check_permission()
-- القلب الأمني — يُستخدم في كل RLS policies
-- ==========================================
CREATE OR REPLACE FUNCTION public.check_permission(
  p_user_id UUID, p_permission TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_granted BOOLEAN;
BEGIN
  -- 1) Override فردي (أعلى أولوية)
  SELECT granted INTO v_granted
  FROM user_permission_overrides
  WHERE user_id = p_user_id
    AND permission = p_permission
    AND (expires_at IS NULL OR expires_at > now());
  IF FOUND THEN RETURN v_granted; END IF;

  -- 2) صلاحيات الدور (wildcard أو محددة)
  RETURN EXISTS (
    SELECT 1
    FROM role_permissions rp
    JOIN user_roles ur ON ur.role_id = rp.role_id
    WHERE ur.user_id = p_user_id
      AND (rp.permission = p_permission OR rp.permission = '*')
      AND ur.is_active = true
  );
END; $$;

-- ==========================================
-- FUNCTION: get_user_permissions()
-- ==========================================
CREATE OR REPLACE FUNCTION public.get_user_permissions(p_user_id UUID)
RETURNS TABLE(permission TEXT) LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Overrides (granted only)
  RETURN QUERY
    SELECT upo.permission FROM user_permission_overrides upo
    WHERE upo.user_id = p_user_id AND upo.granted = true
      AND (upo.expires_at IS NULL OR upo.expires_at > now());

  -- Role permissions (excluding revoked overrides)
  RETURN QUERY
    SELECT DISTINCT rp.permission FROM role_permissions rp
    JOIN user_roles ur ON ur.role_id = rp.role_id
    WHERE ur.user_id = p_user_id AND ur.is_active = true
      AND rp.permission NOT IN (
        SELECT upo2.permission FROM user_permission_overrides upo2
        WHERE upo2.user_id = p_user_id AND upo2.granted = false
          AND (upo2.expires_at IS NULL OR upo2.expires_at > now())
      );
END; $$;

-- ==========================================
-- FUNCTION: get_my_profile()
-- يُستدعى مرة واحدة عند تسجيل الدخول
-- يُرجع profile + roles + permissions
-- ==========================================
CREATE OR REPLACE FUNCTION public.get_my_profile()
RETURNS TABLE (
  id UUID, full_name TEXT, email TEXT, phone TEXT,
  avatar_url TEXT, status user_status,
  last_login_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ,
  roles JSONB, permissions TEXT[]
) LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id, p.full_name, p.email, p.phone, p.avatar_url, p.status,
    p.last_login_at, p.created_at, p.updated_at,
    COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'id', r.id, 'name', r.name, 'name_ar', r.name_ar, 'color', r.color
      ))
      FROM user_roles ur JOIN roles r ON r.id = ur.role_id
      WHERE ur.user_id = auth.uid() AND ur.is_active = true),
      '[]'::jsonb
    ) AS roles,
    COALESCE(
      ARRAY(SELECT gup.permission FROM get_user_permissions(auth.uid()) gup),
      '{}'::TEXT[]
    ) AS permissions
  FROM profiles p
  WHERE p.id = auth.uid();
END; $$;

-- ==========================================
-- RLS — تفعيل الأمان على كل الجداول
-- ==========================================
ALTER TABLE profiles                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE roles                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_permissions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_roles                ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_permission_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_settings          ENABLE ROW LEVEL SECURITY;
ALTER TABLE feature_flags             ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs                ENABLE ROW LEVEL SECURITY;

-- Feature Flags
DROP POLICY IF EXISTS "flags_select" ON feature_flags;
CREATE POLICY "flags_select" ON feature_flags FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "flags_write" ON feature_flags;
CREATE POLICY "flags_write" ON feature_flags FOR ALL USING (
  check_permission(auth.uid(), 'settings.update')
);

-- Profiles
DROP POLICY IF EXISTS "profiles_select" ON profiles;
CREATE POLICY "profiles_select" ON profiles FOR SELECT USING (
  id = auth.uid() OR check_permission(auth.uid(), 'auth.users.read')
);
DROP POLICY IF EXISTS "profiles_update" ON profiles;
CREATE POLICY "profiles_update" ON profiles FOR UPDATE USING (
  id = auth.uid() OR check_permission(auth.uid(), 'auth.users.update')
);

-- Roles
DROP POLICY IF EXISTS "roles_select" ON roles;
CREATE POLICY "roles_select" ON roles FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "roles_insert" ON roles;
CREATE POLICY "roles_insert" ON roles FOR INSERT WITH CHECK (
  check_permission(auth.uid(), 'auth.roles.create')
);
DROP POLICY IF EXISTS "roles_update" ON roles;
CREATE POLICY "roles_update" ON roles FOR UPDATE USING (
  NOT is_system AND check_permission(auth.uid(), 'auth.roles.update')
);
DROP POLICY IF EXISTS "roles_delete" ON roles;
CREATE POLICY "roles_delete" ON roles FOR DELETE USING (
  NOT is_system AND check_permission(auth.uid(), 'auth.roles.delete')
);

-- Role Permissions
DROP POLICY IF EXISTS "role_perms_select" ON role_permissions;
CREATE POLICY "role_perms_select" ON role_permissions FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "role_perms_insert" ON role_permissions;
CREATE POLICY "role_perms_insert" ON role_permissions FOR INSERT WITH CHECK (
  check_permission(auth.uid(), 'auth.roles.update')
);
DROP POLICY IF EXISTS "role_perms_update" ON role_permissions;
CREATE POLICY "role_perms_update" ON role_permissions FOR UPDATE USING (
  check_permission(auth.uid(), 'auth.roles.update')
);
DROP POLICY IF EXISTS "role_perms_delete" ON role_permissions;
CREATE POLICY "role_perms_delete" ON role_permissions FOR DELETE USING (
  check_permission(auth.uid(), 'auth.roles.update')
);

-- User Roles
DROP POLICY IF EXISTS "user_roles_select" ON user_roles;
CREATE POLICY "user_roles_select" ON user_roles FOR SELECT USING (
  user_id = auth.uid() OR check_permission(auth.uid(), 'auth.users.read')
);
DROP POLICY IF EXISTS "user_roles_insert" ON user_roles;
CREATE POLICY "user_roles_insert" ON user_roles FOR INSERT WITH CHECK (
  check_permission(auth.uid(), 'auth.users.update')
);
DROP POLICY IF EXISTS "user_roles_update" ON user_roles;
CREATE POLICY "user_roles_update" ON user_roles FOR UPDATE USING (
  check_permission(auth.uid(), 'auth.users.update')
);
DROP POLICY IF EXISTS "user_roles_delete" ON user_roles;
CREATE POLICY "user_roles_delete" ON user_roles FOR DELETE USING (
  check_permission(auth.uid(), 'auth.users.update')
);

-- User Permission Overrides
DROP POLICY IF EXISTS "overrides_select" ON user_permission_overrides;
CREATE POLICY "overrides_select" ON user_permission_overrides FOR SELECT USING (
  user_id = auth.uid() OR check_permission(auth.uid(), 'auth.users.read')
);
DROP POLICY IF EXISTS "overrides_write" ON user_permission_overrides;
CREATE POLICY "overrides_write" ON user_permission_overrides FOR ALL USING (
  check_permission(auth.uid(), 'auth.users.update')
);

-- Company Settings
DROP POLICY IF EXISTS "settings_select" ON company_settings;
CREATE POLICY "settings_select" ON company_settings FOR SELECT USING (
  is_public = true OR check_permission(auth.uid(), 'settings.read')
);
DROP POLICY IF EXISTS "settings_update" ON company_settings;
CREATE POLICY "settings_update" ON company_settings FOR UPDATE USING (
  check_permission(auth.uid(), 'settings.update')
);

-- Audit Logs (insert allowed for logged in, select restricted)
DROP POLICY IF EXISTS "audit_insert" ON audit_logs;
CREATE POLICY "audit_insert" ON audit_logs FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "audit_select" ON audit_logs;
CREATE POLICY "audit_select" ON audit_logs FOR SELECT USING (
  user_id = auth.uid() OR check_permission(auth.uid(), 'settings.audit.read')
);

-- ==========================================
-- SEED: System Roles
-- ==========================================
INSERT INTO roles (name, name_ar, is_system, color) VALUES
  ('super_admin',      'مدير النظام',         true, '#7c3aed'),
  ('ceo',              'المدير التنفيذي',     true, '#dc2626'),
  ('branch_manager',   'مدير فرع',            true, '#0284c7'),
  ('sales_supervisor', 'مشرف مبيعات',         true, '#d97706'),
  ('sales_rep',        'مندوب مبيعات',        true, '#16a34a'),
  ('warehouse_keeper', 'أمين مخزن',           true, '#6b7280'),
  ('accountant',       'محاسب',               true, '#0891b2'),
  ('hr_manager',       'مدير موارد بشرية',    true, '#9333ea')
ON CONFLICT (name) DO NOTHING;

-- ==========================================
-- SEED: Role Permissions
-- ==========================================

-- Super Admin: wildcard
INSERT INTO role_permissions (role_id, permission)
SELECT id, '*' FROM roles WHERE name = 'super_admin'
ON CONFLICT DO NOTHING;

-- CEO
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('auth.users.read'), ('sales.orders.read'), ('sales.orders.read_all'),
  ('sales.returns.read'), ('purchases.orders.read'), ('purchases.orders.read_all'),
  ('finance.vaults.read'), ('finance.expenses.read'), ('finance.expenses.approve'),
  ('inventory.read'), ('inventory.read_all'),
  ('hr.employees.read'), ('hr.payroll.read'), ('hr.payroll.approve'),
  ('targets.read'), ('targets.read_all'), ('reports.view_all'),
  ('settings.read')
) AS p(perm)
WHERE r.name = 'ceo'
ON CONFLICT DO NOTHING;

-- Branch Manager
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('auth.users.read'),
  ('sales.orders.read'), ('sales.orders.read_all'), ('sales.orders.confirm'),
  ('sales.returns.read'), ('sales.returns.confirm'),
  ('purchases.orders.read'), ('purchases.orders.create'), ('purchases.orders.confirm'),
  ('inventory.read'), ('inventory.read_all'), ('inventory.transfers.approve'),
  ('finance.vaults.read'), ('finance.expenses.read'), ('finance.expenses.approve'),
  ('customers.read'), ('customers.create'), ('customers.update'), ('customers.credit.update'),
  ('hr.employees.read'), ('hr.attendance.read'),
  ('targets.read'), ('targets.read_all'), ('targets.create'), ('targets.update'),
  ('reports.sales'), ('reports.financial'), ('settings.read')
) AS p(perm)
WHERE r.name = 'branch_manager'
ON CONFLICT DO NOTHING;

-- Sales Supervisor
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('sales.orders.read'), ('sales.orders.read_all'), ('sales.orders.confirm'),
  ('sales.orders.cancel'), ('sales.discounts.override'),
  ('sales.returns.read'), ('sales.returns.confirm'),
  ('customers.read'), ('customers.create'), ('customers.update'), ('customers.credit.update'),
  ('inventory.read'),
  ('targets.read'), ('targets.read_all'),
  ('reports.sales')
) AS p(perm)
WHERE r.name = 'sales_supervisor'
ON CONFLICT DO NOTHING;

-- Sales Rep
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('sales.orders.read'), ('sales.orders.create'),
  ('sales.returns.read'), ('sales.returns.create'),
  ('customers.read'), ('customers.update_location'),
  ('activities.create'), ('activities.read_own'),
  ('targets.read_own')
) AS p(perm)
WHERE r.name = 'sales_rep'
ON CONFLICT DO NOTHING;

-- Warehouse Keeper
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('inventory.read'), ('inventory.update'),
  ('inventory.transfers.read'), ('inventory.transfers.approve'),
  ('purchases.receipts.confirm'),
  ('sales.orders.deliver')
) AS p(perm)
WHERE r.name = 'warehouse_keeper'
ON CONFLICT DO NOTHING;

-- Accountant
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('finance.vaults.read'), ('finance.vaults.create'),
  ('finance.expenses.read'), ('finance.expenses.approve'),
  ('finance.payments.read'), ('finance.payments.create'),
  ('finance.journal.read'), ('finance.journal.create'),
  ('customers.read'), ('suppliers.read'),
  ('reports.financial'), ('settings.read')
) AS p(perm)
WHERE r.name = 'accountant'
ON CONFLICT DO NOTHING;

-- HR Manager
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('hr.employees.read'), ('hr.employees.create'),
  ('hr.attendance.read'),
  ('hr.payroll.read'), ('hr.payroll.calculate'), ('hr.payroll.approve'),
  ('settings.read')
) AS p(perm)
WHERE r.name = 'hr_manager'
ON CONFLICT DO NOTHING;

-- ==========================================
-- SEED: Company Settings (40+ settings)
-- ==========================================
INSERT INTO company_settings (key, value, type, description, category, is_public) VALUES
  -- Company
  ('company.name',                    'EDARA',  'text',    'اسم الشركة',                     'company',       true),
  ('company.name_en',                 'EDARA',  'text',    'Company Name (EN)',               'company',       true),
  ('company.logo_url',                '',       'text',    'شعار الشركة',                     'company',       true),
  ('company.phone',                   '',       'text',    'هاتف الشركة',                    'company',       true),
  ('company.address',                 '',       'text',    'عنوان الشركة',                   'company',       true),
  ('company.tax_number',              '',       'text',    'الرقم الضريبي',                  'company',       false),
  ('company.fiscal_year_start',       '01-01',  'text',    'بداية السنة المالية',             'company',       false),
  -- Finance
  ('finance.default_currency',        'EGP',    'text',    'العملة الافتراضية',              'finance',       true),
  ('finance.currency_symbol',         'ج.م',   'text',    'رمز العملة',                     'finance',       true),
  ('finance.decimal_places',          '2',      'number',  'الخانات العشرية',                'finance',       true),
  ('finance.accountant_approval_limit','2000',  'number',  'حد اعتماد المحاسب',              'finance',       false),
  ('finance.manager_approval_limit',  '10000',  'number',  'حد اعتماد المدير',               'finance',       false),
  ('finance.ceo_approval_limit',      '50000',  'number',  'حد اعتماد المدير التنفيذي',      'finance',       false),
  -- Sales
  ('sales.max_discount_percent',      '15',     'number',  'أقصى خصم للمندوب %',             'sales',         false),
  ('sales.allow_rep_discount',        'true',   'boolean', 'السماح بخصم المندوب',            'sales',         false),
  ('sales.credit_check_enabled',      'true',   'boolean', 'تفعيل فحص الائتمان',             'sales',         false),
  ('sales.credit_check_strict',       'true',   'boolean', 'رفض تجاوز حد الائتمان',          'sales',         false),
  ('sales.require_order_approval',    'false',  'boolean', 'موافقة مدير على الطلبات',         'sales',         false),
  ('sales.order_approval_min_amount', '0',      'number',  'حد مبلغ يستوجب موافقة',           'sales',         false),
  ('sales.allow_partial_delivery',    'true',   'boolean', 'السماح بالتسليم الجزئي',          'sales',         false),
  ('sales.allow_negative_stock',      'false',  'boolean', 'السماح بالبيع بمخزون سالب',       'sales',         false),
  ('sales.return_require_approval',   'true',   'boolean', 'موافقة على المرتجعات',            'sales',         false),
  ('sales.max_return_days',           '30',     'number',  'أقصى أيام للمرتجع',              'sales',         false),
  -- Purchases
  ('purchase.require_order_approval', 'true',   'boolean', 'موافقة على أوامر الشراء',         'purchases',     false),
  ('purchase.approval_min_amount',    '5000',   'number',  'حد مبلغ مشتريات للموافقة',        'purchases',     false),
  -- Inventory
  ('inventory.costing_method',        'wac',    'text',    'طريقة تقييم المخزون',             'inventory',     false),
  ('inventory.low_stock_threshold',   '10',     'number',  'نسبة تحذير المخزون المنخفض %',    'inventory',     false),
  ('inventory.batch_tracking_enabled','true',   'boolean', 'تتبع الدفعات',                   'inventory',     false),
  ('inventory.expiry_tracking_enabled','true',  'boolean', 'تتبع تاريخ الصلاحية',             'inventory',     false),
  ('inventory.expiry_alert_days',     '30',     'number',  'تحذير قبل انتهاء الصلاحية (أيام)','inventory',     false),
  -- HR
  ('hr.working_days',                 '[1,2,3,4,6]','json','أيام العمل',                     'hr',            false),
  ('hr.work_start_time',              '08:00',  'text',    'بداية الدوام',                    'hr',            false),
  ('hr.work_end_time',                '17:00',  'text',    'نهاية الدوام',                    'hr',            false),
  ('hr.late_grace_minutes',           '15',     'number',  'دقائق السماح للتأخير',            'hr',            false),
  ('hr.overtime_rate',                '1.5',    'number',  'معامل الإضافي',                   'hr',            false),
  ('hr.payroll_day',                  '28',     'number',  'يوم صرف الراتب',                  'hr',            false),
  ('hr.annual_leave_days',            '21',     'number',  'أيام الإجازة السنوية',             'hr',            false),
  ('hr.sick_leave_days',              '15',     'number',  'أيام الإجازة المرضية',             'hr',            false),
  ('hr.attendance_gps_required',      'true',   'boolean', 'GPS إلزامي للحضور',               'hr',            false),
  ('hr.attendance_gps_radius_meters', '200',    'number',  'نطاق GPS المقبول (متر)',           'hr',            false),
  -- Notifications
  ('notifications.low_stock_enabled', 'true',   'boolean', 'إشعار مخزون منخفض',              'notifications', false),
  ('notifications.credit_limit_enabled','true', 'boolean', 'إشعار تجاوز ائتمان',              'notifications', false),
  ('notifications.order_approval_push','true',  'boolean', 'إشعار طلب موافقة',               'notifications', false),
  ('notifications.payroll_reminder_days','3',    'number',  'تذكير قبل موعد الصرف (أيام)',     'notifications', false),
  ('sales.require_delivery_proof',    'false',  'boolean', 'إلزامية صورة إثبات التسليم',       'sales',         false)
ON CONFLICT (key) DO NOTHING;
