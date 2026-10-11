import { Fragment, useEffect, useRef, useState } from 'react'
import { supabase } from '@/lib/supabase/client'
import { clearSessionData, loadSession } from '@/lib/services/auth'
import { useAuthStore } from '@/stores/auth-store'
import StatePanel from '@/components/patterns/StatePanel'
import Button from '@/components/ui/Button'

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [bootstrapReady, setBootstrapReady] = useState(false)
  const [bootstrapTimedOut, setBootstrapTimedOut] = useState(false)
  const [bootstrapAttempt, setBootstrapAttempt] = useState(0)
  const retryTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const retryCountRef = useRef(0)
  const identityVerified = useAuthStore(s => s.isIdentityVerified)
  const actorId = useAuthStore(s => s.sessionUserId)
  const generation = useAuthStore(s => s.sessionGeneration)
  const isLoading = useAuthStore(s => s.isLoading)
  const profile = useAuthStore(s => s.profile)
  const profileLoadError = useAuthStore(s => s.profileLoadError)

  useEffect(() => {
    let active = true
    let pendingLoad: ReturnType<typeof setTimeout> | null = null
    setBootstrapReady(false)
    setBootstrapTimedOut(false)
    const bootstrapTimer = setTimeout(() => {
      if (active) setBootstrapTimedOut(true)
    }, 15_000)

    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      if (!active) return
      const id = session?.user.id ?? null
      const state = useAuthStore.getState()
      const identityChanged = !state.isIdentityVerified || state.sessionUserId !== id
      if (!['INITIAL_SESSION', 'SIGNED_IN', 'SIGNED_OUT', 'PASSWORD_RECOVERY'].includes(event) && !identityChanged) return
      if (pendingLoad) clearTimeout(pendingLoad)
      if (retryTimerRef.current) clearTimeout(retryTimerRef.current)
      retryTimerRef.current = null
      retryCountRef.current = 0
      // Confirm identity before deferred SDK work; callbacks run under its lock.
      const transition = state.acceptSessionIdentity(id)
      if (transition.changed || event === 'SIGNED_OUT') clearSessionData()
      clearTimeout(bootstrapTimer)
      setBootstrapReady(true)
      setBootstrapTimedOut(false)
      if (!id) return
      pendingLoad = setTimeout(() => {
        pendingLoad = null
        if (active && useAuthStore.getState().sessionGeneration === transition.generation) {
          void loadSession(id)
        }
      }, 0)
    })

    return () => {
      active = false
      clearTimeout(bootstrapTimer)
      if (pendingLoad) clearTimeout(pendingLoad)
      subscription.unsubscribe()
    }
  }, [bootstrapAttempt])

  useEffect(() => {
    if (!bootstrapReady || !actorId || profile || !profileLoadError || isLoading || retryCountRef.current >= 1) return
    retryTimerRef.current = setTimeout(() => {
      retryTimerRef.current = null
      if (useAuthStore.getState().sessionGeneration !== generation) return
      retryCountRef.current += 1
      void loadSession(actorId)
    }, 1500)
    return () => {
      if (retryTimerRef.current) clearTimeout(retryTimerRef.current)
      retryTimerRef.current = null
    }
  }, [bootstrapReady, actorId, generation, profile, profileLoadError, isLoading])

  if (!bootstrapReady || !identityVerified) {
    return (
      <div style={{ display: 'grid', placeItems: 'center', minHeight: '100vh', padding: '24px', background: 'var(--bg-app)' }}>
        {bootstrapTimedOut ? (
          <StatePanel kind="error" title="تعذّر التحقق من الجلسة" description="حاول مرة أخرى للتحقق من جلسة الدخول."
            action={<Button onClick={() => setBootstrapAttempt(value => value + 1)}>إعادة المحاولة</Button>} />
        ) : <div className="spinner-lg spinner" />}
      </div>
    )
  }
  return <Fragment key={actorId ?? 'signed-out'}>{children}</Fragment>
}
