/**
 * GeoPermissionBanner — بانر احترافي لإدارة صلاحيات الموقع
 *
 * يعرض حالة GPS للمستخدم مع خطوات إرشادية مرئية:
 * - ✅ أخضر: GPS نشط ومحدد
 * - 🔵 أزرق: يحتاج سماح — مع زر "السماح"
 * - 🔴 أحمر: محظور — مع خطوات مرئية حسب المتصفح + timer للإعادة التلقائية
 */
import { useState, useEffect, useCallback } from 'react'
import { MapPin, AlertTriangle, RefreshCw, CheckCircle, Loader2 } from 'lucide-react'
import useGeoPermission from '@/hooks/useGeoPermission'
import type { BrowserGuideStep } from '@/hooks/useGeoPermission'

interface GeoPermissionBannerProps {
  /** إظهار البانر حتى في حالة prompt */
  showOnPrompt?: boolean
  /** callback عند نجاح تحديد الموقع */
  onLocationGranted?: (coords: { lat: number; lng: number; accuracy: number }) => void
  /** النص التوضيحي المخصص لحالة prompt */
  contextMessage?: string
}

// ─── Blocked Guide ────────────────────────────────────────────────────────────

function BlockedGuide({
  steps,
  onRetry,
  isRetrying,
}: {
  steps: BrowserGuideStep[]
  onRetry: () => void
  isRetrying: boolean
}) {
  // Countdown للإعادة التلقائية بعد تعديل الإعدادات
  const [countdown, setCountdown] = useState<number | null>(null)

  const startCountdown = useCallback(() => {
    setCountdown(5)
  }, [])

  useEffect(() => {
    if (countdown === null) return
    if (countdown === 0) {
      onRetry()
      setCountdown(null)
      return
    }
    const id = setTimeout(() => setCountdown(c => (c ?? 1) - 1), 1000)
    return () => clearTimeout(id)
  }, [countdown, onRetry])

  return (
    <div className="gpb-blocked">
      {/* Header */}
      <div className="gpb-blocked-header">
        <div className="gpb-blocked-icon">
          <AlertTriangle size={18} aria-hidden="true" />
        </div>
        <div>
          <div className="gpb-blocked-title">تم حظر الوصول للموقع</div>
          <div className="gpb-blocked-sub">اتبع الخطوات التالية لتفعيله</div>
        </div>
      </div>

      {/* Steps */}
      <ol className="gpb-steps" aria-label="خطوات تفعيل الموقع">
        {steps.map((s) => (
          <li key={s.step} className="gpb-step">
            <span className="gpb-step-num" aria-hidden="true">{s.step}</span>
            <span className="gpb-step-icon" aria-hidden="true">{s.icon}</span>
            <span className="gpb-step-text">{s.text}</span>
          </li>
        ))}
      </ol>

      {/* Actions */}
      <div className="gpb-blocked-actions">
        <button
          id="gpb-btn-retry"
          type="button"
          className="gpb-retry-btn"
          onClick={isRetrying ? undefined : onRetry}
          disabled={isRetrying}
          aria-label="إعادة المحاولة بعد تعديل الإعدادات"
        >
          {isRetrying ? (
            <>
              <Loader2 size={14} className="gpb-spin" aria-hidden="true" />
              جاري التحقق...
            </>
          ) : (
            <>
              <RefreshCw size={14} aria-hidden="true" />
              تم التعديل — أعد المحاولة
            </>
          )}
        </button>

        {countdown === null && !isRetrying && (
          <button
            id="gpb-btn-start-countdown"
            type="button"
            className="gpb-countdown-trigger"
            onClick={startCountdown}
            aria-label="إعادة الفحص تلقائياً"
          >
            أعد الفحص تلقائياً
          </button>
        )}

        {countdown !== null && (
          <div className="gpb-countdown" aria-live="polite" role="status">
            <div
              className="gpb-countdown-ring"
              style={{ '--pct': `${(countdown / 5) * 100}%` } as React.CSSProperties}
              aria-hidden="true"
            />
            <span>إعادة الفحص خلال {countdown}ث</span>
          </div>
        )}
      </div>
    </div>
  )
}

// ─── Main Banner ──────────────────────────────────────────────────────────────

