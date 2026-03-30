/**
 * ActivityForm — إنشاء نشاط + تعديل + حفظ call_details إذا category = call
 *
 * call_details flow:
 *  1. إذا ActivityType.category === 'call' → تظهر حقول call_detail
 *  2. بعد save activity → useSaveCallDetail(activityId, callDetailInput)
 *  3. edit mode → prefill من existing.call_detail
 */
import { useState, useEffect } from 'react'
import { useNavigate, useSearchParams, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { useAuthStore } from '@/stores/auth-store'
import {
  useActivityTypes,
  useCreateActivity,
  useUpdateActivity,
  useActivity,
  useSaveCallDetail,
} from '@/hooks/useQueryHooks'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'
import GPSStatusIndicator from '@/components/shared/GPSStatusIndicator'
import type {
  ActivityInput,
  ActivityOutcome,
  ActivityType,
  CallDirection,
  CallResult,
  CallDetailInput,
} from '@/lib/types/activities'
import type { GPSCoords } from '@/components/shared/GPSStatusIndicator'

// ── Outcome options ──────────────────────────────────────────────
const OUTCOME_VISIT_OPTIONS: { value: ActivityOutcome; label: string }[] = [
  { value: 'order_placed',     label: 'طلب مبيعات' },
  { value: 'agreed_order',     label: 'اتفاق على طلب' },
  { value: 'collection',       label: 'تحصيل' },
  { value: 'promised_payment', label: 'وعد بالدفع' },
  { value: 'followup_visit',   label: 'زيارة متابعة' },
  { value: 'refused',          label: 'رفض' },
  { value: 'not_interested',   label: 'غير مهتم' },
  { value: 'promotion',        label: 'ترويج' },
  { value: 'exploratory',      label: 'استكشافية' },
  { value: 'closed',           label: 'مغلق' },
  { value: 'info_only',        label: 'معلومات فقط' },
]
const OUTCOME_CALL_OPTIONS: { value: ActivityOutcome; label: string }[] = [
  { value: 'order_placed',       label: 'طلب مبيعات' },
  { value: 'collection',         label: 'تحصيل' },
  { value: 'promised_payment',   label: 'وعد بالدفع' },
  { value: 'followup_scheduled', label: 'متابعة مجدولة' },
  { value: 'callback_scheduled', label: 'مكالمة لاحقة' },
  { value: 'no_answer',          label: 'لا يرد' },
  { value: 'busy',               label: 'مشغول' },
  { value: 'refused',            label: 'رفض' },
  { value: 'not_interested',     label: 'غير مهتم' },
  { value: 'closed',             label: 'مغلق' },
]
const OUTCOME_TASK_OPTIONS: { value: ActivityOutcome; label: string }[] = [
  { value: 'info_only',   label: 'معلومات فقط' },
  { value: 'exploratory', label: 'استكشافية' },
  { value: 'promotion',   label: 'ترويج' },
  { value: 'closed',      label: 'مغلق' },
]

function getOutcomeOptions(category?: string) {
  if (category === 'call')  return OUTCOME_CALL_OPTIONS
  if (category === 'visit') return OUTCOME_VISIT_OPTIONS
  return OUTCOME_TASK_OPTIONS
}

const CALL_RESULT_OPTIONS: { value: CallResult; label: string }[] = [
  { value: 'answered',           label: 'تم الرد' },
  { value: 'no_answer',          label: 'لا يرد' },
  { value: 'busy',               label: 'مشغول' },
  { value: 'callback_scheduled', label: 'مكالمة لاحقة' },
  { value: 'wrong_number',       label: 'خطأ في الرقم' },
  { value: 'rejected',           label: 'رُفض' },
]

// ── Component ────────────────────────────────────────────────────
interface ActivityFormProps {
  prefillPlanItemId?: string
  prefillPlanType?: 'visit' | 'call'
}

export default function ActivityForm({ prefillPlanItemId, prefillPlanType }: ActivityFormProps = {}) {
  const navigate       = useNavigate()
  const [searchParams] = useSearchParams()
  const { id }         = useParams<{ id: string }>()
  const activityId     = id
  const can            = useAuthStore(s => s.can)

  // plan-first params
  const planItemId = prefillPlanItemId
    || searchParams.get('visitPlanItemId')
    || searchParams.get('callPlanItemId')
    || ''
  const planType = prefillPlanType
    || (searchParams.get('visitPlanItemId') ? 'visit' : searchParams.get('callPlanItemId') ? 'call' : '')
  const customerId = searchParams.get('customerId') || ''

  // ── Activity State ───────────────────────────────────────────
  const [typeId,       setTypeId]       = useState('')
  const [outcomeType,  setOutcomeType]  = useState<ActivityOutcome | ''>('')
  const [outcomeNotes, setOutcomeNotes] = useState('')
  const [refuseReason, setRefuseReason] = useState('')
  const [activityDate, setActivityDate] = useState(() => new Date().toISOString().slice(0, 10))
  const [startTime,    setStartTime]    = useState('')
  const [endTime,      setEndTime]      = useState('')
  const [gpsCoords,    setGpsCoords]    = useState<GPSCoords | null>(null)
  const [saving,       setSaving]       = useState(false)

  // ── Call Detail State ────────────────────────────────────────
  const [callDirection,    setCallDirection]    = useState<CallDirection>('outbound')
  const [callResult,       setCallResult]       = useState<CallResult | ''>('')
  const [callAttempts,     setCallAttempts]     = useState(1)
  const [callPhone,        setCallPhone]        = useState('')
  const [callCallbackAt,   setCallCallbackAt]   = useState('')
  const [callRecordingUrl, setCallRecordingUrl] = useState('')

  // ── Queries ──────────────────────────────────────────────────
  const { data: activityTypes = [] } = useActivityTypes()
  const { data: existing }           = useActivity(activityId)
  const createActivity               = useCreateActivity()
  const updateActivity               = useUpdateActivity()
  const saveCallDetail               = useSaveCallDetail()

  const selectedType: ActivityType | undefined = activityTypes.find(t => t.id === typeId)
  const isCallType = selectedType?.category === 'call'

  // ── Prefill في وضع التعديل ─────────────────────────────────
  useEffect(() => {
    if (!existing) return
    setTypeId(existing.type_id)
    setOutcomeType(existing.outcome_type)
    setOutcomeNotes(existing.outcome_notes ?? '')
    setRefuseReason(existing.refuse_reason ?? '')
    setActivityDate(existing.activity_date)
    if (existing.start_time) setStartTime(new Date(existing.start_time).toTimeString().slice(0, 5))
    if (existing.end_time)   setEndTime(new Date(existing.end_time).toTimeString().slice(0, 5))
    if (existing.gps_lat && existing.gps_lng) setGpsCoords({ lat: existing.gps_lat, lng: existing.gps_lng })
    // prefill call_detail
    const cd = (existing as any).call_detail
    if (cd) {
      setCallDirection(cd.direction    ?? 'outbound')
      setCallResult(cd.call_result     ?? '')
      setCallAttempts(cd.attempt_count ?? 1)
      setCallPhone(cd.phone_number     ?? '')
      setCallCallbackAt(cd.callback_at ? cd.callback_at.slice(0, 16) : '')
      setCallRecordingUrl(cd.call_recording_url ?? '')
    }
  }, [existing])

  // فلترة الأنواع بـ planType
  const availableTypes = activityTypes.filter(t => !planType || t.category === planType)

  const requiresGPS = selectedType?.requires_gps ?? false
  const gpsBlocking = requiresGPS && !gpsCoords

  function validate(): string | null {
    if (!typeId)       return 'اختر نوع النشاط'
    if (!outcomeType)  return 'اختر نتيجة النشاط'
    if (!activityDate) return 'اختر تاريخ النشاط'
    if (gpsBlocking)   return 'يتطلب هذا النوع تحديد موقع GPS'
    if (isCallType && !callResult) return 'اختر نتيجة المكالمة'
    return null
  }

  // ── Submit ───────────────────────────────────────────────────
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    const err = validate()
    if (err) { toast.error(err); return }
    setSaving(true)

    const buildTime = (t: string) => t ? `${activityDate}T${t}:00` : null

    const payload: ActivityInput = {
      type_id:             typeId,
      employee_id:         '',   // service يستبدله من hr_employees
      customer_id:         customerId || null,
      visit_plan_item_id:  planType === 'visit' ? planItemId || null : null,
      call_plan_item_id:   planType === 'call'  ? planItemId || null : null,
      outcome_type:        outcomeType as ActivityOutcome,
      outcome_notes:       outcomeNotes  || null,
      refuse_reason:       refuseReason  || null,
      activity_date:       activityDate,
      start_time:          buildTime(startTime),
      end_time:            buildTime(endTime),
      gps_lat:             gpsCoords?.lat ?? null,
      gps_lng:             gpsCoords?.lng ?? null,
      gps_verified:        !!gpsCoords,
    }

    const callDetailPayload: CallDetailInput | null = isCallType ? {
      direction:           callDirection,
      call_result:         callResult as CallResult || null,
      attempt_count:       callAttempts,
      phone_number:        callPhone     || null,
      callback_at:         callCallbackAt ? `${callCallbackAt}:00` : null,
      call_recording_url:  callRecordingUrl || null,
    } : null

    try {
      if (activityId) {
        // ── Update ─────────────────────────────────────────────
        updateActivity.mutate(
          { id: activityId, input: payload },
          {
            onSuccess: async () => {
              if (callDetailPayload) {
                try {
                  await saveCallDetail.mutateAsync({ activityId, input: callDetailPayload })
                } catch {
                  // call_detail \u063a\u064a\u0631 \u062d\u0631\u062c \u2014 \u0627\u0644\u0646\u0634\u0627\u0637 \u062a\u0645 \u062a\u062d\u062f\u064a\u062b\u0647
                  toast.warning('\u062a\u0645 \u062a\u062d\u062f\u064a\u062b \u0627\u0644\u0646\u0634\u0627\u0637 \u0644\u0643\u0646 \u0641\u0634\u0644 \u062d\u0641\u0638 \u062a\u0641\u0627\u0635\u064a\u0644 \u0627\u0644\u0645\u0643\u0627\u0644\u0645\u0629')
                  setSaving(false)
                  navigate(-1)
                  return
                }
              }
              toast.success('\u062a\u0645 \u062a\u062d\u062f\u064a\u062b \u0627\u0644\u0646\u0634\u0627\u0637')
              navigate(-1)
            },
            onError: () => { toast.error('\u0641\u0634\u0644 \u0627\u0644\u062a\u062d\u062f\u064a\u062b'); setSaving(false) },
          }
        )
      } else {
        // ── Create ─────────────────────────────────────────────
        createActivity.mutate(payload, {
          onSuccess: async (act) => {
            if (callDetailPayload) {
              try {
                await saveCallDetail.mutateAsync({ activityId: act.id, input: callDetailPayload })
              } catch {
                // call_detail غير حرج — النشاط تم إنشاؤه
                toast.warning('تم إنشاء النشاط لكن فشل حفظ تفاصيل المكالمة')
              }
            }
            toast.success('تم تسجيل النشاط')
            navigate('/activities/list')
          },
          onError: (e: any) => { toast.error(e?.message || 'فشل تسجيل النشاط'); setSaving(false) },
        })
      }
    } catch {
      setSaving(false)
    }
  }

  const outcomeOptions = getOutcomeOptions(selectedType?.category)

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title={activityId ? 'تعديل النشاط' : 'نشاط جديد'}
        subtitle={planType ? `خطة ${planType === 'visit' ? 'زيارة' : 'مكالمة'}` : 'تسجيل نشاط ميداني'}
        breadcrumbs={[
          { label: 'الأنشطة', path: '/activities/list' },
          { label: activityId ? 'تعديل' : 'جديد' },
        ]}
      />

      <form className="edara-card act-form" onSubmit={handleSubmit}>

        {/* ── نوع النشاط ── */}
        <div className="form-group">
          <label className="form-label">نوع النشاط <span className="form-required">*</span></label>
          <select
            className="form-select"
            value={typeId}
            onChange={e => { setTypeId(e.target.value); setOutcomeType('') }}
            required
          >
            <option value="">-- اختر نوع النشاط --</option>
            {availableTypes.map(t => (
              <option key={t.id} value={t.id}>{t.name}</option>
            ))}
          </select>
        </div>

        {/* ── GPS ── */}
        {typeId && (
          <div className="form-group">
            <label className="form-label">
              الموقع الجغرافي
              {requiresGPS && <span className="form-required"> *</span>}
            </label>
            <GPSStatusIndicator
              requiresGPS={requiresGPS}
              onCoordsChange={setGpsCoords}
              value={gpsCoords}
            />
          </div>
        )}

        {/* ── نتيجة النشاط ── */}
        <div className="form-group">
          <label className="form-label">نتيجة النشاط <span className="form-required">*</span></label>
          <select
            className="form-select"
            value={outcomeType}
            onChange={e => setOutcomeType(e.target.value as ActivityOutcome)}
            required
            disabled={!typeId}
          >
            <option value="">-- اختر النتيجة --</option>
            {outcomeOptions.map(o => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </select>
        </div>

        {/* ── سبب الرفض ── */}
        {(outcomeType === 'refused' || outcomeType === 'not_interested') && (
          <div className="form-group">
            <label className="form-label">سبب الرفض</label>
            <input
              className="form-input"
              value={refuseReason}
              onChange={e => setRefuseReason(e.target.value)}
              placeholder="اذكر سبب الرفض..."
            />
          </div>
        )}

        {/* ── ━━━━━━ تفاصيل المكالمة (يظهر عند category = call) ━━━━━━ ── */}
        {isCallType && (
          <div className="act-call-section">
            <div className="act-call-section-title">📞 تفاصيل المكالمة</div>

            {/* الاتجاه */}
            <div className="act-call-grid">
              <div className="form-group">
                <label className="form-label">اتجاه المكالمة <span className="form-required">*</span></label>
                <div className="act-direction-btns">
                  <button
                    type="button"
                    className={`act-dir-btn${callDirection === 'outbound' ? ' act-dir-btn--active' : ''}`}
                    onClick={() => setCallDirection('outbound')}
                  >
                    ↗ صادرة
                  </button>
                  <button
                    type="button"
                    className={`act-dir-btn${callDirection === 'inbound' ? ' act-dir-btn--active' : ''}`}
                    onClick={() => setCallDirection('inbound')}
                  >
                    ↙ واردة
                  </button>
                </div>
              </div>

              {/* نتيجة المكالمة */}
              <div className="form-group">
                <label className="form-label">نتيجة المكالمة <span className="form-required">*</span></label>
                <select
                  className="form-select"
                  value={callResult}
                  onChange={e => setCallResult(e.target.value as CallResult)}
                  required
                >
                  <option value="">-- اختر النتيجة --</option>
                  {CALL_RESULT_OPTIONS.map(o => (
                    <option key={o.value} value={o.value}>{o.label}</option>
                  ))}
                </select>
              </div>

              {/* عدد المحاولات */}
              <div className="form-group">
                <label className="form-label">عدد المحاولات</label>
                <input
                  type="number"
                  className="form-input"
                  value={callAttempts}
                  onChange={e => setCallAttempts(Math.max(1, Number(e.target.value)))}
                  min={1}
                  max={99}
                />
              </div>

              {/* رقم الهاتف */}
              <div className="form-group">
                <label className="form-label">رقم الهاتف</label>
                <input
                  className="form-input"
                  dir="ltr"
                  value={callPhone}
                  onChange={e => setCallPhone(e.target.value)}
                  placeholder="+20..."
                  type="tel"
                />
              </div>

              {/* موعد الرد */}
              {(callResult === 'callback_scheduled' || outcomeType === 'callback_scheduled') && (
                <div className="form-group">
                  <label className="form-label">موعد الرد</label>
                  <input
                    type="datetime-local"
                    className="form-input"
                    value={callCallbackAt}
                    onChange={e => setCallCallbackAt(e.target.value)}
                  />
                </div>
              )}

              {/* رابط التسجيل */}
              <div className="form-group" style={{ gridColumn: '1 / -1' }}>
                <label className="form-label">رابط تسجيل المكالمة</label>
                <input
                  className="form-input"
                  dir="ltr"
                  value={callRecordingUrl}
                  onChange={e => setCallRecordingUrl(e.target.value)}
                  placeholder="https://..."
                  type="url"
                />
              </div>
            </div>
          </div>
        )}

        {/* ── التاريخ ── */}
        <div className="form-group">
          <label className="form-label">تاريخ النشاط <span className="form-required">*</span></label>
          <input
            type="date"
            className="form-input"
            value={activityDate}
            onChange={e => setActivityDate(e.target.value)}
            required
          />
        </div>

        {/* ── الوقت ── */}
        <div className="act-form-times">
          <div className="form-group">
            <label className="form-label">وقت البدء</label>
            <input type="time" className="form-input" value={startTime} onChange={e => setStartTime(e.target.value)} />
          </div>
          <div className="form-group">
            <label className="form-label">وقت الانتهاء</label>
            <input type="time" className="form-input" value={endTime} onChange={e => setEndTime(e.target.value)} />
          </div>
        </div>

        {/* ── ملاحظات ── */}
        <div className="form-group">
          <label className="form-label">ملاحظات النتيجة</label>
          <textarea
            className="form-textarea"
            value={outcomeNotes}
            onChange={e => setOutcomeNotes(e.target.value)}
            rows={3}
            placeholder="أضف تفاصيل حول نتيجة النشاط..."
          />
        </div>

        {/* GPS warning */}
        {gpsBlocking && (
          <div className="act-form-gps-warning">
            ⚠ يتطلب نوع هذا النشاط تحديد موقع GPS قبل الحفظ
          </div>
        )}

        {/* ── يخبر المستخدم أن call_detail ستُحفظ ── */}
        {isCallType && callResult && (
          <div className="act-call-ready-hint">
            ✓ ستُحفظ تفاصيل المكالمة تلقائياً مع النشاط
          </div>
        )}

        {/* Buttons */}
        <div className="act-form-actions">
          <Button type="button" variant="secondary" onClick={() => navigate(-1)} disabled={saving}>
            إلغاء
          </Button>
          <Button type="submit" disabled={saving || gpsBlocking}>
            {saving ? 'جاري الحفظ...' : activityId ? 'حفظ التعديلات' : 'تسجيل النشاط'}
          </Button>
        </div>
      </form>

      <style>{`
        .act-form {
          max-width: 640px;
          margin: 0 auto;
          padding: var(--space-6);
          display: flex;
          flex-direction: column;
          gap: var(--space-4);
        }
        .act-call-section {
          border: 1px solid var(--color-primary);
          border-radius: var(--radius-lg);
          padding: var(--space-4);
          background: var(--color-primary-light);
          display: flex;
          flex-direction: column;
          gap: var(--space-3);
        }
        .act-call-section-title {
          font-size: var(--text-sm);
          font-weight: 700;
          color: var(--color-primary);
          margin-bottom: var(--space-1);
        }
        .act-call-grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--space-3);
        }
        .act-direction-btns {
          display: flex;
          gap: var(--space-2);
        }
        .act-dir-btn {
          flex: 1;
          padding: var(--space-2);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-md);
          background: var(--bg-surface);
          color: var(--text-secondary);
          font-size: var(--text-sm);
          font-weight: 500;
          cursor: pointer;
          transition: all var(--transition-fast);
          font-family: inherit;
        }
        .act-dir-btn--active {
          border-color: var(--color-primary);
          background: var(--color-primary);
          color: #fff;
          font-weight: 700;
        }
        .act-call-ready-hint {
          padding: var(--space-2) var(--space-3);
          font-size: var(--text-sm);
          color: var(--color-success);
          background: var(--color-success-light);
          border-radius: var(--radius-md);
          font-weight: 600;
        }
        .act-form-times {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--space-4);
        }
        .act-form-gps-warning {
          padding: var(--space-3);
          background: var(--color-warning-light);
          border: 1px solid var(--color-warning);
          border-radius: var(--radius-md);
          font-size: var(--text-sm);
          color: var(--color-warning);
          font-weight: 600;
        }
        .act-form-actions {
          display: flex;
          gap: var(--space-3);
          justify-content: flex-end;
          padding-top: var(--space-2);
          border-top: 1px solid var(--border-primary);
        }
        @media (max-width: 480px) {
          .act-form { padding: var(--space-4); }
          .act-form-times,
          .act-call-grid { grid-template-columns: 1fr; }
        }
      `}</style>
    </div>
  )
}
