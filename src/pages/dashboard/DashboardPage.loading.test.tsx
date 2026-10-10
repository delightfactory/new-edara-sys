import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, cleanup, render, screen, waitFor, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { useAuthStore } from '@/stores/auth-store'
import DashboardPage from './DashboardPage'
import type { MyProfile } from '@/lib/types/auth'

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
let deferRevenue: boolean
let observedRequests: { url: URL; method: string }[]
const dashboardPermissions = ['sales.read', 'finance.read', 'inventory.read']

function profile(id = 'dashboard-actor-a'): MyProfile {
  return {
    id, full_name: 'مستخدم اختباري', email: null, phone: null, avatar_url: null,
    status: 'active', last_login_at: null, created_at: '2026-01-01', updated_at: '2026-01-01',
    roles: [], permissions: dashboardPermissions,
  }
}

function dashboardKey(group: 'overview' | 'sales', id = 'dashboard-actor-a', permissions = dashboardPermissions) {
  return [`dashboard-${group}`, id, [...new Set(permissions)].sort()]
}

function renderDashboard(permissions = dashboardPermissions) {
  useAuthStore.getState().setProfile(profile())
  useAuthStore.getState().setPermissions(permissions)
  queryClient = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: Infinity } } })
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter>
        <DashboardPage />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

function pendingSalesRequests(requests = pendingRequests) {
  return requests.filter(request => request.init?.method === 'HEAD'
    && request.url.pathname === '/rest/v1/sales_orders'
    && request.url.searchParams.get('status') === 'in.(confirmed,partially_delivered)')
}

