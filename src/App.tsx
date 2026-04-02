import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Toaster } from 'sonner'
import { lazy, Suspense } from 'react'

import { AuthProvider } from '@/components/layout/AuthProvider'
import { ProtectedRoute } from '@/components/layout/ProtectedRoute'
import ErrorBoundary from '@/components/shared/ErrorBoundary'
import GlobalRealtimeManager from '@/components/shared/GlobalRealtimeManager'
import AppLayout from '@/components/layout/AppLayout'
import PWAUpdateBanner from '@/components/pwa/PWAUpdateBanner'

// Auth Pages
import LoginPage from '@/pages/auth/LoginPage'
import UnauthorizedPage from '@/pages/auth/UnauthorizedPage'
import DashboardPage from '@/pages/dashboard/DashboardPage'

// Settings Pages — lazy loaded
const UsersPage = lazy(() => import('@/pages/settings/users/UsersPage'))
const UserFormPage = lazy(() => import('@/pages/settings/users/UserFormPage'))
const RolesPage = lazy(() => import('@/pages/settings/roles/RolesPage'))
const RoleFormPage = lazy(() => import('@/pages/settings/roles/RoleFormPage'))
const CompanySettingsPage = lazy(() => import('@/pages/settings/company/CompanySettingsPage'))
const AuditLogPage = lazy(() => import('@/pages/settings/audit/AuditLogPage'))

// Master Data Pages — lazy loaded
const ProductsPage = lazy(() => import('@/pages/products/ProductsPage'))
const ProductDetailPage = lazy(() => import('@/pages/products/ProductDetailPage'))
const ProductFormPage = lazy(() => import('@/pages/products/ProductFormPage'))
const CategoriesPage = lazy(() => import('@/pages/products/CategoriesPage'))
const PriceListsPage = lazy(() => import('@/pages/products/PriceListsPage'))
const CustomersPage = lazy(() => import('@/pages/customers/CustomersPage'))
const CustomerDetailPage = lazy(() => import('@/pages/customers/CustomerDetailPage'))
const CustomerFormPage = lazy(() => import('@/pages/customers/CustomerFormPage'))
const SuppliersPage = lazy(() => import('@/pages/suppliers/SuppliersPage'))
const SupplierDetailPage = lazy(() => import('@/pages/suppliers/SupplierDetailPage'))
const SupplierFormPage = lazy(() => import('@/pages/suppliers/SupplierFormPage'))
const WarehousesPage = lazy(() => import('@/pages/inventory/WarehousesPage'))
const StockPage = lazy(() => import('@/pages/inventory/StockPage'))
const TransfersPage = lazy(() => import('@/pages/inventory/TransfersPage'))
const TransferDetailPage = lazy(() => import('@/pages/inventory/TransferDetailPage'))
const AdjustmentsPage = lazy(() => import('@/pages/inventory/AdjustmentsPage'))
const AdjustmentDetailPage = lazy(() => import('@/pages/inventory/AdjustmentDetailPage'))
const BranchesPage = lazy(() => import('@/pages/branches/BranchesPage'))
const BundlesPage = lazy(() => import('@/pages/products/BundlesPage'))
const BrandsPage = lazy(() => import('@/pages/products/BrandsPage'))
const StockMovementsPage = lazy(() => import('@/pages/inventory/StockMovementsPage'))
const NotFoundPage = lazy(() => import('@/pages/NotFoundPage'))

// Finance Pages — lazy loaded
const VaultsPage = lazy(() => import('@/pages/finance/VaultsPage'))
const CustodyPage = lazy(() => import('@/pages/finance/CustodyPage'))
const PaymentsPage = lazy(() => import('@/pages/finance/PaymentsPage'))
const PaymentReceiptDetail = lazy(() => import('@/pages/finance/PaymentReceiptDetail'))
const ExpensesPage = lazy(() => import('@/pages/finance/ExpensesPage'))
const ChartOfAccountsPage = lazy(() => import('@/pages/finance/ChartOfAccountsPage'))
const JournalsPage = lazy(() => import('@/pages/finance/JournalsPage'))
const LedgerPage = lazy(() => import('@/pages/finance/LedgerPage'))
const ApprovalRulesPage = lazy(() => import('@/pages/finance/ApprovalRulesPage'))

