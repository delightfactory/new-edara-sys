import { create } from 'zustand'
import type { MyProfile } from '@/lib/types/auth'

interface AuthState {
  sessionGeneration: number
  beginSessionLoad: () => number
  sessionUserId: string | null
  identityGeneration: number
  isIdentityVerified: boolean
  acceptSessionIdentity: (id: string | null) => { generation: number; changed: boolean }
  profile: MyProfile | null
  permissions: string[]
  isLoading: boolean
  isInitialized: boolean
  hasSession: boolean
  profileLoadError: string | null

  setProfile: (profile: MyProfile | null) => void
  setPermissions: (permissions: string[]) => void
  setLoading: (v: boolean) => void
  setInitialized: (v: boolean) => void
  setHasSession: (v: boolean) => void
  setProfileLoadError: (v: string | null) => void

  /** فحص صلاحية واحدة — يدعم wildcard '*' */
  can: (permission: string) => boolean
  /** فحص أي واحدة من مجموعة صلاحيات */
  canAny: (permissions: string[]) => boolean
  /** فحص كل مجموعة صلاحيات */
  canAll: (permissions: string[]) => boolean

  reset: () => void
}

// ─── Session Cache (sessionStorage) ───────────────────────────────────────────
// يُحسّن تجربة العودة للتطبيق بعد تبديل التطبيقات أو إعادة تحميل الصفحة.
// تُمسح عند إغلاق التاب؛ لا تُعرض قبل مطابقة هوية جلسة SDK.
// ⚠️ الصلاحيات لا تُخزن في localStorage أبداً — sessionStorage فقط.

const CACHE_KEY = 'edara_auth_v1'

interface AuthCache {
  v: 1
  profile: MyProfile
  permissions: string[]
}

export function saveAuthCache(profile: MyProfile, permissions: string[]) {
  try {
    const cache: AuthCache = { v: 1, profile, permissions }
    sessionStorage.setItem(CACHE_KEY, JSON.stringify(cache))
  } catch { /* تجاهل أخطاء sessionStorage (وضع التخفي أحياناً يمنع الكتابة) */ }
}

export function clearAuthCache() {
  try { sessionStorage.removeItem(CACHE_KEY) } catch {}
}

function readAuthCache(): { profile: MyProfile; permissions: string[] } | null {
  try {
    const raw = sessionStorage.getItem(CACHE_KEY)
    if (!raw) return null
    const parsed = JSON.parse(raw) as AuthCache
    if (parsed?.v === 1 && parsed.profile?.id && Array.isArray(parsed.permissions)) {
      return { profile: parsed.profile, permissions: parsed.permissions }
    }
    return null
  } catch { return null }
}

// يُقرأ مرة واحدة فقط عند بدء التطبيق
const _cached = readAuthCache()

// ─── Store ─────────────────────────────────────────────────────────────────────
export const useAuthStore = create<AuthState>()((set, get) => ({
  sessionGeneration: 0,
  sessionUserId: null,
  identityGeneration: 0,
  isIdentityVerified: false,
  acceptSessionIdentity: (sessionUserId) => {
    const state = get()
    const previousId = state.isIdentityVerified ? state.sessionUserId : state.profile?.id ?? null
    const changed = sessionUserId === null || previousId !== sessionUserId
    const generation = state.sessionGeneration + (changed ? 1 : 0)
    if (changed) clearAuthCache()
    set({
      sessionUserId, isIdentityVerified: true, sessionGeneration: generation,
      identityGeneration: state.identityGeneration + (changed ? 1 : 0),
      hasSession: sessionUserId !== null,
      ...(changed ? { profile: null, permissions: [], profileLoadError: null } : {}),
      ...(sessionUserId === null
        ? { isLoading: false, isInitialized: true }
        : changed ? { isLoading: true, isInitialized: false } : {}),
    })
    return { generation, changed }
  },
  beginSessionLoad: () => {
    const sessionGeneration = get().sessionGeneration + 1
    set({ sessionGeneration, isLoading: true, profileLoadError: null })
    return sessionGeneration
  },
  // يحتفظ بالكاش لحين مطابقة الهوية؛ AuthProvider يحجب العرض قبلها.
  profile:          _cached?.profile      ?? null,
  permissions:      _cached?.permissions  ?? [],
  isLoading:        !_cached,   // لا spinner إذا عندنا cache
  isInitialized:    !!_cached,  // جاهز فوراً إذا عندنا cache
  hasSession:       !!_cached,
  profileLoadError: null,

  setProfile:     (profile)       => set({ profile }),
  setPermissions: (permissions)   => set({ permissions }),
  setLoading:     (isLoading)     => set({ isLoading }),
  setInitialized: (isInitialized) => set({ isInitialized }),
  setHasSession:  (hasSession)    => set({ hasSession }),
  setProfileLoadError: (profileLoadError) => set({ profileLoadError }),

  can: (permission) => {
    const { permissions } = get()
    // Explicit per-user denies have priority over both exact role grants and '*'.
    if (permissions.includes(`!${permission}`)) return false
    if (permissions.includes('*')) return true
    return permissions.includes(permission)
  },

  canAny: (perms) => perms.some(p => get().can(p)),
  canAll: (perms) => perms.every(p => get().can(p)),

  reset: () => {
    clearAuthCache()
    set({
      sessionGeneration: get().sessionGeneration + 1,
      sessionUserId: null,
      identityGeneration: get().identityGeneration + 1,
      isIdentityVerified: true,
      profile: null,
      permissions: [],
      isLoading: false,
      isInitialized: false,
      hasSession: false,
      profileLoadError: null,
    })
  },
}))