async function completeRequests(requests: PendingRequest[], pendingCount = 4) {
  await act(async () => {
    for (const request of requests) {
      if (request.init?.method === 'HEAD') {
        const table = request.url.pathname.split('/').pop()!
        const count = pendingSalesRequests([request]).length ? pendingCount : counts[table]
        request.resolve(new Response(null, { status: 200, headers: { 'content-range': `*/${count}` } }))
      } else {
        const rows = request.url.pathname.endsWith('/get_low_stock') ? [{ total_count: '3' }] : [{ total_amount: 125 }]
        request.resolve(new Response(JSON.stringify(rows), { status: 200, headers: { 'content-type': 'application/json' } }))
      }
    }
  })
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
    observedRequests = []
    deferRevenue = false
    // Exercise the real Supabase SDK at its HTTP boundary; never send live traffic.
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url)
      if (url.origin !== 'https://example.supabase.co') throw new Error(`Unexpected test host: ${url.origin}`)
      observedRequests.push({ url, method: init?.method ?? 'GET' })
      if (init?.method === 'HEAD' || url.pathname === '/rest/v1/rpc/get_low_stock'
        || (deferRevenue && url.pathname === '/rest/v1/sales_orders')) {
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
    expect(queryClient.getQueryData(dashboardKey('overview'))).toMatchObject({ lowStockItems: 0 })
    expect(screen.getByText('طلبات بيع تحتاج تنفيذ')).toBeTruthy()
  })

  it('shares one cold pending-sales request while both loading groups start independently', async () => {
    deferRevenue = true
    renderDashboard()
    await waitFor(() => expect(pendingRequests.length).toBeGreaterThanOrEqual(10))
    expect(pendingSalesRequests()).toHaveLength(1)
    expect(pendingRequests).toHaveLength(10)
    const request = pendingSalesRequests()[0]
    expect(request.url.searchParams.get('select')).toBe('id')
    expect(new Headers(request.init?.headers).get('prefer')).toBe('count=estimated')
    expect(metric('طلبات معلقة').getByLabelText('جاري تحميل القيمة')).toBeTruthy()
    expect(metric('طلبات محددة').getByLabelText('جاري تحميل القيمة')).toBeTruthy()
    const salesOnly = pendingRequests.filter(candidate => candidate.url.pathname === '/rest/v1/sales_orders')
    await completeRequests(salesOnly, 9)
    await waitFor(() => expect(metric('طلبات محددة').getByText('9')).toBeTruthy())
    expect(metric('طلبات معلقة').getByLabelText('جاري تحميل القيمة')).toBeTruthy()
    await completeRequests(pendingRequests.filter(candidate => !salesOnly.includes(candidate)))
    await waitFor(() => expect(metric('طلبات معلقة').getByText('9')).toBeTruthy())
    expect(queryClient.getQueryData(dashboardKey('sales'))).toMatchObject({ todayRevenue: 125, monthRevenue: 125, pendingOrders: 9 })
  })

  it('preserves shared pending-count transport failure as zero in both groups', async () => {
    renderDashboard()
    await waitFor(() => expect(countRequests()).toHaveLength(7))
    const request = pendingSalesRequests()[0]
    await act(async () => request.reject(new TypeError('Synthetic pending-count failure')))
    await completeRequests(pendingRequests.filter(candidate => candidate !== request))
    await waitFor(() => expect(metric('طلبات معلقة').getByText('0')).toBeTruthy())
    expect(metric('طلبات محددة').getByText('0')).toBeTruthy()
    expect(queryClient.getQueryData(dashboardKey('sales'))).toMatchObject({ pendingOrders: 0 })
  })

  it('requests fresh counts for independent and overlapping refetches with existing data', async () => {
    renderDashboard()
    await waitFor(() => expect(countRequests()).toHaveLength(7))
    await completeRequests([...pendingRequests])
    await waitFor(() => expect(metric('طلبات محددة').getByText('4')).toBeTruthy())

    const overviewStart = pendingRequests.length
    let overviewRefresh!: Promise<void>
    act(() => { overviewRefresh = queryClient.refetchQueries({ queryKey: dashboardKey('overview'), exact: true }) })
    await waitFor(() => expect(pendingRequests.slice(overviewStart)).toHaveLength(7))
    const overviewRequests = pendingRequests.slice(overviewStart)
    expect(pendingSalesRequests(overviewRequests)).toHaveLength(1)

    const salesStart = pendingRequests.length
    let salesRefresh!: Promise<void>
    act(() => { salesRefresh = queryClient.refetchQueries({ queryKey: dashboardKey('sales'), exact: true }) })
    await waitFor(() => expect(pendingRequests.slice(salesStart)).toHaveLength(2))
    const salesRequests = pendingRequests.slice(salesStart)
    expect(pendingSalesRequests(salesRequests)).toHaveLength(1)

    const replacementStart = pendingRequests.length
    let replacementRefresh!: Promise<void>
    act(() => { replacementRefresh = queryClient.refetchQueries({ queryKey: dashboardKey('overview'), exact: true }) })
    await waitFor(() => expect(pendingRequests.slice(replacementStart)).toHaveLength(7))
    const replacementRequests = pendingRequests.slice(replacementStart)
    expect(pendingSalesRequests(replacementRequests)).toHaveLength(1)
    await completeRequests(replacementRequests, 13)
    await act(async () => { await replacementRefresh })
    await waitFor(() => expect(metric('طلبات معلقة').getByText('13')).toBeTruthy())
    await completeRequests(overviewRequests, 6)
    await completeRequests(salesRequests, 8)
    await act(async () => { await overviewRefresh; await salesRefresh })
    expect(metric('طلبات معلقة').getByText('13')).toBeTruthy()
    await waitFor(() => expect(metric('طلبات محددة').getByText('8')).toBeTruthy())
  })

  it('reuses the outer 60-second cache on remount and canonical permission reorder', async () => {
    const mounted = renderDashboard()
    await waitFor(() => expect(countRequests()).toHaveLength(7))
    await completeRequests([...pendingRequests])
    await waitFor(() => expect(metric('طلبات محددة').getByText('4')).toBeTruthy())
    const requestCount = pendingRequests.length
    act(() => useAuthStore.getState().setPermissions([...dashboardPermissions].reverse().concat('sales.read')))
    expect(metric('طلبات محددة').getByText('4')).toBeTruthy()
    mounted.unmount()
    render(<QueryClientProvider client={queryClient}><MemoryRouter><DashboardPage /></MemoryRouter></QueryClientProvider>)
    expect(metric('طلبات محددة').getByText('4')).toBeTruthy()
    await act(async () => { await Promise.resolve() })
    expect(pendingRequests).toHaveLength(requestCount)
    expect(queryClient.getQueryState(dashboardKey('overview'))?.dataUpdatedAt).toBeGreaterThan(0)
  })

  it('isolates a new actor from pending and cached previous-actor dashboard results', async () => {
    renderDashboard()
    await waitFor(() => expect(countRequests()).toHaveLength(7))
    const actorARequests = [...pendingRequests]
    act(() => useAuthStore.getState().setProfile(null))
    expect(metric('طلبات معلقة').queryByText('4')).toBeNull()
    await act(async () => { await Promise.resolve() })
    expect(pendingRequests).toHaveLength(actorARequests.length)
    act(() => useAuthStore.getState().setProfile(profile('dashboard-actor-b')))
    await waitFor(() => expect(pendingRequests.slice(actorARequests.length)).toHaveLength(8))
    const actorBRequests = pendingRequests.slice(actorARequests.length)
    expect(pendingSalesRequests(actorBRequests)).toHaveLength(1)
    await completeRequests(actorBRequests, 17)
    await waitFor(() => expect(metric('طلبات محددة').getByText('17')).toBeTruthy())
    await completeRequests(actorARequests, 41)
    await waitFor(() => expect(queryClient.getQueryData(dashboardKey('overview'))).toMatchObject({ pendingSalesOrders: 41 }))
    expect(metric('طلبات معلقة').getByText('17')).toBeTruthy()
    expect(metric('طلبات محددة').queryByText('41')).toBeNull()
    expect(queryClient.getQueryData(dashboardKey('sales', 'dashboard-actor-b'))).toMatchObject({ pendingOrders: 17 })
  })

  it('does not reuse a settled shared count when the outer cold caches are removed', async () => {
    const mounted = renderDashboard()
    await waitFor(() => expect(countRequests()).toHaveLength(7))
    await completeRequests([...pendingRequests])
    await waitFor(() => expect(metric('طلبات محددة').getByText('4')).toBeTruthy())
    mounted.unmount()
    queryClient.removeQueries({ queryKey: ['dashboard-overview'] })
    queryClient.removeQueries({ queryKey: ['dashboard-sales'] })
    const previousCount = pendingRequests.length
    render(<QueryClientProvider client={queryClient}><MemoryRouter><DashboardPage /></MemoryRouter></QueryClientProvider>)
    await waitFor(() => expect(pendingRequests.slice(previousCount)).toHaveLength(8))
    const newRequests = pendingRequests.slice(previousCount)
    expect(pendingSalesRequests(newRequests)).toHaveLength(1)
    await completeRequests(newRequests, 23)
    await waitFor(() => expect(metric('طلبات محددة').getByText('23')).toBeTruthy())
    expect(metric('طلبات معلقة').getByText('23')).toBeTruthy()
  })

  it('reacts to same-actor permission denies and never requests restricted revenues', async () => {
    renderDashboard()
    await waitFor(() => expect(countRequests()).toHaveLength(7))
    await completeRequests([...pendingRequests])
    await waitFor(() => expect(metric('طلبات محددة').getByText('4')).toBeTruthy())
    const beforeDeny = pendingRequests.length
    const wireBeforeDeny = observedRequests.length
    const denied = ['*', '!sales.read']
    act(() => useAuthStore.getState().setPermissions(denied))
    expect(screen.queryByText('إيرادات المبيعات')).toBeNull()
    await waitFor(() => expect(pendingRequests.slice(beforeDeny)).toHaveLength(7))
    const deniedRequests = pendingRequests.slice(beforeDeny)
    expect(deniedRequests.filter(request => request.url.pathname === '/rest/v1/sales_orders')).toHaveLength(1)
    expect(pendingSalesRequests(deniedRequests)).toHaveLength(1)
    expect(observedRequests.slice(wireBeforeDeny).filter(request =>
      request.url.pathname === '/rest/v1/sales_orders' && request.method === 'GET')).toHaveLength(0)
    await completeRequests(deniedRequests, 11)
    await waitFor(() => expect(queryClient.getQueryData(dashboardKey('overview', 'dashboard-actor-a', denied))).toMatchObject({ pendingSalesOrders: 11 }))
    act(() => useAuthStore.getState().setPermissions(dashboardPermissions))
    expect(metric('طلبات محددة').getByText('4')).toBeTruthy()
    expect(metric('طلبات معلقة').getByText('4')).toBeTruthy()
  })
})
