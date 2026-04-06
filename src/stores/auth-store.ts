import { create } from 'zustand'
import type { MyProfile } from '@/lib/types/auth'

interface AuthState {
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
// sessionStorage (لا localStorage): تُمسح عند إغلاق التاب، لا أثر أمني.
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
  // إذا وُجد cache: ابدأ بحالة جاهزة فوراً بدون spinner
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
    if (permissions.includes('*')) return true
    return permissions.includes(permission)
  },

  canAny: (perms) => perms.some(p => get().can(p)),
  canAll: (perms) => perms.every(p => get().can(p)),

  reset: () => {
    clearAuthCache()
    set({
      profile: null,
      permissions: [],
      isLoading: false,
      isInitialized: false,
      hasSession: false,
      profileLoadError: null,
    })
  },
}))
