import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, cleanup, render, screen, waitFor, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { useAuthStore } from '@/stores/auth-store'
import DashboardPage from './DashboardPage'

interface PendingRequest {
  url: URL
  init: RequestInit | undefined
  resolve: (response: Response) => void
  reject: (reason: Error) => void
}

const counts: Record<string, number> = {
  customers: 12, products: 28, warehouses: 3, stock: 64,
  sales_orders: 4, purchase_invoices: 2,
}

let pendingRequests: PendingRequest[]
let queryClient: QueryClient

function renderDashboard(permissions = ['sales.read', 'finance.read', 'inventory.read']) {
  useAuthStore.getState().setPermissions(permissions)
  queryClient = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: Infinity } } })
  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter>
        <DashboardPage />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

function countRequests() {
  return pendingRequests.filter(request => request.init?.method === 'HEAD')
}

function lowStockRequest() {
  const request = pendingRequests.find(request => request.url.pathname === '/rest/v1/rpc/get_low_stock')
  if (!request) throw new Error('Low-stock request has not started')
  return request
}

async function resolveCounts(missingCounts = false) {
  await act(async () => {
    for (const request of countRequests()) {
      const table = request.url.pathname.split('/').pop()!
      const headers: Record<string, string> = missingCounts ? {} : { 'content-range': `*/${counts[table]}` }
      request.resolve(new Response(null, { status: 200, headers }))
    }
  })
}

async function resolveLowStock(rows: { total_count: string }[] | null) {
  await act(async () => {
    lowStockRequest().resolve(new Response(JSON.stringify(rows), {
      status: 200, headers: { 'content-type': 'application/json' },
    }))
  })
}

function metric(label: string) {
  const card = screen.getByText(label).closest('.ds-stat-card')
  if (!card) throw new Error(`Metric card not found: ${label}`)
  return within(card as HTMLElement)
}

describe('Dashboard overview network loading', () => {
  beforeEach(() => {
    useAuthStore.getState().reset()
    pendingRequests = []
    // Exercise the real Supabase SDK at its HTTP boundary; never send live traffic.
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url)
      if (url.origin !== 'https://example.supabase.co') throw new Error(`Unexpected test host: ${url.origin}`)
      if (init?.method === 'HEAD' || url.pathname === '/rest/v1/rpc/get_low_stock') {
        return new Promise<Response>((resolve, reject) => pendingRequests.push({ url, init, resolve, reject }))
      }
      if (url.pathname === '/rest/v1/targets' || url.pathname === '/rest/v1/sales_orders') {
        return Promise.resolve(new Response('[]', { status: 200, headers: { 'content-type': 'application/json' } }))
      }
      throw new Error(`Unexpected test request: ${url.pathname}`)
    }))
  })

  afterEach(() => {
    cleanup()
    queryClient?.clear()
    useAuthStore.getState().reset()
    vi.unstubAllGlobals()
  })

  it('starts low-stock before unresolved counts and keeps metrics loading until every overview response arrives', async () => {
    // Regression: first-load overview waited for six counts before starting low-stock.
    renderDashboard()
    await waitFor(() => {
      expect(new Set(countRequests().map(request => request.url.pathname)).size).toBe(6)
      expect(lowStockRequest()).toBeDefined()
    })
    expect(JSON.parse(String(lowStockRequest().init?.body))).toEqual({
      p_warehouse_id: null, p_offset: 0, p_limit: 1,
    })
    expect(metric('العملاء النشطون').getByLabelText('جاري تحميل القيمة')).toBeTruthy()

    await resolveCounts()
    expect(metric('العملاء النشطون').getByLabelText('جاري تحميل القيمة')).toBeTruthy()
    expect(screen.queryByText('تنبيهات المخزون')).toBeNull()
    await resolveLowStock([{ total_count: '3' }])

    await waitFor(() => expect(metric('العملاء النشطون').getByText('12')).toBeTruthy())
    expect(metric('المنتجات').getByText('28')).toBeTruthy()
    expect(metric('المخازن النشطة').getByText('3')).toBeTruthy()
    expect(metric('أصناف المخزون').getByText('64')).toBeTruthy()
    expect(metric('طلبات معلقة').getByText('4')).toBeTruthy()
    expect(metric('أصناف منخفضة').getByText('3')).toBeTruthy()
    expect(screen.getByText('3 صنف على وشك النفاد')).toBeTruthy()
    expect(screen.getByText('طلبات بيع تحتاج تنفيذ')).toBeTruthy()
    expect(screen.getByText('فواتير مشتريات معلقة')).toBeTruthy()
    expect(screen.queryByLabelText('جاري تحميل القيمة')).toBeNull()
  })

  it.each([[], null])('retains zero fallbacks for absent counts and low-stock response %j', async rows => {
    renderDashboard()
    await waitFor(() => expect(new Set(countRequests().map(request => request.url.pathname)).size).toBe(6))
    await resolveCounts(true)
    await waitFor(() => expect(lowStockRequest()).toBeDefined())
    await resolveLowStock(rows)
    await waitFor(() => expect(metric('العملاء النشطون').getByText('0')).toBeTruthy())
    for (const label of ['المنتجات', 'المخازن النشطة', 'أصناف المخزون', 'طلبات معلقة']) {
      expect(metric(label).getByText('0')).toBeTruthy()
    }
    expect(screen.queryByText('تنبيهات المخزون')).toBeNull()
    expect(screen.queryByText('يحتاج متابعة')).toBeNull()
  })

  it('keeps restricted sections hidden after actual overview responses', async () => {
    renderDashboard([])
    await waitFor(() => expect(countRequests()).toHaveLength(6))
    await resolveCounts()
    await waitFor(() => expect(lowStockRequest()).toBeDefined())
    await resolveLowStock([{ total_count: '3' }])
    await waitFor(() => expect(metric('العملاء النشطون').getByText('12')).toBeTruthy())
    expect(screen.queryByText('إيرادات المبيعات')).toBeNull()
    expect(screen.queryByText('طلبات معلقة')).toBeNull()
    expect(screen.queryByText('تنبيهات المخزون')).toBeNull()
    expect(screen.queryByText('طلبات بيع تحتاج تنفيذ')).toBeNull()
    expect(screen.queryByText('فواتير مشتريات معلقة')).toBeNull()
    expect(screen.getByText('مرحباً بك')).toBeTruthy()
  })

  it('preserves the existing SDK transport-error fallback without fabricating low-stock rows', async () => {
    renderDashboard()
    await waitFor(() => expect(new Set(countRequests().map(request => request.url.pathname)).size).toBe(6))
    await resolveCounts()
    await waitFor(() => expect(lowStockRequest()).toBeDefined())
    await act(async () => lowStockRequest().reject(new TypeError('Synthetic network failure')))
    await waitFor(() => expect(metric('العملاء النشطون').getByText('12')).toBeTruthy())
    expect(screen.queryByText('تنبيهات المخزون')).toBeNull()
    // PostgREST returns an error result rather than rejecting; Dashboard already ignores it.
    expect(queryClient.getQueryData(['dashboard-overview'])).toMatchObject({ lowStockItems: 0 })
    expect(screen.getByText('طلبات بيع تحتاج تنفيذ')).toBeTruthy()
  })
})
