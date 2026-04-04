/**
 * load-session.test.ts
 * Regression tests for the loadSession() fix:
 *   - أخطاء الشبكة/abort لا تستدعي signOut أو reset()
 *   - PGRST116 / no session → reset()
 *   - account inactive/suspended → signOut()
 *   - successful active session → profile updated, no signOut
 */
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { useAuthStore } from '@/stores/auth-store'

// ── Minimal supabase mock ─────────────────────────────────────────────────────
// المحاكاة تشمل getSession (للـ helper) وrpc (لـ loadSession) وsignOut
const mockSignOut    = vi.fn().mockResolvedValue({})
const mockGetSession = vi.fn()
const mockRpcSingle  = vi.fn()

vi.mock('@/lib/supabase/client', () => ({
  supabase: {
    auth: {
      getSession: mockGetSession,
      signOut:    mockSignOut,
    },
    from: vi.fn().mockReturnValue({
      update: vi.fn().mockReturnValue({
        eq: vi.fn().mockReturnValue({ then: vi.fn() }),
      }),
    }),
    rpc: vi.fn().mockReturnValue({ single: mockRpcSingle }),
  },
}))

// ── useAuthStore mock: بديل بسيط يعكس ما يحدث في الحالة الحقيقية ────────────
// نستخدم الـ store الحقيقي (الأعلى) ونتحقق من حالته مباشرةً

// Import AFTER mocking
const { loadSession } = await import('@/lib/services/auth')

beforeEach(() => {
  vi.clearAllMocks()
  useAuthStore.getState().reset()
  // محاكاة افتراضية: لا session في getSession (اختبارات ستعيد تعريفها إذا لزم)
  mockGetSession.mockResolvedValue({ data: { session: null } })
})

// ─────────────────────────────────────────────────────────────────────────────
// اختبارات عدم الخروج عند أخطاء الشبكة / Abort
// ─────────────────────────────────────────────────────────────────────────────
describe('loadSession() — transient network errors do NOT trigger logout', () => {

  it('Promise.reject(TypeError: Failed to fetch) → no reset, no signOut, profileLoadError=network_error', async () => {
    // get_my_profile RPC يُرمي TypeError (network)
    mockRpcSingle.mockRejectedValue(new TypeError('Failed to fetch'))

    await loadSession()

    expect(mockSignOut).not.toHaveBeenCalled()
    expect(useAuthStore.getState().isInitialized).toBe(true)
    expect(useAuthStore.getState().hasSession).toBe(true)
    expect(useAuthStore.getState().profileLoadError).toBe('network_error')

    // التأكد من أن reset() لم يُستدعَ (profile ما زال null لكن hasSession=true)
    expect(useAuthStore.getState().profile).toBeNull()
  })

  it('Promise.reject(AbortError) → no reset, no signOut, profileLoadError=network_error', async () => {
    const abortErr = new DOMException('The user aborted a request', 'AbortError')
    mockRpcSingle.mockRejectedValue(abortErr)

    await loadSession()

    expect(mockSignOut).not.toHaveBeenCalled()
    expect(useAuthStore.getState().hasSession).toBe(true)
    expect(useAuthStore.getState().profileLoadError).toBe('network_error')
  })

  it('RPC returns transient error (code 503) → no reset, no signOut, profileLoadError=rpc_error', async () => {
    // الخطأ يُعاد كـ object (لا throw) — هذا هو مسار الـ if(error) في loadSession
    mockRpcSingle.mockResolvedValue({
      data: null,
      error: { message: 'Service unavailable', code: '503' },
    })

    await loadSession()

    expect(mockSignOut).not.toHaveBeenCalled()
    expect(useAuthStore.getState().hasSession).toBe(true)
    expect(useAuthStore.getState().profileLoadError).toBe('rpc_error')
  })

  it('unexpected error (non-network) → no reset, no signOut, profileLoadError=unexpected_error', async () => {
    mockRpcSingle.mockRejectedValue(new Error('Something really weird happened'))

    await loadSession()

    expect(mockSignOut).not.toHaveBeenCalled()
    expect(useAuthStore.getState().hasSession).toBe(true)
    expect(useAuthStore.getState().profileLoadError).toBe('unexpected_error')
  })
})

