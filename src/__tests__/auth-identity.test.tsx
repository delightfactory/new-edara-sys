import { StrictMode, useEffect } from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import { QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import { AuthProvider } from '@/components/layout/AuthProvider'
import { ProtectedRoute } from '@/components/layout/ProtectedRoute'
import GlobalRealtimeManager from '@/components/shared/GlobalRealtimeManager'
import { queryClient } from '@/lib/query-client'
import { useAuthStore, saveAuthCache } from '@/stores/auth-store'
import { useNotificationStore } from '@/stores/notification-store'
import { useUnreadCountQuery, useMarkAsReadMutation, useMarkAllAsReadMutation } from '@/hooks/useNotificationQueries'
import type { MyProfile } from '@/lib/types/auth'
import { syntheticAuthSession, syntheticTokenActor } from './synthetic-auth'
import { notificationKeys } from '@/lib/notifications/query-keys'

const sdk = vi.hoisted(() => ({ client: null as SupabaseClient | null }))
// Inject a real first-party SDK client with private synthetic storage/transport.
// No SDK methods, auth events, stores, query functions or components are mocked.
vi.mock('@/lib/supabase/client', () => ({ get supabase() { return sdk.client! } }))

type Pending = { actor: string; reply: (value: unknown, status?: number) => void }
let profiles: Pending[]
let unread: Pending[]
let mutations: Pending[]
let patches: { actor: string; id: string | null }[]
let refresh: ((value: unknown) => void) | null
let holdRefresh: boolean
let holdUnread: boolean
let mounts: string[]
let unmounts: string[]
let socketTopics: string[]
let sockets: SyntheticSocket[]
let sequence = 0

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: { 'content-type': 'application/json' } })
}

function profile(id: string): MyProfile {
  return { id, full_name: id, email: null, phone: null, avatar_url: null, status: 'active', last_login_at: null,
    created_at: '2026-01-01', updated_at: '2026-01-01', roles: [], permissions: ['customers.read'] }
}

class SyntheticSocket extends EventTarget {
  readonly CONNECTING = 0
  readonly OPEN = 1
  readonly CLOSING = 2
  readonly CLOSED = 3
  readyState = 0
  protocol = ''
  onopen: ((event: Event) => void) | null = null
  onmessage: ((event: MessageEvent) => void) | null = null
  onclose: ((event: CloseEvent) => void) | null = null
  onerror: ((event: Event) => void) | null = null
  readonly url: string
  constructor(address: string | URL) {
    super()
    this.url = String(address)
    const parsed = new URL(this.url)
    if (parsed.origin !== 'wss://identity-test.supabase.co' || parsed.pathname !== '/realtime/v1/websocket') throw new Error('Unexpected websocket boundary')
    sockets.push(this)
    queueMicrotask(() => { this.readyState = 1; this.onopen?.(new Event('open')) })
  }
  send(data: string | ArrayBufferLike | Blob | ArrayBufferView) {
    if (typeof data !== 'string') throw new Error('Unexpected binary socket message')
    const [joinRef, ref, topic, event, payload] = JSON.parse(data) as [string, string, string, string, { config?: { postgres_changes?: Record<string, unknown>[] } }]
    if (!['phoenix', 'realtime:global-realtime', 'realtime:notifications:actor-a', 'realtime:notifications:actor-b'].includes(topic)) throw new Error('Unexpected realtime topic')
    if (event === 'access_token') return
    if (!['phx_join', 'phx_leave', 'heartbeat'].includes(event)) throw new Error('Unexpected realtime event')
    if (event === 'phx_join') socketTopics.push(topic)
    const response = event === 'phx_join' ? { postgres_changes: (payload.config?.postgres_changes ?? []).map((row, id) => ({ ...row, id })) } : {}
    queueMicrotask(() => this.onmessage?.(new MessageEvent('message', { data: JSON.stringify([joinRef, ref, topic, 'phx_reply', { status: 'ok', response }]) })))
  }
  close() { this.readyState = 3; this.onclose?.(new CloseEvent('close')) }
}

