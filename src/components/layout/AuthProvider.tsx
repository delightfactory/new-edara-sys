import { useEffect, useRef, useCallback } from 'react'
import { supabase } from '@/lib/supabase/client'
import { loadSession } from '@/lib/services/auth'
import { useAuthStore } from '@/stores/auth-store'

/**
 * AuthProvider — يُغلف التطبيق بالكامل
 * - يجلب الجلسة مرة واحدة عند التشغيل
 * - يمنع الاستدعاء المزدوج عبر loading guard
 * - يستمع لتغييرات Auth بدون race conditions
 */
export function AuthProvider({ children }: { children: React.ReactNode }) {
  const mounted = useRef(false)
  const loadingRef = useRef(false)

  const safeLoadSession = useCallback(async () => {
    // منع الاستدعاء المزدوج — لو loadSession شغالة بالفعل لا نعيدها
    if (loadingRef.current) return
    loadingRef.current = true
    try {
      await loadSession()
    } finally {
      loadingRef.current = false
    }
  }, [])

  useEffect(() => {
    if (mounted.current) return
    mounted.current = true

    // الجلب الأولي
    safeLoadSession()

    // الاستماع لتغييرات Auth
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event) => {
      if (event === 'SIGNED_IN') {
        // فقط أعد التحميل لو المستخدم سجّل دخول جديد (وليس page reload)
        // نستخدم setTimeout(0) لتفادي Supabase الداخلي deadlock
        setTimeout(() => safeLoadSession(), 0)
      }
      if (event === 'SIGNED_OUT') {
        const store = useAuthStore.getState()
        store.reset()
        store.setInitialized(true)
      }
    })

    return () => subscription.unsubscribe()
  }, [safeLoadSession])

  return <>{children}</>
}
