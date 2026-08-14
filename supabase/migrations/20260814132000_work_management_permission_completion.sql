-- Work Management — close permission registry gaps introduced by later engines.
SET lock_timeout='5s';
SET statement_timeout='60s';

WITH permission_matrix(role_name,permission) AS (
  VALUES
    ('sales_supervisor','work.recurrence.manage'),
    ('hr_manager','work.recurrence.manage'),
    ('branch_manager','work.recurrence.manage'),
    ('ceo','work.recurrence.manage')
)
INSERT INTO public.role_permissions(role_id,permission)
SELECT r.id,p.permission
FROM permission_matrix p
JOIN public.roles r ON r.name=p.role_name
ON CONFLICT(role_id,permission) DO NOTHING;

-- super_admin already receives the project wildcard permission.
RESET lock_timeout;
RESET statement_timeout;