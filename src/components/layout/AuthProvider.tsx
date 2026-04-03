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
  const retryTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const retryCountRef = useRef(0)

  const hasSession = useAuthStore(s => s.hasSession)
  const profile = useAuthStore(s => s.profile)
  const profileLoadError = useAuthStore(s => s.profileLoadError)

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
        retryCountRef.current = 0
        // فقط أعد التحميل لو المستخدم سجّل دخول جديد (وليس page reload)
        // نستخدم setTimeout(0) لتفادي Supabase الداخلي deadlock
        setTimeout(() => safeLoadSession(), 0)
      }
      if (event === 'SIGNED_OUT') {
        if (retryTimerRef.current) {
          clearTimeout(retryTimerRef.current)
          retryTimerRef.current = null
        }
        retryCountRef.current = 0
        const store = useAuthStore.getState()
        store.reset()
        store.setInitialized(true)
      }
    })

    return () => {
      if (retryTimerRef.current) {
        clearTimeout(retryTimerRef.current)
        retryTimerRef.current = null
      }
      subscription.unsubscribe()
    }
  }, [safeLoadSession])

  useEffect(() => {
    const shouldRetry = hasSession && !profile && !!profileLoadError && retryCountRef.current < 1
    if (!shouldRetry || loadingRef.current || retryTimerRef.current) return

    retryTimerRef.current = setTimeout(() => {
      retryTimerRef.current = null
      retryCountRef.current += 1
      safeLoadSession()
    }, 1500)

    return () => {
      if (retryTimerRef.current) {
        clearTimeout(retryTimerRef.current)
        retryTimerRef.current = null
      }
    }
  }, [hasSession, profile, profileLoadError, safeLoadSession])

  return <>{children}</>
}
