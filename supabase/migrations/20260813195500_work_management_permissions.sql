-- ============================================================================
-- Work Management — Migration B1: Permission seed
-- Uses the existing role_permissions/check_permission model; no role UUIDs.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

-- --------------------------------------------------------------------------
-- Permission seed.
--
-- role_permissions is the current permission source of truth; there is no
-- separate permission catalogue table. IDs are resolved by stable role names,
-- never hard-coded.
-- --------------------------------------------------------------------------
WITH permission_matrix(role_name, permission) AS (
  VALUES
    -- Customer service
    ('customer_service', 'work.items.create'),
    ('customer_service', 'work.items.read_own'),
    ('customer_service', 'work.items.update_own'),
    ('customer_service', 'work.items.comment'),
    ('customer_service', 'work.requests.create'),

    -- Sales representative
    ('sales_rep', 'work.items.create'),
    ('sales_rep', 'work.items.read_own'),
    ('sales_rep', 'work.items.update_own'),
    ('sales_rep', 'work.items.comment'),
    ('sales_rep', 'work.requests.create'),

    -- Warehouse keeper
    ('warehouse_keeper', 'work.items.create'),
    ('warehouse_keeper', 'work.items.read_own'),
    ('warehouse_keeper', 'work.items.update_own'),
    ('warehouse_keeper', 'work.items.comment'),
    ('warehouse_keeper', 'work.requests.create'),

    -- Accountant
    ('accountant', 'work.items.create'),
    ('accountant', 'work.items.read_own'),
    ('accountant', 'work.items.update_own'),
    ('accountant', 'work.items.comment'),
    ('accountant', 'work.requests.create'),

    -- Sales supervisor
    ('sales_supervisor', 'work.items.create'),
    ('sales_supervisor', 'work.items.read_own'),
    ('sales_supervisor', 'work.items.read_team'),
    ('sales_supervisor', 'work.items.update_own'),
    ('sales_supervisor', 'work.items.manage_team'),
    ('sales_supervisor', 'work.items.comment'),
    ('sales_supervisor', 'work.items.assign'),
    ('sales_supervisor', 'work.items.delegate'),
    ('sales_supervisor', 'work.items.transfer_ownership'),
    ('sales_supervisor', 'work.requests.create'),
    ('sales_supervisor', 'work.requests.triage'),
    ('sales_supervisor', 'work.approvals.decide'),

    -- HR manager
    ('hr_manager', 'work.items.create'),
    ('hr_manager', 'work.items.read_own'),
    ('hr_manager', 'work.items.read_team'),
    ('hr_manager', 'work.items.read_restricted'),
    ('hr_manager', 'work.items.update_own'),
    ('hr_manager', 'work.items.manage_team'),
    ('hr_manager', 'work.items.comment'),
    ('hr_manager', 'work.items.assign'),
    ('hr_manager', 'work.items.delegate'),
    ('hr_manager', 'work.items.transfer_ownership'),
    ('hr_manager', 'work.requests.create'),
    ('hr_manager', 'work.requests.triage'),
    ('hr_manager', 'work.approvals.decide'),

    -- Branch manager
    ('branch_manager', 'work.items.create'),
    ('branch_manager', 'work.items.read_own'),
    ('branch_manager', 'work.items.read_team'),
    ('branch_manager', 'work.items.read_restricted'),
    ('branch_manager', 'work.items.update_own'),
    ('branch_manager', 'work.items.manage_team'),
    ('branch_manager', 'work.items.comment'),
    ('branch_manager', 'work.items.assign'),
    ('branch_manager', 'work.items.assign_branch'),
    ('branch_manager', 'work.items.delegate'),
    ('branch_manager', 'work.items.transfer_ownership'),
    ('branch_manager', 'work.requests.create'),
    ('branch_manager', 'work.requests.triage'),
    ('branch_manager', 'work.queues.manage'),
    ('branch_manager', 'work.approvals.decide'),

    -- CEO
    ('ceo', 'work.items.create'),
    ('ceo', 'work.items.read_own'),
    ('ceo', 'work.items.read_all'),
    ('ceo', 'work.items.read_restricted'),
    ('ceo', 'work.items.read_private'),
    ('ceo', 'work.items.update_own'),
    ('ceo', 'work.items.manage_team'),
    ('ceo', 'work.items.comment'),
    ('ceo', 'work.items.assign'),
    ('ceo', 'work.items.assign_branch'),
    ('ceo', 'work.items.delegate'),
    ('ceo', 'work.items.transfer_ownership'),
    ('ceo', 'work.items.manage'),
    ('ceo', 'work.requests.create'),
    ('ceo', 'work.requests.triage'),
    ('ceo', 'work.queues.manage'),
    ('ceo', 'work.approvals.decide'),
    ('ceo', 'work.templates.manage'),
    ('ceo', 'work.workflows.manage'),
    ('ceo', 'work.policies.manage')
)
INSERT INTO public.role_permissions(role_id, permission)
SELECT r.id, pm.permission
FROM permission_matrix pm
JOIN public.roles r ON r.name = pm.role_name
ON CONFLICT (role_id, permission) DO NOTHING;

-- super_admin already holds wildcard '*', so no duplicated Work grants are needed.

RESET lock_timeout;
RESET statement_timeout;
