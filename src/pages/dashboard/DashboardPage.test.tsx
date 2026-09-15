import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'

const testState = vi.hoisted(() => ({
  permissions: new Set<string>(),
  overview: {
    activeCustomers: 12,
    activeProducts: 28,
    activeWarehouses: 3,
    stockItems: 64,
    pendingSalesOrders: 4,
    pendingPurchaseInvoices: 2,
    lowStockItems: 3,
  },
  sales: {
    todayRevenue: 12500,
    monthRevenue: 184000,
    pendingOrders: 4,
    deliveredToday: 7,
  },
}))

vi.mock('@/stores/auth-store', () => ({
  useAuthStore: (selector: (state: unknown) => unknown) => selector({
    profile: { full_name: 'أحمد محمد' },
    can: (permission: string) => testState.permissions.has(permission),
  }),
}))

vi.mock('@tanstack/react-query', () => ({
  useQuery: ({ queryKey }: { queryKey: string[] }) => {
    if (queryKey[0] === 'dashboard-overview') {
      return { data: testState.overview, isLoading: false }
    }
    if (queryKey[0] === 'dashboard-sales') {
      return { data: testState.sales, isLoading: false }
    }
    return { data: undefined, isLoading: false }
  },
}))

vi.mock('@/lib/supabase/client', () => ({
  supabase: {},
}))

vi.mock('@/components/dashboard/GoalCommandCenter', () => ({
  default: () => <div data-testid="goal-command-center">goal-command-center</div>,
}))

import DashboardPage from './DashboardPage'

function renderDashboard() {
  return render(
    <MemoryRouter>
      <DashboardPage />
    </MemoryRouter>,
  )
}

describe('Dashboard V2 migration', () => {
  beforeEach(() => {
    testState.permissions.clear()
  })

  it('preserves the main operational information when the user has full dashboard access', () => {
    ;[
      'sales.read',
      'finance.read',
      'inventory.read',
    ].forEach(permission => testState.permissions.add(permission))

    renderDashboard()

    expect(screen.getByTestId('goal-command-center')).toBeTruthy()
    expect(screen.getByText('العملاء النشطون')).toBeTruthy()
    expect(screen.getByText('المنتجات')).toBeTruthy()
    expect(screen.getByText('المخازن النشطة')).toBeTruthy()
    expect(screen.getByText('إيرادات المبيعات')).toBeTruthy()
    expect(screen.getByText('تنبيهات المخزون')).toBeTruthy()
    expect(screen.getByText('3 صنف على وشك النفاد')).toBeTruthy()
    expect(screen.getByText('طلبات بيع تحتاج تنفيذ')).toBeTruthy()
    expect(screen.getByText('فواتير مشتريات معلقة')).toBeTruthy()
  })

  it('keeps permission-driven sections hidden and shows the neutral welcome state', () => {
    renderDashboard()

    expect(screen.getByText('العملاء النشطون')).toBeTruthy()
    expect(screen.queryByText('إيرادات المبيعات')).toBeNull()
    expect(screen.queryByText('تنبيهات المخزون')).toBeNull()
    expect(screen.getByText('مرحباً بك')).toBeTruthy()
    expect(screen.getByText('استخدم القائمة الرئيسية للوصول إلى الأقسام المتاحة لك حسب صلاحياتك.')).toBeTruthy()
  })
})
