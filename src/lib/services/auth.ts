import { supabase } from '@/lib/supabase/client'
import { useAuthStore } from '@/stores/auth-store'
import type { MyProfile } from '@/lib/types/auth'
import { captureError, trackAuthFailure, setUserContext } from '@/lib/monitoring/sentry'

/**
 * تحديد ما إذا كان الخطأ ناتجاً عن شبكة / abort / timeout
 * هذه الأخطاء عابرة ولا تعني انتهاء الجلسة
 */
function isNetworkError(err: unknown): boolean {
  // DOMException (AbortError, TimeoutError) — يُفحص أولاً لأنه قد لا يمتد من Error
  if (typeof DOMException !== 'undefined' && err instanceof DOMException) {
    return err.name === 'AbortError' || err.name === 'TimeoutError'
  }

  if (!(err instanceof Error)) return false
  const name = err.name
  const msg  = err.message?.toLowerCase() ?? ''

  // AbortError — طلب تم إلغاؤه (navigation، component unmount، timeout)
  if (name === 'AbortError' || name === 'TimeoutError') return true

  // TypeError من Fetch API عند فقدان الاتصال
  if (name === 'TypeError') {
    return (
      msg.includes('failed to fetch') ||
      msg.includes('network request failed') ||
      msg.includes('load failed') ||
      msg.includes('networkerror') ||
      msg.includes('fetch is not defined') // SSR edge case
    )
  }

  // أخطاء شبكة أخرى شائعة
  return (
    msg.includes('err_internet_disconnected') ||
    msg.includes('err_network') ||
    msg.includes('err_name_not_resolved') ||
    msg.includes('ssl') ||
    msg.includes('timeout')
  )
}

/**
 * تسجيل الدخول
 */
export async function signIn(email: string, password: string) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password })
  if (error) {
    trackAuthFailure('sign_in_failed', { email })
    throw error
  }
  return data
}

/**
 * تسجيل الخروج
 */
export async function signOut() {
  await supabase.auth.signOut()
  useAuthStore.getState().reset()
  setUserContext(null)
}

/**
 * جلب بيانات المستخدم + الأدوار + الصلاحيات دفعة واحدة
 * يُستدعى عند بداية التطبيق وبعد كل SIGNED_IN event
 *
 * سلوك الأخطاء:
 * - PGRST116 / 42501 / JWT / session → reset() (لا جلسة حقيقية)
 * - status !== 'active' → signOut() (حساب موقوف)
 * - network / abort / timeout → profileLoadError='network_error'، لا logout
 * - خطأ غير معروف → profileLoadError='unexpected_error'، لا logout
 *
 * في الحالتين الأخيرتين: hasSession=true لتفعيل retry الحالي في AuthProvider
 */
export async function loadSession() {
  const store = useAuthStore.getState()
  store.setLoading(true)
  store.setProfileLoadError(null)

  try {
    // طلب واحد مباشر بدلاً من طلبين متسلسلين
    // get_my_profile() ستفشل بـ PGRST error إذا لم يكن هناك session
    const { data, error } = await supabase
      .rpc('get_my_profile')
      .single<MyProfile>()

    if (error) {
      // حالات auth الحقيقية: لا جلسة أو JWT منتهٍ أو ممنوع
      if (
        error.code === 'PGRST116' ||
        error.code === '42501' ||
        error.message?.includes('JWT') ||
        error.message?.includes('session')
      ) {
        store.reset()
        store.setInitialized(true)
        setUserContext(null)
        return
      }

      // خطأ شبكة/RPC عابر — الجلسة قد تكون صالحة، لا نُخرج المستخدم
      captureError(error, { stage: 'load_session_rpc' })
      store.setProfileLoadError('rpc_error')
      store.setHasSession(true) // نفترض وجود جلسة لتفعيل retry في AuthProvider
      return
    }

    if (!data) {
      // data=null بدون error نادر جداً لكن ممكن في edge cases (race condition أو DB)
      // لا نعمل reset() هنا — الجلسة قد تكون صالحة
      // hasSession=true يضمن أن ProtectedRoute يعرض retry UI بدلاً من redirect إلى /login
      trackAuthFailure('profile_missing', {})
      store.setProfileLoadError('profile_missing')
      store.setHasSession(true)
      return
    }

    if (data.status !== 'active') {
      trackAuthFailure('account_inactive', { status: data.status })
      await supabase.auth.signOut()
      store.reset()
      store.setInitialized(true)
      setUserContext(null)
      return
    }

    store.setHasSession(true)
    store.setProfile(data)
    store.setPermissions(data.permissions ?? [])
    store.setProfileLoadError(null)
    setUserContext(data.id)

    // تحديث last_login_at بدون انتظار — fire and forget مع قليل من التأخير
    // لتجنب تنافس الطلبات عند تسجيل الدخول
    setTimeout(() => {
      supabase
        .from('profiles')
        .update({ last_login_at: new Date().toISOString() })
        .eq('id', data.id)
        .then()
    }, 2000)

  } catch (err) {
    // ─── catch: أخطاء عابرة أو غير متوقعة ───
    // لا نستدعي store.reset() هنا أبداً —
    // reset() يعني logout وهو غير مقبول لأخطاء الشبكة
    captureError(err, { stage: 'load_session_catch' })

    const errorCode = isNetworkError(err) ? 'network_error' : 'unexpected_error'
    store.setProfileLoadError(errorCode)
    store.setHasSession(true) // نفترض وجود جلسة لتفعيل retry في AuthProvider
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
