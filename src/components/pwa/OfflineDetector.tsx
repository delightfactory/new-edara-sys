import { useState, useEffect } from 'react'
import { WifiOff, Wifi } from 'lucide-react'

/**
 * OfflineDetector — مؤشر الاتصال بالإنترنت
 * يظهر في الأعلى (لا يتعارض مع BottomNav في الأسفل)
 * - عند الانقطاع: شريط أحمر ثابت حتى العودة
 * - عند العودة: شريط أخضر لـ 3 ثوانٍ ثم يختفي
 */
export default function OfflineDetector() {
  const [isOnline, setIsOnline] = useState(navigator.onLine)
  const [showReturnBanner, setShowReturnBanner] = useState(false)

  useEffect(() => {
    const handleOnline = () => {
      setIsOnline(true)
      setShowReturnBanner(true)
      setTimeout(() => setShowReturnBanner(false), 3000)
    }
    const handleOffline = () => {
      setIsOnline(false)
      setShowReturnBanner(false)
    }

    window.addEventListener('online', handleOnline)
    window.addEventListener('offline', handleOffline)
    return () => {
      window.removeEventListener('online', handleOnline)
      window.removeEventListener('offline', handleOffline)
    }
  }, [])

  // متصل — لا شيء يظهر
  if (isOnline && !showReturnBanner) return null

  return (
    <>
      {/* شريط الانقطاع — أحمر ثابت */}
      {!isOnline && (
        <div
          role="alert"
          aria-live="assertive"
          style={{
            position: 'fixed',
            top: 0, left: 0, right: 0,
            zIndex: 9999,
            background: '#dc2626',
            color: '#fff',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: '8px',
            padding: '10px 16px',
            fontSize: '13.5px',
            fontWeight: 600,
            fontFamily: 'var(--font-sans, inherit)',
            boxShadow: '0 2px 12px rgba(220,38,38,0.4)',
            animation: 'od-slide-down 0.25s ease',
          }}
        >
          <WifiOff size={16} />
          <span>لا يوجد اتصال بالإنترنت — بعض الميزات قد لا تعمل</span>
        </div>
      )}

      {/* شريط العودة — أخضر مؤقت */}
      {isOnline && showReturnBanner && (
        <div
          role="status"
          aria-live="polite"
          style={{
            position: 'fixed',
            top: 0, left: 0, right: 0,
            zIndex: 9999,
            background: '#16a34a',
            color: '#fff',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: '8px',
            padding: '10px 16px',
            fontSize: '13.5px',
            fontWeight: 600,
            fontFamily: 'var(--font-sans, inherit)',
            boxShadow: '0 2px 12px rgba(22,163,74,0.4)',
            animation: 'od-slide-down 0.25s ease',
          }}
        >
          <Wifi size={16} />
          <span>تم استعادة الاتصال بالإنترنت</span>
        </div>
      )}

      <style>{`
        @keyframes od-slide-down {
          from { transform: translateY(-100%); opacity: 0; }
          to   { transform: translateY(0);     opacity: 1; }
        }
      `}</style>
    </>
  )
}
