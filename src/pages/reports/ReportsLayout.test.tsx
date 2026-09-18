import { render, screen, within } from '@testing-library/react'
import type { ReactNode } from 'react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import ReportsLayout from './ReportsLayout'

const auth = vi.hoisted(() => ({ can: vi.fn() }))
const pageTitle = vi.hoisted(() => ({ setTitle: vi.fn() }))

vi.mock('@/stores/auth-store', () => ({
  useAuthStore: (selector: (state: { can: (permission: string) => boolean }) => unknown) =>
    selector({ can: auth.can }),
}))

vi.mock('@/components/layout/PageTitleContext', () => ({
  usePageTitle: () => pageTitle,
}))

vi.mock('@/components/reports/AnalyticsGate', () => ({
  default: ({ children }: { children: ReactNode }) => (
    <div data-testid="analytics-gate">{children}</div>
  ),
}))

const REPORT_DESTINATIONS = [
  ['/reports/overview', 'نظرة عامة'],
  ['/reports/sales', 'المبيعات'],
  ['/reports/receivables', 'المستحقات'],
  ['/reports/treasury', 'الخزينة'],
  ['/reports/customers', 'العملاء'],
  ['/reports/reps', 'أداء المندوبين'],
  ['/reports/visits', 'الزيارات'],
  ['/reports/products', 'أداء المنتجات'],
  ['/reports/churn-risk', 'خطر الخمود'],
  ['/reports/geography', 'جغرافى'],
  ['/reports/target-attainment', 'إنجاز الأهداف'],
  ['/reports/credit-commitment', 'التزام المندوبين'],
  ['/reports/reengagement', 'إعادة الاستهداف'],
  ['/reports/profitability', 'الربحية'],
] as const

function renderAt(path: string) {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/reports" element={<ReportsLayout />}>
          <Route path="*" element={<div>محتوى التقرير</div>} />
        </Route>
      </Routes>
    </MemoryRouter>,
  )
}

describe('ReportsLayout route sub-navigation', () => {
  beforeEach(() => {
    auth.can.mockReset()
    auth.can.mockReturnValue(true)
    pageTitle.setTitle.mockClear()
  })

  it('uses the shared named route navigation and preserves destination order, copy and active-link semantics', () => {
    renderAt('/reports/sales')

    const navigation = screen.getByRole('navigation', { name: 'أقسام التقارير' })
    const links = within(navigation).getAllByRole('link')

    expect(links.map(link => [link.getAttribute('href'), link.textContent])).toEqual(REPORT_DESTINATIONS)
    expect(screen.getByRole('link', { name: 'المبيعات' }).className).toContain('ds-subnav__item--active')
    expect(screen.queryByRole('tab')).toBeNull()
  })

  it('keeps permission eligibility in ReportsLayout before items reach SubNav', () => {
    auth.can.mockImplementation((permission: string) => permission === 'reports.activities')

    renderAt('/reports/visits')

    const navigation = screen.getByRole('navigation', { name: 'أقسام التقارير' })
    const links = within(navigation).getAllByRole('link')

    expect(links).toHaveLength(1)
    expect(links[0].getAttribute('href')).toBe('/reports/visits')
    expect(links[0].textContent).toBe('الزيارات')
  })

  it('keeps analytics pages gated', () => {
    renderAt('/reports/sales')

    expect(screen.getByTestId('analytics-gate')).not.toBeNull()
    expect(screen.getByText('محتوى التقرير')).not.toBeNull()
  })

  it.each(['/reports/visits', '/reports/reengagement'])('keeps %s outside AnalyticsGate', path => {
    renderAt(path)

    expect(screen.queryByTestId('analytics-gate')).toBeNull()
    expect(screen.getByText('محتوى التقرير')).not.toBeNull()
  })
})
