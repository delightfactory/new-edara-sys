import { useEffect, useRef } from 'react'
import { useRegisterSW } from 'virtual:pwa-register/react'
import { toast } from 'sonner'
import { isFilePicking } from '@/lib/utils/file-picking-guard'

/**
 * PWAUpdateManager — Professional Silent Update Strategy (v2)
 *
 * ── Why controllerchange instead of postMessage? ──
 * The SW broadcasts APP_UPDATED via postMessage during `activate`, but at
 * that exact moment the React app may not have mounted its message listener
 * yet (e.g. initial page load). This is an inherent race condition.
 *
 * `navigator.serviceWorker.controllerchange` is the correct low-level event:
 * it fires on the *client* (not the SW) the instant the new SW takes control,
 * with zero race conditions. This is the pattern used by Workbox, Vite PWA
 * docs, and production apps like Figma and Linear.
 *
 * ── Update flow ──
 * 1. SW installs → our sw.ts calls skipWaiting() immediately
 * 2. SW activates → clientsClaim() takes control of all tabs
 * 3. `controllerchange` fires in every open tab
 * 4. This hook: shows toast → waits 2s → window.location.reload()
 *    (2s delay lets the current user action complete gracefully)
 *
 * ── Form-safety guard ──
 * Reload is skipped if an <input>, <textarea> or <select> currently has
 * focus — protecting users mid-entry. The reload will happen on next
 * visibility change instead.
 *
 * ── SW update polling ──
 * Managed entirely inside useEffect so cleanup is guaranteed:
 * - Immediate check on mount
 * - Every 5 minutes
 * - On every tab-visibility change (user returns from another tab)
 */
export default function PWAUpdateManager() {
  const reloadingRef = useRef(false)

  // ── Register SW + handle offline-ready toast ──
  // onRegistered is intentionally NOT used for polling here — cleanup from
  // within the useRegisterSW callback is not guaranteed (the return value
  // of onRegistered is ignored by the library). Polling is handled below
  // in its own useEffect with proper cleanup.
  useRegisterSW({
    onOfflineReady() {
      toast.success('جاهز للعمل بدون إنترنت ✅', {
        duration: 3000,
        position: 'bottom-center',
      })
    },
  })

  // ── Listen for controllerchange — the correct update signal ──
  // Fires when skipWaiting() + clientsClaim() complete in the new SW.
  // No race condition: this event is buffered by the browser until our
  // listener attaches, unlike postMessage which is fire-and-forget.
  useEffect(() => {
    if (!('serviceWorker' in navigator)) return

    const handleControllerChange = () => {
      if (reloadingRef.current) return

      // Guard: don't reload while user is using camera/gallery picker
      // isFilePicking stays true for 1200ms after camera closes, so this
      // check safely defers the reload until after the image is selected.
      if (isFilePicking()) {
        const waitForPicker = () => {
          if (isFilePicking()) {
            setTimeout(waitForPicker, 200)
            return
          }
          handleControllerChange()
        }
        setTimeout(waitForPicker, 200)
        return
      }

      // Guard: don't interrupt an active form entry
      const active = document.activeElement
      const isFormActive =
        active instanceof HTMLInputElement ||
        active instanceof HTMLTextAreaElement ||
        active instanceof HTMLSelectElement

      if (isFormActive) {
        // Defer: reload when user leaves the form (blur → focus goes to body)
        const deferReload = () => {
          if (reloadingRef.current) return
          reloadingRef.current = true
          window.location.reload()
        }
        active.addEventListener('blur', deferReload, { once: true })
        return
      }

      reloadingRef.current = true

      toast.loading('✨ تحديث جديد — يُطبَّق الآن...', {
        id: 'pwa-update',
        duration: 2500,
        position: 'bottom-center',
      })

      setTimeout(() => window.location.reload(), 2000)
    }

    navigator.serviceWorker.addEventListener('controllerchange', handleControllerChange)
    return () => {
      navigator.serviceWorker.removeEventListener('controllerchange', handleControllerChange)
    }
  }, [])

  // ── SW update polling — with guaranteed cleanup ──
  useEffect(() => {
    if (!('serviceWorker' in navigator)) return

    const checkForUpdate = () => {
      navigator.serviceWorker.getRegistration().then(reg => {
        reg?.update().catch(() => {})
      })
    }

    // Immediate check catches updates deployed while the app was closed
    checkForUpdate()

    // Poll every 5 minutes
    const interval = setInterval(checkForUpdate, 5 * 60 * 1000)

    // Re-check when user switches back to this tab
    // Guard: skip check if user is returning from camera/gallery picker
    // (isFilePicking = true for 1200ms after camera closes — enough time to avoid triggering
    //  a SW update check that could fire controllerchange and reload the page)
    const handleVisibilityChange = () => {
      if (document.visibilityState !== 'visible') return
      if (isFilePicking()) return
      checkForUpdate()
    }
    document.addEventListener('visibilitychange', handleVisibilityChange)

    return () => {
      clearInterval(interval)
      document.removeEventListener('visibilitychange', handleVisibilityChange)
    }
  }, []) // runs once on mount — deliberately empty deps

  return null
}