// Sales Pages — lazy loaded
const SalesOrdersPage = lazy(() => import('@/pages/sales/SalesOrdersPage'))
const SalesOrderForm = lazy(() => import('@/pages/sales/SalesOrderForm'))
const SalesOrderDetail = lazy(() => import('@/pages/sales/SalesOrderDetail'))
const SalesReturnsPage = lazy(() => import('@/pages/sales/SalesReturnsPage'))
const SalesReturnForm = lazy(() => import('@/pages/sales/SalesReturnForm'))
const SalesReturnDetail = lazy(() => import('@/pages/sales/SalesReturnDetail'))
const ShippingCompaniesPage = lazy(() => import('@/pages/sales/ShippingCompaniesPage'))

// Procurement Pages — lazy loaded
const PurchaseInvoicesPage = lazy(() => import('@/pages/purchases/PurchaseInvoicesPage'))
const PurchaseInvoiceForm  = lazy(() => import('@/pages/purchases/PurchaseInvoiceForm'))
const PurchaseReturnForm   = lazy(() => import('@/pages/purchases/PurchaseReturnForm'))
const PurchaseReturnsPage  = lazy(() => import('@/pages/purchases/PurchaseReturnsPage'))

// HR Pages — lazy loaded
const HRDashboard        = lazy(() => import('@/pages/hr/HRDashboard'))
const EmployeesPage      = lazy(() => import('@/pages/hr/employees/EmployeesPage'))
const EmployeeProfile    = lazy(() => import('@/pages/hr/employees/EmployeeProfile'))
const AttendanceCheckin  = lazy(() => import('@/pages/hr/attendance/AttendanceCheckin'))
const AttendancePage     = lazy(() => import('@/pages/hr/attendance/AttendancePage'))
const LeavesPage         = lazy(() => import('@/pages/hr/leaves/LeavesPage'))
const AdvancesPage       = lazy(() => import('@/pages/hr/advances/AdvancesPage'))
const PayrollPage        = lazy(() => import('@/pages/hr/payroll/PayrollPage'))
const PayrollRunDetail   = lazy(() => import('@/pages/hr/payroll/PayrollRunDetail'))
const TargetPayoutsPage  = lazy(() => import('@/pages/hr/payroll/TargetPayoutsPage'))
const HRSettingsPage     = lazy(() => import('@/pages/hr/settings/HRSettingsPage'))
const CommissionsPage    = lazy(() => import('@/pages/hr/commissions/CommissionsPage'))
const PermissionsPage    = lazy(() => import('@/pages/hr/permissions/PermissionsPage'))
const DelegationsPage    = lazy(() => import('@/pages/hr/delegations/DelegationsPage'))
const HRAdjustmentsPage  = lazy(() => import('@/pages/hr/adjustments/AdjustmentsPage'))
const MyProfilePage      = lazy(() => import('@/pages/hr/MyProfilePage'))

// Activities Pages — lazy loaded
const ActivitiesDashboard = lazy(() => import('@/pages/activities/ActivitiesDashboard'))
const ActivitiesPage      = lazy(() => import('@/pages/activities/ActivitiesPage'))
const ActivityForm        = lazy(() => import('@/pages/activities/ActivityForm'))
const ActivityDetail      = lazy(() => import('@/pages/activities/ActivityDetail'))
const ActivityTypesPage   = lazy(() => import('@/pages/activities/ActivityTypesPage'))
const TargetTypesPage     = lazy(() => import('@/pages/activities/TargetTypesPage'))
const VisitPlansPage      = lazy(() => import('@/pages/activities/VisitPlansPage'))
const VisitPlanForm       = lazy(() => import('@/pages/activities/VisitPlanForm'))
const VisitPlanDetail     = lazy(() => import('@/pages/activities/VisitPlanDetail'))
const VisitExecutionMode  = lazy(() => import('@/pages/activities/VisitExecutionMode'))
const CallPlansPage       = lazy(() => import('@/pages/activities/CallPlansPage'))
const CallPlanForm        = lazy(() => import('@/pages/activities/CallPlanForm'))
const CallPlanDetail      = lazy(() => import('@/pages/activities/CallPlanDetail'))
const TargetsPage         = lazy(() => import('@/pages/activities/TargetsPage'))
const TargetForm          = lazy(() => import('@/pages/activities/TargetForm'))
const TargetDetail        = lazy(() => import('@/pages/activities/TargetDetail'))
// Wave A Admin Pages
const ChecklistTemplatesPage = lazy(() => import('@/pages/activities/ChecklistTemplatesPage'))
const PlanTemplatesPage      = lazy(() => import('@/pages/activities/PlanTemplatesPage'))

