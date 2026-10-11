import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { loadSession, signOut } from '@/lib/services/auth'
import { useAuthStore } from '@/stores/auth-store'

interface PendingRequest {
  path: string
  search: string
  method: string
  resolve: (response: Response) => void
  reject: (error: Error) => void
}

let requests: PendingRequest[]

function reply(request: PendingRequest, value: unknown, status = 200) {
  request.resolve(new Response(JSON.stringify(value), {
    status, headers: { 'content-type': 'application/json' },
  }))
}

async function requestAt(index: number, path: string) {
  await vi.waitFor(() => expect(requests[index]?.path).toBe(path))
  return requests[index]
}

function profile(id: string) {
  return { id, status: 'active', permissions: [`${id}.read`] }
}

async function finishLoad(index: number, actor: string, task: Promise<void>) {
  reply(await requestAt(index, '/rest/v1/rpc/get_my_profile'), profile(actor))
  reply(await requestAt(index + 1, '/rest/v1/rpc/get_my_permission_denials'), [])
  await task
}

beforeEach(() => {
  useAuthStore.getState().reset()
  requests = []
  vi.useFakeTimers()
  // Use the application's actual Supabase client. Only HTTP is intercepted;
  // unknown hosts/routes fail instead of reaching any external backend.
  vi.stubGlobal('fetch', vi.fn((input: string | URL | Request, init?: RequestInit) => {
    const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url)
    const method = init?.method ?? 'GET'
    const allowed = method === 'POST' && ['/rest/v1/rpc/get_my_profile', '/rest/v1/rpc/get_my_permission_denials'].includes(url.pathname)
      || method === 'PATCH' && url.pathname === '/rest/v1/profiles'
    if (url.origin !== 'https://example.supabase.co' || !allowed) {
      throw new Error(`Unexpected synthetic request: ${method} ${url.origin}${url.pathname}`)
    }
    return new Promise<Response>((resolve, reject) => requests.push({ path: url.pathname, search: url.search, method, resolve, reject }))
  }))
})

afterEach(() => {
  useAuthStore.getState().reset()
  vi.clearAllTimers()
  vi.useRealTimers()
  vi.unstubAllGlobals()
})

describe('auth load generations through the real SDK', () => {
  it('drops an old profile after a newer load has published', async () => {
    const oldTask = loadSession()
    const oldRequest = await requestAt(0, '/rest/v1/rpc/get_my_profile')
    const newTask = loadSession()
    await finishLoad(1, 'actor-b', newTask)
    reply(oldRequest, profile('actor-a'))
    await vi.advanceTimersByTimeAsync(1)
    expect(requests).toHaveLength(3)
    await oldTask
    expect(useAuthStore.getState().profile?.id).toBe('actor-b')
    expect(useAuthStore.getState().permissions).toEqual(['actor-b.read'])
    expect(JSON.parse(sessionStorage.getItem('edara_auth_v1')!).profile.id).toBe('actor-b')
  })

  it('does not let an old denial response publish over a newer actor', async () => {
    const oldTask = loadSession()
    reply(await requestAt(0, '/rest/v1/rpc/get_my_profile'), profile('actor-a'))
    const oldDenials = await requestAt(1, '/rest/v1/rpc/get_my_permission_denials')
    const newTask = loadSession()
    await finishLoad(2, 'actor-b', newTask)
    reply(oldDenials, [{ permission: '!actor-b.read' }])
    await oldTask
    expect(useAuthStore.getState().profile?.id).toBe('actor-b')
    expect(useAuthStore.getState().can('actor-b.read')).toBe(true)
  })

  it('drops late errors and finally without completing a newer pending load', async () => {
    const oldTask = loadSession()
    const oldRequest = await requestAt(0, '/rest/v1/rpc/get_my_profile')
    const newTask = loadSession()
    await requestAt(1, '/rest/v1/rpc/get_my_profile')
    oldRequest.reject(new Error('synthetic old failure'))
    await oldTask
    expect(useAuthStore.getState().isLoading).toBe(true)
    expect(useAuthStore.getState().isInitialized).toBe(false)
    expect(useAuthStore.getState().profileLoadError).toBeNull()
    await finishLoad(1, 'actor-b', newTask)
  })

  it('does not retry a failed obsolete profile request', async () => {
    const oldTask = loadSession()
    const oldRequest = await requestAt(0, '/rest/v1/rpc/get_my_profile')
    const newTask = loadSession()
    await finishLoad(1, 'actor-b', newTask)
    reply(oldRequest, { code: '503', message: 'Service unavailable' }, 503)
    await oldTask
    await vi.advanceTimersByTimeAsync(500)
    expect(requests).toHaveLength(3)
    expect(useAuthStore.getState().profile?.id).toBe('actor-b')
  })

  it('prevents late profile completion after logout from reviving the session', async () => {
    const task = loadSession()
    const pending = await requestAt(0, '/rest/v1/rpc/get_my_profile')
    await signOut()
    reply(pending, profile('actor-a'))
    await task
    expect(useAuthStore.getState().profile).toBeNull()
    expect(useAuthStore.getState().hasSession).toBe(false)
    expect(useAuthStore.getState().isInitialized).toBe(true)
    expect(sessionStorage.getItem('edara_auth_v1')).toBeNull()
    expect(requests).toHaveLength(1)
  })

  it('cancels the old delayed login PATCH after the store resets', async () => {
    const task = loadSession()
    await finishLoad(0, 'actor-a', task)
    useAuthStore.getState().reset()
    await vi.advanceTimersByTimeAsync(2100)
    expect(requests.filter(request => request.method === 'PATCH')).toHaveLength(0)
  })

  it('still sends the delayed login PATCH for the current successful load', async () => {
    const task = loadSession()
    await finishLoad(0, 'actor-a', task)
    await vi.advanceTimersByTimeAsync(2100)
    const patch = await requestAt(2, '/rest/v1/profiles')
    expect(patch.method).toBe('PATCH')
    expect(new URLSearchParams(patch.search).get('id')).toBe('eq.actor-a')
    reply(patch, null)
    await vi.advanceTimersByTimeAsync(1)
  })

  it('does not send a retry after reset during the retry delay', async () => {
    const task = loadSession()
    reply(await requestAt(0, '/rest/v1/rpc/get_my_profile'), { code: '503', message: 'Service unavailable' }, 503)
    await vi.advanceTimersByTimeAsync(1)
    useAuthStore.getState().reset()
    await vi.advanceTimersByTimeAsync(450)
    await task
    expect(requests).toHaveLength(1)
    expect(useAuthStore.getState().hasSession).toBe(false)
    expect(useAuthStore.getState().isInitialized).toBe(false)
  })
})
