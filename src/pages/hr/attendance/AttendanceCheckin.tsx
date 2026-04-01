import { useState, useCallback, useEffect, useRef } from 'react'
import {
  MapPin, CheckCircle, XCircle, AlertCircle,
  LogIn, LogOut, Wifi, WifiOff, Info, UserX,
  Clock, Timer,
} from 'lucide-react'
import { useCurrentEmployee } from '@/hooks/useQueryHooks'
import { useQuery } from '@tanstack/react-query'
import {
  recordAttendanceGPS,
  getAttendanceDays,
  type AttendanceGPSResult,
} from '@/lib/services/hr'
import type { HRAttendanceDay } from '@/lib/types/hr'
import Spinner from '@/components/ui/Spinner'
import { toast } from 'sonner'
import useGeoPermission from '@/hooks/useGeoPermission'
import GeoPermissionDialog from '@/components/shared/GeoPermissionDialog'
import GeoPermissionBanner from '@/components/shared/GeoPermissionBanner'

// ─────────────────────────────────────────────────────────────
// TYPES
// ─────────────────────────────────────────────────────────────
type FlowState =
  | 'idle'        // انتظار المستخدم
  | 'locating'    // جلب GPS
  | 'submitting'  // التسجيل في DB عبر RPC
  | 'success'     // نجاح (auto-reset بعد 2.5s)
  | 'error'       // خطأ قابل للإعادة

type ActionType = 'check_in' | 'check_out'

interface GeoPos { latitude: number; longitude: number; accuracy: number }

const SUCCESS_RESET_MS = 2500

