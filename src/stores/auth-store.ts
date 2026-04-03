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

/**
 * ⚠️ NO persist middleware — الصلاحيات لا تُخزن في localStorage أبداً
 * تُجلب من DB عند كل تسجيل دخول عبر get_my_profile() RPC
 */
export const useAuthStore = create<AuthState>()((set, get) => ({
  profile: null,
  permissions: [],
  isLoading: true,
  isInitialized: false,
  hasSession: false,
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

  reset: () => set({
    profile: null,
    permissions: [],
    isLoading: false,
    isInitialized: false,
    hasSession: false,
    profileLoadError: null,
  }),
}))
