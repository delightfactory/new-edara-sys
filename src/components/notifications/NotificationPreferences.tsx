// src/components/notifications/NotificationPreferences.tsx
// ─────────────────────────────────────────────────────────────
// Notification preferences settings panel.
// Auto-saves with 800ms debounce. Shows "تم الحفظ" indicator.
// ─────────────────────────────────────────────────────────────

import { useEffect, useRef, useState } from 'react'
import { Check, Loader2, Monitor, Smartphone, Tablet, Trash2 } from 'lucide-react'
import {
  usePreferencesQuery,
  useUpdatePreferencesMutation,
  usePushDevicesQuery,
} from '@/hooks/useNotificationQueries'
import { usePushNotifications } from '@/hooks/usePushNotifications'
import { Skeleton } from '@/components/ui/Skeleton'
import type { NotificationCategory, NotificationPreferences, PushSubscriptionRecord } from '@/lib/notifications/types'

// ── Category labels ───────────────────────────────────────────
const CATEGORY_LABELS: Partial<Record<NotificationCategory, string>> = {
  hr_attendance:    'الحضور والانصراف',
  hr_leaves:        'الإجازات',
  hr_payroll:       'الرواتب',
  finance_expenses: 'المصروفات',
  finance_approvals:'الموافقات المالية',
  inventory:        'المخزون',
  sales:            'المبيعات',
  procurement:      'المشتريات',   // C-06: previously missing
  tasks:            'المهام',            // C-06: previously missing
  system:           'النظام',
  alerts:           'التنبيهات',
}

const PRIORITY_OPTIONS = [
  { value: 'low',      label: 'الكل (منخفض فأعلى)' },
  { value: 'medium',   label: 'متوسط فأعلى' },
  { value: 'high',     label: 'عالٍ فأعلى' },
  { value: 'critical', label: 'حرج فقط' },
]

// ── Toggle slide switch ───────────────────────────────────────
function Toggle({
  checked,
  onChange,
  id,
  disabled = false,
}: {
  checked: boolean
  onChange: (v: boolean) => void
  id: string
  disabled?: boolean
}) {
  return (
    <label className="pref-toggle" htmlFor={id} style={{ opacity: disabled ? 0.45 : 1 }}>
      <input
        id={id}
        type="checkbox"
        checked={checked}
        onChange={e => !disabled && onChange(e.target.checked)}
        disabled={disabled}
        className="pref-toggle-input"
        role="switch"
        aria-checked={checked}
      />
      <span className="pref-toggle-track" />
    </label>
  )
}

// ── DevicesList sub-component ─────────────────────────────────
function DeviceIcon({ deviceType }: { deviceType: string }) {
  const size = 18
  if (deviceType === 'mobile')  return <Smartphone size={size} />
  if (deviceType === 'tablet')  return <Tablet size={size} />
  return <Monitor size={size} />
}

function DevicesList({ unsubscribeFn, isUnsubscribing }: {
  unsubscribeFn: (endpoint: string) => Promise<void>
  isUnsubscribing: boolean
}) {
  const { data: devices, isLoading } = usePushDevicesQuery()

  if (isLoading) {
    return (
      <div style={{ padding: 'var(--space-3) var(--space-4)', display: 'flex', flexDirection: 'column', gap: 8 }}>
        <Skeleton height={44} />
        <Skeleton height={44} />
      </div>
    )
  }

  if (!devices || devices.length === 0) return null

  return (
    <div className="pref-devices">
      <span className="pref-categories-label" style={{ padding: 'var(--space-2) var(--space-4) var(--space-1)', display: 'block' }}>
        الأجهزة المسجلة
      </span>
      {(devices as PushSubscriptionRecord[]).map(device => (
        <div
          key={device.id}
          className={`pref-device-row${!device.isActive ? ' pref-device-inactive' : ''}`}
        >
          <span className="pref-device-icon">
            <DeviceIcon deviceType={device.deviceType ?? 'desktop'} />
          </span>
          <div className="pref-device-info">
            <div className="pref-device-name">
              {device.deviceName ?? device.browser ?? 'جهاز غير معروف'}
            </div>
            <div className="pref-device-meta">
              {device.isActive ? 'نشط' : 'غير نشط'}
              {device.lastPushAt && ` • آخر إشعار: ${new Date(device.lastPushAt).toLocaleDateString('ar')}`}
            </div>
          </div>
          <button
            className="btn btn-ghost btn-sm btn-icon"
            onClick={() => unsubscribeFn(device.endpoint)}
            disabled={isUnsubscribing}
            aria-label="إلغاء اشتراك هذا الجهاز"
            type="button"
          >
            {isUnsubscribing ? <Loader2 size={13} className="pref-spinner" /> : <Trash2 size={13} />}
          </button>
        </div>
      ))}
    </div>
  )
}