// ─────────────────────────────────────────────────────────────
// LIVE CLOCK — عرض الوقت بدقة الثانية
// ─────────────────────────────────────────────────────────────
function LiveClock() {
  const [now, setNow] = useState(() => new Date())
  const rafRef = useRef<number>(0)
  useEffect(() => {
    let last = -1
    const tick = () => {
      const t = new Date()
      if (t.getSeconds() !== last) { last = t.getSeconds(); setNow(new Date(t)) }
      rafRef.current = requestAnimationFrame(tick)
    }
    rafRef.current = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(rafRef.current)
  }, [])

  return (
    <div style={{ textAlign: 'center' }}>
      <div
        dir="ltr"
        style={{
          fontVariantNumeric: 'tabular-nums',
          fontSize: 'clamp(3rem, 18vw, 5.5rem)',
          fontWeight: 800,
          letterSpacing: '-0.04em',
          lineHeight: 1,
          background: 'linear-gradient(135deg, var(--text-primary) 0%, color-mix(in srgb, var(--color-primary) 60%, var(--text-primary)) 100%)',
          WebkitBackgroundClip: 'text',
          WebkitTextFillColor: 'transparent',
          backgroundClip: 'text',
        }}
      >
        {now.toLocaleTimeString('ar-EG-u-nu-latn', { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false })}
      </div>
      <div style={{
        fontSize: 'var(--text-sm)', color: 'var(--text-muted)',
        marginTop: 'var(--space-2)', fontWeight: 500,
      }}>
        {now.toLocaleDateString('ar-EG-u-nu-latn', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}
      </div>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────
// ELAPSED TIMER — يعدّ الوقت المنقضي بدقة الدقيقة
// ─────────────────────────────────────────────────────────────
function ElapsedTimer({ since }: { since: string }) {
  const [, forceUpdate] = useState(0)
  useEffect(() => {
    const id = setInterval(() => forceUpdate(x => x + 1), 30_000)
    return () => clearInterval(id)
  }, [])

  const diffMs = Date.now() - new Date(since).getTime()
  const h = Math.floor(diffMs / 3_600_000)
  const m = Math.floor((diffMs % 3_600_000) / 60_000)
  return (
    <span dir="ltr" style={{ fontVariantNumeric: 'tabular-nums' }}>
      {String(h).padStart(2, '0')}:{String(m).padStart(2, '0')}
    </span>
  )
}

// ─────────────────────────────────────────────────────────────
// TODAY STATUS — بطاقة الحالة الذكية
// ─────────────────────────────────────────────────────────────
function TodayStatus({
  record, isLoading,
}: { record: HRAttendanceDay | null; isLoading: boolean }) {
  const fmt = (t: string | null) =>
    t ? new Date(t).toLocaleTimeString('ar-EG-u-nu-latn', { hour: '2-digit', minute: '2-digit', hour12: false }) : '—'

  if (isLoading) return (
    <div className="ci-status-pill ci-status-pill--loading">
      <div className="ci-dot ci-dot--pulse" />
      <span>جارٍ التحقق من الحالة...</span>
    </div>
  )

  if (!record) return (
    <div className="ci-status-pill ci-status-pill--idle">
      <Clock size={14} />
      <span>لم تبدأ دوامك بعد</span>
    </div>
  )

  const out = !!record.punch_out_time
  return (
    <div className={`ci-status-pill ${out ? 'ci-status-pill--done' : 'ci-status-pill--active'}`}>
      {!out && <div className="ci-dot ci-dot--green" />}
      {out
        ? <><CheckCircle size={14} /> <span>انتهى دوامك</span></>
        : <><span>في الدوام منذ</span></>
      }
      <div className="ci-status-times">
        {!out && (
          <span className="ci-time-badge ci-time-badge--elapsed">
            <Timer size={10} />
            <ElapsedTimer since={record.punch_in_time!} />
          </span>
        )}
        <span className="ci-time-badge">
          <LogIn size={10} /> {fmt(record.punch_in_time)}
        </span>
        {out && (
          <span className="ci-time-badge">
            <LogOut size={10} /> {fmt(record.punch_out_time)}
          </span>
        )}
      </div>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────
// SMART ACTION BUTTON — زر واحد يتغير بالسياق
// ─────────────────────────────────────────────────────────────
interface ActionBtnProps {
  record: HRAttendanceDay | null
  flowState: FlowState
  onAction: (type: ActionType) => void
}
function SmartActionButton({ record, flowState, onAction }: ActionBtnProps) {
  const isProcessing = ['locating', 'validating', 'submitting'].includes(flowState)

  // الحالة المنطقية الصحيحة
  const hasCheckIn  = !!record?.punch_in_time
  const hasCheckOut = !!record?.punch_out_time
  const isDayDone   = hasCheckIn && hasCheckOut

  if (isDayDone) return null // لا حاجة لأي زر

  const isCheckin = !hasCheckIn
  const color     = isCheckin ? 'var(--color-success)' : 'var(--color-danger)'
  const label     = isCheckin ? 'بدء الدوام' : 'إنهاء الدوام'
  const Icon      = isCheckin ? LogIn : LogOut

  return (
    <button
      id={isCheckin ? 'btn-check-in' : 'btn-check-out'}
      type="button"
      disabled={isProcessing || flowState === 'success'}
      onClick={() => onAction(isCheckin ? 'check_in' : 'check_out')}
      className="ci-action-btn"
      style={{ '--action-color': color } as React.CSSProperties}
      aria-label={label}
    >
      <span className="ci-action-ring">
        <span className="ci-action-ring-pulse" />
        <span className="ci-action-icon-wrap">
          {isProcessing
            ? <div className="ci-spinner" />
            : <Icon size={36} strokeWidth={2.5} />
          }
        </span>
      </span>
      <span className="ci-action-label">{isProcessing ? 'جارٍ التسجيل...' : label}</span>
    </button>
  )
}

// ─────────────────────────────────────────────────────────────
// PROGRESS STEPS — خطوات التسجيل
// ─────────────────────────────────────────────────────────────
// خطوتان فقط بعد إلغاء validating المنفصلة
const STEPS: { id: FlowState; label: string }[] = [
  { id: 'locating',   label: 'تحديد الموقع GPS' },
  { id: 'submitting', label: 'تسجيل الحضور' },
]
function ProgressSteps({ flowState, position }: { flowState: FlowState; position: GeoPos | null }) {
  const cur = STEPS.findIndex(s => s.id === flowState)
  return (
    <div className="ci-progress">
      {STEPS.map((step, i) => {
        const done   = i < cur
        const active = i === cur
        return (
          <div key={step.id} className={`ci-step ${done ? 'ci-step--done' : active ? 'ci-step--active' : 'ci-step--pending'}`}>
            <div className="ci-step-dot">
              {done
                ? <CheckCircle size={12} />
                : active
                ? <div className="ci-spinner ci-spinner--sm" />
                : <span>{i + 1}</span>
              }
            </div>
            <div className="ci-step-info">
              <span className="ci-step-label">{step.label}</span>
              {done && step.id === 'locating' && position && (
                <span className="ci-step-sub" dir="ltr">±{Math.round(position.accuracy)}م</span>
              )}
            </div>
            {i < STEPS.length - 1 && <div className="ci-step-line" />}
          </div>
        )
      })}
    </div>
  )
}

// ─────────────────────────────────────────────────────────────
// MAIN COMPONENT
// ─────────────────────────────────────────────────────────────
export default function AttendanceCheckin() {
  const { data: employee, isLoading: empLoading } = useCurrentEmployee()

  // Geolocation hook — إدارة احترافية للصلاحيات
  const geo = useGeoPermission()

  // الحالة الداخلية
  const [flowState,      setFlowState]      = useState<FlowState>('idle')
  const [actionType,     setActionType]     = useState<ActionType>('check_in')
  const [pendingAction,  setPendingAction]  = useState<ActionType | null>(null) // الإجراء المعلق حتى إذن GPS
  const [showGeoDialog,  setShowGeoDialog]  = useState(false)  // dialog التوضيحي قبل الطلب
  const [position,       setPosition]       = useState<GeoPos | null>(null)
  const [rpcResult,      setRpcResult]      = useState<AttendanceGPSResult | null>(null)
  const [errorMsg,       setErrorMsg]       = useState<string | null>(null)
  const [isOnline,       setIsOnline]       = useState(navigator.onLine)

  // ✅ إصلاح الخطأ الحرج: useEffect وليس useState لمراقبة الاتصال
  useEffect(() => {
    const onOnline  = () => setIsOnline(true)
    const onOffline = () => setIsOnline(false)
    window.addEventListener('online',  onOnline)
    window.addEventListener('offline', onOffline)
    return () => {
      window.removeEventListener('online',  onOnline)
      window.removeEventListener('offline', onOffline)
    }
  }, [])

  // جلب سجل اليوم
  const today = new Date().toISOString().split('T')[0]
  const { data: todayResult, isLoading: todayLoading, refetch: refetchToday } = useQuery({
    queryKey: ['hr-attendance-today', employee?.id, today],
    queryFn: () => employee
      ? getAttendanceDays({ employeeId: employee.id, dateFrom: today, dateTo: today, pageSize: 1 })
      : null,
    enabled:   !!employee,
    staleTime: 0,
  })
  const todayRecord = todayResult?.data?.[0] ?? null

  // Auto-reset بعد النجاح
  useEffect(() => {
    if (flowState !== 'success') return
    const id = setTimeout(() => {
      setFlowState('idle')
      setPosition(null)
      setRpcResult(null)
      setErrorMsg(null)
    }, SUCCESS_RESET_MS)
    return () => clearTimeout(id)
  }, [flowState])

  // ── عند الضغط على زر الحضور/الانصراف ─────────────────────────────────────
  // نتحقق من حالة الصلاحية أولاً ونقرر هل نعرض dialog توضيحي أم لا
  const handleAction = useCallback(async (type: ActionType) => {
    if (!employee) return
    setActionType(type)
    setFlowState('idle')
    setErrorMsg(null)
    setRpcResult(null)
    setPosition(null)

    if (!navigator.onLine) {
      toast.warning('أنت غير متصل — لا يمكن التسجيل الآن')
      return
    }

    // ── تحقق من حالة الصلاحية ──
    // granted  → استمر مباشرةً
    // prompt   → أظهر dialog توضيحي أولاً (Explain before Ask)
    // denied   → البانر يعرض الإرشادات — لا نستمر
    if (geo.status === 'denied') {
      setErrorMsg(geo.blockedMessage)
      setFlowState('error')
      return
    }

    if (geo.status === 'prompt') {
      // احفظ الإجراء المعلق وأظهر dialog التوضيح
      setPendingAction(type)
      setShowGeoDialog(true)
      return
    }

    // granted (أو unavailable — نحاول ونتعامل مع الخطأ)
    await executeWithGPS(type)

  }, [employee, geo.status, geo.blockedMessage])

  // ── التنفيذ الفعلي بعد الحصول على GPS ──────────────────────────────────
  const executeWithGPS = useCallback(async (type: ActionType) => {
    // خطوة 1: جلب GPS
    setFlowState('locating')
    const geoCoords = await geo.requestLocation()

    if (!geoCoords) {
      // فشل GPS — الخطأ محفوظ في geo.error
      if (geo.status === 'denied') {
        setErrorMsg(geo.blockedMessage)
      } else {
        setErrorMsg(geo.error ?? 'فشل تحديد الموقع — حاول مرة أخرى')
      }
      setFlowState('error')
      return
    }

    setPosition({ latitude: geoCoords.lat, longitude: geoCoords.lng, accuracy: geoCoords.accuracy })

    // خطوة 2: RPC ذرية
    setFlowState('submitting')
    try {
      const result = await recordAttendanceGPS({
        latitude:     geoCoords.lat,
        longitude:    geoCoords.lng,
        gps_accuracy: geoCoords.accuracy,
        log_type:     type,
        event_time:   new Date().toISOString(),
      })
      setRpcResult(result)

      if (!result.success) {
        const msg =
          result.code === 'ALREADY_CHECKED_IN'  ? 'لقد سجلت حضورك بالفعل اليوم' :
          result.code === 'ALREADY_CHECKED_OUT' ? 'لقد سجلت انصرافك بالفعل اليوم' :
          result.code === 'NOT_CHECKED_IN'      ? 'يجب تسجيل الحضور أولاً' :
          result.code === 'OUT_OF_RANGE'        ? `خارج النطاق — ${result.nearest_location ?? ''} (${Math.round(result.distance_meters ?? 0)}م)` :
          result.code === 'LOW_GPS_ACCURACY'    ? `دقة GPS ضعيفة (${Math.round(geoCoords.accuracy)}م)` :
          result.code === 'NO_LOCATION_FOUND'   ? 'لا توجد مواقع عمل مسجلة في النظام' :
          result.code === 'NO_EMPLOYEE'         ? 'حسابك غير مرتبط بموظف' :
          result.error ?? 'تعذر التسجيل'
        setErrorMsg(msg)
        setFlowState('error')
        return
      }

      // ✅ نجاح
      await refetchToday()
      setFlowState('success')
      toast.success(
        type === 'check_in'
          ? `✅ تم تسجيل الحضور${result.location_name ? ` — ${result.location_name}` : ''}`
          : '✅ تم تسجيل الانصراف',
        { duration: 3000 }
      )
    } catch (e) {
      setErrorMsg(e instanceof Error ? e.message : 'فشل التسجيل — يرجى المحاولة مجدداً')
      setFlowState('error')
    }
  }, [geo, refetchToday])

  // ── عند موافقة المستخدم في dialog التوضيحي ──────────────────────────────
  const handleGeoDialogAllow = useCallback(async () => {
    setShowGeoDialog(false)
    if (!pendingAction) return
    const type = pendingAction
    setPendingAction(null)
    await executeWithGPS(type)
  }, [pendingAction, executeWithGPS])

  const handleGeoDialogDismiss = useCallback(() => {
    setShowGeoDialog(false)
    setPendingAction(null)
  }, [])

  // ── Loading / No Employee ──
  if (empLoading) return (
    <div className="ci-page" style={{ justifyContent: 'center' }}>
      <Spinner />
    </div>
  )

  if (!employee) return (
    <div className="ci-page" style={{ justifyContent: 'center', textAlign: 'center', gap: 'var(--space-4)' }}>
      <UserX size={52} style={{ color: 'var(--color-danger)', opacity: 0.6 }} />
      <div style={{ fontWeight: 700, fontSize: 'var(--text-lg)' }}>غير مرتبط بسجل موظف</div>
      <div style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)', maxWidth: 300 }}>
        تواصل مع مدير الموارد البشرية لربط حسابك.
      </div>
    </div>
  )

  const isProcessing  = ['locating', 'submitting'].includes(flowState)
  const isGeoBlocked  = geo.isBlocked
  const hasCheckIn    = !!todayRecord?.punch_in_time
  const hasCheckOut   = !!todayRecord?.punch_out_time
  const isDayDone     = hasCheckIn && hasCheckOut

  // ─────────────────────────────────────
  // RENDER
  // ─────────────────────────────────────
  return (
    <div id="attendance-checkin-page" className="ci-page">

      {/* ── شريط علوي ── */}
      <header className="ci-header">
        <div className="ci-header-title">تسجيل الحضور</div>
        <div className={`ci-chip ${isOnline ? 'ci-chip--online' : 'ci-chip--offline'}`}>
          {isOnline ? <Wifi size={11} /> : <WifiOff size={11} />}
          {isOnline ? 'متصل' : 'غير متصل'}
        </div>
      </header>

      {/* ── الساعة ── */}
      <LiveClock />

      {/* ── حالة الحضور ── */}
      <TodayStatus record={todayRecord} isLoading={todayLoading} />

      {/* ── بطاقة الموظف ── */}
      <div className="ci-employee-card">
        <div className="ci-avatar">{employee.full_name.charAt(0)}</div>
        <div>
          <div className="ci-emp-name">{employee.full_name}</div>
          <div className="ci-emp-meta">
            {employee.employee_number}
            {employee.position?.name ? ` · ${employee.position.name}` : ''}
          </div>
        </div>
      </div>

      {/* ── نجاح ── */}
      {flowState === 'success' && (
        <div className="ci-feedback-card ci-feedback-card--success">
          <div className="ci-success-ring">
            <CheckCircle size={32} />
          </div>
          <div className="ci-feedback-title">
            {actionType === 'check_in' ? 'تم تسجيل الحضور!' : 'تم تسجيل الانصراف!'}
          </div>
          {rpcResult?.location_name && (
            <div className="ci-feedback-sub">
              <MapPin size={12} /> {rpcResult.location_name}
            </div>
          )}
        </div>
      )}

      {/* ── خطأ ── */}
      {flowState === 'error' && errorMsg && (
        <div className="ci-feedback-card ci-feedback-card--error">
          <XCircle size={22} />
          <div>
            <div className="ci-feedback-title">تعذر التسجيل</div>
            <div className="ci-feedback-sub">{errorMsg}</div>
          </div>
        </div>
      )}

      {/* ── بانر حالة GPS (للحالات: checking/denied/prompt) ── */}
      {!isProcessing && flowState !== 'success' && !isDayDone && (
        <GeoPermissionBanner
          showOnPrompt={false}
          contextMessage="تسجيل الحضور يتطلب تحديد موقعك الجغرافي للتحقق من تواجدك"
        />
      )}

      {/* ── تقدم العملية ── */}
      {isProcessing && (
        <ProgressSteps flowState={flowState} position={position} />
      )}

      {/* ── الزر الذكي الرئيسي ── */}
      {!isProcessing && flowState !== 'success' && (
        isDayDone ? (
          /* انتهى الدوام — لا أزرار */
          <div className="ci-day-done">
            <div className="ci-day-done-ring">
              <CheckCircle size={28} strokeWidth={2} />
            </div>
            <div className="ci-day-done-title">أنهيت دوامك اليوم</div>
            {todayRecord?.punch_in_time && todayRecord?.punch_out_time && (
              <div className="ci-day-done-meta">
                {(() => {
                  const ms = new Date(todayRecord.punch_out_time!).getTime()
                    - new Date(todayRecord.punch_in_time!).getTime()
                  const h = Math.floor(ms / 3_600_000)
                  const m = Math.floor((ms % 3_600_000) / 60_000)
                  return `إجمالي الدوام: ${h}س ${m}د`
                })()}
              </div>
            )}
          </div>
        ) : isGeoBlocked ? (
          /* الصلاحية محظورة — GeoPermissionBanner يعرض الإرشادات */
          null
        ) : (
          <SmartActionButton
            record={todayRecord}
            flowState={flowState}
            onAction={handleAction}
          />
        )
      )}

      {/* تحذير دقة GPS ضعيفة */}
      {position && position.accuracy > 50 && isProcessing && (
        <div className="ci-gps-warn">
          <AlertCircle size={12} />
          دقة GPS ضعيفة ({Math.round(position.accuracy)}م) — انتقل لمكان مفتوح
        </div>
      )}

      {/* ملاحظة الخصوصية */}
      <div className="ci-privacy-note">
        <Info size={12} />
        موقعك يُستخدم لتسجيل الحضور فقط — لا يُتتبع خلال اليوم.
      </div>

      {/* ── Dialog التوضيحي قبل طلب الصلاحية ── */}
      <GeoPermissionDialog
        open={showGeoDialog}
        context="attendance"
        onAllow={handleGeoDialogAllow}
        onDismiss={handleGeoDialogDismiss}
      />

      {/* ── الأنماط ── */}
      <style>{`
        /* ══ Layout ══ */
        .ci-page {
          min-height: 100dvh;
          background: var(--bg-base);
          display: flex;
          flex-direction: column;
          align-items: center;
          padding: env(safe-area-inset-top, 16px) var(--space-4) var(--space-8);
          gap: var(--space-5);
          overflow-x: hidden;
        }

        /* ══ Header ══ */
        .ci-header {
          width: 100%; max-width: 440px;
          display: flex; justify-content: space-between; align-items: center;
          padding-top: var(--space-4);
        }
        .ci-header-title {
          font-size: var(--text-lg); font-weight: 800;
          color: var(--text-primary); letter-spacing: -0.02em;
        }

        /* ══ Online chip ══ */
        .ci-chip {
          display: flex; align-items: center; gap: 5px;
          font-size: 11px; font-weight: 700;
          padding: 4px 10px; border-radius: 99px;
          border: 1px solid transparent;
        }
        .ci-chip--online  { color: var(--color-success); background: color-mix(in srgb, var(--color-success) 10%, transparent); border-color: color-mix(in srgb, var(--color-success) 22%, transparent); }
        .ci-chip--offline { color: var(--color-danger);  background: color-mix(in srgb, var(--color-danger) 10%, transparent);  border-color: color-mix(in srgb, var(--color-danger) 22%, transparent); }

        /* ══ Status pill ══ */
        .ci-status-pill {
          display: flex; align-items: center; flex-wrap: wrap;
          gap: var(--space-2);
          padding: 10px 16px;
          border-radius: 99px;
          font-size: var(--text-sm); font-weight: 600;
          border: 1px solid transparent;
          max-width: 440px; width: 100%;
        }
        .ci-status-pill--idle    { background: color-mix(in srgb, var(--color-warning) 8%, transparent); color: var(--color-warning); border-color: color-mix(in srgb, var(--color-warning) 22%, transparent); }
        .ci-status-pill--active  { background: color-mix(in srgb, var(--color-success) 8%, transparent); color: var(--color-success); border-color: color-mix(in srgb, var(--color-success) 22%, transparent); }
        .ci-status-pill--done    { background: color-mix(in srgb, var(--color-info) 8%, transparent);    color: var(--color-info);    border-color: color-mix(in srgb, var(--color-info) 22%, transparent); }
        .ci-status-pill--loading { background: var(--bg-surface-2); color: var(--text-muted); border-color: var(--border-color); }

        .ci-dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
        .ci-dot--green { background: var(--color-success); }
        .ci-dot--pulse { background: var(--color-primary); animation: ci-pulse-dot 1.5s ease-in-out infinite; }

        .ci-status-times { display: flex; gap: var(--space-2); flex-wrap: wrap; margin-right: auto; }
        .ci-time-badge {
          display: flex; align-items: center; gap: 4px;
          font-size: 11px; font-variant-numeric: tabular-nums;
          background: rgba(255,255,255,0.15); padding: 2px 8px; border-radius: 99px;
          color: inherit;
        }
        .ci-time-badge--elapsed { font-weight: 800; font-size: 12px; }

        /* ══ Employee card ══ */
        .ci-employee-card {
          display: flex; align-items: center; gap: var(--space-3);
          background: var(--bg-card);
          border: 1px solid var(--border-color);
          border-radius: var(--radius-2xl);
          padding: var(--space-3) var(--space-5);
          width: 100%; max-width: 440px;
        }
        .ci-avatar {
          width: 44px; height: 44px; border-radius: 50%; flex-shrink: 0;
          background: color-mix(in srgb, var(--color-primary) 14%, transparent);
          border: 2px solid color-mix(in srgb, var(--color-primary) 28%, transparent);
          display: flex; align-items: center; justify-content: center;
          font-size: 1.25rem; font-weight: 800; color: var(--color-primary);
        }
        .ci-emp-name  { font-weight: 700; font-size: var(--text-sm); color: var(--text-primary); }
        .ci-emp-meta  { font-size: var(--text-xs); color: var(--text-muted); margin-top: 2px; }

        /* ══ Smart Action Button ══ */
        .ci-action-btn {
          display: flex; flex-direction: column; align-items: center; gap: var(--space-4);
          background: none; border: none; cursor: pointer;
          font-family: var(--font-sans);
          padding: var(--space-4) 0;
          transition: transform 0.15s;
        }
        .ci-action-btn:active { transform: scale(0.96); }
        .ci-action-btn:disabled { opacity: 0.6; cursor: not-allowed; }

        .ci-action-ring {
          position: relative;
          width: 140px; height: 140px;
          border-radius: 50%;
          background: var(--action-color);
          display: flex; align-items: center; justify-content: center;
          box-shadow:
            0 0 0 0 color-mix(in srgb, var(--action-color) 35%, transparent),
            0 16px 48px color-mix(in srgb, var(--action-color) 40%, transparent);
          animation: ci-pulse-ring 2.5s ease-in-out infinite;
        }
        .ci-action-ring-pulse {
          position: absolute; inset: -12px;
          border-radius: 50%;
          border: 2px solid color-mix(in srgb, var(--action-color) 30%, transparent);
          animation: ci-ring-scale 2.5s ease-out infinite;
        }
        .ci-action-icon-wrap { color: #fff; display: flex; align-items: center; justify-content: center; }
        .ci-action-label { font-size: var(--text-xl); font-weight: 800; color: var(--text-primary); letter-spacing: -0.02em; }

        /* ══ Spinner ══ */
        .ci-spinner {
          width: 32px; height: 32px; border-radius: 50%;
          border: 3px solid rgba(255,255,255,0.3);
          border-top-color: #fff;
          animation: ci-spin 0.75s linear infinite;
        }
        .ci-spinner--sm { width: 14px; height: 14px; border-width: 2px; border-color: rgba(0,0,0,0.15); border-top-color: currentColor; }

        /* ══ Progress Steps ══ */
        .ci-progress {
          display: flex; flex-direction: column; gap: var(--space-3);
          width: 100%; max-width: 440px;
          background: var(--bg-card);
          border: 1px solid var(--border-color);
          border-radius: var(--radius-2xl);
          padding: var(--space-5);
        }
        .ci-step { display: flex; align-items: center; gap: var(--space-3); }
        .ci-step-dot {
          width: 30px; height: 30px; border-radius: 50%; flex-shrink: 0;
          display: flex; align-items: center; justify-content: center;
          font-size: 11px; font-weight: 700;
          transition: all 0.3s;
        }
        .ci-step--done    .ci-step-dot { background: color-mix(in srgb, var(--color-success) 12%, transparent); color: var(--color-success); }
        .ci-step--active  .ci-step-dot { background: color-mix(in srgb, var(--color-primary) 12%, transparent); color: var(--color-primary); }
        .ci-step--pending .ci-step-dot { background: var(--bg-surface-2); color: var(--text-muted); }
        .ci-step--pending { opacity: 0.4; }
        .ci-step-info  { flex: 1; }
        .ci-step-label { font-size: var(--text-sm); font-weight: 600; color: var(--text-primary); }
        .ci-step-sub   { font-size: 11px; color: var(--color-success); margin-top: 2px; display: block; }
        .ci-step-line  {
          display: none; /* vertical connector — hidden for now */
        }

        /* ══ Feedback cards ══ */
        .ci-feedback-card {
          display: flex; align-items: center; gap: var(--space-3);
          width: 100%; max-width: 440px;
          border-radius: var(--radius-2xl);
          padding: var(--space-4) var(--space-5);
          border: 1px solid transparent;
        }
        .ci-feedback-card--success {
          flex-direction: column; text-align: center;
          background: color-mix(in srgb, var(--color-success) 6%, transparent);
          border-color: color-mix(in srgb, var(--color-success) 22%, transparent);
          color: var(--color-success);
          padding: var(--space-6);
        }
        .ci-feedback-card--error {
          background: color-mix(in srgb, var(--color-danger) 6%, transparent);
          border-color: color-mix(in srgb, var(--color-danger) 22%, transparent);
          color: var(--color-danger);
        }
        .ci-success-ring {
          width: 64px; height: 64px; border-radius: 50%;
          background: color-mix(in srgb, var(--color-success) 15%, transparent);
          display: flex; align-items: center; justify-content: center;
          animation: ci-pop 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
        }
        .ci-feedback-title { font-size: var(--text-base); font-weight: 700; }
        .ci-feedback-sub   { font-size: var(--text-xs); opacity: 0.8; margin-top: 4px; display: flex; align-items: center; gap: 4px; justify-content: center; flex-wrap: wrap; }

        /* ══ Day done ══ */
        .ci-day-done {
          display: flex; flex-direction: column; align-items: center;
          gap: var(--space-3); padding: var(--space-6) var(--space-4);
        }
        .ci-day-done-ring {
          width: 96px; height: 96px; border-radius: 50%;
          background: color-mix(in srgb, var(--color-success) 10%, transparent);
          border: 3px solid color-mix(in srgb, var(--color-success) 30%, transparent);
          display: flex; align-items: center; justify-content: center;
          color: var(--color-success);
        }
        .ci-day-done-title { font-size: var(--text-xl); font-weight: 800; color: var(--text-primary); }
        .ci-day-done-meta  { font-size: var(--text-sm); color: var(--text-muted); }

        /* ══ GPS warning ══ */
        .ci-gps-warn {
          display: flex; align-items: center; gap: var(--space-2);
          font-size: 12px; color: var(--color-warning);
          background: color-mix(in srgb, var(--color-warning) 8%, transparent);
          padding: 8px 14px; border-radius: 99px;
          border: 1px solid color-mix(in srgb, var(--color-warning) 22%, transparent);
        }

        /* ══ Privacy note ══ */
        .ci-privacy-note {
          display: flex; align-items: flex-start; gap: 6px;
          font-size: 11px; color: var(--text-muted); line-height: 1.6;
          max-width: 440px; width: 100%;
          margin-top: auto; padding-top: var(--space-4);
        }

        /* ══ Animations ══ */
        @keyframes ci-pulse-ring {
          0%, 100% { box-shadow: 0 0 0 0 color-mix(in srgb, var(--action-color) 35%, transparent), 0 16px 48px color-mix(in srgb, var(--action-color) 40%, transparent); }
          50%       { box-shadow: 0 0 0 14px color-mix(in srgb, var(--action-color) 0%, transparent), 0 16px 48px color-mix(in srgb, var(--action-color) 40%, transparent); }
        }
        @keyframes ci-ring-scale {
          0%   { transform: scale(1);    opacity: 0.8; }
          100% { transform: scale(1.35); opacity: 0; }
        }
        @keyframes ci-pulse-dot {
          0%, 100% { opacity: 1; transform: scale(1); }
          50%      { opacity: 0.4; transform: scale(0.7); }
        }
        @keyframes ci-spin  { to { transform: rotate(360deg); } }
        @keyframes ci-pop {
          0%   { transform: scale(0.5); opacity: 0; }
          60%  { transform: scale(1.15); }
          100% { transform: scale(1); opacity: 1; }
        }

        /* ══ Responsive ══ */
        @media (max-width: 380px) {
          .ci-action-ring { width: 120px; height: 120px; }
          .ci-action-label { font-size: var(--text-lg); }
        }
      `}</style>

    </div>
  )
}
