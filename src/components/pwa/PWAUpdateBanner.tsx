import { useRegisterSW } from 'virtual:pwa-register/react'
import { RefreshCw, WifiOff, X } from 'lucide-react'

/**
 * PWAUpdateBanner
 * Shows two states:
 *  - "Offline ready" — first time the app is cached for offline use
 *  - "Update available" — a new service worker is waiting to activate
 *
 * Uses registerType:'prompt' so the user controls when to update.
 * The service worker checks for updates every hour automatically.
 */
export default function PWAUpdateBanner() {
  const {
    needRefresh: [needRefresh, setNeedRefresh],
    offlineReady: [offlineReady, setOfflineReady],
    updateServiceWorker,
  } = useRegisterSW({
    // Auto-check for new SW every 60 minutes
    onRegistered(registration: ServiceWorkerRegistration | undefined) {
      if (registration) {
        setInterval(() => registration.update(), 60 * 60 * 1000)
      }
    },
  })

  const dismiss = () => {
    setNeedRefresh(false)
    setOfflineReady(false)
  }

  if (!needRefresh && !offlineReady) return null

  return (
    <div className="pwa-banner" role="status" aria-live="polite">
      <div className="pwa-banner-content">
        {offlineReady ? (
          <>
            <WifiOff size={16} style={{ color: 'var(--color-success)', flexShrink: 0 }} />
            <span>جاهز للعمل بدون إنترنت ✅</span>
          </>
        ) : (
          <>
            <RefreshCw size={16} style={{ color: 'var(--color-primary)', flexShrink: 0 }} />
            <span>تحديث جديد متاح</span>
            <button
              className="btn btn-primary btn-sm"
              onClick={() => updateServiceWorker(true)}
              style={{ flexShrink: 0 }}
            >
              تحديث الآن
            </button>
          </>
        )}
      </div>
      <button
        className="pwa-banner-close"
        onClick={dismiss}
        aria-label="إغلاق"
      >
        <X size={14} />
      </button>

      <style>{`
        .pwa-banner {
          position: fixed;
          bottom: calc(var(--bottom-nav-height, 64px) + 12px);
          left: 12px;
          right: 12px;
          z-index: var(--z-toast, 300);
          background: var(--bg-surface);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-lg, 14px);
          padding: 12px 14px;
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 10px;
          box-shadow: var(--shadow-lg);
          backdrop-filter: blur(12px);
          animation: pwa-slide-in 0.3s cubic-bezier(.22,.68,0,1.2) both;
        }
        @keyframes pwa-slide-in {
          from { opacity: 0; transform: translateY(16px); }
          to   { opacity: 1; transform: none; }
        }
        .pwa-banner-content {
          display: flex;
          align-items: center;
          gap: 10px;
          flex: 1;
          font-size: 13px;
          font-weight: 500;
          color: var(--text-primary);
          flex-wrap: wrap;
        }
        .pwa-banner-close {
          background: none;
          border: none;
          cursor: pointer;
          color: var(--text-muted);
          padding: 4px;
          display: flex;
          align-items: center;
          flex-shrink: 0;
          transition: color 0.15s;
        }
        .pwa-banner-close:hover { color: var(--text-primary); }

        @media (min-width: 768px) {
          .pwa-banner {
            left: auto;
            right: 24px;
            bottom: 24px;
            width: 340px;
          }
        }
      `}</style>
    </div>
  )
}
