/**
 * load-session.test.ts
 * Regression tests for the loadSession() fix (S1-T4).
 * Confirms that a transient RPC error does NOT sign the user out,
 * and that an inactive account DOES sign the user out.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { useAuthStore } from '@/stores/auth-store'

// ── Minimal supabase mock ───────────────────────────────────────
// We mock the module before importing loadSession so the service
// picks up the mock rather than the real Supabase client.
const mockSignOut   = vi.fn().mockResolvedValue({})
const mockGetUser   = vi.fn()
const mockRpcSingle = vi.fn()

vi.mock('@/lib/supabase/client', () => ({
  supabase: {
    auth: {
      getUser:  mockGetUser,
      signOut:  mockSignOut,
    },
    from: vi.fn().mockReturnValue({
      update: vi.fn().mockReturnValue({ eq: vi.fn().mockReturnValue({ then: vi.fn() }) }),
    }),
    rpc: vi.fn().mockReturnValue({ single: mockRpcSingle }),
  },
}))

// Import AFTER mocking
const { loadSession } = await import('@/lib/services/auth')

beforeEach(() => {
  vi.clearAllMocks()
  useAuthStore.getState().reset()
})

describe('loadSession() — transient error handling', () => {
  it('does NOT call signOut when get_my_profile returns a network error', async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: 'u1' } } })
    // Simulate a transient 502 / network error from the RPC
    mockRpcSingle.mockResolvedValue({ data: null, error: { message: 'network error', code: '503' } })

    await loadSession()

    expect(mockSignOut).not.toHaveBeenCalled()
    expect(useAuthStore.getState().isInitialized).toBe(true)
    expect(useAuthStore.getState().hasSession).toBe(true)
    expect(useAuthStore.getState().profileLoadError).toBe('rpc_error')
  })

  it('calls signOut when profile status is "inactive"', async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: 'u1' } } })
    mockRpcSingle.mockResolvedValue({
      data: { id: 'u1', status: 'inactive', permissions: [] },
      error: null,
    })

    await loadSession()

    expect(mockSignOut).toHaveBeenCalledOnce()
  })

  it('calls signOut when profile status is "suspended"', async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: 'u1' } } })
    mockRpcSingle.mockResolvedValue({
      data: { id: 'u1', status: 'suspended', permissions: [] },
      error: null,
    })

    await loadSession()

    expect(mockSignOut).toHaveBeenCalledOnce()
  })

  it('does NOT call signOut on a successful active session', async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: 'u1' } } })
    mockRpcSingle.mockResolvedValue({
      data: { id: 'u1', status: 'active', permissions: ['sales.orders.read'] },
      error: null,
    })

    await loadSession()

    expect(mockSignOut).not.toHaveBeenCalled()
    expect(useAuthStore.getState().profile).not.toBeNull()
    expect(useAuthStore.getState().hasSession).toBe(true)
    expect(useAuthStore.getState().profileLoadError).toBeNull()
  })

  it('does NOT call signOut when there is no logged-in user', async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } })

    await loadSession()

    expect(mockSignOut).not.toHaveBeenCalled()
  })
})
