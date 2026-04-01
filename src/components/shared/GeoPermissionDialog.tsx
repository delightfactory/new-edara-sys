/**
 * GeoPermissionDialog — Modal احترافي يُعرض قبل طلب صلاحية الموقع
 *
 * Best Practice: "Explain → Ask → Guide"
 * يشرح للمستخدم السبب الحقيقي قبل أن يرى نافذة المتصفح الرسمية
 * مما يزيد معدل القبول بشكل كبير.
 */
import { useEffect, useRef } from 'react'
import { MapPin, Shield, Clock, Lock } from 'lucide-react'

interface GeoPermissionDialogProps {
  /** هل الـ Dialog مفتوح */
  open: boolean
  /** السياق: لماذا نحتاج الموقع */
  context: 'attendance' | 'visit' | 'general'
  /** عند الضغط على "السماح" */
  onAllow: () => void
  /** عند الضغط على "لاحقاً" أو الإغلاق */
  onDismiss: () => void
}

const CONTEXT_CONFIG = {
  attendance: {
    title: 'تسجيل الحضور يحتاج موقعك',
    subtitle: 'للتحقق من تواجدك في مكان العمل',
    reasons: [
      { icon: '🏢', text: 'التحقق من تواجدك في مكان العمل' },
      { icon: '✅', text: 'تسجيل حضورك وانصرافك بدقة' },
      { icon: '🔒', text: 'موقعك لا يُتتبع خلال اليوم' },
    ],
    allowLabel: '📍 السماح وتسجيل الحضور',
  },
  visit: {
    title: 'تسجيل الزيارة يحتاج موقعك',
    subtitle: 'للتحقق من وصولك لموقع العميل',
    reasons: [
      { icon: '📍', text: 'التحقق من وصولك لموقع العميل' },
      { icon: '📊', text: 'تسجيل بيانات الزيارة الميدانية' },
      { icon: '🔒', text: 'موقعك يُحفظ فقط عند بدء وإنهاء الزيارة' },
    ],
    allowLabel: '📍 السماح وبدء الزيارة',
  },
  general: {
    title: 'نحتاج إذن الوصول لموقعك',
    subtitle: 'لإتمام هذه العملية بدقة',
    reasons: [
      { icon: '📍', text: 'تسجيل الموقع الجغرافي بدقة' },
      { icon: '🔒', text: 'بياناتك آمنة ومحمية' },
      { icon: '✅', text: 'يمكنك سحب الإذن في أي وقت' },
    ],
    allowLabel: '📍 السماح بتحديد الموقع',
  },
}