function createSdk(actor: string | null, expired = false) {
  const storageKey = `edara-c2b-${++sequence}`
  const storage = new Map<string, string>()
  if (actor) storage.set(storageKey, JSON.stringify(syntheticAuthSession(actor, expired ? -3600 : 3600)))
  return createClient('https://identity-test.supabase.co', 'synthetic-only-key', {
    auth: { storageKey, persistSession: true, autoRefreshToken: false, detectSessionInUrl: false,
      storage: { getItem: key => storage.get(key) ?? null, setItem: (key, value) => { storage.set(key, value) }, removeItem: key => { storage.delete(key) } } },
    realtime: { transport: SyntheticSocket },
    global: { fetch: async (input, init) => {
      const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url)
      if (url.origin !== 'https://identity-test.supabase.co') throw new Error('Unexpected external HTTP')
      const method = init?.method ?? 'GET'
      if (method === 'POST' && url.pathname === '/auth/v1/token' && url.searchParams.get('grant_type') === 'refresh_token') {
        if (!holdRefresh) throw new Error('Unexpected token refresh')
        return new Promise<Response>(resolve => { refresh = value => resolve(json(value)) })
      }
      if (method === 'POST' && url.pathname === '/auth/v1/logout') return new Response(null, { status: 204 })
      const actorId = syntheticTokenActor(init?.headers).sub
      if (!['actor-a', 'actor-b'].includes(actorId)) throw new Error('Unexpected synthetic actor')
      if (method === 'GET' && url.pathname === '/auth/v1/user') return json({ user: syntheticAuthSession(actorId).user })
      if (method === 'POST' && url.pathname === '/rest/v1/rpc/get_my_profile') {
        return new Promise<Response>(resolve => profiles.push({ actor: actorId, reply: (value, status) => resolve(json(value, status)) }))
      }
      if (method === 'POST' && url.pathname === '/rest/v1/rpc/get_my_permission_denials') return json([])
      if (method === 'POST' && ['/rest/v1/rpc/mark_notification_read', '/rest/v1/rpc/mark_all_notifications_read'].includes(url.pathname)) {
        return new Promise<Response>(resolve => mutations.push({ actor: actorId, reply: (value, status) => resolve(json(value, status)) }))
      }
      if (method === 'POST' && url.pathname === '/rest/v1/rpc/get_unread_notifications_count') {
        if (!holdUnread) return json(0)
        return new Promise<Response>(resolve => unread.push({ actor: actorId, reply: value => resolve(json(value)) }))
      }
      if (method === 'PATCH' && url.pathname === '/rest/v1/profiles') {
        const id = url.searchParams.get('id')
        if (id !== `eq.${actorId}`) throw new Error('Cross-actor synthetic profile PATCH')
        patches.push({ actor: actorId, id })
        return new Response(null, { status: 204 })
      }
      throw new Error(`Unqualified HTTP: ${method} ${url.pathname}`)
    } },
  })
}

function ActorView() {
  const actor = useAuthStore(s => s.profile!.id)
  const count = useNotificationStore(s => s.unreadCount)
  useUnreadCountQuery()
  const markRead = useMarkAsReadMutation()
  const markAll = useMarkAllAsReadMutation()
  useEffect(() => { mounts.push(actor); return () => { unmounts.push(actor) } }, [actor])
  return <><div>مستخدم {actor} إشعارات {count}</div>
    <button onClick={() => markRead.mutate('old-a-note')}>قراءة إشعار</button>
    <button onClick={() => markAll.mutate(undefined)}>قراءة الكل</button></>
}

function renderApp(strict = false) {
  const app = <QueryClientProvider client={queryClient}><MemoryRouter><AuthProvider>
    <GlobalRealtimeManager />
    <Routes><Route path="/" element={<ProtectedRoute><ActorView /></ProtectedRoute>} /><Route path="/login" element={<div>شاشة الدخول</div>} /></Routes>
  </AuthProvider></MemoryRouter></QueryClientProvider>
  return render(strict ? <StrictMode>{app}</StrictMode> : app)
}

async function settled(check: () => void) {
  await act(async () => { await vi.advanceTimersByTimeAsync(50) })
  await vi.waitFor(check)
}
async function switchActor(id: 'actor-a' | 'actor-b') {
  await act(async () => { const result = await sdk.client!.auth.setSession(syntheticAuthSession(id)); expect(result.error).toBeNull() })
}
async function publish(index: number, id: string) {
  await settled(() => expect(profiles[index]?.actor).toBe(id))
  await act(async () => { profiles[index].reply(profile(id)); await vi.advanceTimersByTimeAsync(1) })
}
function cache(id: string) {
  const cached = profile(id)
  saveAuthCache(cached, cached.permissions)
  useAuthStore.setState({ profile: cached, permissions: cached.permissions, hasSession: true, isInitialized: true,
    isLoading: false, sessionUserId: null, isIdentityVerified: false })
}

