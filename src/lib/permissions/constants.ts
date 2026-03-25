/**
 * قائمة كل الصلاحيات في النظام — المرجع الرسمي
 * يُستخدم في: Sidebar filtering, Route guards, Role editor UI, RLS policies
 */
export const PERMISSIONS = {
  // Auth & Users
  AUTH_USERS_READ:           'auth.users.read',
  AUTH_USERS_CREATE:         'auth.users.create',
  AUTH_USERS_UPDATE:         'auth.users.update',
  AUTH_USERS_DEACTIVATE:     'auth.users.deactivate',
  AUTH_USERS_RESET_PASSWORD: 'auth.users.reset_password',
  AUTH_ROLES_READ:           'auth.roles.read',
  AUTH_ROLES_CREATE:         'auth.roles.create',
  AUTH_ROLES_UPDATE:         'auth.roles.update',
  AUTH_ROLES_DELETE:         'auth.roles.delete',

  // Settings
  SETTINGS_READ:       'settings.read',
  SETTINGS_UPDATE:     'settings.update',
  SETTINGS_AUDIT_READ: 'settings.audit.read',

  // Sales
  SALES_ORDERS_READ:        'sales.orders.read',
  SALES_ORDERS_READ_ALL:    'sales.orders.read_all',
  SALES_ORDERS_CREATE:      'sales.orders.create',
  SALES_ORDERS_CONFIRM:     'sales.orders.confirm',
  SALES_ORDERS_DELIVER:     'sales.orders.deliver',
  SALES_ORDERS_CANCEL:      'sales.orders.cancel',
  SALES_RETURNS_READ:       'sales.returns.read',
  SALES_RETURNS_CREATE:     'sales.returns.create',
  SALES_RETURNS_CONFIRM:    'sales.returns.confirm',
  SALES_DISCOUNTS_OVERRIDE: 'sales.discounts.override',

  // Products & Categories
  PRODUCTS_READ:     'products.read',
  PRODUCTS_CREATE:   'products.create',
  PRODUCTS_UPDATE:   'products.update',
  PRODUCTS_DELETE:   'products.delete',
  CATEGORIES_CREATE: 'categories.create',

  // Price Lists
  PRICE_LISTS_READ:   'price_lists.read',
  PRICE_LISTS_UPDATE: 'price_lists.update',

  // Branches
  BRANCHES_READ:   'branches.read',
  BRANCHES_CREATE: 'branches.create',
  BRANCHES_UPDATE: 'branches.update',

  // Customers
  CUSTOMERS_READ:            'customers.read',
  CUSTOMERS_READ_ALL:        'customers.read_all',
  CUSTOMERS_CREATE:          'customers.create',
  CUSTOMERS_UPDATE:          'customers.update',
  CUSTOMERS_DELETE:          'customers.delete',
  CUSTOMERS_UPDATE_LOCATION: 'customers.update_location',
  CUSTOMERS_CREDIT_UPDATE:   'customers.credit.update',

  // Suppliers
  SUPPLIERS_READ:   'suppliers.read',
  SUPPLIERS_CREATE: 'suppliers.create',
  SUPPLIERS_UPDATE: 'suppliers.update',
  SUPPLIERS_DELETE: 'suppliers.delete',

  // Inventory
  INVENTORY_READ:               'inventory.read',
  INVENTORY_READ_ALL:           'inventory.read_all',
  INVENTORY_CREATE:             'inventory.create',
  INVENTORY_UPDATE:             'inventory.update',
  INVENTORY_TRANSFERS_READ:     'inventory.transfers.read',
  INVENTORY_TRANSFERS_CREATE:   'inventory.transfers.create',
  INVENTORY_TRANSFERS_APPROVE:  'inventory.transfers.approve',
  INVENTORY_ADJUSTMENTS_READ:   'inventory.adjustments.read',
  INVENTORY_ADJUSTMENTS_CREATE: 'inventory.adjustments.create',

  // Purchases
  PURCHASES_ORDERS_READ:      'purchases.orders.read',
  PURCHASES_ORDERS_READ_ALL:  'purchases.orders.read_all',
  PURCHASES_ORDERS_CREATE:    'purchases.orders.create',
  PURCHASES_ORDERS_CONFIRM:   'purchases.orders.confirm',
  PURCHASES_RECEIPTS_CONFIRM: 'purchases.receipts.confirm',

  // Finance
  FINANCE_VIEW_COSTS:         'finance.view_costs',
  FINANCE_VAULTS_READ:        'finance.vaults.read',
  FINANCE_VAULTS_READ_ALL:    'finance.vaults.read_all',
  FINANCE_VAULTS_CREATE:      'finance.vaults.create',
  FINANCE_VAULTS_UPDATE:      'finance.vaults.update',
  FINANCE_VAULTS_TRANSACT:    'finance.vaults.transact',
  FINANCE_CUSTODY_READ:       'finance.custody.read',
  FINANCE_CUSTODY_READ_ALL:   'finance.custody.read_all',
  FINANCE_CUSTODY_CREATE:     'finance.custody.create',
  FINANCE_CUSTODY_TRANSACT:   'finance.custody.transact',
  FINANCE_EXPENSES_READ:      'finance.expenses.read',
  FINANCE_EXPENSES_READ_ALL:  'finance.expenses.read_all',
  FINANCE_EXPENSES_CREATE:    'finance.expenses.create',
  FINANCE_EXPENSES_APPROVE:   'finance.expenses.approve',
  FINANCE_PAYMENTS_READ:      'finance.payments.read',
  FINANCE_PAYMENTS_READ_ALL:  'finance.payments.read_all',
  FINANCE_PAYMENTS_CREATE:    'finance.payments.create',
  FINANCE_PAYMENTS_CONFIRM:   'finance.payments.confirm',
  FINANCE_JOURNAL_READ:       'finance.journal.read',
  FINANCE_JOURNAL_CREATE:     'finance.journal.create',
  FINANCE_LEDGER_READ:        'finance.ledger.read',
  FINANCE_LEDGER_ADJUST:      'finance.ledger.adjust',

  // HR
  HR_EMPLOYEES_READ:    'hr.employees.read',
  HR_EMPLOYEES_CREATE:  'hr.employees.create',
  HR_ATTENDANCE_READ:   'hr.attendance.read',
  HR_PAYROLL_READ:      'hr.payroll.read',
  HR_PAYROLL_CALCULATE: 'hr.payroll.calculate',
  HR_PAYROLL_APPROVE:   'hr.payroll.approve',

  // Activities
  ACTIVITIES_CREATE:  'activities.create',
  ACTIVITIES_READ_OWN:'activities.read_own',

  // Reports
  REPORTS_SALES:     'reports.sales',
  REPORTS_FINANCIAL: 'reports.financial',
  REPORTS_VIEW_ALL:  'reports.view_all',

  // Targets
  TARGETS_READ_OWN: 'targets.read_own',
  TARGETS_READ:     'targets.read',
  TARGETS_READ_ALL: 'targets.read_all',
  TARGETS_CREATE:   'targets.create',
  TARGETS_UPDATE:   'targets.update',

  // Wildcard
  WILDCARD: '*',
} as const

