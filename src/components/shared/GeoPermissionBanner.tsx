import useGeoPermission from '@/hooks/useGeoPermission'
import type { GeoPermissionStatus } from '@/hooks/useGeoPermission'
import { MapPin, AlertTriangle, RefreshCw, Settings, CheckCircle } from 'lucide-react'

interface GeoPermissionBannerProps {
  /** إظهار البانر حتى في حالة prompt (لتعليم المستخدم قبل الطلب) */
  showOnPrompt?: boolean
  /** callback عند نجاح تحديد الموقع */
  onLocationGranted?: (coords: { lat: number; lng: number; accuracy: number }) => void
  /** النص التوضيحي المخصص */
  contextMessage?: string
}

/**
 * GeoPermissionBanner — بانر احترافي لإدارة صلاحيات الموقع
 *
 * يعرض حالة GPS للمستخدم:
 * - 📍 أخضر: GPS نشط ومحدد
 * - ⚠ أصفر: يحتاج سماح — مع زر "السماح"
 * - 🔴 أحمر: محظور — مع تعليمات خطوة بخطوة حسب المتصفح
 */
export default function GeoPermissionBanner({
  showOnPrompt = false,
  onLocationGranted,
  contextMessage = 'التطبيق يحتاج موقعك لتسجيل الزيارة بدقة',
}: GeoPermissionBannerProps) {
  const {
    status,
    coords,
    error,
    requestLocation,
    isBlocked,
    recheckPermission,
    isLoading,
  } = useGeoPermission()

  const handleRequestLocation = async () => {
    const result = await requestLocation()
    if (result && onLocationGranted) {
      onLocationGranted(result)
    }
  }

  // لا نعرض شيئاً إذا الصلاحية ممنوحة وبدون أخطاء (الحالة المثالية)
  if (status === 'granted' && coords) {
    return (
      <div className="geo-banner geo-banner--success">
        <CheckCircle size={16} />
        <span>
          📍 GPS محدد
          {coords.accuracy && ` • دقة ${Math.round(coords.accuracy)} م`}
        </span>
      </div>
    )
  }

  // حالة الجهاز لا يدعم GPS
  if (status === 'unavailable') {
    return (
      <div className="geo-banner geo-banner--error">
        <AlertTriangle size={16} />
        <span>{error}</span>
      </div>
    )
  }

  // حالة checking — قيد الفحص
  if (status === 'checking' || isLoading) {
    return (
      <div className="geo-banner geo-banner--loading">
        <div className="geo-spinner" />
        <span>جاري فحص صلاحية الموقع...</span>
      </div>
    )
  }

  // حالة prompt — يمكن طلب الصلاحية
  if (status === 'prompt') {
    if (!showOnPrompt) return null
    return (
      <div className="geo-banner geo-banner--prompt">
        <MapPin size={16} />
        <div className="geo-banner-content">
          <span className="geo-banner-msg">{contextMessage}</span>
          <button
            className="geo-banner-btn geo-banner-btn--primary"
            onClick={handleRequestLocation}
            type="button"
          >
            📍 السماح بتحديد الموقع
          </button>
        </div>
      </div>
    )
  }

  // حالة denied — محظور
  if (isBlocked) {
    return (
      <div className="geo-banner geo-banner--blocked">
        <AlertTriangle size={16} />
        <div className="geo-banner-content">
          <span className="geo-banner-msg geo-banner-msg--error">{error}</span>
          <div className="geo-banner-actions">
            <button
              className="geo-banner-btn geo-banner-btn--retry"
              onClick={async () => {
                recheckPermission()
                const result = await requestLocation()
                if (result && onLocationGranted) {
                  onLocationGranted(result)
                }
              }}
              type="button"
            >
              <RefreshCw size={14} />
              تم التعديل — أعد المحاولة
            </button>
          </div>
        </div>

        <style>{blockedStyles}</style>
      </div>
    )
  }

  return null
}

const blockedStyles = `
  .geo-banner {
    display: flex;
    align-items: flex-start;
    gap: var(--space-3, 12px);
    padding: var(--space-3, 12px) var(--space-4, 16px);
    border-radius: var(--radius-lg, 12px);
    font-size: var(--text-sm, 14px);
    line-height: 1.5;
  }
  .geo-banner svg {
    flex-shrink: 0;
    margin-top: 2px;
  }
  .geo-banner--success {
    background: rgba(16, 185, 129, 0.08);
    border: 1px solid rgba(16, 185, 129, 0.2);
    color: var(--color-success, #10b981);
    font-weight: 500;
  }
  .geo-banner--loading {
    background: var(--bg-surface-2, #f9f9f9);
    border: 1px solid var(--border-light, #e5e5e5);
    color: var(--text-muted, #888);
  }
  .geo-banner--prompt {
    background: rgba(59, 130, 246, 0.06);
    border: 1px solid rgba(59, 130, 246, 0.15);
    color: var(--text-primary, #333);
  }
  .geo-banner--blocked {
    background: rgba(220, 38, 38, 0.05);
    border: 1px solid rgba(220, 38, 38, 0.15);
    color: var(--text-primary, #333);
  }
  .geo-banner--error {
    background: rgba(220, 38, 38, 0.05);
    border: 1px solid rgba(220, 38, 38, 0.15);
    color: var(--color-danger, #dc2626);
  }
  .geo-banner-content {
    display: flex;
    flex-direction: column;
    gap: var(--space-2, 8px);
    flex: 1;
  }
  .geo-banner-msg {
    font-size: var(--text-sm, 14px);
  }
  .geo-banner-msg--error {
    color: var(--color-danger, #dc2626);
    font-weight: 500;
  }
  .geo-banner-actions {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-2, 8px);
  }
  .geo-banner-btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 6px 14px;
    border-radius: var(--radius-md, 8px);
    font-size: var(--text-xs, 12px);
    font-weight: 600;
    cursor: pointer;
    border: none;
    transition: all 0.15s ease;
  }
  .geo-banner-btn--primary {
    background: var(--color-primary, #3b82f6);
    color: white;
  }
  .geo-banner-btn--primary:hover {
    opacity: 0.9;
    transform: translateY(-1px);
  }
  .geo-banner-btn--retry {
    background: var(--bg-surface-2, #f0f0f0);
    color: var(--text-primary, #333);
    border: 1px solid var(--border-light, #ddd);
  }
  .geo-banner-btn--retry:hover {
    background: var(--bg-surface-3, #e5e5e5);
  }
  .geo-spinner {
    width: 14px;
    height: 14px;
    border: 2px solid var(--border-primary, #ddd);
    border-top-color: var(--color-primary, #3b82f6);
    border-radius: 50%;
    animation: geo-spin 0.8s linear infinite;
    flex-shrink: 0;
    margin-top: 2px;
  }
  @keyframes geo-spin { to { transform: rotate(360deg); } }
`

export type { GeoPermissionBannerProps }