beforeEach(() => {
  vi.useFakeTimers()
  useAuthStore.getState().reset()
  useAuthStore.setState({ isIdentityVerified: false })
  queryClient.clear()
  useNotificationStore.setState({ unreadCount: 0, isPanelOpen: false })
  profiles = []; unread = []; mutations = []; patches = []; mounts = []; unmounts = []; socketTopics = []
  refresh = null; holdRefresh = false; holdUnread = false
  sockets = []
  sdk.client = createSdk('actor-a')
})
afterEach(async () => {
  cleanup()
  useAuthStore.getState().reset()
  queryClient.clear()
  await sdk.client!.removeAllChannels()
  sdk.client!.realtime.disconnect()
  await sdk.client!.auth.stopAutoRefresh()
  vi.clearAllTimers()
  vi.useRealTimers()
})

describe('verified identity before cached UI and realtime', () => {
  it('hides cached identity and all channels while real SDK initialization waits on refresh HTTP', async () => {
    holdRefresh = true
    sdk.client = createSdk('actor-a', true)
    cache('actor-a')
    renderApp()
    await settled(() => expect(refresh).not.toBeNull())
    expect(screen.queryByText(/مستخدم actor-a/)).toBeNull()
    expect(sdk.client.getChannels()).toHaveLength(0)
    expect(profiles).toHaveLength(0)
    await act(async () => { refresh!(syntheticAuthSession('actor-a')); await vi.advanceTimersByTimeAsync(1) })
    await settled(() => expect(screen.getByText(/مستخدم actor-a/)).toBeTruthy())
    expect(profiles).toHaveLength(1)
    expect(useAuthStore.getState().isLoading).toBe(true)
    await publish(0, 'actor-a')
  })

  it('never paints or subscribes the mismatched cached actor', async () => {
    cache('actor-b')
    queryClient.setQueryData(['old-actor-data'], 'actor-b-private')
    renderApp()
    expect(screen.queryByText(/مستخدم actor-b/)).toBeNull()
    await publish(0, 'actor-a')
    expect(screen.getByText(/مستخدم actor-a/)).toBeTruthy()
    expect(mounts).not.toContain('actor-b')
    expect(socketTopics).not.toContain('realtime:notifications:actor-b')
    expect(queryClient.getQueryData(['old-actor-data'])).toBeUndefined()
  })

  it('opens public login and clears cache when SDK has no session', async () => {
    sdk.client = createSdk(null)
    cache('actor-a')
    renderApp()
    await settled(() => expect(screen.getByText('شاشة الدخول')).toBeTruthy())
    expect(profiles).toHaveLength(0)
    expect(sdk.client.getChannels()).toHaveLength(0)
    expect(sessionStorage.getItem('edara_auth_v1')).toBeNull()
  })

  it('does not drop actor B SIGNED_IN while actor A profile request is pending', async () => {
    renderApp()
    await settled(() => expect(profiles[0]?.actor).toBe('actor-a'))
    await switchActor('actor-b')
    await publish(1, 'actor-b')
    await act(async () => { profiles[0].reply(profile('actor-a')); await vi.advanceTimersByTimeAsync(1) })
    expect(screen.getByText(/مستخدم actor-b/)).toBeTruthy()
    expect(mounts).not.toContain('actor-a')
    expect(useAuthStore.getState().profile?.id).toBe('actor-b')
  })

  it('remounts the actor subtree, removes old channels and rejects a late unread count', async () => {
    holdUnread = true
    renderApp()
    await publish(0, 'actor-a')
    await settled(() => expect(unread[0]?.actor).toBe('actor-a'))
    useNotificationStore.setState({ unreadCount: 7, isPanelOpen: true })
    queryClient.setQueryData(['old-actor-data'], 'actor-a-private')
    await switchActor('actor-b')
    await publish(1, 'actor-b')
    await settled(() => expect(unread[1]?.actor).toBe('actor-b'))
    await act(async () => { unread[1].reply(2); unread[0].reply(99); await vi.advanceTimersByTimeAsync(1) })
    expect(screen.getByText(/مستخدم actor-b إشعارات 2/)).toBeTruthy()
    expect(queryClient.getQueryData(notificationKeys.unreadCount())).toBe(2)
    expect(unmounts).toContain('actor-a')
    expect(queryClient.getQueryData(['old-actor-data'])).toBeUndefined()
    expect(useNotificationStore.getState().isPanelOpen).toBe(false)
    expect(sdk.client!.getChannels().map(channel => channel.topic)).not.toContain('realtime:notifications:actor-a')
    expect(sdk.client!.getChannels().map(channel => channel.topic)).toContain('realtime:notifications:actor-b')
  })

  it('retains an active SDK subscription after StrictMode replay and handles logout', async () => {
    renderApp(true)
    await publish(0, 'actor-a')
    expect(profiles).toHaveLength(1)
    await act(async () => { await sdk.client!.auth.signOut() })
    await settled(() => expect(screen.getByText('شاشة الدخول')).toBeTruthy())
    expect(useAuthStore.getState().hasSession).toBe(false)
    expect(sdk.client!.getChannels()).toHaveLength(0)
  })

  it('keeps same-actor verified cache after profile failure', async () => {
    cache('actor-a')
    renderApp()
    await settled(() => expect(profiles[0]?.actor).toBe('actor-a'))
    await act(async () => { profiles[0].reply({ code: '500', message: 'Synthetic unavailable' }, 500); await vi.advanceTimersByTimeAsync(1) })
    expect(screen.getByText(/مستخدم actor-a/)).toBeTruthy()
    expect(useAuthStore.getState().profileLoadError).toBe('rpc_error')
  })

  it('rejects a mismatched profile and exposes the existing retry action', async () => {
    renderApp()
    await settled(() => expect(profiles[0]?.actor).toBe('actor-a'))
    await act(async () => { profiles[0].reply(profile('actor-b')); await vi.advanceTimersByTimeAsync(1) })
    expect(useAuthStore.getState().profile).toBeNull()
    expect(useAuthStore.getState().profileLoadError).toBe('identity_mismatch')
    expect(screen.queryByText(/مستخدم actor-b/)).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'إعادة المحاولة' }))
    await publish(1, 'actor-a')
    expect(screen.getByText(/مستخدم actor-a/)).toBeTruthy()
  })

  it('replaces a deferred actor A load with actor B before either RPC starts', async () => {
    renderApp()
    await act(async () => {
      await sdk.client!.auth.getSession()
      const result = await sdk.client!.auth.setSession(syntheticAuthSession('actor-b'))
      expect(result.error).toBeNull()
    })
    expect(profiles).toHaveLength(0)
    await publish(0, 'actor-b')
    expect(profiles).toHaveLength(1)
    expect(mounts).not.toContain('actor-a')
  })

  it('retires a deferred load when real SDK logout arrives before the timer fires', async () => {
    renderApp()
    await act(async () => { await sdk.client!.auth.getSession(); await sdk.client!.auth.signOut() })
    await settled(() => expect(screen.getByText('شاشة الدخول')).toBeTruthy())
    await act(async () => { await vi.advanceTimersByTimeAsync(2100) })
    expect(profiles).toHaveLength(0)
    expect(patches).toHaveLength(0)
    expect(queryClient.getQueryCache().getAll()).toHaveLength(0)
  })

  it('exposes bounded bootstrap recovery while SDK initialization is still pending', async () => {
    holdRefresh = true
    sdk.client = createSdk('actor-a', true)
    cache('actor-a')
    renderApp()
    await settled(() => expect(refresh).not.toBeNull())
    await act(async () => { await vi.advanceTimersByTimeAsync(15_001) })
    expect(screen.getByText('تعذّر التحقق من الجلسة')).toBeTruthy()
    expect(screen.queryByText(/مستخدم actor-a/)).toBeNull()
    expect(sdk.client.getChannels()).toHaveLength(0)
    fireEvent.click(screen.getByRole('button', { name: 'إعادة المحاولة' }))
    await act(async () => { refresh!(syntheticAuthSession('actor-a')); await vi.advanceTimersByTimeAsync(1) })
    await publish(0, 'actor-a')
    expect(screen.getByText(/مستخدم actor-a/)).toBeTruthy()
    expect(screen.queryByText('تعذّر التحقق من الجلسة')).toBeNull()
  })

  it('ignores an old realtime notification delivered during the actor transition', async () => {
    renderApp()
    await publish(0, 'actor-a')
    await settled(() => expect(socketTopics).toContain('realtime:notifications:actor-a'))
    await act(async () => {
      const result = await sdk.client!.auth.setSession(syntheticAuthSession('actor-b'))
      expect(result.error).toBeNull()
      // Deliver through the real SDK before React cleans up the old subtree.
      sockets[0].onmessage?.(new MessageEvent('message', { data: JSON.stringify([null, null, 'realtime:notifications:actor-a', 'postgres_changes', {
        ids: [0], data: { schema: 'public', table: 'notifications', type: 'INSERT', columns: [], record: {
          id: 'old-notification', user_id: 'actor-a', priority: 'high', category: 'system', title: 'إشعار الحساب السابق', body: 'اختبار',
        } },
      }]) }))
      expect(useNotificationStore.getState().unreadCount).toBe(0)
    })
    await publish(1, 'actor-b')
    expect(screen.getByText(/مستخدم actor-b إشعارات 0/)).toBeTruthy()
  })

  it('does not restore an old optimistic notification snapshot after A to B to A', async () => {
    renderApp()
    await publish(0, 'actor-a')
    const key = [...notificationKeys.lists(), 'synthetic-list']
    queryClient.setQueryData(key, { data: [{ id: 'old-a-note', isRead: false }], count: 1 })
    fireEvent.click(screen.getByRole('button', { name: 'قراءة إشعار' }))
    await settled(() => expect(mutations[0]?.actor).toBe('actor-a'))
    expect(queryClient.getQueryData<{ data: { isRead: boolean }[] }>(key)?.data[0].isRead).toBe(true)
    await switchActor('actor-b')
    await publish(1, 'actor-b')
    await switchActor('actor-a')
    await publish(2, 'actor-a')
    queryClient.setQueryData(key, { data: [{ id: 'fresh-a-note', isRead: false }], count: 1 })
    await act(async () => { mutations[0].reply({ code: '503', message: 'Synthetic mutation failed' }, 503); await vi.advanceTimersByTimeAsync(1) })
    expect(queryClient.getQueryData<{ data: { id: string }[] }>(key)?.data[0].id).toBe('fresh-a-note')
  })

  it('does not reset actor B unread count when actor A mark-all response arrives late', async () => {
    holdUnread = true
    renderApp()
    await publish(0, 'actor-a')
    await settled(() => expect(unread[0]?.actor).toBe('actor-a'))
    await act(async () => { unread[0].reply(7); await vi.advanceTimersByTimeAsync(1) })
    fireEvent.click(screen.getByRole('button', { name: 'قراءة الكل' }))
    await settled(() => expect(mutations[0]?.actor).toBe('actor-a'))
    await switchActor('actor-b')
    await publish(1, 'actor-b')
    await settled(() => expect(unread[1]?.actor).toBe('actor-b'))
    await act(async () => { unread[1].reply(2); mutations[0].reply(7); await vi.advanceTimersByTimeAsync(1) })
    expect(screen.getByText(/مستخدم actor-b إشعارات 2/)).toBeTruthy()
  })

  it('preserves a current actor mark-all success and its fresh count request', async () => {
    holdUnread = true
    renderApp()
    await publish(0, 'actor-a')
    await settled(() => expect(unread[0]?.actor).toBe('actor-a'))
    await act(async () => { unread[0].reply(3); await vi.advanceTimersByTimeAsync(1) })
    fireEvent.click(screen.getByRole('button', { name: 'قراءة الكل' }))
    await settled(() => expect(mutations[0]?.actor).toBe('actor-a'))
    await act(async () => { mutations[0].reply(3); await vi.advanceTimersByTimeAsync(1) })
    expect(screen.getByText(/مستخدم actor-a إشعارات 0/)).toBeTruthy()
    await settled(() => expect(unread[1]?.actor).toBe('actor-a'))
    await act(async () => { unread[1].reply(0); await vi.advanceTimersByTimeAsync(1) })
  })
})
