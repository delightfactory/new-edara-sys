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

// ══════════════════════════════════════════════════════════════
// UPDATE STRATEGY: Instant Silent Update
// 1. skipWaiting() on install → new SW activates immediately
// 2. clientsClaim() → takes control of all open tabs instantly
// 3. Browser fires `controllerchange` event on each tab — the React
//    app listens for this (not postMessage) to trigger a safe reload.
//    Using controllerchange avoids the postMessage race condition where
//    the message may arrive before the React listener is attached.
// ══════════════════════════════════════════════════════════════

// ── 1. Skip waiting immediately on install ──
self.addEventListener('install', () => {
  ;(self as unknown as { skipWaiting: () => void }).skipWaiting()
})

// ── 2. Claim all open clients on activate ──
// clientsClaim() fires the `controllerchange` event on every open tab,
// which is the signal the React app uses to trigger a graceful reload.
clientsClaim()

// ── 3. Precache all build assets + cleanup old caches ──
cleanupOutdatedCaches()
precacheAndRoute(self.__WB_MANIFEST)

// ── 4. Supabase REST / Auth / Storage → NOT cached ──
//       All authenticated API traffic must bypass the service worker cache.
//       Caching bearer-token responses in a shared cache risks leaking one
//       user's data to another user on the same device (shared-cache attack).
//       The Supabase JS client manages its own in-memory state; no SW cache needed.

// ── 5. Google Fonts → CacheFirst (immutable, cache 1 year) ──
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

// ── 6. Static assets (JS, CSS, images) → CacheFirst ──
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

// ── 7. App Shell navigation → serve index.html from precache ──
const appShellHandler = createHandlerBoundToURL('index.html')
registerRoute(
  new NavigationRoute(appShellHandler, { denylist: [/^\/api\//] })
)

// ══════════════════════════════════════════════════════════════
// PUSH NOTIFICATION HANDLERS
// Registered AFTER Workbox routes — Workbox does not manage push/click events
// ══════════════════════════════════════════════════════════════

// ── PUSH EVENT HANDLER ──────────────────────────────────────────
self.addEventListener('push', (event: PushEvent) => {
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
    return
  }

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
self.addEventListener('notificationclick', (event: NotificationEvent) => {
  event.notification.close()

  if (event.action === 'dismiss') return

  const notifData = event.notification.data as { url?: string; notificationId?: string }
  const targetUrl = notifData?.url ?? '/'

  event.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then(clientList => {
        const existingClient = clientList.find(
          client => new URL(client.url).origin === self.location.origin
        )
        if (existingClient) {
          return existingClient.navigate(targetUrl).then(c => c?.focus() ?? existingClient.focus())
        }
        return self.clients.openWindow(targetUrl)
      })
  )
})

// ── APP BADGE UPDATE HANDLER ────────────────────────────────────
self.addEventListener('message', (event: ExtendableMessageEvent) => {
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