export default function GeoPermissionBanner({
  showOnPrompt = false,
  onLocationGranted,
  contextMessage = 'التطبيق يحتاج موقعك لتسجيل العملية بدقة',
}: GeoPermissionBannerProps) {
  const {
    status,
    coords,
    error,
    requestLocation,
    isBlocked,
    recheckPermission,
    isLoading,
    browserGuideSteps,
  } = useGeoPermission()

  const [isRetrying, setIsRetrying] = useState(false)

  const handleRetry = useCallback(async () => {
    setIsRetrying(true)
    recheckPermission()
    // نعطي المتصفح لحظة لتحديث حالة الصلاحية
    await new Promise(r => setTimeout(r, 600))
    const geoResult = await requestLocation()
    setIsRetrying(false)
    if (geoResult.ok && onLocationGranted) {
      onLocationGranted(geoResult.coords)
    }
  }, [recheckPermission, requestLocation, onLocationGranted])

  const handleRequestLocation = useCallback(async () => {
    const geoResult = await requestLocation()
    if (geoResult.ok && onLocationGranted) {
      onLocationGranted(geoResult.coords)
    }
  }, [requestLocation, onLocationGranted])

  // ── حالة الجهاز لا يدعم GPS ─────────────────────────────────────────────
  if (status === 'unavailable') {
    return (
      <div className="gpb gpb--error" role="alert" aria-live="assertive">
        <AlertTriangle size={16} aria-hidden="true" />
        <span>{error ?? 'جهازك لا يدعم خدمات تحديد الموقع'}</span>
        <style>{bannerStyles}</style>
      </div>
    )
  }

  // ── حالة checking / loading ──────────────────────────────────────────────
  if (status === 'checking' || isLoading) {
    return (
      <div className="gpb gpb--loading" role="status" aria-live="polite">
        <Loader2 size={15} className="gpb-spin" aria-hidden="true" />
        <span>{isLoading ? 'جاري تحديد موقعك...' : 'جاري فحص صلاحية الموقع...'}</span>
        <style>{bannerStyles}</style>
      </div>
    )
  }

  // ── حالة granted مع إحداثيات ────────────────────────────────────────────
  if (status === 'granted' && coords) {
    return (
      <div className="gpb gpb--success" role="status">
        <CheckCircle size={15} aria-hidden="true" />
        <span>
          📍 تم تحديد موقعك
          {coords.accuracy
            ? ` • دقة ±${Math.round(coords.accuracy)} م`
            : ''}
        </span>
        <style>{bannerStyles}</style>
      </div>
    )
  }

  // ── حالة prompt — يمكن طلب الصلاحية ────────────────────────────────────
  if (status === 'prompt') {
    if (!showOnPrompt) return null
    return (
      <div className="gpb gpb--prompt" role="region" aria-label="طلب صلاحية الموقع">
        <MapPin size={15} aria-hidden="true" />
        <div className="gpb-content">
          <span className="gpb-msg">{contextMessage}</span>
          <button
            id="gpb-btn-allow"
            type="button"
            className="gpb-allow-btn"
            onClick={handleRequestLocation}
            disabled={isLoading}
          >
            {isLoading
              ? <><Loader2 size={13} className="gpb-spin" aria-hidden="true" /> جاري التحقق...</>
              : '📍 السماح بتحديد الموقع'
            }
          </button>
        </div>
        <style>{bannerStyles}</style>
      </div>
    )
  }

  // ── حالة denied — محظور ─────────────────────────────────────────────────
  if (isBlocked) {
    return (
      <div className="gpb gpb--blocked" role="alert" aria-live="assertive">
        <BlockedGuide
          steps={browserGuideSteps}
          onRetry={handleRetry}
          isRetrying={isRetrying}
        />
        <style>{bannerStyles}</style>
      </div>
    )
  }

  return null
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const bannerStyles = `
  /* ── Base ── */
  .gpb {
    display: flex;
    align-items: flex-start;
    gap: var(--space-3, 12px);
    padding: var(--space-3, 12px) var(--space-4, 16px);
    border-radius: var(--radius-lg, 12px);
    font-size: var(--text-sm, 14px);
    line-height: 1.5;
    width: 100%;
  }
  .gpb svg { flex-shrink: 0; margin-top: 2px; }

  /* ── Variants ── */
  .gpb--success {
    background: color-mix(in srgb, var(--color-success, #16a34a) 8%, transparent);
    border: 1px solid color-mix(in srgb, var(--color-success, #16a34a) 20%, transparent);
    color: var(--color-success, #16a34a);
    font-weight: 500;
    align-items: center;
  }
  .gpb--loading {
    background: var(--bg-surface-2, #f9f9f9);
    border: 1px solid var(--border-color, #e5e5e5);
    color: var(--text-muted, #888);
    align-items: center;
  }
  .gpb--prompt {
    background: color-mix(in srgb, var(--color-primary, #2563eb) 6%, transparent);
    border: 1px solid color-mix(in srgb, var(--color-primary, #2563eb) 18%, transparent);
    color: var(--text-primary, #333);
    align-items: center;
  }
  .gpb--error {
    background: color-mix(in srgb, var(--color-danger, #dc2626) 6%, transparent);
    border: 1px solid color-mix(in srgb, var(--color-danger, #dc2626) 18%, transparent);
    color: var(--color-danger, #dc2626);
    font-weight: 500;
    align-items: center;
  }
  .gpb--blocked {
    background: color-mix(in srgb, var(--color-danger, #dc2626) 4%, transparent);
    border: 1px solid color-mix(in srgb, var(--color-danger, #dc2626) 15%, transparent);
    padding: var(--space-4, 16px);
    border-radius: var(--radius-xl, 16px);
    flex-direction: column;
    gap: 0;
  }

  /* ── Prompt content ── */
  .gpb-content {
    display: flex;
    flex-direction: column;
    gap: var(--space-2, 8px);
    flex: 1;
  }
  .gpb-msg { font-size: var(--text-sm, 14px); font-weight: 500; }
  .gpb-allow-btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 8px 16px;
    background: var(--color-primary, #2563eb);
    color: #fff;
    border: none;
    border-radius: var(--radius-lg, 12px);
    font-size: var(--text-sm, 14px);
    font-weight: 700;
    font-family: var(--font-sans, inherit);
    cursor: pointer;
    transition: all 0.15s ease;
    align-self: flex-start;
    min-height: 40px;
  }
  .gpb-allow-btn:hover { opacity: 0.9; transform: translateY(-1px); }
  .gpb-allow-btn:active { transform: scale(0.98); }
  .gpb-allow-btn:disabled { opacity: 0.6; cursor: not-allowed; transform: none; }

  /* ── Blocked guide ── */
  .gpb-blocked-header {
    display: flex;
    align-items: center;
    gap: var(--space-3, 12px);
    margin-bottom: var(--space-4, 16px);
  }
  .gpb-blocked-icon {
    width: 40px;
    height: 40px;
    border-radius: 50%;
    background: color-mix(in srgb, var(--color-danger, #dc2626) 12%, transparent);
    color: var(--color-danger, #dc2626);
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }
  .gpb-blocked-title {
    font-weight: 700;
    font-size: var(--text-base, 15px);
    color: var(--color-danger, #dc2626);
  }
  .gpb-blocked-sub {
    font-size: var(--text-xs, 12px);
    color: var(--text-muted, #888);
    margin-top: 2px;
  }

  /* ── Steps ── */
  .gpb-steps {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 0;
    background: var(--bg-surface, #f8fafc);
    border: 1px solid var(--border-color, #e2e8f0);
    border-radius: var(--radius-lg, 12px);
    overflow: hidden;
    margin-bottom: var(--space-4, 16px);
  }
  .gpb-step {
    display: flex;
    align-items: center;
    gap: var(--space-3, 12px);
    padding: var(--space-3, 12px) var(--space-4, 16px);
    font-size: var(--text-sm, 14px);
    color: var(--text-secondary, #334155);
    border-bottom: 1px solid var(--border-color, #e2e8f0);
    transition: background 0.15s;
  }
  .gpb-step:last-child { border-bottom: none; }
  .gpb-step-num {
    width: 22px;
    height: 22px;
    border-radius: 50%;
    background: color-mix(in srgb, var(--color-primary, #2563eb) 12%, transparent);
    color: var(--color-primary, #2563eb);
    font-size: 11px;
    font-weight: 700;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }
  .gpb-step-icon { font-size: 16px; flex-shrink: 0; }
  .gpb-step-text { font-weight: 500; line-height: 1.4; }

  /* ── Actions ── */
  .gpb-blocked-actions {
    display: flex;
    align-items: center;
    gap: var(--space-3, 12px);
    flex-wrap: wrap;
  }
  .gpb-retry-btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 10px 18px;
    background: var(--color-primary, #2563eb);
    color: #fff;
    border: none;
    border-radius: var(--radius-lg, 12px);
    font-size: var(--text-sm, 14px);
    font-weight: 700;
    font-family: var(--font-sans, inherit);
    cursor: pointer;
    transition: all 0.15s ease;
    min-height: 44px;
  }
  .gpb-retry-btn:hover:not(:disabled) { opacity: 0.9; }
  .gpb-retry-btn:active:not(:disabled) { transform: scale(0.98); }
  .gpb-retry-btn:disabled { opacity: 0.7; cursor: not-allowed; }

  .gpb-countdown-trigger {
    font-size: var(--text-xs, 12px);
    color: var(--text-muted, #888);
    background: none;
    border: 1px solid var(--border-color, #e2e8f0);
    border-radius: var(--radius-md, 8px);
    padding: 6px 12px;
    cursor: pointer;
    font-family: var(--font-sans, inherit);
    transition: all 0.15s;
  }
  .gpb-countdown-trigger:hover { background: var(--bg-surface-2); }

  /* ── Countdown ring ── */
  .gpb-countdown {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: var(--text-xs, 12px);
    color: var(--text-muted, #888);
  }
  .gpb-countdown-ring {
    position: relative;
    width: 24px;
    height: 24px;
    border-radius: 50%;
    background: conic-gradient(
      var(--color-primary, #2563eb) var(--pct, 0%),
      var(--bg-surface-2, #e2e8f0) var(--pct, 0%)
    );
    transition: --pct 0.9s linear;
  }
  .gpb-countdown-ring::after {
    content: '';
    position: absolute;
    inset: 4px;
    border-radius: 50%;
    background: var(--bg-card, #fff);
  }

  /* ── Spinner ── */
  .gpb-spin {
    animation: gpb-spin 0.8s linear infinite;
    flex-shrink: 0;
  }
  @keyframes gpb-spin { to { transform: rotate(360deg); } }
`

export type { GeoPermissionBannerProps }
