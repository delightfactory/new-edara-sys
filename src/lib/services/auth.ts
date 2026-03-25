import { supabase } from '@/lib/supabase/client'
import { useAuthStore } from '@/stores/auth-store'
import type { MyProfile } from '@/lib/types/auth'

/**
 * تسجيل الدخول
 */
export async function signIn(email: string, password: string) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password })
  if (error) throw error
  return data
}

/**
 * تسجيل الخروج
 */
export async function signOut() {
  await supabase.auth.signOut()
  useAuthStore.getState().reset()
}

/**
 * جلب بيانات المستخدم + الأدوار + الصلاحيات دفعة واحدة
 * يُستدعى عند بداية التطبيق وبعد كل SIGNED_IN event
 */
export async function loadSession() {
  const store = useAuthStore.getState()
  store.setLoading(true)

  try {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) {
      store.reset()
      store.setInitialized(true)
      return
    }

    // RPC واحدة ترجع profile + roles + permissions
    const { data, error } = await supabase
      .rpc('get_my_profile')
      .single<MyProfile>()

    if (error || !data || data.status !== 'active') {
      await supabase.auth.signOut()
      store.reset()
      store.setInitialized(true)
      return
    }

    store.setProfile(data)
    store.setPermissions(data.permissions ?? [])

    // تحديث last_login_at بدون انتظار
    supabase
      .from('profiles')
      .update({ last_login_at: new Date().toISOString() })
      .eq('id', user.id)
      .then() // fire and forget
  } catch {
    store.reset()
  } finally {
    store.setLoading(false)
    store.setInitialized(true)
  }
}

/**
 * إعادة تعيين كلمة المرور عبر Edge Function
 */
export async function adminResetPassword(userId: string, newPassword: string) {
  const { error } = await supabase.functions.invoke('admin-reset-password', {
    body: { userId, newPassword },
  })
  if (error) throw error
}

/**
 * إنشاء مستخدم جديد عبر Edge Function
 */
export async function createUser(data: {
  full_name: string
  email: string
  password: string
  phone?: string
  role_ids: string[]
}) {
  const { data: result, error } = await supabase.functions.invoke('create-user', {
    body: data,
  })
  if (error) throw error
  return result as { user_id: string }
}
