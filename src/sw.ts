import {
  cleanupOutdatedCaches,
  precacheAndRoute,
} from 'workbox-precaching'
import { clientsClaim } from 'workbox-core'
import { registerRoute, NavigationRoute } from 'workbox-routing'
import {
  NetworkFirst,
  CacheFirst,
  StaleWhileRevalidate,
} from 'workbox-strategies'
import { ExpirationPlugin } from 'workbox-expiration'
import { CacheableResponsePlugin } from 'workbox-cacheable-response'

declare let self: ServiceWorkerGlobalScope

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

// ── 3. Supabase REST / Auth / Storage → NetworkFirst ──
//       Live data first, cache fallback if offline (ERP critical)
registerRoute(
  ({ url }) => url.hostname.includes('supabase.co'),
  new NetworkFirst({
    cacheName: 'supabase-api-v1',
    networkTimeoutSeconds: 8,
    plugins: [
      new ExpirationPlugin({
        maxEntries: 150,
        maxAgeSeconds: 60 * 60, // 1 hour
      }),
      new CacheableResponsePlugin({ statuses: [0, 200] }),
    ],
  })
)

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
registerRoute(
  new NavigationRoute(
    new StaleWhileRevalidate({ cacheName: 'pages-v1' }),
    { denylist: [/^\/api\//] }
  )
)
