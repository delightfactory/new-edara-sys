-- Add an editable office customer-service role.
-- This migration only creates the role and seeds its initial permissions.

INSERT INTO public.roles (
  name,
  name_ar,
  description,
  is_system,
  color,
  grade
)
VALUES (
  'customer_service',
  'خدمة العملاء',
  'موظفات خدمة العملاء اللاتي يعملن من المكتب',
  false,
  '#db2777',
  5
)
ON CONFLICT (name) DO UPDATE
SET
  name_ar = EXCLUDED.name_ar,
  description = EXCLUDED.description,
  -- Keep this role editable through the normal roles UI.
  is_system = false,
  color = EXCLUDED.color,
  grade = EXCLUDED.grade;

INSERT INTO public.role_permissions (role_id, permission)
SELECT r.id, p.permission
FROM public.roles r
CROSS JOIN (VALUES
  ('auth.users.read'),
  ('branches.read'),
  ('products.read'),
  ('price_lists.read'),
  ('inventory.read'),
  ('customers.read'),
  ('customers.read_all'),
  ('customers.create'),
  ('customers.update'),
  ('sales.read'),
  ('sales.orders.read'),
  ('sales.orders.read_all'),
  ('sales.orders.create'),
  ('sales.orders.update'),
  ('sales.returns.read'),
  ('sales.returns.create'),
  ('activities.create'),
  ('activities.read_own'),
  ('activities.update_own'),
  ('call_plans.create'),
  ('call_plans.read_own'),
  ('call_plans.update_own'),

  -- Employee self-service only. Own records remain enforced by HR RLS/RPCs.
  ('hr.attendance.checkin'),
  ('hr.leaves.request'),
  ('hr.advances.create')
) AS p(permission)
WHERE r.name = 'customer_service'
ON CONFLICT (role_id, permission) DO NOTHING;
