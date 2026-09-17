/**
 * ActivityForm — إنشاء نشاط + تعديل + حفظ call_details إذا category = call
 *
 * call_details flow:
 *  1. إذا ActivityType.category === 'call' → تظهر حقول call_detail
 *  2. بعد save activity → useSaveCallDetail(activityId, callDetailInput)
 *  3. edit mode → prefill من existing.call_detail
 */
import { useState, useEffect, useMemo } from 'react'
import { useNavigate, useSearchParams, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { useAuthStore } from '@/stores/auth-store'
import {
  useActivityTypes,
  useCreateActivity,
  useUpdateActivity,
  useActivity,
  useSaveCallDetail,
  useCustomer,
  useCustomers,
  useActivities,
  useTargetStatus,
} from '@/hooks/useQueryHooks'
import { Target, Clock, ExternalLink } from 'lucide-react'
import { supabase } from '@/lib/supabase/client'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'
import FormActions from '@/components/patterns/FormActions'
import FormGrid from '@/components/patterns/FormGrid'
import FormSection from '@/components/patterns/FormSection'
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
import '@/styles/field-activity-form-v2.css'

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
  if (category === 'call') return OUTCOME_CALL_OPTIONS
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

interface ActivityFormProps {
  prefillPlanItemId?: string
  prefillPlanType?: 'visit' | 'call'
}

export default function ActivityForm({ prefillPlanItemId, prefillPlanType }: ActivityFormProps = {}) {
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const { id } = useParams<{ id: string }>()
  const activityId = id
  const can = useAuthStore(s => s.can)

  const planItemId = prefillPlanItemId
    || searchParams.get('visitPlanItemId')
    || searchParams.get('callPlanItemId')
    || ''
  const planType = prefillPlanType
    || (searchParams.get('visitPlanItemId') ? 'visit' : searchParams.get('callPlanItemId') ? 'call' : '')
  const urlCustomerId = searchParams.get('customerId') || ''

  const [selectedCustomerId, setSelectedCustomerId] = useState(urlCustomerId)
  useEffect(() => { if (urlCustomerId) setSelectedCustomerId(urlCustomerId) }, [urlCustomerId])
  const customerId = selectedCustomerId || urlCustomerId

  const [typeId, setTypeId] = useState('')
  const [outcomeType, setOutcomeType] = useState<ActivityOutcome | ''>('')
  const [outcomeNotes, setOutcomeNotes] = useState('')
  const [refuseReason, setRefuseReason] = useState('')
  const [closedReason, setClosedReason] = useState('')
  const [activityDate, setActivityDate] = useState(() => new Date().toISOString().slice(0, 10))
  const [startTime, setStartTime] = useState('')
  const [endTime, setEndTime] = useState('')
  const [gpsCoords, setGpsCoords] = useState<GPSCoords | null>(null)
  const [saving, setSaving] = useState(false)

  const [orderId, setOrderId] = useState('')
  const [collectionId, setCollectionId] = useState('')
  const [customerOrders, setCustomerOrders] = useState<{id:string;order_number:string;total_amount:number;status:string}[]>([])
  const [loadingOrders, setLoadingOrders] = useState(false)

  const [callDirection, setCallDirection] = useState<CallDirection>('outbound')
  const [callResult, setCallResult] = useState<CallResult | ''>('')
  const [callAttempts, setCallAttempts] = useState(1)
  const [callPhone, setCallPhone] = useState('')
  const [callCallbackAt, setCallCallbackAt] = useState('')
  const [callRecordingUrl, setCallRecordingUrl] = useState('')

  const { data: activityTypes = [] } = useActivityTypes()
  const { data: existing } = useActivity(activityId)
  const { data: customerData } = useCustomer(customerId || null)
  const { data: customersResult } = useCustomers({ pageSize: 300 })
  const allCustomers = customersResult?.data ?? []
  const createActivity = useCreateActivity()
  const updateActivity = useUpdateActivity()
  const saveCallDetail = useSaveCallDetail()

  const selectedType: ActivityType | undefined = activityTypes.find(t => t.id === typeId)
  const isCallType = selectedType?.category === 'call'

  const { data: targetRows = [] } = useTargetStatus({ isActive: true })
  const { data: recentActsResult } = useActivities({ customerId: customerId || undefined, pageSize: 3 })
  const recentActivities = recentActsResult?.data ?? []

  const activeTarget = typeId && selectedType ? targetRows.find(t => {
    if (selectedType.category === 'visit' && t.type_code === 'visits_count') return true
    if (selectedType.category === 'call' && t.type_code === 'calls_count') return true
    return false
  }) : null

  useEffect(() => {
    if (!existing) return
    setTypeId(existing.type_id)
    setOutcomeType(existing.outcome_type)
    setOutcomeNotes(existing.outcome_notes ?? '')
    setRefuseReason(existing.refuse_reason ?? '')
    setClosedReason(existing.closed_reason ?? '')
    setActivityDate(existing.activity_date)
    if (existing.start_time) setStartTime(new Date(existing.start_time).toTimeString().slice(0, 5))
    if (existing.end_time) setEndTime(new Date(existing.end_time).toTimeString().slice(0, 5))
    if (existing.gps_lat && existing.gps_lng) setGpsCoords({ lat: existing.gps_lat, lng: existing.gps_lng })
    const cd = (existing as any).call_detail
    if (cd) {
      setCallDirection(cd.direction ?? 'outbound')
      setCallResult(cd.call_result ?? '')
      setCallAttempts(cd.attempt_count ?? 1)
      setCallPhone(cd.phone_number ?? '')
      setCallCallbackAt(cd.callback_at ? cd.callback_at.slice(0, 16) : '')
      setCallRecordingUrl(cd.call_recording_url ?? '')
    }
    if (existing.customer_id && !urlCustomerId) setSelectedCustomerId(existing.customer_id)
  }, [existing])

  useEffect(() => {
    if (!customerId || (outcomeType !== 'order_placed' && outcomeType !== 'agreed_order')) {
      setCustomerOrders([])
      return
    }
    setLoadingOrders(true)
    supabase
      .from('sales_orders')
      .select('id, order_number, total_amount, status')
      .eq('customer_id', customerId)
      .in('status', ['draft', 'confirmed', 'delivered', 'completed'])
      .order('created_at', { ascending: false })
      .limit(20)
      .then(({ data }) => {
        setCustomerOrders((data ?? []) as any[])
        setLoadingOrders(false)
      })
  }, [customerId, outcomeType])

  const [resolvedPlanId, setResolvedPlanId] = useState<string | null>(null)

  useEffect(() => {
    if (planType === 'visit' && planItemId) {
      supabase
        .from('visit_plan_items')
        .select('plan_id')
        .eq('id', planItemId)
        .maybeSingle()
        .then(({ data }) => {
          if (data?.plan_id) {
            setResolvedPlanId(data.plan_id)
          }
        })
    }
  }, [planType, planItemId])

  if (planType === 'visit' && planItemId) {
    return (
      <div className="page-container animate-enter">
        <PageHeader
          title="تنبيه: تنفيذ زيارة خطة"
          subtitle="تسجيل الأنشطة للزيارات المخططة"
          breadcrumbs={[
            { label: 'الأنشطة', path: '/activities/list' },
            { label: 'تنبيه' },
          ]}
        />
        <div className="edara-card p-6 text-center text-amber-600 max-w-md mx-auto mt-8 flex flex-col items-center">
          <h2 className="text-lg font-bold mb-2">تنبيه أمني وصحي للبيانات</h2>
          <p className="text-sm text-secondary mb-6 leading-relaxed">
            تنفيذ زيارات الخطة وتسجيل أنشطتها يتم حصرياً من شاشة "وضع التنفيذ الميداني" للزيارات، وذلك لضمان المزامنة الذرية والتحقق الجغرافي السليم للـ GPS.
            لا يمكن استخدام هذا النموذج اليدوي لزيارة خطة.
          </p>
          <div className="flex flex-col gap-2 w-full">
            <Button
              onClick={() => {
                if (resolvedPlanId) {
                  navigate(`/activities/visit-plans/${resolvedPlanId}/execute`)
                } else {
                  navigate('/activities/visit-plans')
                }
              }}
              className="w-full"
            >
              {resolvedPlanId ? 'الانتقال إلى شاشة تنفيذ الزيارة' : 'الذهاب إلى خطط الزيارات'}
            </Button>
            <Button
              variant="secondary"
              onClick={() => navigate(-1)}
              className="w-full"
            >
              العودة للصفحة السابقة
            </Button>
          </div>
        </div>
      </div>
    )
  }

  const availableTypes = activityTypes.filter(t => !planType || t.category === planType)

  const requiresGPS = selectedType?.requires_gps ?? false
  const gpsBlocking = requiresGPS && !gpsCoords

  function validate(): string | null {
    if (!typeId) return 'اختر نوع النشاط'
    if (!outcomeType) return 'اختر نتيجة النشاط'
    if (!activityDate) return 'اختر تاريخ النشاط'
    if (gpsBlocking) return 'يتطلب هذا النوع تحديد موقع GPS'
    if (isCallType && !callResult) return 'اختر نتيجة المكالمة'
    if (selectedType?.requires_customer && !customerId && !planItemId) {
      return 'يتطلب هذا النوع اختيار عميل'
    }
    return null
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    const err = validate()
    if (err) { toast.error(err); return }
    setSaving(true)

    const buildTime = (t: string) => t ? `${activityDate}T${t}:00` : null

    let distanceMeters: number | null = null
    const cust = customerData as any
    if (gpsCoords && cust?.gps_lat && cust?.gps_lng) {
      const R = 6371000
      const lat1 = gpsCoords.lat * Math.PI / 180
      const lat2 = (cust.gps_lat as number) * Math.PI / 180
      const dLat = lat2 - lat1
      const dLng = ((cust.gps_lng as number) - gpsCoords.lng) * Math.PI / 180
      const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2
      distanceMeters = Math.round(R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)))
    }

    const payload: ActivityInput = {
      type_id:             typeId,
      employee_id:         '',
      customer_id:         customerId || null,
      visit_plan_item_id:  planType === 'visit' ? planItemId || null : null,
      call_plan_item_id:   planType === 'call' ? planItemId || null : null,
      outcome_type:        outcomeType as ActivityOutcome,
      outcome_notes:       outcomeNotes || null,
      refuse_reason:       refuseReason || null,
      closed_reason:       closedReason || null,
      activity_date:       activityDate,
      start_time:          buildTime(startTime),
      end_time:            buildTime(endTime),
      order_id:            orderId || null,
      collection_id:       collectionId || null,
      followup_activity_id: null,
      metadata:            {},
      gps_lat:             gpsCoords?.lat ?? null,
      gps_lng:             gpsCoords?.lng ?? null,
      gps_verified:        !!gpsCoords,
      distance_meters:     distanceMeters,
    }

    const callDetailPayload: CallDetailInput | null = isCallType ? {
      direction:           callDirection,
      call_result:         callResult as CallResult || null,
      attempt_count:       callAttempts,
      phone_number:        callPhone || null,
      callback_at:         callCallbackAt ? `${callCallbackAt}:00` : null,
      call_recording_url:  callRecordingUrl || null,
    } : null

    try {
      if (activityId) {
        updateActivity.mutate(
          { id: activityId, input: payload },
          {
            onSuccess: async () => {
              if (callDetailPayload) {
                try {
                  await saveCallDetail.mutateAsync({ activityId, input: callDetailPayload })
                } catch {
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
        createActivity.mutate(payload, {
          onSuccess: async (act) => {
            if (callDetailPayload) {
              try {
                await saveCallDetail.mutateAsync({ activityId: act.id, input: callDetailPayload })
              } catch {
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

      <form className="ds-field-activity-form" onSubmit={handleSubmit}>
        <FormSection title="بيانات النشاط">
          <div className="form-group">
            <label className="form-label" htmlFor="activity-type">
              نوع النشاط <span className="form-required">*</span>
            </label>
            <select
              id="activity-type"
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

          {!urlCustomerId && !planItemId && typeId && selectedType?.requires_customer && (
            <div className="form-group">
              <label className="form-label" htmlFor="activity-customer">
                العميل <span className="form-required">*</span>
              </label>
              {allCustomers.length > 0 ? (
                <select
                  id="activity-customer"
                  className="form-select"
                  value={selectedCustomerId}
                  onChange={e => setSelectedCustomerId(e.target.value)}
                >
                  <option value="">-- اختر العميل --</option>
                  {allCustomers.map(c => (
                    <option key={c.id} value={c.id}>{c.name} ({c.code})</option>
                  ))}
                </select>
              ) : (
                <div className="text-sm text-muted p-2">جاري تحميل العملاء...</div>
              )}
            </div>
          )}

          {typeId && (
            <div className="form-group">
              <span className="form-label">
                الموقع الجغرافي
                {requiresGPS && <span className="form-required"> *</span>}
              </span>
              <GPSStatusIndicator
                requiresGPS={requiresGPS}
                onCoordsChange={setGpsCoords}
                value={gpsCoords}
              />
            </div>
          )}

          {activeTarget && activeTarget.remaining_value > 0 && (
            <div className="bg-primary-light border border-primary rounded-md p-3 flex gap-2 items-center text-primary-dark">
              <Target size={18} className="text-primary" />
              <div className="flex-1 text-sm font-medium">
                هذا النشاط سيقربك من هدفك! ({activeTarget.name})
              </div>
              <div className="text-[11px] font-semibold bg-primary text-white px-2 py-0.5 rounded-full">
                باقي {activeTarget.remaining_value}
              </div>
            </div>
          )}

          {customerId && recentActivities.length > 0 && !activityId && (
            <div className="bg-surface-2 rounded-md p-3 border-l-4 border-secondary">
              <div className="flex items-center gap-2 mb-2">
                <Clock size={14} className="text-muted" />
                <span className="text-xs font-semibold text-secondary">تاريخ العميل السريع</span>
              </div>
              <div className="flex flex-col gap-2">
                {recentActivities.map(act => {
                  const outcomeLabel = getOutcomeOptions((act as any).type?.category).find(o => o.value === act.outcome_type)?.label ?? act.outcome_type
                  const date = new Date(act.activity_date).toLocaleDateString('ar-EG-u-nu-latn', { day: 'numeric', month: 'short' })
                  return (
                    <div key={act.id} className="flex justify-between text-[11px]">
                      <span className="text-secondary">• {(act as any).type?.name}</span>
                      <span className="font-semibold text-primary">{outcomeLabel}</span>
                      <span className="text-muted">{date}</span>
                    </div>
                  )
                })}
              </div>
            </div>
          )}
        </FormSection>

        <FormSection title="النتيجة والربط">
          <div className="form-group">
            <label className="form-label" htmlFor="activity-outcome">
              نتيجة النشاط <span className="form-required">*</span>
            </label>
            <select
              id="activity-outcome"
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

          {(outcomeType === 'refused' || outcomeType === 'not_interested') && (
            <div className="form-group">
              <label className="form-label" htmlFor="activity-refuse-reason">سبب الرفض</label>
              <input
                id="activity-refuse-reason"
                className="form-input"
                value={refuseReason}
                onChange={e => setRefuseReason(e.target.value)}
                placeholder="اذكر سبب الرفض..."
              />
            </div>
          )}

          {outcomeType === 'closed' && (
            <div className="form-group">
              <label className="form-label" htmlFor="activity-closed-reason">سبب الإغلاق</label>
              <input
                id="activity-closed-reason"
                className="form-input"
                value={closedReason}
                onChange={e => setClosedReason(e.target.value)}
                placeholder="ما سبب إغلاق هذا النشاط..."
              />
            </div>
          )}

          {(outcomeType === 'order_placed' || outcomeType === 'agreed_order') && customerId && (
            <div className="act-link-section">
              <div className="act-link-title">🛒 ربط بطلب بيع</div>
              {loadingOrders ? (
                <div className="skeleton h-9 rounded-md" />
              ) : customerOrders.length > 0 ? (
                <select className="form-select" value={orderId} onChange={e => setOrderId(e.target.value)}>
                  <option value="">— بدون ربط —</option>
                  {customerOrders.map(o => (
                    <option key={o.id} value={o.id}>
                      {o.order_number} • {o.total_amount?.toLocaleString('en-US')} ج.م ({o.status === 'draft' ? 'مسودة' : o.status === 'confirmed' ? 'مؤكد' : o.status === 'delivered' ? 'مسلّم' : 'مكتمل'})
                    </option>
                  ))}
                </select>
              ) : (
                <div className="text-xs text-muted p-2">لا توجد طلبات لهذا العميل</div>
              )}
              <button
                type="button"
                className="act-link-create-btn"
                onClick={() => {
                  const returnUrl = encodeURIComponent(window.location.pathname + window.location.search)
                  navigate(`/sales/orders/new?customerId=${customerId}&returnUrl=${returnUrl}`)
                }}
              >
                + إنشاء طلب بيع جديد
              </button>
            </div>
          )}

          {outcomeType === 'collection' && customerId && (
            <div className="act-link-section">
              <div className="act-link-title">💰 تحصيل</div>
              <button
                type="button"
                className="act-link-create-btn"
                onClick={() => navigate(`/finance/payments?customerId=${customerId}`)}
              >
                إنشاء سند تحصيل →
              </button>
              <div className="text-xs text-muted mt-1">
                سيتم إنشاء سند تحصيل مستقل — يمكن ربطه لاحقاً
              </div>
            </div>
          )}

          {isCallType && (
            <div className="act-call-section">
              <div className="act-call-section-title">📞 تفاصيل المكالمة</div>
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

                <div className="form-group col-span-full">
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
        </FormSection>

        <FormSection title="التوقيت والملاحظات">
          <FormGrid columns={3}>
            <div className="form-group">
              <label className="form-label" htmlFor="activity-date">
                تاريخ النشاط <span className="form-required">*</span>
              </label>
              <input
                id="activity-date"
                type="date"
                className="form-input"
                value={activityDate}
                onChange={e => setActivityDate(e.target.value)}
                required
              />
            </div>

            <div className="form-group">
              <label className="form-label" htmlFor="activity-start-time">وقت البدء</label>
              <input
                id="activity-start-time"
                type="time"
                className="form-input"
                value={startTime}
                onChange={e => setStartTime(e.target.value)}
              />
            </div>

            <div className="form-group">
              <label className="form-label" htmlFor="activity-end-time">وقت الانتهاء</label>
              <input
                id="activity-end-time"
                type="time"
                className="form-input"
                value={endTime}
                onChange={e => setEndTime(e.target.value)}
              />
            </div>
          </FormGrid>

          <div className="form-group">
            <label className="form-label" htmlFor="activity-outcome-notes">ملاحظات النتيجة</label>
            <textarea
              id="activity-outcome-notes"
              className="form-textarea"
              value={outcomeNotes}
              onChange={e => setOutcomeNotes(e.target.value)}
              rows={3}
              placeholder="أضف تفاصيل حول نتيجة النشاط..."
            />
          </div>

          {gpsBlocking && (
            <div className="act-form-gps-warning">
              ⚠ يتطلب نوع هذا النشاط تحديد موقع GPS قبل الحفظ
            </div>
          )}

          {isCallType && callResult && (
            <div className="act-call-ready-hint">
              ✓ ستُحفظ تفاصيل المكالمة تلقائياً مع النشاط
            </div>
          )}
        </FormSection>

        <FormActions>
          <Button
            type="button"
            variant="secondary"
            onClick={() => navigate(-1)}
            disabled={saving}
            touchTarget
          >
            إلغاء
          </Button>
          <Button type="submit" disabled={saving || gpsBlocking} touchTarget>
            {saving ? 'جاري الحفظ...' : activityId ? 'حفظ التعديلات' : 'تسجيل النشاط'}
          </Button>
        </FormActions>
      </form>
    </div>
  )
}
