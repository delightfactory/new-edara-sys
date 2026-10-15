import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { useAuthStore } from '@/stores/auth-store'
import DashboardPage from './DashboardPage'
import type { MyProfile } from '@/lib/types/auth'

interface PendingRequest {
  path: string
  resolve: (response: Response) => void
}
const permissions = ['sales.read', 'finance.read', 'inventory.read']
const overview = { activeCustomers: 12, activeProducts: 28, activeWarehouses: 3,
  stockItems: 64, pendingSalesOrders: 4, pendingPurchaseInvoices: 2, lowStockItems: 3 }
const sales = { todayRevenue: 125, monthRevenue: 125, pendingOrders: 4, deliveredToday: 1 }
let requests: PendingRequest[]
let client: QueryClient

function profile(id = 'dashboard-actor-a'): MyProfile {
  return { id, full_name: 'مستخدم اختباري', email: null, phone: null, avatar_url: null,
    status: 'active', last_login_at: null, created_at: '2026-01-01', updated_at: '2026-01-01',
    roles: [], permissions }
}
function key(group: string, actor = 'dashboard-actor-a', granted = permissions) {
  return [`dashboard-${group}`, actor, [...new Set(granted)].sort()]
}
function mount(granted = permissions) {
  useAuthStore.getState().setProfile(profile())
  useAuthStore.getState().setPermissions(granted)
  client = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: Infinity } } })
  return render(<QueryClientProvider client={client}><MemoryRouter><DashboardPage /></MemoryRouter></QueryClientProvider>)
}
function metric(label: string) {
  const card = screen.getByText(label).closest('.ds-stat-card')
  if (!card) throw Error(`Missing metric: ${label}`)
  return within(card as HTMLElement)
}
function groupRequest(group: 'overview' | 'sales', batch = requests) {
  const request = batch.find(r => r.path.endsWith(`get_dashboard_${group}_metrics`))
  if (!request) throw Error(`Missing ${group} request`)
  return request
}
async function reply(request: PendingRequest, body: unknown, status = 200) {
  await act(async () => request.resolve(new Response(JSON.stringify(body), {
    status, headers: { 'content-type': 'application/json' },
  })))
}
async function complete(batch = requests, pending = 4) {
  for (const request of batch) await reply(request, request.path.endsWith('overview_metrics')
    ? { ...overview, pendingSalesOrders: pending } : { ...sales, pendingOrders: pending })
}