// ─────────────────────────────────────────────────────────────────────────────
// اختبارات حالات auth الحقيقية
// ─────────────────────────────────────────────────────────────────────────────
describe('loadSession() — real auth failures → reset()', () => {

  it('PGRST116 (no session) → reset(), initialized=true, no signOut', async () => {
    mockRpcSingle.mockResolvedValue({
      data: null,
      error: { message: 'No session', code: 'PGRST116' },
    })

    await loadSession()

    // لا logout صريح بل reset() الذي يضع hasSession=false
    expect(mockSignOut).not.toHaveBeenCalled()
    expect(useAuthStore.getState().isInitialized).toBe(true)
    expect(useAuthStore.getState().hasSession).toBe(false)
    expect(useAuthStore.getState().profile).toBeNull()
  })

  it('JWT error → reset(), initialized=true', async () => {
    mockRpcSingle.mockResolvedValue({
      data: null,
      error: { message: 'JWT expired', code: '401' },
    })

    await loadSession()

    expect(mockSignOut).not.toHaveBeenCalled()
    expect(useAuthStore.getState().hasSession).toBe(false)
    expect(useAuthStore.getState().isInitialized).toBe(true)
  })
})

// ─────────────────────────────────────────────────────────────────────────────
// اختبارات حالة الحساب
// ─────────────────────────────────────────────────────────────────────────────
describe('loadSession() — account status checks', () => {

  it('inactive account → signOut() called, reset()', async () => {
    mockRpcSingle.mockResolvedValue({
      data: { id: 'u1', status: 'inactive', permissions: [] },
      error: null,
    })

    await loadSession()

    expect(mockSignOut).toHaveBeenCalledOnce()
    expect(useAuthStore.getState().hasSession).toBe(false)
    expect(useAuthStore.getState().profile).toBeNull()
  })

  it('suspended account → signOut() called', async () => {
    mockRpcSingle.mockResolvedValue({
      data: { id: 'u1', status: 'suspended', permissions: [] },
      error: null,
    })

    await loadSession()

    expect(mockSignOut).toHaveBeenCalledOnce()
  })

  it('active session → profile updated, no signOut, profileLoadError=null', async () => {
    mockRpcSingle.mockResolvedValue({
      data: { id: 'u1', status: 'active', permissions: ['sales.orders.read'] },
      error: null,
    })

    await loadSession()

    expect(mockSignOut).not.toHaveBeenCalled()
    expect(useAuthStore.getState().profile?.id).toBe('u1')
    expect(useAuthStore.getState().hasSession).toBe(true)
    expect(useAuthStore.getState().profileLoadError).toBeNull()
    expect(useAuthStore.getState().isInitialized).toBe(true)
  })
})

// ─────────────────────────────────────────────────────────────────────────────
// profile_missing edge case
// الحالة: RPC ترجع data=null, error=null (نادر جداً — race condition أو DB glitch)
// المتوقع: لا reset(), hasSession=true, profileLoadError='profile_missing'
//          ProtectedRoute يعرض retry UI وليس redirect إلى /login
// ─────────────────────────────────────────────────────────────────────────────
describe('loadSession() — profile_missing (data=null, error=null)', () => {

  it('data=null error=null → no signOut, hasSession=true, profileLoadError=profile_missing', async () => {
    // حالة edge case: RPC نجحت لكن لا بيانات
    mockRpcSingle.mockResolvedValue({ data: null, error: null })

    await loadSession()

    // لا خروج — الجلسة قد تكون صالحة
    expect(mockSignOut).not.toHaveBeenCalled()

    // hasSession=true مطلوب حتى يعرض ProtectedRoute retry UI وليس /login
    expect(useAuthStore.getState().hasSession).toBe(true)

    // خطأ واضح يدل على المشكلة
    expect(useAuthStore.getState().profileLoadError).toBe('profile_missing')

    // لم يُحمَّل أي profile
    expect(useAuthStore.getState().profile).toBeNull()

    // التهيئة اكتملت (Spinner يختفي)
    expect(useAuthStore.getState().isInitialized).toBe(true)
  })

  it('data=null error=null → retry بعد loadSession() الثاني يُصلح الحالة', async () => {
    // المرحلة 1: profile_missing
    mockRpcSingle.mockResolvedValue({ data: null, error: null })
    await loadSession()
    expect(useAuthStore.getState().profileLoadError).toBe('profile_missing')
    expect(useAuthStore.getState().hasSession).toBe(true)

    // المرحلة 2: retry — هذه المرة الـ RPC تعيد البيانات
    mockRpcSingle.mockResolvedValue({
      data: { id: 'u1', status: 'active', permissions: ['sales.orders.read'] },
      error: null,
    })
    await loadSession()

    expect(mockSignOut).not.toHaveBeenCalled()
    expect(useAuthStore.getState().profile?.id).toBe('u1')
    expect(useAuthStore.getState().profileLoadError).toBeNull()
    expect(useAuthStore.getState().hasSession).toBe(true)
  })
})

