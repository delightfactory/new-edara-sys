import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'
import './styles/main.css'
import { initSentry } from '@/lib/monitoring/sentry'

initSentry()

async function cleanupDevServiceWorkers() {
  if (!import.meta.env.DEV) return
  if (!('serviceWorker' in navigator)) return

  const registrations = await navigator.serviceWorker.getRegistrations()
  if (registrations.length === 0) return

  await Promise.allSettled(registrations.map(r => r.unregister()))

  if ('caches' in window) {
    const cacheKeys = await caches.keys()
    const appCacheKeys = cacheKeys.filter(key =>
      key.startsWith('pages-') ||
      key.startsWith('static-assets-') ||
      key.startsWith('google-fonts-') ||
      key.startsWith('workbox-')
    )
    await Promise.allSettled(appCacheKeys.map(key => caches.delete(key)))
  }

  const reloadFlag = '__dev_sw_cleanup_reloaded__'
  if (navigator.serviceWorker.controller && !sessionStorage.getItem(reloadFlag)) {
    sessionStorage.setItem(reloadFlag, '1')
    window.location.reload()
  }
}

void cleanupDevServiceWorkers().finally(() => {
  createRoot(document.getElementById('root')!).render(
    <StrictMode>
      <App />
    </StrictMode>,
  )
})
