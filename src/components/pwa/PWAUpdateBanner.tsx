import { useEffect } from 'react'
import { useRegisterSW } from 'virtual:pwa-register/react'
import { RefreshCw, WifiOff, X } from 'lucide-react'
import { useLocation } from 'react-router-dom'

/**
 * PWAUpdateBanner — ERP-Grade Smart Update Strategy
 *
 * Update flow:
 *  1. SW installs silently in background (no disruption)
 *  2. Hourly auto-check for new SW version
 *  3. When new SW is WAITING → show "Update available" banner
 *  4. Smart auto-apply: if user navigates to a new route AND there's
 *     a pending update, apply it on that navigation (zero data-loss risk
 *     because navigation means the current page is done)
 *  5. Manual: user can tap "تحديث الآن" at any time
 *
 * This matches the ERP 2025 best practice:
 *  - No forced reloads (data integrity preserved)
 *  - Seamless update on next page navigation
 *  - User can also trigger manually
 */
export default function PWAUpdateBanner() {
  const location = useLocation()

  const {
    needRefresh: [needRefresh, setNeedRefresh],
    offlineReady: [offlineReady, setOfflineReady],
    updateServiceWorker,
  } = useRegisterSW({
    // ── Auto-check every 60 minutes ──
    onRegistered(registration: ServiceWorkerRegistration | undefined) {
      if (registration) {
        setInterval(() => registration.update(), 60 * 60 * 1000)
      }
    },
    // ── Send SKIP_WAITING via postMessage (not skipWaiting directly) ──
    onNeedRefresh() {
      // Banner will show; auto-apply will happen on next navigation
      setNeedRefresh(true)
    },
  })

  // ── Auto-apply update on navigation (between pages = safe, no data loss) ──
  useEffect(() => {
    if (needRefresh) {
      // User navigated → apply update now (page transition = safe point)
      updateServiceWorker(true)
    }
    // Only trigger on route change, not on initial mount
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [location.pathname])

  const dismiss = () => {
    setNeedRefresh(false)
    setOfflineReady(false)
  }

  const handleManualUpdate = () => {
    updateServiceWorker(true)
  }

  if (!needRefresh && !offlineReady) return null

  return (
    <div className="pwa-banner" role="status" aria-live="polite">
      <div className="pwa-banner-content">
        {offlineReady && !needRefresh ? (
          <>
            <WifiOff size={16} style={{ color: 'var(--color-success)', flexShrink: 0 }} />
            <span>جاهز للعمل بدون إنترنت ✅</span>
          </>
        ) : (
          <>
            <RefreshCw size={16} style={{ color: 'var(--color-primary)', flexShrink: 0 }} />
            <span>تحديث جديد — سيُطبَّق عند الانتقال للصفحة التالية</span>
            <button
              className="btn btn-primary btn-sm"
              onClick={handleManualUpdate}
              style={{ flexShrink: 0 }}
            >
              الآن
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
            width: 360px;
          }
        }
      `}</style>
    </div>
  )
}