export default function GeoPermissionDialog({
  open,
  context,
  onAllow,
  onDismiss,
}: GeoPermissionDialogProps) {
  const dialogRef = useRef<HTMLDialogElement>(null)
  const cfg = CONTEXT_CONFIG[context]

  useEffect(() => {
    const el = dialogRef.current
    if (!el) return
    if (open) {
      el.showModal?.()
    } else {
      el.close?.()
    }
  }, [open])

  useEffect(() => {
    const el = dialogRef.current
    if (!el) return
    const handleCancel = (e: Event) => {
      e.preventDefault()
      onDismiss()
    }
    el.addEventListener('cancel', handleCancel)
    return () => el.removeEventListener('cancel', handleCancel)
  }, [onDismiss])

  if (!open) return null

  return (
    <dialog
      ref={dialogRef}
      id="geo-permission-dialog"
      className="gpd-dialog"
      onClick={(e) => {
        // إغلاق عند النقر على الخلفية
        if (e.target === dialogRef.current) onDismiss()
      }}
      aria-labelledby="gpd-title"
      aria-describedby="gpd-desc"
    >
      <div className="gpd-content">

        {/* ── Icon ── */}
        <div className="gpd-icon-wrap">
          <div className="gpd-icon-ring">
            <div className="gpd-icon-ring-pulse" />
            <MapPin size={28} strokeWidth={2.5} />
          </div>
        </div>

        {/* ── Title ── */}
        <h2 id="gpd-title" className="gpd-title">{cfg.title}</h2>
        <p id="gpd-desc" className="gpd-subtitle">{cfg.subtitle}</p>

        {/* ── Reasons list ── */}
        <div className="gpd-reasons" aria-label="أسباب طلب الموقع">
          {cfg.reasons.map((r, i) => (
            <div key={i} className="gpd-reason">
              <span className="gpd-reason-icon" aria-hidden="true">{r.icon}</span>
              <span className="gpd-reason-text">{r.text}</span>
            </div>
          ))}
        </div>

        {/* ── Privacy note ── */}
        <div className="gpd-privacy">
          <Lock size={11} aria-hidden="true" />
          <span>هذا الإذن لا يمنح التطبيق تتبع موقعك في الخلفية</span>
        </div>

        {/* ── Actions ── */}
        <div className="gpd-actions">
          <button
            id="gpd-btn-allow"
            type="button"
            className="gpd-btn gpd-btn--primary"
            onClick={onAllow}
            autoFocus
          >
            {cfg.allowLabel}
          </button>
          <button
            id="gpd-btn-dismiss"
            type="button"
            className="gpd-btn gpd-btn--secondary"
            onClick={onDismiss}
          >
            لاحقاً
          </button>
        </div>

        {/* ── Compliance badges ── */}
        <div className="gpd-badges">
          <span className="gpd-badge"><Shield size={10} /> محمي</span>
          <span className="gpd-badge"><Clock size={10} /> عند الطلب فقط</span>
        </div>

      </div>

      <style>{`
        .gpd-dialog {
          position: fixed;
          inset: 0;
          z-index: 9000;
          border: none;
          background: transparent;
          max-width: 100vw;
          max-height: 100vh;
          width: 100%;
          height: 100%;
          display: flex;
          align-items: flex-end;
          justify-content: center;
          padding: 0;
          margin: 0;
        }
        .gpd-dialog::backdrop {
          background: rgba(0, 0, 0, 0.55);
          backdrop-filter: blur(4px);
          animation: gpd-fade-in 0.2s ease;
        }
        @media (min-width: 480px) {
          .gpd-dialog {
            align-items: center;
          }
        }
        .gpd-content {
          background: var(--bg-card, #fff);
          border-radius: 24px 24px 0 0;
          padding: var(--space-8, 32px) var(--space-6, 24px) calc(var(--space-8, 32px) + env(safe-area-inset-bottom, 0px));
          max-width: 440px;
          width: 100%;
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: var(--space-4, 16px);
          animation: gpd-slide-up 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);
          box-shadow: 0 -4px 40px rgba(0,0,0,0.15);
        }
        @media (min-width: 480px) {
          .gpd-content {
            border-radius: 24px;
            padding: var(--space-8, 32px) var(--space-6, 24px);
            animation: gpd-pop 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);
          }
        }

        /* Icon */
        .gpd-icon-wrap {
          position: relative;
          display: flex;
          align-items: center;
          justify-content: center;
          margin-bottom: var(--space-2, 8px);
        }
        .gpd-icon-ring {
          position: relative;
          width: 72px;
          height: 72px;
          border-radius: 50%;
          background: color-mix(in srgb, var(--color-primary, #2563eb) 12%, transparent);
          display: flex;
          align-items: center;
          justify-content: center;
          color: var(--color-primary, #2563eb);
          animation: gpd-icon-pulse 3s ease-in-out infinite;
        }
        .gpd-icon-ring-pulse {
          position: absolute;
          inset: -8px;
          border-radius: 50%;
          border: 2px solid color-mix(in srgb, var(--color-primary, #2563eb) 25%, transparent);
          animation: gpd-ring-expand 2.5s ease-out infinite;
        }

        /* Text */
        .gpd-title {
          font-size: var(--text-xl, 20px);
          font-weight: 800;
          color: var(--text-primary, #0f172a);
          text-align: center;
          margin: 0;
          line-height: 1.3;
          letter-spacing: -0.02em;
        }
        .gpd-subtitle {
          font-size: var(--text-sm, 14px);
          color: var(--text-muted, #64748b);
          text-align: center;
          margin: 0;
          margin-top: -var(--space-2, 8px);
        }

        /* Reasons */
        .gpd-reasons {
          width: 100%;
          display: flex;
          flex-direction: column;
          gap: var(--space-2, 8px);
          background: var(--bg-surface, #f8fafc);
          border: 1px solid var(--border-color, #e2e8f0);
          border-radius: var(--radius-xl, 16px);
          padding: var(--space-4, 16px);
        }
        .gpd-reason {
          display: flex;
          align-items: center;
          gap: var(--space-3, 12px);
          font-size: var(--text-sm, 14px);
          color: var(--text-secondary, #334155);
        }
        .gpd-reason-icon {
          font-size: 18px;
          flex-shrink: 0;
          width: 28px;
          text-align: center;
        }
        .gpd-reason-text { font-weight: 500; }

        /* Privacy */
        .gpd-privacy {
          display: flex;
          align-items: center;
          gap: 6px;
          font-size: 11px;
          color: var(--text-muted, #64748b);
          text-align: center;
          line-height: 1.5;
          padding: 0 var(--space-2);
        }
        .gpd-privacy svg { flex-shrink: 0; color: var(--color-success, #16a34a); }

        /* Actions */
        .gpd-actions {
          width: 100%;
          display: flex;
          flex-direction: column;
          gap: var(--space-2, 8px);
          margin-top: var(--space-2, 8px);
        }
        .gpd-btn {
          width: 100%;
          padding: 14px var(--space-4, 16px);
          border-radius: var(--radius-xl, 16px);
          font-size: var(--text-base, 15px);
          font-weight: 700;
          font-family: var(--font-sans, inherit);
          cursor: pointer;
          border: none;
          transition: all 0.15s ease;
          min-height: 52px;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .gpd-btn--primary {
          background: var(--color-primary, #2563eb);
          color: #fff;
          box-shadow: 0 4px 12px color-mix(in srgb, var(--color-primary, #2563eb) 35%, transparent);
        }
        .gpd-btn--primary:hover { opacity: 0.92; transform: translateY(-1px); }
        .gpd-btn--primary:active { transform: scale(0.98); }
        .gpd-btn--secondary {
          background: var(--bg-surface-2, #f1f5f9);
          color: var(--text-muted, #64748b);
          font-weight: 600;
        }
        .gpd-btn--secondary:hover { background: var(--bg-hover, #e2e8f0); }

        /* Badges */
        .gpd-badges {
          display: flex;
          gap: var(--space-2, 8px);
          justify-content: center;
          flex-wrap: wrap;
        }
        .gpd-badge {
          display: inline-flex;
          align-items: center;
          gap: 4px;
          padding: 3px 10px;
          border-radius: 99px;
          font-size: 11px;
          font-weight: 600;
          background: color-mix(in srgb, var(--color-success, #16a34a) 10%, transparent);
          color: var(--color-success, #16a34a);
          border: 1px solid color-mix(in srgb, var(--color-success, #16a34a) 20%, transparent);
        }

        /* Animations */
        @keyframes gpd-fade-in {
          from { opacity: 0; }
          to   { opacity: 1; }
        }
        @keyframes gpd-slide-up {
          from { transform: translateY(100%); opacity: 0; }
          to   { transform: translateY(0);    opacity: 1; }
        }
        @keyframes gpd-pop {
          from { transform: scale(0.85); opacity: 0; }
          to   { transform: scale(1);    opacity: 1; }
        }
        @keyframes gpd-icon-pulse {
          0%, 100% { box-shadow: 0 0 0 0 color-mix(in srgb, var(--color-primary, #2563eb) 20%, transparent); }
          50%       { box-shadow: 0 0 0 12px color-mix(in srgb, var(--color-primary, #2563eb) 0%, transparent); }
        }
        @keyframes gpd-ring-expand {
          0%   { transform: scale(1);    opacity: 0.8; }
          100% { transform: scale(1.4); opacity: 0;   }
        }
      `}</style>
    </dialog>
  )
}

export type { GeoPermissionDialogProps }
