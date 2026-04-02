// src/lib/notifications/push-utils.ts
// ─────────────────────────────────────────────────────────────
// Browser-side utilities for Web Push API.
// All functions are pure / side-effect free where possible.
// ─────────────────────────────────────────────────────────────

/**
 * Convert a URL-safe base64 string to a Uint8Array.
 * Required for VAPID public key when calling pushManager.subscribe().
 */
export function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4)
  const base64   = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/')
  const rawData  = window.atob(base64)
  return Uint8Array.from([...rawData].map(char => char.charCodeAt(0)))
}

/**
 * Detect the current browser name from the user agent.
 * Returns a human-readable string for device management UI.
 */
export function detectBrowser(): string {
  const ua = navigator.userAgent
  if (ua.includes('Edg/'))     return 'Edge'
  if (ua.includes('OPR/'))     return 'Opera'
  if (ua.includes('Chrome/'))  return 'Chrome'
  if (ua.includes('Firefox/')) return 'Firefox'
  if (ua.includes('Safari/'))  return 'Safari'
  return 'متصفح غير معروف'
}

/**
 * Detect the device type from screen width and touch support.
 */
export function detectDeviceType(): 'desktop' | 'mobile' | 'tablet' {
  const width = window.screen.width
  if (width < 768) return 'mobile'
  if (width < 1024 && navigator.maxTouchPoints > 0) return 'tablet'
  return 'desktop'
}

/**
 * Build a human-readable device name, e.g. "Chrome على Windows"
 */
export function buildDeviceName(): string {
  const browser = detectBrowser()
  const ua = navigator.userAgent

  let os = 'جهاز غير معروف'
  if (ua.includes('Windows'))          os = 'Windows'
  else if (ua.includes('Mac OS'))      os = 'macOS'
  else if (ua.includes('Linux'))       os = 'Linux'
  else if (/iPad|iPhone|iPod/.test(ua)) os = 'iOS'
  else if (ua.includes('Android'))     os = 'Android'

  return `${browser} على ${os}`
}

/**
 * Check whether Push Notifications are supported in this browser.
 * Returns false for: old Safari, SSR context, browser without SW support.
 */
export function isPushSupported(): boolean {
  return (
    typeof window !== 'undefined' &&
    'serviceWorker' in navigator &&
    'PushManager' in window &&
    'Notification' in window
  )
}

/**
 * Send a badge count update to the service worker.
 * The SW will call navigator.setAppBadge() if supported (Chrome/Edge only).
 * Failure is non-critical — this function never throws.
 */
export async function updateAppBadge(count: number): Promise<void> {
  if (!('serviceWorker' in navigator)) return
  try {
    const reg = await navigator.serviceWorker.ready
    reg.active?.postMessage({ type: 'UPDATE_BADGE', count })
  } catch {
    // Non-critical — badge update failure should never surface to the user
  }
}
