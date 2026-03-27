import { useState, useEffect } from 'react'

interface BeforeInstallPromptEvent extends Event {
  prompt(): Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

/**
 * usePWAInstall
 * Manages the PWA installation prompt lifecycle.
 * - Android/Chrome/Edge: uses native `beforeinstallprompt`
 * - iOS Safari: detected separately; show manual "Add to Home Screen" instructions
 * - Already installed (standalone mode): flag is set
 */
export function usePWAInstall() {
  const [deferredPrompt, setDeferredPrompt] = useState<BeforeInstallPromptEvent | null>(null)
  const [isInstalled, setIsInstalled] = useState(false)

  // Detect iOS (iPhone / iPad) — no `beforeinstallprompt` on iOS
  const isIOS =
    /iphone|ipad|ipod/i.test(navigator.userAgent) &&
    !(window as any).MSStream

  // Detect standalone mode — already installed as PWA
  const isStandalone =
    window.matchMedia('(display-mode: standalone)').matches ||
    (navigator as any).standalone === true

  useEffect(() => {
    if (isStandalone) {
      setIsInstalled(true)
      return
    }

    const handler = (e: Event) => {
      e.preventDefault()
      setDeferredPrompt(e as BeforeInstallPromptEvent)
    }

    const onInstalled = () => {
      setIsInstalled(true)
      setDeferredPrompt(null)
    }

    window.addEventListener('beforeinstallprompt', handler)
    window.addEventListener('appinstalled', onInstalled)

    return () => {
      window.removeEventListener('beforeinstallprompt', handler)
      window.removeEventListener('appinstalled', onInstalled)
    }
  }, [isStandalone])

  /**
   * Trigger the native install dialog (Android / Chrome / Edge only)
   */
  const install = async (): Promise<'accepted' | 'dismissed' | 'unavailable'> => {
    if (!deferredPrompt) return 'unavailable'
    await deferredPrompt.prompt()
    const { outcome } = await deferredPrompt.userChoice
    setDeferredPrompt(null)
    return outcome
  }

  return {
    /** Can show native install prompt (Android/Chrome/Edge) */
    canInstall: !!deferredPrompt && !isInstalled,
    /** Is running on iOS — show manual instructions instead */
    isIOS,
    /** Already installed as standalone PWA */
    isInstalled: isInstalled || isStandalone,
    /** Trigger native install prompt */
    install,
  }
}