describe('Dashboard batched reads and loading regressions', () => {
  beforeEach(() => {
    requests = []
    useAuthStore.getState().reset()
    // Real SDK and query cache; only the HTTP boundary is synthetic.
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url)
      if (url.origin !== 'https://example.supabase.co') throw Error('Unexpected test host')
      if (url.pathname.endsWith('/targets')) return Promise.resolve(new Response('[]', {
        status: 200, headers: { 'content-type': 'application/json' },
      }))
      if (!/\/rpc\/get_dashboard_(overview|sales)_metrics$/.test(url.pathname)) throw Error(`Unexpected request: ${url.pathname}`)
      return new Promise<Response>(resolve => requests.push({ path: url.pathname, resolve }))
    }))
  })
  afterEach(() => { cleanup(); client?.clear(); useAuthStore.getState().reset(); vi.unstubAllGlobals() })

  it('loads each metrics group with one request and starts both independently', async () => {
    // 2026-10-16: dashboard request fan-out contributed to multi-second startup.
    mount()
    await waitFor(() => expect(requests).toHaveLength(2))
    expect(metric('العملاء النشطون').getByLabelText('جاري تحميل القيمة')).toBeTruthy()
    await reply(groupRequest('overview'), overview)
    await waitFor(() => expect(metric('العملاء النشطون').getByText('12')).toBeTruthy())
    expect(metric('إيرادات اليوم').getByLabelText('جاري تحميل القيمة')).toBeTruthy()
    expect(screen.getByText('3 صنف على وشك النفاد')).toBeTruthy()
    expect(screen.getByText('فواتير مشتريات معلقة')).toBeTruthy()
    await reply(groupRequest('sales'), sales)
    await waitFor(() => expect(metric('إيرادات اليوم').getByText('125.00')).toBeTruthy())
  })

  it('keeps restricted revenue sections hidden without requesting their data', async () => {
    mount([])
    await waitFor(() => expect(requests).toHaveLength(1))
    await reply(groupRequest('overview'), overview)
    await waitFor(() => expect(metric('العملاء النشطون').getByText('12')).toBeTruthy())
    expect(screen.queryByText('إيرادات المبيعات')).toBeNull()
    expect(screen.queryByText('تنبيهات المخزون')).toBeNull()
  })

  it.each(['overview', 'sales'] as const)('shows %s failure without false zeros, preserves the other group, and retries explicitly', async group => {
    mount()
    await waitFor(() => expect(requests).toHaveLength(2))
    const other = group === 'overview' ? 'sales' : 'overview'
    await reply(groupRequest(other), other === 'overview' ? overview : sales)
    await reply(groupRequest(group), { message: 'Synthetic unavailable', code: '503' }, 503)
    const errorText = group === 'overview' ? 'تعذّر تحميل مؤشرات النظام' : 'تعذّر تحميل مؤشرات المبيعات'
    await waitFor(() => expect(screen.getByText(errorText)).toBeTruthy())
    fireEvent.click(screen.getByRole('button', { name: group === 'overview' ? 'إعادة تحميل المؤشرات' : 'إعادة تحميل المبيعات' }))
    await waitFor(() => expect(requests).toHaveLength(3))
    await reply(requests[2], group === 'overview' ? overview : sales)
    await waitFor(() => expect(screen.queryByText(errorText)).toBeNull())
  })

  it('keeps cached values visibly stale when a sales refresh fails', async () => {
    mount()
    await waitFor(() => expect(requests).toHaveLength(2))
    await complete()
    await waitFor(() => expect(metric('إيرادات اليوم').getByText('125.00')).toBeTruthy())
    let refreshed!: Promise<void>
    act(() => { refreshed = client.refetchQueries({ queryKey: key('sales'), exact: true }) })
    await waitFor(() => expect(requests).toHaveLength(3))
    await reply(requests[2], { message: 'Synthetic unavailable', code: '503' }, 503)
    await act(async () => { await refreshed })
    expect(metric('إيرادات اليوم').getByText('125.00')).toBeTruthy()
    await waitFor(() => expect(screen.getByText('القيم المعروضة من آخر تحميل ناجح ولم تُحدّث.')).toBeTruthy())
    expect(metric('العملاء النشطون').getByText('12')).toBeTruthy()
  })

  it('does not reuse previous-actor in-flight responses', async () => {
    mount()
    await waitFor(() => expect(requests).toHaveLength(2))
    const actorA = [...requests]
    act(() => useAuthStore.getState().setProfile(null))
    act(() => useAuthStore.getState().setProfile(profile('dashboard-actor-b')))
    await waitFor(() => expect(requests).toHaveLength(4))
    await complete(requests.slice(2), 17)
    await waitFor(() => expect(metric('طلبات محددة').getByText('17')).toBeTruthy())
    await complete(actorA, 41)
    expect(metric('طلبات محددة').getByText('17')).toBeTruthy()
    expect(metric('طلبات معلقة').queryByText('41')).toBeNull()
  })

  it('retains the outer cache for canonical permission reorder and remount', async () => {
    const mounted = mount()
    await waitFor(() => expect(requests).toHaveLength(2))
    await complete()
    await waitFor(() => expect(metric('طلبات محددة').getByText('4')).toBeTruthy())
    act(() => useAuthStore.getState().setPermissions([...permissions].reverse().concat('sales.read')))
    mounted.unmount()
    render(<QueryClientProvider client={client}><MemoryRouter><DashboardPage /></MemoryRouter></QueryClientProvider>)
    expect(metric('طلبات محددة').getByText('4')).toBeTruthy()
    expect(requests).toHaveLength(2)
  })

  it('refreshes overview and sales independently and ignores superseded responses', async () => {
    mount()
    await waitFor(() => expect(requests).toHaveLength(2))
    await complete()
    await waitFor(() => expect(metric('طلبات محددة').getByText('4')).toBeTruthy())
    let first!: Promise<void>; let second!: Promise<void>; let replacement!: Promise<void>
    act(() => { first = client.refetchQueries({ queryKey: key('overview'), exact: true }) })
    await waitFor(() => expect(requests).toHaveLength(3))
    act(() => { second = client.refetchQueries({ queryKey: key('sales'), exact: true }) })
    await waitFor(() => expect(requests).toHaveLength(4))
    act(() => { replacement = client.refetchQueries({ queryKey: key('overview'), exact: true }) })
    await waitFor(() => expect(requests).toHaveLength(5))
    await reply(requests[4], { ...overview, pendingSalesOrders: 13 })
    await act(async () => { await replacement })
    await reply(requests[2], { ...overview, pendingSalesOrders: 6 })
    await reply(requests[3], { ...sales, pendingOrders: 8 })
    await act(async () => { await first; await second })
    expect(metric('طلبات معلقة').getByText('13')).toBeTruthy()
    await waitFor(() => expect(metric('طلبات محددة').getByText('8')).toBeTruthy())
  })

  it('honors same-actor permission denies without fetching revenue', async () => {
    mount()
    await waitFor(() => expect(requests).toHaveLength(2))
    await complete()
    await waitFor(() => expect(metric('طلبات محددة').getByText('4')).toBeTruthy())
    act(() => useAuthStore.getState().setPermissions(['*', '!sales.read']))
    expect(screen.queryByText('إيرادات المبيعات')).toBeNull()
    await waitFor(() => expect(requests).toHaveLength(3))
    expect(requests[2].path).toContain('overview_metrics')
    await reply(requests[2], overview)
  })
})
