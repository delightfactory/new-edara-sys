export type NavigationPermission = string | string[]

export type NavigationGroupId =
  | 'home'
  | 'operations'
  | 'inventory'
  | 'finance'
  | 'field'
  | 'people'
  | 'insights'
  | 'settings'

export interface NavigationDestination {
  id: string
  label: string
  path: string
  permission?: NavigationPermission
  group: NavigationGroupId
  exact?: boolean
  mobilePrimary?: boolean
}

export interface CreationActionDescriptor {
  id: string
  label: string
  matchPath: string
  navigateTo: string
  permission: string
}

/**
 * Presentation metadata only.
 *
 * This registry never grants access. Route protection and backend authorization
 * remain owned by ProtectedRoute / RBAC / RLS. Consumers may only use this
 * metadata to decide whether an already-authorized destination should be shown.
 */
export const NAVIGATION_DESTINATIONS: NavigationDestination[] = [
  { id: 'dashboard', label: 'الرئيسية', path: '/', group: 'home', exact: true, mobilePrimary: true },
  { id: 'notifications', label: 'الإشعارات', path: '/notifications', group: 'home' },

  { id: 'work', label: 'مساحة العمل', path: '/work', group: 'operations', exact: true, mobilePrimary: true, permission: ['work.items.read_own', 'work.items.read_team', 'work.items.read_all'] },
  { id: 'work-team', label: 'أعمال الفريق', path: '/work/team', group: 'operations', permission: ['work.items.read_team', 'work.items.read_all', 'work.items.manage_team'] },
  { id: 'work-manage', label: 'إدارة العمل', path: '/work/manage', group: 'operations', permission: ['work.queues.manage', 'work.templates.manage', 'work.workflows.manage', 'work.recurrence.manage', 'work.policies.manage'] },

  { id: 'sales-orders', label: 'طلبات البيع', path: '/sales/orders', group: 'operations', mobilePrimary: true, permission: ['sales.orders.read', 'sales.orders.create'] },
  { id: 'sales-returns', label: 'مرتجعات البيع', path: '/sales/returns', group: 'operations', permission: ['sales.returns.read', 'sales.returns.create'] },
  { id: 'sales-shipping', label: 'شركات الشحن', path: '/sales/shipping', group: 'operations', permission: 'sales.shipping.manage' },

  { id: 'purchase-invoices', label: 'فواتير الشراء', path: '/purchases/invoices', group: 'operations', permission: ['procurement.invoices.read', 'procurement.invoices.create'] },
  { id: 'purchase-returns', label: 'مرتجعات المشتريات', path: '/purchases/returns', group: 'operations', permission: 'procurement.returns.read' },

  { id: 'customers', label: 'العملاء', path: '/customers', group: 'operations', mobilePrimary: true, permission: ['customers.read', 'customers.create'] },
  { id: 'credit', label: 'إدارة الائتمان', path: '/credit', group: 'operations', permission: ['customers.read', 'customers.read_all'] },
  { id: 'credit-overdue', label: 'الفواتير المتأخرة', path: '/credit/overdue', group: 'operations', permission: ['customers.read', 'customers.read_all', 'sales.orders.read', 'sales.orders.read_all'] },
  { id: 'suppliers', label: 'الموردون', path: '/suppliers', group: 'operations', permission: ['suppliers.read', 'suppliers.create'] },

  { id: 'warehouses', label: 'المخازن', path: '/inventory/warehouses', group: 'inventory', permission: 'inventory.read' },
  { id: 'stock', label: 'أرصدة المخزون', path: '/inventory/stock', group: 'inventory', permission: 'inventory.read' },
  { id: 'transfers', label: 'التحويلات', path: '/inventory/transfers', group: 'inventory', permission: ['inventory.transfers.read', 'inventory.transfers.create'] },
  { id: 'adjustments', label: 'التسويات', path: '/inventory/adjustments', group: 'inventory', permission: ['inventory.adjustments.read', 'inventory.adjustments.create'] },
  { id: 'stock-movements', label: 'حركات المخزون', path: '/inventory/movements', group: 'inventory', permission: 'inventory.read' },
  { id: 'inventory-valuation', label: 'تقييم المخزون', path: '/inventory/valuation', group: 'inventory', permission: 'finance.view_costs' },
  { id: 'products', label: 'المنتجات', path: '/products', group: 'inventory', permission: ['products.read', 'products.create'] },
  { id: 'categories', label: 'التصنيفات', path: '/products/categories', group: 'inventory', permission: 'categories.create' },
  { id: 'price-lists', label: 'قوائم الأسعار', path: '/products/price-lists', group: 'inventory', permission: 'price_lists.read' },
  { id: 'bundles', label: 'الباقات', path: '/products/bundles', group: 'inventory', permission: 'products.read' },
  { id: 'brands', label: 'العلامات التجارية', path: '/products/brands', group: 'inventory', permission: 'products.read' },
  { id: 'branches', label: 'الفروع', path: '/branches', group: 'inventory', permission: 'branches.read' },

  { id: 'vaults', label: 'الخزائن', path: '/finance/vaults', group: 'finance', permission: 'finance.vaults.read' },
  { id: 'custody', label: 'العهد', path: '/finance/custody', group: 'finance', permission: ['finance.custody.read', 'finance.custody.create'] },
  { id: 'payments', label: 'إيصالات الدفع', path: '/finance/payments', group: 'finance', permission: ['finance.payments.read', 'finance.payments.create'] },
  { id: 'expenses', label: 'المصروفات', path: '/finance/expenses', group: 'finance', permission: ['finance.expenses.read', 'finance.expenses.create'] },
  { id: 'accounts', label: 'شجرة الحسابات', path: '/finance/accounts', group: 'finance', permission: 'finance.journal.read' },
  { id: 'journals', label: 'القيود المحاسبية', path: '/finance/journals', group: 'finance', permission: 'finance.journal.read' },
  { id: 'ledger', label: 'دفتر الحسابات', path: '/finance/ledger', group: 'finance', permission: 'finance.ledger.read' },
  { id: 'balance-sheet', label: 'الميزان المالي', path: '/finance/balance-sheet', group: 'finance', permission: 'finance.journal.read' },
  { id: 'approval-rules', label: 'قواعد الموافقات', path: '/finance/approval-rules', group: 'finance', permission: 'settings.update' },

  { id: 'activities', label: 'لوحة الأنشطة', path: '/activities', group: 'field', exact: true, permission: ['activities.read_own', 'activities.read_team', 'activities.read_all'] },
  { id: 'activities-list', label: 'قائمة الأنشطة', path: '/activities/list', group: 'field', permission: ['activities.read_own', 'activities.read_team', 'activities.read_all'] },
  { id: 'visit-plans', label: 'خطط الزيارات', path: '/activities/visit-plans', group: 'field', permission: ['visit_plans.read_own', 'visit_plans.read_team', 'visit_plans.read_all'] },
  { id: 'call-plans', label: 'خطط المكالمات', path: '/activities/call-plans', group: 'field', permission: ['call_plans.read_own', 'call_plans.read_team', 'call_plans.read_all'] },
  { id: 'targets', label: 'الأهداف', path: '/activities/targets', group: 'field', permission: ['targets.read_own', 'targets.read_team', 'targets.read_all'] },
  { id: 'checklists', label: 'استبيانات الزيارات', path: '/activities/checklists', group: 'field', permission: 'checklists.manage' },
  { id: 'activity-types', label: 'أنواع الأنشطة', path: '/activities/types', group: 'field', permission: 'settings.update' },
  { id: 'target-types', label: 'أنواع الأهداف', path: '/activities/target-types', group: 'field', permission: 'settings.update' },

  { id: 'my-profile', label: 'ملفي الشخصي', path: '/hr/my-profile', group: 'people' },
  { id: 'attendance-checkin', label: 'تسجيل الحضور', path: '/hr/attendance/checkin', group: 'people', permission: 'hr.attendance.checkin' },
  { id: 'hr-permissions', label: 'الأذونات', path: '/hr/permissions', group: 'people', permission: ['hr.permissions.approve', 'hr.attendance.checkin', 'hr.leaves.create'] },
  { id: 'leaves', label: 'الإجازات', path: '/hr/leaves', group: 'people', permission: ['hr.leaves.create', 'hr.leaves.read', 'hr.leaves.approve', 'hr.leaves.request'] },
  { id: 'advances', label: 'السلف', path: '/hr/advances', group: 'people', permission: ['hr.advances.create', 'hr.advances.read', 'hr.advances.approve'] },
  { id: 'hr-dashboard', label: 'الشئون الإدارية', path: '/hr', group: 'people', exact: true, permission: 'hr.employees.read' },
  { id: 'employees', label: 'الموظفون', path: '/hr/employees', group: 'people', permission: 'hr.employees.read' },
  { id: 'attendance', label: 'الحضور', path: '/hr/attendance', group: 'people', permission: 'hr.attendance.read' },
  { id: 'commissions', label: 'العمولات', path: '/hr/commissions', group: 'people', permission: ['hr.commissions.create', 'hr.employees.read'] },
  { id: 'payroll', label: 'مسير الرواتب', path: '/hr/payroll', group: 'people', permission: 'hr.payroll.read' },
  { id: 'target-payouts', label: 'مكافآت الأهداف', path: '/hr/payroll/target-payouts', group: 'people', permission: 'hr.payroll.read' },
  { id: 'hr-adjustments', label: 'مكافآت وخصومات', path: '/hr/adjustments', group: 'people', permission: ['hr.payroll.read', 'hr.adjustments.read', 'hr.adjustments.create'] },
  { id: 'delegations', label: 'التفويضات', path: '/hr/delegations', group: 'people', permission: ['hr.leaves.approve', 'hr.advances.approve', 'hr.attendance.approve', 'hr.permissions.approve'] },
  { id: 'hr-settings', label: 'إعدادات الموارد البشرية', path: '/hr/settings', group: 'people', permission: 'hr.settings.update' },

  { id: 'reports-overview', label: 'نظرة عامة', path: '/reports/overview', group: 'insights', permission: ['reports.sales', 'reports.view_all'] },
  { id: 'reports-sales', label: 'تقارير المبيعات', path: '/reports/sales', group: 'insights', permission: ['reports.sales', 'reports.view_all'] },
  { id: 'reports-receivables', label: 'المستحقات', path: '/reports/receivables', group: 'insights', permission: ['reports.sales', 'reports.targets', 'reports.view_all'] },
  { id: 'reports-treasury', label: 'الخزينة', path: '/reports/treasury', group: 'insights', permission: ['reports.financial', 'reports.sales', 'reports.view_all'] },
  { id: 'reports-customers', label: 'صحة العملاء', path: '/reports/customers', group: 'insights', permission: ['reports.sales', 'reports.view_all'] },
  { id: 'reports-reps', label: 'أداء المندوبين', path: '/reports/reps', group: 'insights', permission: ['reports.sales', 'reports.view_all'] },
  { id: 'reports-visits', label: 'تقارير الزيارات', path: '/reports/visits', group: 'insights', permission: ['reports.activities', 'reports.view_all'] },
  { id: 'reports-products', label: 'أداء المنتجات', path: '/reports/products', group: 'insights', permission: ['reports.sales', 'reports.view_all'] },
  { id: 'reports-churn', label: 'خطر الخمود', path: '/reports/churn-risk', group: 'insights', permission: ['reports.sales', 'reports.view_all'] },
  { id: 'reports-geography', label: 'التحليل الجغرافي', path: '/reports/geography', group: 'insights', permission: ['reports.sales', 'reports.view_all'] },
  { id: 'reports-targets', label: 'إنجاز الأهداف', path: '/reports/target-attainment', group: 'insights', permission: ['reports.targets', 'reports.view_all'] },
  { id: 'reports-credit', label: 'التزام المندوبين الائتماني', path: '/reports/credit-commitment', group: 'insights', permission: ['reports.sales', 'reports.view_all'] },
  { id: 'reports-reengagement', label: 'إعادة الاستهداف', path: '/reports/reengagement', group: 'insights', permission: ['reports.sales', 'reports.view_all'] },
  { id: 'reports-profitability', label: 'الربحية', path: '/reports/profitability', group: 'insights', permission: ['reports.financial', 'reports.view_all'] },

  { id: 'settings-users', label: 'المستخدمون', path: '/settings/users', group: 'settings', permission: 'auth.users.read' },
  { id: 'settings-roles', label: 'الأدوار والصلاحيات', path: '/settings/roles', group: 'settings', permission: 'auth.roles.read' },
  { id: 'settings-company', label: 'إعدادات الشركة', path: '/settings/company', group: 'settings', permission: 'settings.read' },
  { id: 'settings-audit', label: 'سجل المراجعة', path: '/settings/audit', group: 'settings', permission: 'settings.audit.read' },
]