export type Permission = typeof PERMISSIONS[keyof typeof PERMISSIONS]

/**
 * تجميع الصلاحيات حسب الوحدات — يُستخدم في واجهة تحرير الأدوار
 */
export const PERMISSION_GROUPS = [
  {
    id: 'auth',
    label: 'المصادقة والمستخدمين',
    permissions: [
      { key: PERMISSIONS.AUTH_USERS_READ,           label: 'عرض المستخدمين' },
      { key: PERMISSIONS.AUTH_USERS_CREATE,         label: 'إنشاء مستخدم' },
      { key: PERMISSIONS.AUTH_USERS_UPDATE,         label: 'تعديل مستخدم' },
      { key: PERMISSIONS.AUTH_USERS_DEACTIVATE,     label: 'تعطيل مستخدم' },
      { key: PERMISSIONS.AUTH_USERS_RESET_PASSWORD, label: 'إعادة تعيين كلمة المرور' },
      { key: PERMISSIONS.AUTH_ROLES_READ,           label: 'عرض الأدوار' },
      { key: PERMISSIONS.AUTH_ROLES_CREATE,         label: 'إنشاء دور' },
      { key: PERMISSIONS.AUTH_ROLES_UPDATE,         label: 'تعديل دور' },
      { key: PERMISSIONS.AUTH_ROLES_DELETE,         label: 'حذف دور' },
    ]
  },
  {
    id: 'settings',
    label: 'الإعدادات',
    permissions: [
      { key: PERMISSIONS.SETTINGS_READ,       label: 'عرض الإعدادات' },
      { key: PERMISSIONS.SETTINGS_UPDATE,     label: 'تعديل الإعدادات' },
      { key: PERMISSIONS.SETTINGS_AUDIT_READ, label: 'عرض سجل التدقيق' },
    ]
  },
  {
    id: 'products',
    label: 'المنتجات',
    permissions: [
      { key: PERMISSIONS.PRODUCTS_READ,     label: 'عرض المنتجات' },
      { key: PERMISSIONS.PRODUCTS_CREATE,   label: 'إنشاء منتج' },
      { key: PERMISSIONS.PRODUCTS_UPDATE,   label: 'تعديل منتج' },
      { key: PERMISSIONS.PRODUCTS_DELETE,   label: 'حذف منتج' },
      { key: PERMISSIONS.CATEGORIES_CREATE, label: 'إدارة التصنيفات' },
    ]
  },
  {
    id: 'price_lists',
    label: 'قوائم الأسعار',
    permissions: [
      { key: PERMISSIONS.PRICE_LISTS_READ,   label: 'عرض قوائم الأسعار' },
      { key: PERMISSIONS.PRICE_LISTS_UPDATE, label: 'تعديل قوائم الأسعار' },
    ]
  },
  {
    id: 'branches',
    label: 'الفروع',
    permissions: [
      { key: PERMISSIONS.BRANCHES_READ,   label: 'عرض الفروع' },
      { key: PERMISSIONS.BRANCHES_CREATE, label: 'إنشاء فرع' },
      { key: PERMISSIONS.BRANCHES_UPDATE, label: 'تعديل فرع' },
    ]
  },
  {
    id: 'sales',
    label: 'المبيعات',
    permissions: [
      { key: PERMISSIONS.SALES_ORDERS_READ,        label: 'عرض الطلبات' },
      { key: PERMISSIONS.SALES_ORDERS_READ_ALL,    label: 'عرض كل الطلبات' },
      { key: PERMISSIONS.SALES_ORDERS_CREATE,      label: 'إنشاء طلب' },
      { key: PERMISSIONS.SALES_ORDERS_CONFIRM,     label: 'تأكيد طلب' },
      { key: PERMISSIONS.SALES_ORDERS_DELIVER,     label: 'تسليم طلب' },
      { key: PERMISSIONS.SALES_ORDERS_CANCEL,      label: 'إلغاء طلب' },
      { key: PERMISSIONS.SALES_RETURNS_READ,       label: 'عرض المرتجعات' },
      { key: PERMISSIONS.SALES_RETURNS_CREATE,     label: 'إنشاء مرتجع' },
      { key: PERMISSIONS.SALES_RETURNS_CONFIRM,    label: 'تأكيد مرتجع' },
      { key: PERMISSIONS.SALES_DISCOUNTS_OVERRIDE, label: 'تجاوز حد الخصم' },
    ]
  },
  {
    id: 'customers',
    label: 'العملاء',
    permissions: [
      { key: PERMISSIONS.CUSTOMERS_READ,            label: 'عرض العملاء (عملاءه)' },
      { key: PERMISSIONS.CUSTOMERS_READ_ALL,        label: 'عرض كل العملاء' },
      { key: PERMISSIONS.CUSTOMERS_CREATE,          label: 'إنشاء عميل' },
      { key: PERMISSIONS.CUSTOMERS_UPDATE,          label: 'تعديل عميل' },
      { key: PERMISSIONS.CUSTOMERS_DELETE,          label: 'حذف عميل' },
      { key: PERMISSIONS.CUSTOMERS_UPDATE_LOCATION, label: 'تحديث موقع العميل' },
      { key: PERMISSIONS.CUSTOMERS_CREDIT_UPDATE,   label: 'تعديل حد الائتمان' },
    ]
  },
  {
    id: 'inventory',
    label: 'المخزون',
    permissions: [
      { key: PERMISSIONS.INVENTORY_READ,               label: 'عرض المخزون' },
      { key: PERMISSIONS.INVENTORY_READ_ALL,           label: 'عرض كل المخازن' },
      { key: PERMISSIONS.INVENTORY_CREATE,             label: 'إنشاء مخزن' },
      { key: PERMISSIONS.INVENTORY_UPDATE,             label: 'تعديل المخزون' },
      { key: PERMISSIONS.INVENTORY_TRANSFERS_READ,     label: 'عرض التحويلات' },
      { key: PERMISSIONS.INVENTORY_TRANSFERS_CREATE,   label: 'إنشاء تحويل' },
      { key: PERMISSIONS.INVENTORY_TRANSFERS_APPROVE,  label: 'اعتماد تحويل' },
      { key: PERMISSIONS.INVENTORY_ADJUSTMENTS_READ,   label: 'عرض التسويات' },
      { key: PERMISSIONS.INVENTORY_ADJUSTMENTS_CREATE,  label: 'إنشاء تسوية' },
    ]
  },
  {
    id: 'suppliers',
    label: 'الموردين',
    permissions: [
      { key: PERMISSIONS.SUPPLIERS_READ,   label: 'عرض الموردين' },
      { key: PERMISSIONS.SUPPLIERS_CREATE, label: 'إنشاء مورد' },
      { key: PERMISSIONS.SUPPLIERS_UPDATE, label: 'تعديل مورد' },
      { key: PERMISSIONS.SUPPLIERS_DELETE, label: 'حذف مورد' },
    ]
  },
  {
    id: 'purchases',
    label: 'المشتريات',
    permissions: [
      { key: PERMISSIONS.PURCHASES_ORDERS_READ,      label: 'عرض أوامر الشراء' },
      { key: PERMISSIONS.PURCHASES_ORDERS_READ_ALL,  label: 'عرض كل الأوامر' },
      { key: PERMISSIONS.PURCHASES_ORDERS_CREATE,    label: 'إنشاء أمر شراء' },
      { key: PERMISSIONS.PURCHASES_ORDERS_CONFIRM,   label: 'تأكيد أمر شراء' },
      { key: PERMISSIONS.PURCHASES_RECEIPTS_CONFIRM, label: 'اعتماد استلام' },
    ]
  },
  {
    id: 'finance',
    label: 'المالية',
    permissions: [
      { key: PERMISSIONS.FINANCE_VIEW_COSTS,         label: 'عرض التكاليف وهوامش الربح' },
      { key: PERMISSIONS.FINANCE_VAULTS_READ,        label: 'عرض الخزائن (خزائنه)' },
      { key: PERMISSIONS.FINANCE_VAULTS_READ_ALL,    label: 'عرض كل الخزائن' },
      { key: PERMISSIONS.FINANCE_VAULTS_CREATE,      label: 'إنشاء خزنة' },
      { key: PERMISSIONS.FINANCE_VAULTS_UPDATE,      label: 'تعديل خزنة' },
      { key: PERMISSIONS.FINANCE_VAULTS_TRANSACT,    label: 'إيداع/سحب من الخزنة' },
      { key: PERMISSIONS.FINANCE_CUSTODY_READ,       label: 'عرض العُهد (عهدته)' },
      { key: PERMISSIONS.FINANCE_CUSTODY_READ_ALL,   label: 'عرض كل العُهد' },
      { key: PERMISSIONS.FINANCE_CUSTODY_CREATE,     label: 'إنشاء عهدة' },
      { key: PERMISSIONS.FINANCE_CUSTODY_TRANSACT,   label: 'تحميل/تسوية العهدة' },
      { key: PERMISSIONS.FINANCE_EXPENSES_READ,      label: 'عرض المصروفات (مصروفاته)' },
      { key: PERMISSIONS.FINANCE_EXPENSES_READ_ALL,  label: 'عرض كل المصروفات' },
      { key: PERMISSIONS.FINANCE_EXPENSES_CREATE,    label: 'إنشاء مصروف' },
      { key: PERMISSIONS.FINANCE_EXPENSES_APPROVE,   label: 'اعتماد مصروف' },
      { key: PERMISSIONS.FINANCE_PAYMENTS_READ,      label: 'عرض المدفوعات (مدفوعاته)' },
      { key: PERMISSIONS.FINANCE_PAYMENTS_READ_ALL,  label: 'عرض كل المدفوعات' },
      { key: PERMISSIONS.FINANCE_PAYMENTS_CREATE,     label: 'إنشاء دفعة' },
      { key: PERMISSIONS.FINANCE_PAYMENTS_CONFIRM,   label: 'تأكيد/رفض إيصال دفع' },
      { key: PERMISSIONS.FINANCE_JOURNAL_READ,       label: 'عرض القيود' },
      { key: PERMISSIONS.FINANCE_JOURNAL_CREATE,     label: 'إنشاء قيد يدوي' },
      { key: PERMISSIONS.FINANCE_LEDGER_READ,        label: 'عرض دفتر الحسابات' },
      { key: PERMISSIONS.FINANCE_LEDGER_ADJUST,      label: 'تسوية أرصدة يدوياً' },
    ]
  },
  {
    id: 'hr',
    label: 'الموارد البشرية',
    permissions: [
      { key: PERMISSIONS.HR_EMPLOYEES_READ,    label: 'عرض الموظفين' },
      { key: PERMISSIONS.HR_EMPLOYEES_CREATE,  label: 'إنشاء موظف' },
      { key: PERMISSIONS.HR_ATTENDANCE_READ,   label: 'عرض الحضور' },
      { key: PERMISSIONS.HR_PAYROLL_READ,      label: 'عرض الرواتب' },
      { key: PERMISSIONS.HR_PAYROLL_CALCULATE, label: 'حساب الرواتب' },
      { key: PERMISSIONS.HR_PAYROLL_APPROVE,   label: 'اعتماد الرواتب' },
    ]
  },
  {
    id: 'reports',
    label: 'التقارير',
    permissions: [
      { key: PERMISSIONS.REPORTS_SALES,     label: 'تقارير المبيعات' },
      { key: PERMISSIONS.REPORTS_FINANCIAL, label: 'تقارير المالية' },
      { key: PERMISSIONS.REPORTS_VIEW_ALL,  label: 'كل التقارير' },
    ]
  },
  {
    id: 'targets',
    label: 'الأهداف',
    permissions: [
      { key: PERMISSIONS.TARGETS_READ_OWN, label: 'عرض أهدافي' },
      { key: PERMISSIONS.TARGETS_READ,     label: 'عرض الأهداف' },
      { key: PERMISSIONS.TARGETS_READ_ALL, label: 'عرض كل الأهداف' },
      { key: PERMISSIONS.TARGETS_CREATE,   label: 'إنشاء هدف' },
      { key: PERMISSIONS.TARGETS_UPDATE,   label: 'تعديل هدف' },
    ]
  },
] as const
