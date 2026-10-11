const profileId = '00000000-0000-4000-8000-000000000001'
const stamp = '2026-01-01T00:00:00Z'
export const customerName = 'شركة الاختبار الصناعي لتجارة وتوزيع المنتجات ذات الاسم العربي الطويل'
export const profile = {
  id: profileId, full_name: 'أحمد الاختبار الصناعي ذو الاسم العربي الطويل',
  email: 'synthetic@example.invalid', phone: null, avatar_url: null,
  status: 'active', last_login_at: null, created_at: stamp, updated_at: stamp,
  roles: [{ id: 'synthetic-admin', name: 'admin', name_ar: 'مدير صناعي', color: '#2563eb' }],
  permissions: ['*'],
}

export function syntheticSession() {
  const expiresAt = Math.floor(Date.now() / 1000) + 3600
  const encode = object => Buffer.from(JSON.stringify(object)).toString('base64url')
  return {
    access_token: `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode({ sub: profileId, role: 'authenticated', exp: expiresAt })}.synthetic`,
    refresh_token: 'synthetic-refresh-token', token_type: 'bearer', expires_in: 3600,
    expires_at: expiresAt, user: { id: profileId, aud: 'authenticated', role: 'authenticated', email: profile.email, app_metadata: {}, user_metadata: {}, created_at: stamp },
  }
}

const counts = { customers: 12, products: 28, warehouses: 3, stock: 64, sales_orders: 4, purchase_invoices: 2 }
const customer = {
  id: '00000000-0000-4000-8000-000000000002', code: 'SYN-001', name: customerName,
  type: 'retail', governorate_id: null, city_id: null, area_id: null, address: null,
  phone: null, mobile: null, email: null, tax_number: null, payment_terms: 'cash',
  credit_limit: 0, credit_days: 0, price_list_id: null, assigned_rep_id: null,
  opening_balance: 0, current_balance: 0, latitude: null, longitude: null,
  location_accuracy: null, location_updated_at: null, location_updated_by: null, created_by: null,
  is_active: true, notes: null, created_at: stamp, updated_at: stamp,
  governorate: null, city: null, assigned_rep: null,
}

function reply(body, status = 200, headers = {}) {
  return { status, headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(body) }
}

export function fixtureResponse(request, scenario, state) {
  const url = new URL(request.url())
  const method = request.method()
  const path = url.pathname
  if (method === 'POST' && path === '/rest/v1/rpc/get_my_profile') {
    state.profileAttempts += 1
    if (scenario.kind === 'signedout') return reply({ code: 'PGRST116', message: 'Synthetic session missing' }, 406)
    if (scenario.kind === 'retry' && !state.allowProfileRecovery) return reply({ code: '503', message: 'Synthetic transient unavailable' }, 503)
    return reply({ ...profile, status: scenario.kind === 'inactive' ? 'inactive' : 'active' })
  }
  if (method === 'POST' && path === '/rest/v1/rpc/get_my_permission_denials') {
    return reply(scenario.kind === 'limited'
      ? ['!auth.users.read', '!sales.read', '!finance.read', '!finance.view_costs', '!inventory.read'].map(permission => ({ permission }))
      : [])
  }
  if (method === 'POST' && path === '/rest/v1/rpc/get_unread_notifications_count') return reply(0)
  if (method === 'POST' && path === '/rest/v1/rpc/get_low_stock') {
    const body = request.postDataJSON()
    if (body.p_warehouse_id !== null || body.p_offset !== 0 || body.p_limit !== 1) throw new Error('Unexpected low-stock contract')
    if (scenario.kind === 'dashboard-error' && scenario.errorGroup === 'overview' && !state.allowDashboardRecovery) {
      return reply({ code: '503', message: 'Synthetic dashboard unavailable' }, 503)
    }
    return reply([{ total_count: '3' }])
  }
  if (method === 'POST' && path === '/auth/v1/logout') return { status: 204 }
  if (method === 'PATCH' && path === '/rest/v1/profiles'
    && url.searchParams.get('id') === `eq.${profileId}`
    && Object.keys(request.postDataJSON()).join() === 'last_login_at') return { status: 204 }
  const table = path.startsWith('/rest/v1/') ? path.slice('/rest/v1/'.length) : ''
  if (method === 'HEAD' && Object.hasOwn(counts, table) && url.searchParams.get('select') === 'id') {
    return { status: 200, headers: { 'content-range': `*/${counts[table]}` } }
  }
  if (method === 'GET' && table === 'sales_orders' && url.searchParams.get('select') === 'total_amount'
    && url.searchParams.get('status') === 'eq.delivered' && url.searchParams.has('created_at')) {
    if (scenario.kind === 'dashboard-error' && scenario.errorGroup === 'sales' && !state.allowDashboardRecovery) {
      return reply({ code: '503', message: 'Synthetic sales unavailable' }, 503)
    }
    return reply([{ total_amount: 100 }])
  }
  if (method === 'GET' && table === 'targets' && url.searchParams.get('is_active') === 'eq.true') return reply([], 200, { 'content-range': '*/0' })
  if (method === 'GET' && table === 'customers' && url.searchParams.get('is_active') === 'eq.true'
    && url.searchParams.get('select')?.includes('assigned_rep:profiles')) return reply([customer], 200, { 'content-range': '0-0/1' })
  if (method === 'GET' && table === 'governorates' && url.searchParams.get('select') === '*') return reply([])
  if (method === 'GET' && table === 'cities' && url.searchParams.get('select')?.startsWith('*,governorate:')) return reply([])
  if (method === 'GET' && table === 'profiles' && url.searchParams.get('status') === 'eq.active') return reply([profile])
  throw new Error(`Unqualified fixture: ${method} ${path}`)
}

export function isOverviewRequest(request) {
  const path = new URL(request.url()).pathname
  return (request.method() === 'HEAD' && Object.hasOwn(counts, path.slice('/rest/v1/'.length)))
    || path === '/rest/v1/rpc/get_low_stock'
}

export function realtimeReply(message) {
  const [joinRef, ref, topic, event, payload] = JSON.parse(message)
  if (topic !== 'phoenix' && topic !== 'realtime:global-realtime' && topic !== `realtime:notifications:${profileId}`) {
    throw new Error('Unqualified realtime topic')
  }
  if (event === 'access_token') return null
  if (!['phx_join', 'phx_leave', 'heartbeat'].includes(event)) throw new Error(`Unqualified realtime event: ${event}`)
  const response = event === 'phx_join'
    ? { postgres_changes: (payload.config?.postgres_changes ?? []).map((change, id) => ({ ...change, id })) }
    : {}
  return JSON.stringify([joinRef, ref, topic, 'phx_reply', { status: 'ok', response }])
}
