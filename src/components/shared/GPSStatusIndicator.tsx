import { useState, useCallback } from 'react'
import useGeoPermission from '@/hooks/useGeoPermission'

interface GPSCoords {
  lat: number
  lng: number
  accuracy?: number
}

interface GPSStatusIndicatorProps {
  requiresGPS: boolean          // من activity_type.requires_gps
  onCoordsChange: (coords: GPSCoords | null) => void
  customerLat?: number | null   // موقع العميل للمقارنة
  customerLng?: number | null
  value?: GPSCoords | null      // القيمة الحالية
}

type GPSState = 'idle' | 'loading' | 'success' | 'error' | 'denied'

const DISTANCE_WARNING_METERS = 500   // > 500م تحذير بدون منع
const ACCURACY_WARNING_METERS = 50    // < 50م دقة مقبولة

function haversineDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R   = 6371000
  const dLat = (lat2 - lat1) * Math.PI / 180
  const dLng = (lng2 - lng1) * Math.PI / 180
  const a   = Math.sin(dLat / 2) ** 2 +
              Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
              Math.sin(dLng / 2) ** 2
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

/**
 * GPSStatusIndicator
 *
 * منطق التحقق (يطابق validate_activity_payload() في الـ backend):
 * - requiresGPS=true + لا GPS → منع submit (يجب تمرير هذه الحالة للـ parent)
 * - requiresGPS=true + GPS + دقة منخفضة → تحذير فقط
 * - requiresGPS=true + GPS + distance > 500م → تحذير فقط (لا منع)
 * - requiresGPS=false → لا يظهر المكوّن
 */
export default function GPSStatusIndicator({
  requiresGPS,
  onCoordsChange,
  customerLat,
  customerLng,
  value,
}: GPSStatusIndicatorProps) {
  const [state,    setState]    = useState<GPSState>('idle')
  const [error,    setError]    = useState<string>('')
  const [distance, setDistance] = useState<number | null>(null)

  const geo = useGeoPermission()

  const requestGPS = useCallback(() => {
    if (!navigator.geolocation) {
      setState('error')
      setError('متصفحك لا يدعم تحديد الموقع')
      onCoordsChange(null)
      return
    }

    setState('loading')
    setError('')

    // نستخدم الـ hook لطلب الموقع للاستفادة من retry strategy
    geo.requestLocation().then(geoResult => {
      if (!geoResult.ok) {
        if (geoResult.reason === 'denied') {
          setState('denied')
          setError(geoResult.message)
        } else {
          setState('error')
          setError(geoResult.message)
        }
        onCoordsChange(null)
        return
      }

      const coords = geoResult.coords

      setState('success')
      onCoordsChange({ lat: coords.lat, lng: coords.lng, accuracy: coords.accuracy })

      // حساب المسافة من موقع العميل
      if (customerLat != null && customerLng != null) {
        const dist = haversineDistance(coords.lat, coords.lng, customerLat, customerLng)
        setDistance(Math.round(dist))
      }
    })
  }, [customerLat, customerLng, onCoordsChange, geo])

  // إذا كان GPS غير مطلوب لا نعرض شيئاً
  if (!requiresGPS) return null

  const hasCoords     = state === 'success' || value != null
  const lowAccuracy   = value?.accuracy != null && value.accuracy > ACCURACY_WARNING_METERS
  const farFromClient = distance != null && distance > DISTANCE_WARNING_METERS

  return (
    <div className="gps-ind">
      {/* حالة النجاح */}
      {hasCoords && (
        <div className="gps-ind--success">
          <span className="gps-dot gps-dot--green" />
          <span>
            GPS محدد
            {value?.accuracy && ` • دقة ${Math.round(value.accuracy)}م`}
          </span>
          <button
            className="gps-refresh"
            onClick={requestGPS}
            type="button"
            title="تحديث الموقع"
          >
            ↻
          </button>
        </div>
      )}

      {/* تحذير دقة منخفضة */}
      {hasCoords && lowAccuracy && (
        <div className="gps-warn">
          ⚠ دقة GPS منخفضة ({Math.round(value!.accuracy!)}م) — يُنصح بالانتظار
        </div>
      )}

      {/* تحذير بُعد عن العميل */}
      {hasCoords && farFromClient && (
        <div className="gps-warn">
          ⚠ أنت على بُعد {distance?.toLocaleString('ar-EG')} م من موقع العميل
        </div>
      )}

      {/* حالة التحميل */}
      {state === 'loading' && (
        <div className="gps-ind--loading">
          <span className="gps-spinner" />
          <span>جاري تحديد الموقع...</span>
        </div>
      )}

      {/* حالة الخطأ / الرفض — يمنع submit */}
      {(state === 'error' || state === 'denied') && (
        <div className="gps-ind--error">
          <span>✗</span>
          <span>{error}</span>
        </div>
      )}

      {/* حالة البداية — لم يُطلب GPS بعد */}
      {state === 'idle' && !value && (
        <button
          className="btn btn--secondary btn--sm gps-btn"
          onClick={requestGPS}
          type="button"
        >
          📍 تحديد موقعي
        </button>
      )}

      <style>{`
        .gps-ind {
          display: flex;
          flex-direction: column;
          gap: var(--space-2);
        }
        .gps-ind--success {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          font-size: var(--text-sm);
          color: var(--color-success);
          font-weight: 500;
        }
        .gps-dot {
          width: 8px; height: 8px;
          border-radius: 50%;
          flex-shrink: 0;
          animation: gps-pulse 2s infinite;
        }
        .gps-dot--green { background: var(--color-success); }
        @keyframes gps-pulse {
          0%, 100% { opacity: 1; transform: scale(1); }
          50% { opacity: 0.6; transform: scale(1.3); }
        }
        .gps-refresh {
          border: none;
          background: none;
          cursor: pointer;
          font-size: 14px;
          color: var(--text-muted);
          padding: 2px 6px;
          border-radius: var(--radius-sm);
          transition: background var(--transition-fast);
        }
        .gps-refresh:hover { background: var(--bg-surface-2); }
        .gps-ind--loading {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          font-size: var(--text-sm);
          color: var(--text-muted);
        }
        .gps-spinner {
          width: 14px; height: 14px;
          border: 2px solid var(--border-primary);
          border-top-color: var(--color-primary);
          border-radius: 50%;
          animation: spin 0.8s linear infinite;
        }
        @keyframes spin { to { transform: rotate(360deg); } }
        .gps-warn {
          font-size: var(--text-xs);
          color: var(--color-warning);
          padding: var(--space-2);
          background: var(--color-warning-light);
          border-radius: var(--radius-sm);
          border: 1px solid rgba(217, 119, 6, 0.2);
        }
        .gps-ind--error {
          display: flex;
          align-items: flex-start;
          gap: var(--space-2);
          font-size: var(--text-sm);
          color: var(--color-danger);
          padding: var(--space-2);
          background: var(--color-danger-light);
          border-radius: var(--radius-sm);
          border: 1px solid rgba(220, 38, 38, 0.15);
        }
        .gps-btn { align-self: flex-start; }
      `}</style>
    </div>
  )
}

export type { GPSCoords }
