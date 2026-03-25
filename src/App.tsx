import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Toaster } from 'sonner'
import { lazy, Suspense } from 'react'

import { AuthProvider } from '@/components/layout/AuthProvider'
import { ProtectedRoute } from '@/components/layout/ProtectedRoute'
import ErrorBoundary from '@/components/shared/ErrorBoundary'
import AppLayout from '@/components/layout/AppLayout'

// Auth Pages
import LoginPage from '@/pages/auth/LoginPage'
import UnauthorizedPage from '@/pages/auth/UnauthorizedPage'
import DashboardPage from '@/pages/dashboard/DashboardPage'

// Settings Pages
import UsersPage from '@/pages/settings/users/UsersPage'
import UserFormPage from '@/pages/settings/users/UserFormPage'
import RolesPage from '@/pages/settings/roles/RolesPage'
import RoleFormPage from '@/pages/settings/roles/RoleFormPage'
import CompanySettingsPage from '@/pages/settings/company/CompanySettingsPage'
import AuditLogPage from '@/pages/settings/audit/AuditLogPage'

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
                <ProtectedRoute permission="products.read"><Suspense fallback={<LazyFallback />}><ProductsPage /></Suspense></ProtectedRoute>
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
                <ProtectedRoute permission="customers.read"><Suspense fallback={<LazyFallback />}><CustomersPage /></Suspense></ProtectedRoute>
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
                <ProtectedRoute permission="suppliers.read"><Suspense fallback={<LazyFallback />}><SuppliersPage /></Suspense></ProtectedRoute>
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
                <ProtectedRoute permission="inventory.transfers.read"><Suspense fallback={<LazyFallback />}><TransfersPage /></Suspense></ProtectedRoute>
              } />
              <Route path="inventory/transfers/:id" element={
                <ProtectedRoute permission="inventory.transfers.read"><Suspense fallback={<LazyFallback />}><TransferDetailPage /></Suspense></ProtectedRoute>
              } />
              <Route path="inventory/adjustments" element={
                <ProtectedRoute permission="inventory.adjustments.read"><Suspense fallback={<LazyFallback />}><AdjustmentsPage /></Suspense></ProtectedRoute>
              } />
              <Route path="inventory/adjustments/:id" element={
                <ProtectedRoute permission="inventory.adjustments.read"><Suspense fallback={<LazyFallback />}><AdjustmentDetailPage /></Suspense></ProtectedRoute>
              } />
              <Route path="inventory/movements" element={
                <ProtectedRoute permission="inventory.read"><Suspense fallback={<LazyFallback />}><StockMovementsPage /></Suspense></ProtectedRoute>
              } />

              {/* Branches */}
              <Route path="branches" element={
                <ProtectedRoute permission="branches.read"><Suspense fallback={<LazyFallback />}><BranchesPage /></Suspense></ProtectedRoute>
              } />

              {/* Settings */}
              <Route path="settings/users" element={
                <ProtectedRoute permission="auth.users.read"><UsersPage /></ProtectedRoute>
              } />
              <Route path="settings/users/new" element={
                <ProtectedRoute permission="auth.users.create"><UserFormPage /></ProtectedRoute>
              } />
              <Route path="settings/users/:id/edit" element={
                <ProtectedRoute permission="auth.users.update"><UserFormPage /></ProtectedRoute>
              } />
              <Route path="settings/roles" element={
                <ProtectedRoute permission="auth.roles.read"><RolesPage /></ProtectedRoute>
              } />
              <Route path="settings/roles/new" element={
                <ProtectedRoute permission="auth.roles.create"><RoleFormPage /></ProtectedRoute>
              } />
              <Route path="settings/roles/:id/edit" element={
                <ProtectedRoute permission="auth.roles.update"><RoleFormPage /></ProtectedRoute>
              } />
              <Route path="settings/company" element={
                <ProtectedRoute permission="settings.read"><CompanySettingsPage /></ProtectedRoute>
              } />
              <Route path="settings/audit" element={
                <ProtectedRoute permission="settings.audit.read"><AuditLogPage /></ProtectedRoute>
              } />
            </Route>

              {/* 404 */}
              <Route path="*" element={
                <Suspense fallback={<LazyFallback />}><NotFoundPage /></Suspense>
              } />
          </Routes>
          </ErrorBoundary>

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
