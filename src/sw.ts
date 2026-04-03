/// <reference lib="webworker" />
import {
  cleanupOutdatedCaches,
  createHandlerBoundToURL,
  precacheAndRoute,
} from 'workbox-precaching'

import { clientsClaim } from 'workbox-core'
import { registerRoute, NavigationRoute } from 'workbox-routing'
import {
  CacheFirst,
} from 'workbox-strategies'
import { ExpirationPlugin } from 'workbox-expiration'
import { CacheableResponsePlugin } from 'workbox-cacheable-response'

declare let self: ServiceWorkerGlobalScope

// ── Push notification payload shape (matches dispatch-notification output) ──
interface PushPayload {
  id: string              // notification id (for mark-as-read on click)
  title: string
  body: string
  icon?: string           // icon name (not URL — resolved client-side)
  category: string
  priority: 'low' | 'medium' | 'high' | 'critical'
  actionUrl?: string      // deep-link URL in the app
  badge?: number          // unread count for app badge
  tag?: string            // notification grouping tag
}

// ── 1. Smart update strategy for ERP: notify clients, they apply on next navigation ──
// Do NOT skipWaiting immediately — wait for PWAUpdateBanner user confirmation
// OR apply automatically when user navigates between pages (safe for data integrity)
clientsClaim()

// Listen for SKIP_WAITING message from PWAUpdateBanner or auto-apply logic
;(self as unknown as EventTarget).addEventListener('message', (e: Event) => {
  const event = e as MessageEvent
  if (event.data?.type === 'SKIP_WAITING') {
    ;(self as unknown as { skipWaiting: () => void }).skipWaiting()
  }
})

// ── 2. Precache all build assets + cleanup old caches ──
cleanupOutdatedCaches()
precacheAndRoute(self.__WB_MANIFEST)

// ── 3. Supabase REST / Auth / Storage → NOT cached ──
//       All authenticated API traffic must bypass the service worker cache.
//       Caching bearer-token responses in a shared cache risks leaking one
//       user's data to another user on the same device (shared-cache attack).
//       The Supabase JS client manages its own in-memory state; no SW cache needed.

// ── 4. Google Fonts → CacheFirst (immutable, cache 1 year) ──
registerRoute(
  ({ url }) =>
    url.hostname.includes('fonts.gstatic.com') ||
    url.hostname.includes('fonts.googleapis.com'),
  new CacheFirst({
    cacheName: 'google-fonts-v1',
    plugins: [
      new ExpirationPlugin({
        maxEntries: 20,
        maxAgeSeconds: 60 * 60 * 24 * 365,
      }),
      new CacheableResponsePlugin({ statuses: [0, 200] }),
    ],
  })
)

// ── 5. Static assets (JS, CSS, images) → CacheFirst ──
registerRoute(
  ({ request }) =>
    ['style', 'script', 'image'].includes(request.destination),
  new CacheFirst({
    cacheName: 'static-assets-v1',
    plugins: [
      new ExpirationPlugin({
        maxEntries: 100,
        maxAgeSeconds: 60 * 60 * 24 * 30, // 30 days
      }),
    ],
  })
)

// ── 6. App Shell navigation → StaleWhileRevalidate ──
//       Instant load from cache + silent background refresh
const appShellHandler = createHandlerBoundToURL('index.html')
registerRoute(
  new NavigationRoute(appShellHandler, { denylist: [/^\/api\//] })
)

// ══════════════════════════════════════════════════════════════
// PUSH NOTIFICATION HANDLERS
// Registered AFTER Workbox routes — Workbox does not manage push/click events
// ══════════════════════════════════════════════════════════════

// ── PUSH EVENT HANDLER ──────────────────────────────────────────
// Triggered when the browser receives a push message from the server.
// Must call event.waitUntil() — the browser may close the SW otherwise.
self.addEventListener('push', (event: PushEvent) => {
  // Guard: if no data, show a generic fallback
  if (!event.data) {
    event.waitUntil(
      self.registration.showNotification('إشعار جديد', {
        body: 'لديك رسالة جديدة',
        icon: '/pwa-192x192.png',
        badge: '/pwa-64x64.png',
      })
    )
    return
  }

  let payload: PushPayload
  try {
    payload = event.data.json() as PushPayload
  } catch {
    return  // malformed payload — ignore silently
  }

  // Cast to bypass TS lib.webworker.d.ts lag on 'renotify' — valid browser property per spec
  const options = {
    body:    payload.body,
    icon:    '/pwa-192x192.png',
    badge:   '/pwa-64x64.png',
    data:    { url: payload.actionUrl ?? '/', notificationId: payload.id },
    tag:     payload.tag ?? payload.category ?? 'default',
    renotify: payload.priority === 'critical',
    requireInteraction: payload.priority === 'critical',
    vibrate: payload.priority === 'critical' ? [200, 100, 200, 100, 200] : [100],
    actions: payload.actionUrl
      ? [{ action: 'open', title: 'فتح' }, { action: 'dismiss', title: 'تجاهل' }]
      : [{ action: 'dismiss', title: 'تجاهل' }],
    dir: 'rtl',
    lang: 'ar',
  } as NotificationOptions


  event.waitUntil(
    self.registration.showNotification(payload.title, options)
  )
})

// ── NOTIFICATION CLICK HANDLER ──────────────────────────────────
// Fired when the user clicks the notification or one of its actions.
self.addEventListener('notificationclick', (event: NotificationEvent) => {
  event.notification.close()

  // If user clicked dismiss action — just close, no navigation
  if (event.action === 'dismiss') return

  const notifData = event.notification.data as { url?: string; notificationId?: string }
  const targetUrl = notifData?.url ?? '/'

  event.waitUntil(
    // Try to focus an existing tab showing this app first
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then(clientList => {
        const existingClient = clientList.find(
          client => new URL(client.url).origin === self.location.origin
        )
        if (existingClient) {
          // Navigate existing window to the target URL
          return existingClient.navigate(targetUrl).then(c => c?.focus() ?? existingClient.focus())
        }
        // No open window — open a new one
        return self.clients.openWindow(targetUrl)
      })
  )
})

// ── APP BADGE UPDATE HANDLER ────────────────────────────────────
// Called by the React app to update the OS-level app badge counter.
// Chrome/Edge support navigator.setAppBadge; Firefox/Safari ignore silently.
self.addEventListener('message', (event: ExtendableMessageEvent) => {
  // Handle SKIP_WAITING (pre-existing logic)
  if (event.data?.type === 'SKIP_WAITING') {
    ;(self as unknown as { skipWaiting: () => void }).skipWaiting()
    return
  }

  // Handle badge count updates
  if (event.data?.type !== 'UPDATE_BADGE') return

  const count = (event.data?.count as number) ?? 0

  if ('setAppBadge' in navigator) {
    if (count > 0) {
      ;(navigator as Navigator & { setAppBadge: (n: number) => Promise<void> })
        .setAppBadge(count).catch(() => {})
    } else {
      ;(navigator as Navigator & { clearAppBadge: () => Promise<void> })
        .clearAppBadge().catch(() => {})
    }
  }
})