export const MOBILE_PRIMARY_DESTINATION_IDS = [
  'dashboard',
  'work',
  'sales-orders',
  'customers',
] as const

export const CREATION_ACTIONS: CreationActionDescriptor[] = [
  { id: 'new-sales-order', label: '+ طلب بيع', matchPath: '/sales/orders', navigateTo: '/sales/orders/new', permission: 'sales.orders.create' },
  { id: 'new-sales-return', label: '+ مرتجع بيع', matchPath: '/sales/returns', navigateTo: '/sales/returns/new', permission: 'sales.returns.create' },
  { id: 'new-customer', label: '+ عميل', matchPath: '/customers', navigateTo: '/customers/new', permission: 'customers.create' },
  { id: 'new-supplier', label: '+ مورد', matchPath: '/suppliers', navigateTo: '/suppliers/new', permission: 'suppliers.create' },
  { id: 'new-product', label: '+ منتج', matchPath: '/products', navigateTo: '/products/new', permission: 'products.create' },
  { id: 'new-purchase-invoice', label: '+ فاتورة', matchPath: '/purchases/invoices', navigateTo: '/purchases/invoices/new', permission: 'procurement.invoices.create' },
  { id: 'new-purchase-return', label: '+ مرتجع', matchPath: '/purchases/returns', navigateTo: '/purchases/returns/new', permission: 'procurement.returns.create' },
  { id: 'new-activity', label: '+ نشاط', matchPath: '/activities/list', navigateTo: '/activities/new', permission: 'activities.create' },
  { id: 'new-activity-dashboard', label: '+ نشاط', matchPath: '/activities', navigateTo: '/activities/new', permission: 'activities.create' },
  { id: 'new-visit-plan', label: '+ خطة زيارة', matchPath: '/activities/visit-plans', navigateTo: '/activities/visit-plans/new', permission: 'visit_plans.create' },
  { id: 'new-call-plan', label: '+ خطة مكالمات', matchPath: '/activities/call-plans', navigateTo: '/activities/call-plans/new', permission: 'call_plans.create' },
  { id: 'new-target', label: '+ هدف', matchPath: '/activities/targets', navigateTo: '/activities/targets/new', permission: 'targets.assign' },
]