// ── Section wrapper ───────────────────────────────────────────
function PrefSection({
  title,
  children,
}: {
  title: string
  children: React.ReactNode
}) {
  return (
    <div className="pref-section">
      <h3 className="pref-section-title">{title}</h3>
      {children}
    </div>
  )
}

function PrefRow({
  label,
  description,
  children,
}: {
  label: string
  description?: string
  children: React.ReactNode
}) {
  return (
    <div className="pref-row">
      <div className="pref-row-text">
        <span className="pref-row-label">{label}</span>
        {description && <span className="pref-row-desc">{description}</span>}
      </div>
      <div className="pref-row-control">{children}</div>
    </div>
  )
}

// ── Push Permission Dialog (WCAG 2.4.3 compliant) ────────────
function PushPermissionDialog({
  onConfirm,
  onDismiss,
}: {
  onConfirm: () => void
  onDismiss: () => void
}) {
  const dialogRef = useRef<HTMLDivElement>(null)

  // Focus the dialog on mount + restore focus on unmount
  useEffect(() => {
    const previousFocus = document.activeElement as HTMLElement | null
    dialogRef.current?.focus()

    // Escape key handler
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault()
        onDismiss()
      }
      // Focus trap: keep Tab within dialog
      if (e.key === 'Tab' && dialogRef.current) {
        const focusable = dialogRef.current.querySelectorAll<HTMLElement>(
          'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
        )
        const first = focusable[0]
        const last  = focusable[focusable.length - 1]
        if (e.shiftKey) {
          if (document.activeElement === first) { e.preventDefault(); last.focus() }
        } else {
          if (document.activeElement === last)  { e.preventDefault(); first.focus() }
        }
      }
    }

    document.addEventListener('keydown', handleKeyDown)
    return () => {
      document.removeEventListener('keydown', handleKeyDown)
      previousFocus?.focus()
    }
  }, [onDismiss])

  return (
    <div className="push-prompt-overlay" role="alertdialog" aria-modal="true" aria-labelledby="push-prompt-title">
      <div className="push-prompt-dialog" ref={dialogRef} tabIndex={-1}>
        <div className="push-prompt-icon" aria-hidden="true">🔔</div>
        <h3 className="push-prompt-title" id="push-prompt-title">تفعيل الإشعارات الفورية</h3>
        <p className="push-prompt-body">
          ستحصل على إشعارات مباشرة حتى عند إغلاق التطبيق — للإجازات والرواتب والمهام العاجلة.
          <br />
          <strong>سيطلب المتصفح إذنك في الخطوة التالية.</strong>
        </p>
        <div className="push-prompt-actions">
          <button className="btn btn-primary" onClick={onConfirm} type="button">
            تفعيل الإشعارات
          </button>
          <button className="btn btn-ghost" onClick={onDismiss} type="button">
            ليس الآن
          </button>
        </div>
      </div>
    </div>
  )
}

// ── Main component ────────────────────────────────────────────