// Notifications
const NotificationsPage = lazy(() => import('@/pages/notifications/NotificationsPage'))

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      staleTime: 30_000,
      refetchOnWindowFocus: false,
    },
  },
})

const LazyFallback = () => (
  <div style={{ padding: 'var(--space-6)' }}>
    {[1,2,3,4,5].map(i => <div key={i} className="skeleton skeleton-row" />)}
  </div>
)

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <GlobalRealtimeManager />
      <BrowserRouter>
        <AuthProvider>
        <ErrorBoundary>
          <Routes>
            {/* Public */}
            <Route path="/login" element={<LoginPage />} />
            <Route path="/unauthorized" element={<UnauthorizedPage />} />

            {/* Protected — يتطلب تسجيل دخول */}
            <Route
              path="/"
              element={
                <ProtectedRoute>
                  <AppLayout />
                </ProtectedRoute>
              }
            >
              <Route index element={<DashboardPage />} />

              {/* Products */}
              <Route path="products" element={
                <ProtectedRoute permission={['products.read', 'products.create']}><Suspense fallback={<LazyFallback />}><ProductsPage /></Suspense></ProtectedRoute>
              } />
              <Route path="products/new" element={
                <ProtectedRoute permission="products.create"><Suspense fallback={<LazyFallback />}><ProductFormPage /></Suspense></ProtectedRoute>
              } />
              <Route path="products/:id" element={
                <ProtectedRoute permission="products.read"><Suspense fallback={<LazyFallback />}><ProductDetailPage /></Suspense></ProtectedRoute>
              } />
              <Route path="products/:id/edit" element={
                <ProtectedRoute permission="products.update"><Suspense fallback={<LazyFallback />}><ProductFormPage /></Suspense></ProtectedRoute>
              } />
              <Route path="products/categories" element={
                <ProtectedRoute permission="categories.create"><Suspense fallback={<LazyFallback />}><CategoriesPage /></Suspense></ProtectedRoute>
              } />
              <Route path="products/price-lists" element={
                <ProtectedRoute permission="price_lists.read"><Suspense fallback={<LazyFallback />}><PriceListsPage /></Suspense></ProtectedRoute>
              } />
              <Route path="products/bundles" element={
                <ProtectedRoute permission="products.read"><Suspense fallback={<LazyFallback />}><BundlesPage /></Suspense></ProtectedRoute>
              } />
              <Route path="products/brands" element={
                <ProtectedRoute permission="products.read"><Suspense fallback={<LazyFallback />}><BrandsPage /></Suspense></ProtectedRoute>
              } />

              {/* Customers */}
              <Route path="customers" element={
                <ProtectedRoute permission={['customers.read', 'customers.create']}><Suspense fallback={<LazyFallback />}><CustomersPage /></Suspense></ProtectedRoute>
              } />
              <Route path="customers/new" element={
                <ProtectedRoute permission="customers.create"><Suspense fallback={<LazyFallback />}><CustomerFormPage /></Suspense></ProtectedRoute>
              } />
              <Route path="customers/:id" element={
                <ProtectedRoute permission="customers.read"><Suspense fallback={<LazyFallback />}><CustomerDetailPage /></Suspense></ProtectedRoute>
              } />
              <Route path="customers/:id/edit" element={
                <ProtectedRoute permission="customers.update"><Suspense fallback={<LazyFallback />}><CustomerFormPage /></Suspense></ProtectedRoute>
              } />

              {/* Suppliers */}
              <Route path="suppliers" element={
                <ProtectedRoute permission={['suppliers.read', 'suppliers.create']}><Suspense fallback={<LazyFallback />}><SuppliersPage /></Suspense></ProtectedRoute>
              } />
              <Route path="suppliers/new" element={
                <ProtectedRoute permission="suppliers.create"><Suspense fallback={<LazyFallback />}><SupplierFormPage /></Suspense></ProtectedRoute>
              } />
              <Route path="suppliers/:id" element={
                <ProtectedRoute permission="suppliers.read"><Suspense fallback={<LazyFallback />}><SupplierDetailPage /></Suspense></ProtectedRoute>
              } />
              <Route path="suppliers/:id/edit" element={
                <ProtectedRoute permission="suppliers.update"><Suspense fallback={<LazyFallback />}><SupplierFormPage /></Suspense></ProtectedRoute>
              } />

              {/* Inventory */}
              <Route path="inventory/warehouses" element={
                <ProtectedRoute permission="inventory.read"><Suspense fallback={<LazyFallback />}><WarehousesPage /></Suspense></ProtectedRoute>
              } />
              <Route path="inventory/stock" element={
                <ProtectedRoute permission="inventory.read"><Suspense fallback={<LazyFallback />}><StockPage /></Suspense></ProtectedRoute>
              } />
              <Route path="inventory/transfers" element={
                <ProtectedRoute permission={['inventory.transfers.read', 'inventory.transfers.create']}><Suspense fallback={<LazyFallback />}><TransfersPage /></Suspense></ProtectedRoute>
              } />
              <Route path="inventory/transfers/:id" element={
                <ProtectedRoute permission="inventory.transfers.read"><Suspense fallback={<LazyFallback />}><TransferDetailPage /></Suspense></ProtectedRoute>
              } />
              <Route path="inventory/adjustments" element={
                <ProtectedRoute permission={['inventory.adjustments.read', 'inventory.adjustments.create']}><Suspense fallback={<LazyFallback />}><AdjustmentsPage /></Suspense></ProtectedRoute>
              } />
              <Route path="inventory/adjustments/:id" element={
                <ProtectedRoute permission="inventory.adjustments.read"><Suspense fallback={<LazyFallback />}><AdjustmentDetailPage /></Suspense></ProtectedRoute>
              } />
              <Route path="inventory/movements" element={
                <ProtectedRoute permission="inventory.read"><Suspense fallback={<LazyFallback />}><StockMovementsPage /></Suspense></ProtectedRoute>
              } />

              {/* Sales */}
              <Route path="sales/orders" element={
                <ProtectedRoute permission={['sales.orders.read', 'sales.orders.create']}><Suspense fallback={<LazyFallback />}><SalesOrdersPage /></Suspense></ProtectedRoute>
              } />
              <Route path="sales/orders/new" element={
                <ProtectedRoute permission="sales.orders.create"><Suspense fallback={<LazyFallback />}><SalesOrderForm /></Suspense></ProtectedRoute>
              } />
              <Route path="sales/orders/:id" element={
                <ProtectedRoute permission="sales.orders.read"><Suspense fallback={<LazyFallback />}><SalesOrderDetail /></Suspense></ProtectedRoute>
              } />
              <Route path="sales/orders/:id/edit" element={
                <ProtectedRoute permission="sales.orders.create"><Suspense fallback={<LazyFallback />}><SalesOrderForm /></Suspense></ProtectedRoute>
              } />
              <Route path="sales/returns" element={
                <ProtectedRoute permission={['sales.returns.read', 'sales.returns.create']}><Suspense fallback={<LazyFallback />}><SalesReturnsPage /></Suspense></ProtectedRoute>
              } />
              <Route path="sales/returns/new" element={
                <ProtectedRoute permission="sales.returns.create"><Suspense fallback={<LazyFallback />}><SalesReturnForm /></Suspense></ProtectedRoute>
              } />
              <Route path="sales/returns/:id" element={
                <ProtectedRoute permission="sales.returns.read"><Suspense fallback={<LazyFallback />}><SalesReturnDetail /></Suspense></ProtectedRoute>
              } />
              <Route path="sales/shipping" element={
                <ProtectedRoute permission="sales.shipping.manage"><Suspense fallback={<LazyFallback />}><ShippingCompaniesPage /></Suspense></ProtectedRoute>
              } />

              {/* Purchases */}
              <Route path="purchases/invoices" element={
                <ProtectedRoute permission={['procurement.invoices.read', 'procurement.invoices.create']}><Suspense fallback={<LazyFallback />}><PurchaseInvoicesPage /></Suspense></ProtectedRoute>
              } />
              <Route path="purchases/invoices/new" element={
                <ProtectedRoute permission="procurement.invoices.create"><Suspense fallback={<LazyFallback />}><PurchaseInvoiceForm /></Suspense></ProtectedRoute>
              } />
              <Route path="purchases/invoices/:id" element={
                <ProtectedRoute permission="procurement.invoices.read"><Suspense fallback={<LazyFallback />}><PurchaseInvoiceForm /></Suspense></ProtectedRoute>
              } />
              <Route path="purchases/returns" element={
                <ProtectedRoute permission="procurement.returns.read"><Suspense fallback={<LazyFallback />}><PurchaseReturnsPage /></Suspense></ProtectedRoute>
              } />
              <Route path="purchases/returns/new" element={
                <ProtectedRoute permission="procurement.returns.create"><Suspense fallback={<LazyFallback />}><PurchaseReturnForm /></Suspense></ProtectedRoute>
              } />
              <Route path="purchases/returns/:id" element={
                <ProtectedRoute permission="procurement.returns.read"><Suspense fallback={<LazyFallback />}><PurchaseReturnForm /></Suspense></ProtectedRoute>
              } />
              <Route path="finance/vaults" element={
                <ProtectedRoute permission="finance.vaults.read"><Suspense fallback={<LazyFallback />}><VaultsPage /></Suspense></ProtectedRoute>
              } />
              <Route path="finance/custody" element={
                <ProtectedRoute permission={['finance.custody.read', 'finance.custody.create']}><Suspense fallback={<LazyFallback />}><CustodyPage /></Suspense></ProtectedRoute>
              } />
              <Route path="finance/payments" element={
                <ProtectedRoute permission={['finance.payments.read', 'finance.payments.create']}><Suspense fallback={<LazyFallback />}><PaymentsPage /></Suspense></ProtectedRoute>
              } />
              <Route path="finance/payments/:id" element={
                <ProtectedRoute permission="finance.payments.read"><Suspense fallback={<LazyFallback />}><PaymentReceiptDetail /></Suspense></ProtectedRoute>
              } />
              <Route path="finance/expenses" element={
                <ProtectedRoute permission={['finance.expenses.read', 'finance.expenses.create']}><Suspense fallback={<LazyFallback />}><ExpensesPage /></Suspense></ProtectedRoute>
              } />
              <Route path="finance/accounts" element={
                <ProtectedRoute permission="finance.journal.read"><Suspense fallback={<LazyFallback />}><ChartOfAccountsPage /></Suspense></ProtectedRoute>
              } />
              <Route path="finance/journals" element={
                <ProtectedRoute permission="finance.journal.read"><Suspense fallback={<LazyFallback />}><JournalsPage /></Suspense></ProtectedRoute>
              } />
              <Route path="finance/ledger" element={
                <ProtectedRoute permission="finance.ledger.read"><Suspense fallback={<LazyFallback />}><LedgerPage /></Suspense></ProtectedRoute>
              } />
              <Route path="finance/approval-rules" element={
                <ProtectedRoute permission="settings.update"><Suspense fallback={<LazyFallback />}><ApprovalRulesPage /></Suspense></ProtectedRoute>
              } />

              {/* Branches */}
              <Route path="branches" element={
                <ProtectedRoute permission="branches.read"><Suspense fallback={<LazyFallback />}><BranchesPage /></Suspense></ProtectedRoute>
              } />

              {/* HR — Dashboard (index) / Admin Workspace */}
              <Route path="hr" element={
                <ProtectedRoute permission="hr.employees.read"><Suspense fallback={<LazyFallback />}><HRDashboard /></Suspense></ProtectedRoute>
              } />
              <Route path="hr/employees" element={
                <ProtectedRoute permission={['hr.employees.read', 'hr.employees.create']}><Suspense fallback={<LazyFallback />}><EmployeesPage /></Suspense></ProtectedRoute>
              } />
              <Route path="hr/employees/:id" element={
                <ProtectedRoute permission="hr.employees.read"><Suspense fallback={<LazyFallback />}><EmployeeProfile /></Suspense></ProtectedRoute>
              } />
              <Route path="hr/attendance/checkin" element={
                <ProtectedRoute permission="hr.attendance.checkin"><Suspense fallback={<LazyFallback />}><AttendanceCheckin /></Suspense></ProtectedRoute>
              } />
              <Route path="hr/leaves" element={
                <ProtectedRoute permission={['hr.leaves.request', 'hr.leaves.read', 'hr.leaves.approve', 'hr.leaves.create']}><Suspense fallback={<LazyFallback />}><LeavesPage /></Suspense></ProtectedRoute>
              } />
              <Route path="hr/advances" element={
                <ProtectedRoute permission={['hr.advances.create', 'hr.advances.read', 'hr.advances.approve']}><Suspense fallback={<LazyFallback />}><AdvancesPage /></Suspense></ProtectedRoute>
              } />
              <Route path="hr/payroll" element={
                <ProtectedRoute permission="hr.payroll.read"><Suspense fallback={<LazyFallback />}><PayrollPage /></Suspense></ProtectedRoute>
              } />
              <Route path="hr/payroll/:runId" element={
                <ProtectedRoute permission="hr.payroll.read"><Suspense fallback={<LazyFallback />}><PayrollRunDetail /></Suspense></ProtectedRoute>
              } />
              <Route path="hr/payroll/target-payouts" element={
                <ProtectedRoute permission="hr.payroll.read"><Suspense fallback={<LazyFallback />}><TargetPayoutsPage /></Suspense></ProtectedRoute>
              } />
              <Route path="hr/attendance" element={
                <ProtectedRoute permission="hr.attendance.read"><Suspense fallback={<LazyFallback />}><AttendancePage /></Suspense></ProtectedRoute>
              } />
              <Route path="hr/permissions" element={
                <ProtectedRoute permission={['hr.permissions.approve', 'hr.attendance.checkin', 'hr.leaves.create']}><Suspense fallback={<LazyFallback />}><PermissionsPage /></Suspense></ProtectedRoute>
              } />
              <Route path="hr/commissions" element={
                <ProtectedRoute permission={['hr.commissions.create', 'hr.employees.read']}><Suspense fallback={<LazyFallback />}><CommissionsPage /></Suspense></ProtectedRoute>
              } />
              <Route path="hr/settings" element={
                <ProtectedRoute permission="hr.settings.update"><Suspense fallback={<LazyFallback />}><HRSettingsPage /></Suspense></ProtectedRoute>
              } />
              <Route path="hr/delegations" element={
                <ProtectedRoute permission={['hr.leaves.approve', 'hr.advances.approve', 'hr.attendance.approve', 'hr.permissions.approve']}><Suspense fallback={<LazyFallback />}><DelegationsPage /></Suspense></ProtectedRoute>
              } />
              <Route path="hr/adjustments" element={
                <ProtectedRoute permission={['hr.payroll.read', 'hr.adjustments.read', 'hr.adjustments.create']}><Suspense fallback={<LazyFallback />}><HRAdjustmentsPage /></Suspense></ProtectedRoute>
              } />
              <Route path="hr/my-profile" element={
                <ProtectedRoute><Suspense fallback={<LazyFallback />}><MyProfilePage /></Suspense></ProtectedRoute>
              } />

              {/* Notifications */}
              <Route path="notifications" element={
                <ProtectedRoute>
                  <Suspense fallback={<LazyFallback />}>
                    <NotificationsPage />
                  </Suspense>
                </ProtectedRoute>
              } />

              {/* Settings */}
              <Route path="settings/users" element={
                <ProtectedRoute permission="auth.users.read"><Suspense fallback={<LazyFallback />}><UsersPage /></Suspense></ProtectedRoute>
              } />
              <Route path="settings/users/new" element={
                <ProtectedRoute permission="auth.users.create"><Suspense fallback={<LazyFallback />}><UserFormPage /></Suspense></ProtectedRoute>
              } />
              <Route path="settings/users/:id/edit" element={
                <ProtectedRoute permission="auth.users.update"><Suspense fallback={<LazyFallback />}><UserFormPage /></Suspense></ProtectedRoute>
              } />
              <Route path="settings/roles" element={
                <ProtectedRoute permission="auth.roles.read"><Suspense fallback={<LazyFallback />}><RolesPage /></Suspense></ProtectedRoute>
              } />
              <Route path="settings/roles/new" element={
                <ProtectedRoute permission="auth.roles.create"><Suspense fallback={<LazyFallback />}><RoleFormPage /></Suspense></ProtectedRoute>
              } />
              <Route path="settings/roles/:id/edit" element={
                <ProtectedRoute permission="auth.roles.update"><Suspense fallback={<LazyFallback />}><RoleFormPage /></Suspense></ProtectedRoute>
              } />
              <Route path="settings/company" element={
                <ProtectedRoute permission="settings.read"><Suspense fallback={<LazyFallback />}><CompanySettingsPage /></Suspense></ProtectedRoute>
              } />
              <Route path="settings/audit" element={
                <ProtectedRoute permission="settings.audit.read"><Suspense fallback={<LazyFallback />}><AuditLogPage /></Suspense></ProtectedRoute>
              } />

              {/* ── Activities Module ──────────────────────────────── */}
              {/* Dashboard */}
              <Route path="activities" element={
                <ProtectedRoute permission={['activities.read_own', 'activities.read_team', 'activities.read_all']}>
                  <Suspense fallback={<LazyFallback />}><ActivitiesDashboard /></Suspense>
                </ProtectedRoute>
              } />
              {/* List */}
              <Route path="activities/list" element={
                <ProtectedRoute permission={['activities.read_own', 'activities.read_team', 'activities.read_all']}>
                  <Suspense fallback={<LazyFallback />}><ActivitiesPage /></Suspense>
                </ProtectedRoute>
              } />
              {/* Create */}
              <Route path="activities/new" element={
                <ProtectedRoute permission="activities.create">
                  <Suspense fallback={<LazyFallback />}><ActivityForm /></Suspense>
                </ProtectedRoute>
              } />
              {/* Detail */}
              <Route path="activities/:id" element={
                <ProtectedRoute permission={['activities.read_own', 'activities.read_team', 'activities.read_all']}>
                  <Suspense fallback={<LazyFallback />}><ActivityDetail /></Suspense>
                </ProtectedRoute>
              } />
              {/* Edit */}
              <Route path="activities/:id/edit" element={
                <ProtectedRoute permission="activities.update_own">
                  <Suspense fallback={<LazyFallback />}><ActivityForm /></Suspense>
                </ProtectedRoute>
              } />
              {/* Activity Types (Settings) */}
              <Route path="activities/types" element={
                <ProtectedRoute permission="settings.update">
                  <Suspense fallback={<LazyFallback />}><ActivityTypesPage /></Suspense>
                </ProtectedRoute>
              } />
              {/* Target Types (Settings) */}
              <Route path="activities/target-types" element={
                <ProtectedRoute permission="settings.update">
                  <Suspense fallback={<LazyFallback />}><TargetTypesPage /></Suspense>
                </ProtectedRoute>
              } />
              {/* ── Visit Plans ── */}
              <Route path="activities/visit-plans" element={
                <ProtectedRoute permission={['visit_plans.read_own', 'visit_plans.read_team', 'visit_plans.read_all']}>
                  <Suspense fallback={<LazyFallback />}><VisitPlansPage /></Suspense>
                </ProtectedRoute>
              } />
              <Route path="activities/visit-plans/new" element={
                <ProtectedRoute permission="visit_plans.create">
                  <Suspense fallback={<LazyFallback />}><VisitPlanForm /></Suspense>
                </ProtectedRoute>
              } />
              <Route path="activities/visit-plans/:id" element={
                <ProtectedRoute permission={['visit_plans.read_own', 'visit_plans.read_team', 'visit_plans.read_all']}>
                  <Suspense fallback={<LazyFallback />}><VisitPlanDetail /></Suspense>
                </ProtectedRoute>
              } />
              <Route path="activities/visit-plans/:id/execute" element={
                <ProtectedRoute permission="activities.create">
                  <Suspense fallback={<LazyFallback />}><VisitExecutionMode /></Suspense>
                </ProtectedRoute>
              } />
              {/* ── Call Plans ── */}
              <Route path="activities/call-plans" element={
                <ProtectedRoute permission={['call_plans.read_own', 'call_plans.read_team', 'call_plans.read_all']}>
                  <Suspense fallback={<LazyFallback />}><CallPlansPage /></Suspense>
                </ProtectedRoute>
              } />
              <Route path="activities/call-plans/new" element={
                <ProtectedRoute permission="call_plans.create">
                  <Suspense fallback={<LazyFallback />}><CallPlanForm /></Suspense>
                </ProtectedRoute>
              } />
              <Route path="activities/call-plans/:id" element={
                <ProtectedRoute permission={['call_plans.read_own', 'call_plans.read_team', 'call_plans.read_all']}>
                  <Suspense fallback={<LazyFallback />}><CallPlanDetail /></Suspense>
                </ProtectedRoute>
              } />
              {/* ── Targets ── */}
              <Route path="activities/targets" element={
                <ProtectedRoute permission={['targets.read_own', 'targets.read_team', 'targets.read_all']}>
                  <Suspense fallback={<LazyFallback />}><TargetsPage /></Suspense>
                </ProtectedRoute>
              } />
              {/* /new: يُرندر TargetForm الحقيقي */}
              <Route path="activities/targets/new" element={
                <ProtectedRoute permission="targets.assign">
                  <Suspense fallback={<LazyFallback />}><TargetForm /></Suspense>
                </ProtectedRoute>
              } />
              <Route path="activities/targets/:id" element={
                <ProtectedRoute permission={['targets.read_own', 'targets.read_team', 'targets.read_all']}>
                  <Suspense fallback={<LazyFallback />}><TargetDetail /></Suspense>
                </ProtectedRoute>
              } />

              {/* ── Wave A Admin: Checklists & Template Management ── */}
              <Route path="activities/checklists" element={
                <ProtectedRoute permission="checklists.manage">
                  <Suspense fallback={<LazyFallback />}><ChecklistTemplatesPage /></Suspense>
                </ProtectedRoute>
              } />
              <Route path="activities/plan-templates" element={
                <ProtectedRoute permission={['visit_plans.create', 'call_plans.create']}>
                  <Suspense fallback={<LazyFallback />}><PlanTemplatesPage /></Suspense>
                </ProtectedRoute>
              } />

            </Route>

              {/* 404 */}
              <Route path="*" element={
                <Suspense fallback={<LazyFallback />}><NotFoundPage /></Suspense>
              } />
          </Routes>
          </ErrorBoundary>

          {/* PWA: update available / offline ready banner */}
          <PWAUpdateBanner />

          <Toaster
            position="top-center"
            dir="rtl"
            toastOptions={{
              style: {
                fontFamily: 'var(--font-sans)',
                direction: 'rtl',
              },
            }}
          />
        </AuthProvider>
      </BrowserRouter>
    </QueryClientProvider>
  )
}