export default function NotificationPreferences() {
  const { data: prefs, isLoading } = usePreferencesQuery()
  const update    = useUpdatePreferencesMutation()
  const pushNotif = usePushNotifications()
  // Pre-permission dialog — explains push before requesting browser permission
  const [showPushPrompt, setShowPushPrompt] = useState(false)

  // Local shadow state for debounced save
  const [local, setLocal] = useState<Partial<NotificationPreferences>>({})
  const [savedAt, setSavedAt] = useState<number | null>(null)
  const debounceRef  = useRef<ReturnType<typeof setTimeout> | null>(null)
  // Accumulates ALL patches since last flush so debounce never loses earlier changes
  const pendingRef   = useRef<Partial<NotificationPreferences>>({})
  // Guards against re-hydrating local state after the user has made edits
  const hydratedRef  = useRef(false)

  // Hydrate local state once on first server load — hydratedRef prevents re-hydrating
  // after the user has made edits, and eliminates the 'local' exhaustive-deps warning.
  useEffect(() => {
    if (prefs && !hydratedRef.current) {
      hydratedRef.current = true
      setLocal(prefs)
    }
  }, [prefs])

  const patch = (partial: Partial<NotificationPreferences>) => {
    setLocal(prev => ({ ...prev, ...partial }))
    // Merge into pending so fast sequential patches are all sent together
    pendingRef.current = { ...pendingRef.current, ...partial }

    if (debounceRef.current) clearTimeout(debounceRef.current)
    debounceRef.current = setTimeout(async () => {
      const toSave = { ...pendingRef.current }
      pendingRef.current = {}        // clear before await so concurrent patches start fresh
      await update.mutateAsync(toSave)
      setSavedAt(Date.now())
      setTimeout(() => setSavedAt(null), 2000)
    }, 800)
  }

  useEffect(() => () => {
    if (debounceRef.current) clearTimeout(debounceRef.current)
  }, [])

  if (isLoading) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)', padding: 'var(--space-6)' }}>
        {[1, 2, 3].map(i => <Skeleton key={i} height={72} />)}
      </div>
    )
  }

  if (!prefs) return null

  // Merge prefs with local changes
  const p = { ...prefs, ...local } as NotificationPreferences

  return (
    <div className="pref-root">

      {/* Save indicator */}
      {savedAt && (
        <div className="pref-saved" role="status" aria-live="polite">
          <Check size={14} />
          <span>تم الحفظ</span>
        </div>
      )}
      {update.isPending && (
        <div className="pref-saving" role="status" aria-live="polite">
          <Loader2 size={14} className="pref-spinner" />
          <span>جارٍ الحفظ...</span>
        </div>
      )}

      {/* 1. In-app notifications */}
      <PrefSection title="إشعارات داخل التطبيق">
        <PrefRow
          label="تفعيل الإشعارات الداخلية"
          description="استقبال الإشعارات داخل التطبيق"
        >
          <Toggle
            id="pref-inapp"
            checked={p.inAppEnabled}
            onChange={v => patch({ inAppEnabled: v })}
          />
        </PrefRow>

        {p.inAppEnabled && (
          <>
            <PrefRow label="الأولوية الدنيا للعرض">
              <select
                className="form-select pref-select"
                value={p.minPriorityInApp}
                onChange={e => patch({ minPriorityInApp: e.target.value as NotificationPreferences['minPriorityInApp'] })}
                aria-label="الأولوية الدنيا للإشعارات الداخلية"
              >
                {PRIORITY_OPTIONS.map(opt => (
                  <option key={opt.value} value={opt.value}>{opt.label}</option>
                ))}
              </select>
            </PrefRow>

            <div className="pref-categories">
              <div className="pref-categories-header">
                <span className="pref-categories-label">إشعارات حسب الفئة</span>
                <div className="pref-categories-channels">
                  <span className="pref-channel-label">داخل التطبيق</span>
                  <span className="pref-channel-label">Push</span>
                </div>
              </div>
              {(Object.keys(CATEGORY_LABELS) as NotificationCategory[]).map(cat => {
                const catPref = p.categoryPreferences?.[cat]
                const inAppEnabled = catPref?.inApp ?? true
                const pushEnabled  = catPref?.push  ?? true
                return (
                  <div key={cat} className="pref-cat-row">
                    <span className="pref-cat-name">{CATEGORY_LABELS[cat] ?? cat}</span>
                    <div className="pref-cat-toggles">
                      <Toggle
                        id={`pref-cat-inapp-${cat}`}
                        checked={inAppEnabled}
                        onChange={v => patch({
                          categoryPreferences: {
                            ...p.categoryPreferences,
                            [cat]: { ...catPref, inApp: v },
                          },
                        })}
                      />
                      <Toggle
                        id={`pref-cat-push-${cat}`}
                        checked={pushEnabled}
                        disabled={!p.pushEnabled}
                        onChange={v => patch({
                          categoryPreferences: {
                            ...p.categoryPreferences,
                            [cat]: { ...catPref, push: v },
                          },
                        })}
                      />
                    </div>
                  </div>
                )
              })}
            </div>
          </>
        )}
      </PrefSection>


      {/* 2. Push notifications */}
      <PrefSection title="إشعارات Push">

        {/* Pre-permission explanation dialog */}
        {showPushPrompt && (
          <PushPermissionDialog
            onConfirm={() => {
              setShowPushPrompt(false)
              pushNotif.requestAndSubscribe()
            }}
            onDismiss={() => setShowPushPrompt(false)}
          />
        )}

        {/* Unsupported banner */}
        {pushNotif.permission === 'unsupported' && (
          <div className="pref-push-info pref-push-warning">
            ⚠️ متصفحك لا يدعم Push Notifications — جرّب Chrome أو Edge أو Firefox
          </div>
        )}

        {/* Denied banner with step-by-step instructions */}
        {pushNotif.permission === 'denied' && (
          <div className="pref-push-info pref-push-denied">
            <strong>🚫 تم حجب إذن الإشعارات</strong><br />
            لإعادة التفعيل:
            <ol className="push-denied-steps">
              <li>اضغط على أيقونة القفل 🔒 أو ⓘ بجانب عنوان الصفحة</li>
              <li>ابحث عن «إشعارات» أو Notifications</li>
              <li>غيّر الحالة إلى «سماح» أو Allow ثم أعد تحميل الصفحة</li>
            </ol>
          </div>
        )}

        {/* Main subscribe / unsubscribe row */}
        <PrefRow
          label="تفعيل إشعارات Push"
          description={
            pushNotif.permission === 'granted' && pushNotif.currentSubscription
              ? '✅ مفعّل على هذا الجهاز'
              : pushNotif.permission === 'denied'
              ? 'محجوب — انظر التعليمات أعلاه'
              : 'استقبل الإشعارات حتى عند إغلاق التطبيق'
          }
        >
          {pushNotif.permission === 'granted' && pushNotif.currentSubscription ? (
            <button
              className="btn btn-sm"
              style={{ background: 'var(--danger-bg, #fee2e2)', color: 'var(--danger, #dc2626)', border: '1px solid var(--danger, #dc2626)' }}
              onClick={() => pushNotif.unsubscribe(pushNotif.currentSubscription!.endpoint)}
              disabled={pushNotif.isUnsubscribing}
              type="button"
            >
              {pushNotif.isUnsubscribing && <Loader2 size={14} className="pref-spinner" />}
              إلغاء الاشتراك
            </button>
          ) : pushNotif.permission !== 'unsupported' && pushNotif.permission !== 'denied' ? (
            <button
              className="btn btn-primary btn-sm"
              onClick={() => {
                // Show pre-permission dialog if not yet asked
                if (Notification.permission === 'default') {
                  setShowPushPrompt(true)
                } else {
                  // Already granted but no subscription — go directly
                  pushNotif.requestAndSubscribe()
                }
              }}
              disabled={pushNotif.isSubscribing || pushNotif.permission === 'loading'}
              type="button"
            >
              {pushNotif.isSubscribing && <Loader2 size={14} className="pref-spinner" />}
              تفعيل 🔔
            </button>
          ) : null}
        </PrefRow>

        {/* Subscribe error */}
        {pushNotif.error && (
          <div className="pref-push-info pref-push-error">{pushNotif.error}</div>
        )}

        {/* Registered devices list */}
        {pushNotif.permission === 'granted' && (
          <DevicesList
            unsubscribeFn={pushNotif.unsubscribe}
            isUnsubscribing={pushNotif.isUnsubscribing}
          />
        )}

      </PrefSection>

      {/* 3. Quiet hours */}
      <PrefSection title="وقت الهدوء">
        <PrefRow
          label="تفعيل وقت الهدوء"
          description="إيقاف الإشعارات خلال ساعات الراحة"
        >
          <Toggle
            id="pref-quiet"
            checked={p.quietHoursEnabled}
            onChange={v => patch({ quietHoursEnabled: v })}
          />
        </PrefRow>

        {p.quietHoursEnabled && (
          <>
            <PrefRow label="من الساعة">
              <input
                type="time"
                className="form-input pref-time"
                value={p.quietStart}
                onChange={e => patch({ quietStart: e.target.value })}
                aria-label="بداية وقت الهدوء"
              />
            </PrefRow>
            <PrefRow label="حتى الساعة">
              <input
                type="time"
                className="form-input pref-time"
                value={p.quietEnd}
                onChange={e => patch({ quietEnd: e.target.value })}
                aria-label="نهاية وقت الهدوء"
              />
            </PrefRow>
            <PrefRow label="المنطقة الزمنية">
              <span className="pref-readonly">{p.timezone}</span>
            </PrefRow>
          </>
        )}
      </PrefSection>

      {/* 4. Digest Mode — C-05: previously dead asset, now wired to UI */}
      <PrefSection title="وضع التجميع">
        <PrefRow
          label="تجميع الإشعارات"
          description="استقبل ملخصاً دورياً بدلاً من إشعارات فردية"
        >
          <Toggle
            id="pref-digest"
            checked={p.digestModeEnabled}
            onChange={v => patch({ digestModeEnabled: v })}
          />
        </PrefRow>

        {p.digestModeEnabled && (
          <PrefRow label="تكرار الملخص" description="كم مرة تريد استقبال الملخص">
            <select
              className="form-select pref-select"
              value={p.digestFrequency}
              onChange={e => patch({ digestFrequency: e.target.value as 'realtime' | 'hourly' | 'daily' })}
              aria-label="تكرار الملخص"
            >
              <option value="realtime">فوري (بدون تجميع)</option>
              <option value="hourly">كل ساعة</option>
              <option value="daily">يومياً</option>
            </select>
          </PrefRow>
        )}
      </PrefSection>

      <style>{`
        .pref-root {
          display: flex;
          flex-direction: column;
          gap: var(--space-6);
          max-width: 560px;
          position: relative;
        }

        /* Save indicator */
        .pref-saved,
        .pref-saving {
          position: fixed;
          top: var(--space-4);
          inset-inline-start: var(--space-4);
          display: flex;
          align-items: center;
          gap: var(--space-2);
          background: var(--bg-surface);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-full);
          padding: var(--space-2) var(--space-3);
          font-size: var(--text-xs);
          font-weight: 600;
          box-shadow: var(--shadow-sm);
          z-index: 10;
          animation: pref-fade-in 0.2s ease;
        }
        .pref-saved { color: var(--success, #16a34a); }
        .pref-saving { color: var(--text-secondary); }
        @keyframes pref-fade-in {
          from { opacity: 0; transform: translateY(-4px); }
          to   { opacity: 1; transform: translateY(0); }
        }
        @keyframes pref-spin {
          to { transform: rotate(360deg); }
        }
        .pref-spinner { animation: pref-spin 1s linear infinite; }

        /* Section */
        .pref-section {
          background: var(--bg-surface);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-lg);
          overflow: hidden;
        }
        .pref-section-title {
          font-size: var(--text-sm);
          font-weight: 700;
          color: var(--text-primary);
          padding: var(--space-4);
          margin: 0;
          border-bottom: 1px solid var(--border-primary);
          background: var(--bg-app);
        }

        /* Row */
        .pref-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--space-4);
          padding: var(--space-3) var(--space-4);
          border-bottom: 1px solid var(--border-primary);
        }
        .pref-row:last-child { border-bottom: none; }
        .pref-row-text {
          display: flex;
          flex-direction: column;
          gap: 3px;
          flex: 1;
          min-width: 0;
        }
        .pref-row-label {
          font-size: var(--text-sm);
          font-weight: 500;
          color: var(--text-primary);
        }
        .pref-row-desc {
          font-size: var(--text-xs);
          color: var(--text-muted);
        }
        .pref-row-control {
          flex-shrink: 0;
        }

        /* Categories indent */
        .pref-categories {
          padding: var(--space-2) var(--space-4) var(--space-4);
          display: flex;
          flex-direction: column;
          gap: var(--space-1);
          border-top: 1px solid var(--border-primary);
          background: var(--bg-app);
        }
        .pref-categories-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: var(--space-2) var(--space-3) var(--space-1);
        }
        .pref-categories-label {
          font-size: var(--text-xs);
          font-weight: 700;
          color: var(--text-muted);
          text-transform: uppercase;
          letter-spacing: 0.5px;
        }
        .pref-categories-channels {
          display: flex;
          gap: var(--space-5);
        }
        .pref-channel-label {
          font-size: var(--text-xs);
          color: var(--text-muted);
          font-weight: 600;
          min-width: 40px;
          text-align: center;
        }
        /* Per-category dual-toggle row */
        .pref-cat-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: var(--space-2) var(--space-3);
          background: var(--bg-surface);
          border-radius: var(--radius-md);
          margin-bottom: 2px;
        }
        .pref-cat-name {
          font-size: var(--text-sm);
          color: var(--text-secondary);
          flex: 1;
        }
        .pref-cat-toggles {
          display: flex;
          gap: var(--space-5);
          align-items: center;
        }
        .pref-cat-toggles .pref-toggle {
          margin: 0;
        }

        /* Toggle switch — direction-safe implementation
         * The track uses direction:ltr internally so that left/right are
         * always physical (not logical). This avoids the RTL flip where
         * inset-inline-start:3px would place the knob at the visual RIGHT
         * in RTL, making OFF look like ON.
         * OFF state:  knob at physical LEFT  (translateX 0)
         * ON  state:  knob at physical RIGHT (translateX +18px)
         * The label wrapper still participates in the RTL document flow.  */
        .pref-toggle {
          cursor: pointer;
          display: inline-flex;
          align-items: center;
          user-select: none;
          flex-shrink: 0;
        }
        .pref-toggle-input {
          position: absolute;
          opacity: 0;
          width: 0;
          height: 0;
          pointer-events: none;
        }
        .pref-toggle-track {
          position: relative;
          width: 44px;
          height: 24px;
          border-radius: 12px;
          background: var(--border-secondary, #cbd5e1);
          transition: background 0.25s ease;
          direction: ltr; /* force physical left/right inside the track */
          flex-shrink: 0;
        }
        .pref-toggle-track::after {
          content: '';
          position: absolute;
          top: 4px;
          left: 4px;           /* physical left — OFF position */
          width: 16px;
          height: 16px;
          border-radius: 50%;
          background: #fff;
          box-shadow: 0 1px 4px rgba(0,0,0,0.25);
          transition: transform 0.22s cubic-bezier(0.34, 1.56, 0.64, 1);
        }
        .pref-toggle-input:checked + .pref-toggle-track {
          background: var(--primary, #2563eb);
        }
        .pref-toggle-input:checked + .pref-toggle-track::after {
          transform: translateX(20px); /* always moves RIGHT (physical) to ON */
        }

        /* Other controls */
        .pref-select,
        .pref-time {
          min-width: 140px;
        }
        .pref-readonly {
          font-size: var(--text-sm);
          color: var(--text-secondary);
        }

        /* Push info banners */
        .pref-push-info {
          padding: var(--space-3) var(--space-4);
          font-size: var(--text-sm);
          border-radius: var(--radius-md);
          margin: var(--space-2) var(--space-4);
          line-height: 1.6;
        }
        .pref-push-warning { background: var(--warning-bg, #fef3c7); color: var(--warning, #d97706); }
        .pref-push-error   { background: var(--danger-bg, #fee2e2);  color: var(--danger, #dc2626); }
        .pref-push-denied  {
          background: var(--danger-bg, #fee2e2);
          color: var(--danger, #dc2626);
        }
        .push-denied-steps {
          margin: var(--space-2) 0 0 var(--space-4);
          padding: 0;
          display: flex;
          flex-direction: column;
          gap: 2px;
          font-size: var(--text-xs);
        }

        /* Pre-permission dialog overlay */
        .push-prompt-overlay {
          position: fixed;
          inset: 0;
          z-index: 9999;
          background: rgba(0,0,0,0.55);
          backdrop-filter: blur(3px);
          display: flex;
          align-items: center;
          justify-content: center;
          padding: var(--space-4);
          animation: fade-in 0.15s ease;
        }
        @keyframes fade-in { from { opacity: 0 } to { opacity: 1 } }
        .push-prompt-dialog {
          background: var(--bg-surface);
          border-radius: var(--radius-xl);
          padding: var(--space-6);
          max-width: 360px;
          width: 100%;
          box-shadow: var(--shadow-lg);
          text-align: center;
          animation: slide-up 0.2s cubic-bezier(0.16,1,0.3,1);
        }
        @keyframes slide-up { from { transform: translateY(20px); opacity: 0 } to { transform: translateY(0); opacity: 1 } }
        .push-prompt-icon { font-size: 2.5rem; margin-bottom: var(--space-3); }
        .push-prompt-title {
          font-size: var(--text-lg);
          font-weight: 700;
          color: var(--text-primary);
          margin: 0 0 var(--space-3);
        }
        .push-prompt-body {
          font-size: var(--text-sm);
          color: var(--text-secondary);
          line-height: 1.7;
          margin: 0 0 var(--space-5);
        }
        .push-prompt-actions {
          display: flex;
          flex-direction: column;
          gap: var(--space-2);
        }

        /* Devices list */
        .pref-devices {
          border-top: 1px solid var(--border-primary);
          background: var(--bg-app);
          display: flex;
          flex-direction: column;
        }
        .pref-device-row {
          display: flex;
          align-items: center;
          gap: var(--space-3);
          padding: var(--space-2) var(--space-4);
          border-bottom: 1px solid var(--border-primary);
        }
        .pref-device-row:last-child { border-bottom: none; }
        .pref-device-icon { color: var(--text-muted); flex-shrink: 0; }
        .pref-device-info { flex: 1; min-width: 0; }
        .pref-device-name { font-size: var(--text-sm); font-weight: 500; color: var(--text-primary); }
        .pref-device-meta { font-size: var(--text-xs); color: var(--text-muted); }
        .pref-device-inactive { opacity: 0.5; }

        /* Coming soon — kept for other future features */
        .pref-coming-soon {
          padding: var(--space-3) var(--space-4);
          font-size: var(--text-sm);
          color: var(--text-muted);
          background: var(--bg-app);
        }
      `}</style>
    </div>
  )
}
