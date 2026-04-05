/**
 * VisitExecutionMode — وضع التنفيذ الذكي للمندوب
 * شاشة مخصصة للتنفيذ الميداني (Mobile-first):
 *
 * - بطاقة الزيارة الحالية (اسم + هاتف + عنوان + رصيد + غرض)
 * - زر "بدء الزيارة" → GPS + Timer
 * - استبيان إجباري (حسب purpose_type)
 * - زر "إنهاء الزيارة" → GPS مزدوج + حفظ النشاط
 * - زر "تخطي" + سبب
 * - شريط تقدم علوي
 * - زر التوجه 🗺️
 */
import { useState, useMemo, useCallback } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import {
  useVisitPlan, useVisitPlanItems, useUpdateVisitPlanItem,
  useChecklistTemplates, useCreateActivity, useActivityTypes,
  useSaveChecklistResponses,
} from '@/hooks/useQueryHooks'
import useGeoPermission from '@/hooks/useGeoPermission'
import type { GeoCoords } from '@/hooks/useGeoPermission'
import type { ChecklistResponseInput, VisitPlanItem, ActivityInput, ActivityOutcome } from '@/lib/types/activities'
import GeoPermissionBanner from '@/components/shared/GeoPermissionBanner'
import GeoPermissionDialog from '@/components/shared/GeoPermissionDialog'
import VisitTimer from '@/components/shared/VisitTimer'
import ChecklistForm from '@/components/shared/ChecklistForm'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import {
  Play, CheckCircle, SkipForward, Phone, MapPin,
  Navigation, CreditCard, Target, ChevronLeft, ChevronRight,
  ArrowLeft, Loader2, PartyPopper,
} from 'lucide-react'

// Skip reasons
const SKIP_REASONS = [
  'محل مغلق', 'العميل غير متاح', 'تأجيل بطلب العميل',
  'ظروف طارئة', 'مسافة بعيدة / وقت غير كافٍ', 'أخرى',
]

const PURPOSE_LABELS: Record<string, string> = {
  sales: 'مبيعات', collection: 'تحصيل', activation: 'تنشيط',
  promotion: 'ترويج', followup: 'متابعة', service: 'خدمة',
}

export default function VisitExecutionMode() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()

  // ── Data
  const { data: plan, isLoading: planLoading } = useVisitPlan(id)
  const { data: items = [], isLoading: itemsLoading } = useVisitPlanItems(id)
  const updateItem = useUpdateVisitPlanItem()
  const createActivity = useCreateActivity()
  const saveResponses = useSaveChecklistResponses()
  const { data: activityTypes = [] } = useActivityTypes()
  const geo = useGeoPermission()

  // ── نوع النشاط: visit_planned
  const visitTypeId = useMemo(
    () => activityTypes.find(t => t.code === 'visit_planned')?.id || '',
    [activityTypes]
  )

  // ── State
  const [activeItemId,       setActiveItemId]       = useState<string | null>(null)
  const [startTime,          setStartTime]          = useState<string | null>(null)
  const [startGPS,           setStartGPS]           = useState<GeoCoords | null>(null)
  const [skipModal,          setSkipModal]          = useState<VisitPlanItem | null>(null)
  const [skipReason,         setSkipReason]         = useState('')
  const [skipCustom,         setSkipCustom]         = useState('')
  const [skipping,           setSkipping]           = useState(false)
  const [checklistReady,     setChecklistReady]     = useState(false)
  const [checklistResponses, setChecklistResponses] = useState<ChecklistResponseInput[]>([])
  const [completing,         setCompleting]         = useState(false)
  const [showGeoDialog,      setShowGeoDialog]      = useState(false) // pre-permission dialog

  // ── Sorted items
  const sortedItems = useMemo(
    () => [...items].sort((a, b) => (a.sequence ?? 0) - (b.sequence ?? 0)),
    [items]
  )

  // ── Current item (first pending or active item)
  const currentItem = useMemo(() => {
    if (activeItemId) return sortedItems.find(i => i.id === activeItemId)
    return sortedItems.find(i => i.status === 'in_progress' || i.status === 'pending')
  }, [sortedItems, activeItemId])

  const currentIndex = currentItem ? sortedItems.indexOf(currentItem) : -1
  const nextItem = currentIndex >= 0 ? sortedItems[currentIndex + 1] : null

  // ── Checklist templates for current visit purpose
  const purposeType = currentItem?.purpose_type || undefined
  const { data: templates = [] } = useChecklistTemplates(
    currentItem ? { category: 'visit', purposeType } : undefined
  )
  const allQuestions = useMemo(
    () => templates.flatMap(t => (t.questions ?? []).map(q => ({ ...q, _templateId: t.id }))),
    [templates]
  )
  const mandatoryTemplates = templates.filter(t => t.is_mandatory)

  // ── Progress stats
  const stats = useMemo(() => {
    const completed = sortedItems.filter(i => i.status === 'completed').length
    const skipped = sortedItems.filter(i => i.status === 'skipped').length
    const total = sortedItems.length
    const done = completed + skipped
    const pct = total > 0 ? Math.round((done / total) * 100) : 0
    return { completed, skipped, total, done, pct }
  }, [sortedItems])

  const isActive = activeItemId === currentItem?.id && startTime != null

  // ── Start Visit
  const [isStarting, setIsStarting] = useState(false)

  const handleStartVisit = useCallback(async () => {
    if (!currentItem || !id) return

    // ── Explain before Ask: إذا كانت الصلاحية لم تُمنح بعد ──
    if (geo.status === 'prompt') {
      setShowGeoDialog(true)
      return
    }

    setIsStarting(true)

    try {
      const geoResult = await geo.requestLocation()
      if (!geoResult.ok && geoResult.reason === 'denied') {
        setIsStarting(false)
        return
      }
      const coords = geoResult.ok ? geoResult.coords : null

      const now = new Date().toISOString()
      setStartTime(now)
      setStartGPS(coords)
      setActiveItemId(currentItem.id)
      setChecklistReady(false)
      setChecklistResponses([])

      // Update item to in_progress
      await updateItem.mutateAsync({
        itemId: currentItem.id,
        planId: id,
        input: {
          status: 'in_progress',
          actual_start_time: now,
          gps_lat: coords?.lat ?? null,
          gps_lng: coords?.lng ?? null,
        },
      })
    } catch (err: any) {
      toast.error(err?.message || 'فشل بدء الزيارة — تحقق من الصلاحيات')
      // Reset state on failure
      setActiveItemId(null)
      setStartTime(null)
      setStartGPS(null)
    } finally {
      setIsStarting(false)
    }
  }, [currentItem, id, geo, updateItem])

  // ── موافقة dialog التوضيحي ──
  const handleGeoDialogAllow = useCallback(async () => {
    setShowGeoDialog(false)
    if (!currentItem || !id) return
    setIsStarting(true)
    try {
      const geoResult = await geo.requestLocation()
      if (!geoResult.ok && geoResult.reason === 'denied') { setIsStarting(false); return }
      const coords = geoResult.ok ? geoResult.coords : null
      const now = new Date().toISOString()
      setStartTime(now)
      setStartGPS(coords)
      setActiveItemId(currentItem.id)
      setChecklistReady(false)
      setChecklistResponses([])
      await updateItem.mutateAsync({
        itemId: currentItem.id,
        planId: id,
        input: { status: 'in_progress', actual_start_time: now, gps_lat: coords?.lat ?? null, gps_lng: coords?.lng ?? null },
      })
    } catch (err: any) {
      toast.error(err?.message || 'فشل بدء الزيارة')
      setActiveItemId(null); setStartTime(null); setStartGPS(null)
    } finally {
      setIsStarting(false)
    }
  }, [currentItem, id, geo, updateItem])

  // ── Complete Visit  
  const handleCompleteVisit = useCallback(async () => {
    if (!currentItem || !id || !plan) return
    if (!visitTypeId) {
      toast.error('لم يتم تحميل أنواع الأنشطة — أعد المحاولة')
      return
    }
    setCompleting(true)

    try {
      // 1) GPS النهاية
      const geoResultEnd = await geo.requestLocation()
      const endCoords = geoResultEnd.ok ? geoResultEnd.coords : null
      const endTime = new Date().toISOString()

      // 2) حساب المسافة
      let distance: number | null = null
      if (startGPS && endCoords) {
        distance = haversine(startGPS.lat, startGPS.lng, endCoords.lat, endCoords.lng)
      }

      // 3) إنشاء سجل النشاط (activity) — يجعل الزيارة تظهر في سجل الأنشطة واللوحات
      const activityPayload: ActivityInput = {
        type_id: visitTypeId,
        employee_id: plan.employee_id,
        customer_id: currentItem.customer_id,
        visit_plan_item_id: currentItem.id,
        subject: currentItem.purpose || PURPOSE_LABELS[currentItem.purpose_type || ''] || 'زيارة مخططة',
        subject_type: currentItem.purpose_type || null,
        outcome_type: 'visited' as ActivityOutcome,
        outcome_notes: null,
        gps_lat: startGPS?.lat ?? null,
        gps_lng: startGPS?.lng ?? null,
        gps_verified: !!(startGPS && endCoords),
        distance_meters: distance ? Math.round(distance) : null,
        start_time: startTime,
        end_time: endTime,
        activity_date: new Date().toISOString().slice(0, 10),
        metadata: {
          end_gps_lat: endCoords?.lat ?? null,
          end_gps_lng: endCoords?.lng ?? null,
          distance_start_end: distance,
          source: 'visit_execution_mode',
        },
      }

      const createdActivity = await createActivity.mutateAsync(activityPayload)

      // 4) حفظ إجابات الاستبيان مع activity_id الحقيقي
      if (checklistResponses.length > 0) {
        const responsesWithRealId = checklistResponses.map(r => ({
          ...r,
          activity_id: createdActivity.id,
        }))
        try {
          await saveResponses.mutateAsync(responsesWithRealId)
        } catch {
          // لا نوقف التدفق — الإجابات محفوظة أيضاً في metadata كنسخة احتياطية
          console.warn('فشل حفظ إجابات الاستبيان في الجدول المخصص — محفوظة في metadata')
        }
      }

      // 5) تحديث بند الخطة — ربط بالنشاط المُنشأ
      const metadataPayload: Record<string, unknown> = {
        distance_start_end: distance,
        activity_created: true,
      }
      if (checklistResponses.length > 0) {
        metadataPayload.checklist_completed = true
        metadataPayload.checklist_responses = checklistResponses.map(r => ({
          question_id: r.question_id,
          template_id: r.template_id,
          answer_value: r.answer_value,
          answer_json: r.answer_json,
        }))
      }

      await updateItem.mutateAsync({
        itemId: currentItem.id,
        planId: id,
        input: {
          status: 'completed',
          activity_id: createdActivity.id,
          actual_end_time: endTime,
          end_gps_lat: endCoords?.lat ?? null,
          end_gps_lng: endCoords?.lng ?? null,
          metadata: metadataPayload,
        },
      })

      toast.success('✓ تم إنهاء الزيارة وتسجيل النشاط بنجاح')
      
      // Reset state
      setActiveItemId(null)
      setStartTime(null)
      setStartGPS(null)
      setChecklistReady(false)
      setChecklistResponses([])
    } catch (err: any) {
      toast.error(err?.message || 'فشل إنهاء الزيارة')
    } finally {
      setCompleting(false)
    }
  }, [currentItem, id, plan, visitTypeId, geo, startGPS, startTime, checklistResponses, createActivity, saveResponses, updateItem])

  // ── Skip
  const handleSkip = useCallback(async () => {
    if (!skipModal || !id) return
    const reason = skipReason === 'أخرى' ? (skipCustom || 'أخرى') : skipReason
    if (!reason) { toast.error('اختر سبب التخطي'); return }
    setSkipping(true)
    try {
      await updateItem.mutateAsync({
        itemId: skipModal.id,
        planId: id,
        input: { status: 'skipped', skip_reason: reason },
      })
      toast.success('تم تخطي الزيارة')
      setSkipModal(null)
      setSkipReason('')
      setSkipCustom('')
      setActiveItemId(null)
      setStartTime(null)
    } catch (err: any) {
      toast.error(err?.message || 'فشل التخطي')
    } finally {
      setSkipping(false)
    }
  }, [skipModal, id, skipReason, skipCustom, updateItem])

  // ── Navigate to Google Maps
  const openNavigation = useCallback((item: VisitPlanItem) => {
    const cust = item.customer
    if (!cust) return
    if (cust.latitude && cust.longitude) {
      window.open(`https://www.google.com/maps/dir/?api=1&destination=${cust.latitude},${cust.longitude}`, '_blank')
    }
  }, [])

  // ── Loading
  if (planLoading || itemsLoading) {
    return (
      <div className="page-container animate-enter">
        <div className="edara-card p-6 text-center">
          <Loader2 size={32} className="animate-spin mx-auto mb-3 text-primary" />
          <p className="text-muted">جاري تحميل بيانات الزيارة...</p>
        </div>
      </div>
    )
  }

  if (!plan || sortedItems.length === 0) {
    return (
      <div className="page-container animate-enter flex-1 flex flex-col items-center justify-center min-h-[50vh]">
        <div className="empty-state p-8">
          <p className="empty-state-title">الزيارة غير موجودة المرجو الرجوع للجدول</p>
          <Button variant="secondary" onClick={() => navigate(-1)}>العودة</Button>
        </div>
      </div>
    )
  }

  // All done?
  const allDone = sortedItems.every(i => i.status === 'completed' || i.status === 'skipped' || i.status === 'missed')

  return (
    <div className="page-container vem animate-enter">
      {/* ── Header bar ── */}
      <div className="vem-header">
        <button className="vem-back" onClick={() => navigate(`/activities/visit-plans/${id}`)}>
          <ArrowLeft size={20} />
        </button>
        <div className="vem-header-info">
          <span className="vem-header-title">خطة {new Date(plan.plan_date).toLocaleDateString('ar-EG', { day: 'numeric', month: 'short' })}</span>
          <span className="vem-header-progress">مكتمل {stats.done}/{stats.total}</span>
        </div>
        <div className="vem-progress-bar">
          <div className="vem-progress-fill" style={{ width: `${stats.pct}%` }} />
        </div>
      </div>

      {/* ── GPS Banner ── */}
      <GeoPermissionBanner
        showOnPrompt={false}
        contextMessage="تسجيل الزيارة يتطلب تحديد موقعك للتحقق من وصولك لموقع العميل"
      />

      {/* ── All Done State ── */}
      {allDone ? (
        <div className="vem-done">
          <PartyPopper size={48} />
          <h2>تهانينا! 🎉</h2>
          <p>تم إكمال جميع الزيارات</p>
          <div className="vem-done-stats">
            <span className="vem-done-stat vem-done-stat--success">✓ {stats.completed} مكتملة</span>
            <span className="vem-done-stat vem-done-stat--skip">↩ {stats.skipped} متخطاة</span>
          </div>
          <Button onClick={() => navigate(`/activities/visit-plans/${id}`)}>
            العودة للخطة
          </Button>
        </div>
      ) : currentItem ? (
        <>
          {/* ── Current Visit Card ── */}
          <div className={`vem-card ${isActive ? 'vem-card--active' : ''}`}>
            <div className="vem-card-seq">#{currentIndex + 1}</div>
            
            <div className="vem-card-body">
              <h3 className="vem-card-name">{currentItem.customer?.name || 'عميل'}</h3>
              <span className="vem-card-code">{currentItem.customer?.code}</span>

              {/* Phone */}
              {currentItem.customer?.phone && (
                <a href={`tel:${currentItem.customer.phone}`} className="vem-card-row vem-card-phone">
                  <Phone size={14} /> {currentItem.customer.phone}
                </a>
              )}

              {/* Location */}
              {(currentItem.customer?.latitude || currentItem.customer?.longitude) && (
                <div className="vem-card-row">
                  <MapPin size={14} />
                  <span>موقع محدد</span>
                  <button className="vem-nav-btn" onClick={() => openNavigation(currentItem)}>
                    <Navigation size={14} /> توجه
                  </button>
                </div>
              )}

              {/* Purpose */}
              {currentItem.purpose_type && (
                <div className="vem-card-row">
                  <Target size={14} />
                  <span>{PURPOSE_LABELS[currentItem.purpose_type] || currentItem.purpose_type}</span>
                  {currentItem.priority === 'high' && (
                    <span className="vem-priority-badge">⚡ عالية</span>
                  )}
                </div>
              )}

              {/* Timer */}
              {isActive && startTime && (
                <div className="vem-timer-row">
                  <VisitTimer startTime={startTime} isRunning={true} size="lg" />
                </div>
              )}
            </div>

            {/* Main Action */}
            {!isActive ? (
              <button className="vem-start-btn" onClick={handleStartVisit} disabled={isStarting}>
                {isStarting ? (
                  <><Loader2 size={22} className="vpw-spin" /> جاري التحضير...</>
                ) : (
                  <><Play size={22} /> بدء الزيارة</>
                )}
              </button>
            ) : (
              <div className="vem-active-actions">
                {/* Checklist */}
                {allQuestions.length > 0 && (
                  <div className="vem-checklist-section">
                    <h4 className="vem-checklist-title">📋 استبيان الزيارة</h4>
                    <ChecklistForm
                      questions={allQuestions}
                      activityId={currentItem.id}
                      templateId={mandatoryTemplates[0]?.id || templates[0]?.id || ''}
                      onChange={(responses, complete) => {
                        setChecklistResponses(responses)
                        setChecklistReady(complete)
                      }}
                    />
                  </div>
                )}

                <button
                  className={`vem-complete-btn ${allQuestions.length === 0 || checklistReady ? '' : 'vem-complete-btn--disabled'}`}
                  onClick={handleCompleteVisit}
                  disabled={completing || (mandatoryTemplates.length > 0 && !checklistReady)}
                >
                  {completing ? (
                    <><Loader2 size={18} className="vpw-spin" /> جاري الإنهاء...</>
                  ) : (
                    <><CheckCircle size={18} /> إنهاء الزيارة</>
                  )}
                </button>
              </div>
            )}

            {/* Skip */}
            <button
              className="vem-skip-btn"
              onClick={() => { setSkipModal(currentItem); setSkipReason('') }}
            >
              <SkipForward size={14} /> تخطي
            </button>
          </div>

          {/* ── Upcoming visits ── */}
          {nextItem && (
            <div className="vem-upcoming">
              <span className="vem-upcoming-label">التالي:</span>
              <span className="vem-upcoming-name">#{currentIndex + 2} {nextItem.customer?.name}</span>
              {nextItem.purpose_type && (
                <span className="vem-upcoming-purpose">— {PURPOSE_LABELS[nextItem.purpose_type]}</span>
              )}
            </div>
          )}

          {/* ── All items sidebar ── */}
          <div className="vem-items-list">
            {sortedItems.map((item, idx) => (
              <div
                key={item.id}
                className={`vem-item-mini ${item.id === currentItem?.id ? 'vem-item-mini--current' : ''} ${item.status === 'completed' ? 'vem-item-mini--done' : ''} ${item.status === 'skipped' ? 'vem-item-mini--skip' : ''}`}
              >
                <span className="vem-item-mini-seq">{idx + 1}</span>
                <span className="vem-item-mini-name">{item.customer?.name}</span>
                <span className="vem-item-mini-status">
                  {item.status === 'completed' && '✓'}
                  {item.status === 'skipped' && '↩'}
                  {item.status === 'in_progress' && '⏱'}
                </span>
              </div>
            ))}
          </div>
        </>
      ) : null}

      {/* ── Skip Modal ── */}
      <ResponsiveModal open={!!skipModal} onClose={() => setSkipModal(null)} title="تخطي الزيارة">
        <div className="flex flex-col gap-3">
          <p className="text-sm text-muted">
            اختر سبب تخطي زيارة {skipModal?.customer?.name}
          </p>
          <div className="vp-skip-reasons">
            {SKIP_REASONS.map(r => (
              <button
                key={r}
                type="button"
                className={`vp-skip-reason-btn ${skipReason === r ? 'vp-skip-reason-btn--active' : ''}`}
                onClick={() => setSkipReason(r)}
              >
                {r}
              </button>
            ))}
          </div>
          {skipReason === 'أخرى' && (
            <input
              className="form-input"
              placeholder="اكتب السبب..."
              value={skipCustom}
              onChange={e => setSkipCustom(e.target.value)}
            />
          )}
          <Button
            onClick={handleSkip}
            disabled={!skipReason || skipping}
            variant="danger"
          >
            {skipping ? 'جاري التخطي...' : 'تأكيد التخطي'}
          </Button>
        </div>
      </ResponsiveModal>

      {/* ── Pre-permission Dialog ── */}
      <GeoPermissionDialog
        open={showGeoDialog}
        context="visit"
        onAllow={handleGeoDialogAllow}
        onDismiss={() => setShowGeoDialog(false)}
      />

      <style>{styles}</style>
    </div>
  )
}

// ── Haversine distance (meters)
function haversine(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000
  const dLat = (lat2 - lat1) * Math.PI / 180
  const dLng = (lng2 - lng1) * Math.PI / 180
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) *
    Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLng / 2) ** 2
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

const styles = `
  .vem { max-width: 600px; margin: 0 auto; padding-bottom: var(--space-8); }
  .vem-header {
    display: flex; align-items: center; gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    background: var(--bg-surface); border-radius: var(--radius-lg);
    margin-bottom: var(--space-4); flex-wrap: wrap;
    box-shadow: 0 1px 3px rgba(0,0,0,0.06);
  }
  .vem-back { border: none; background: none; cursor: pointer; color: var(--text-secondary); padding: 4px; }
  .vem-header-info { flex: 1; min-width: 0; }
  .vem-header-title { font-weight: 700; font-size: var(--text-sm); display: block; }
  .vem-header-progress { font-size: var(--text-xs); color: var(--text-muted); }
  .vem-progress-bar {
    width: 100%; height: 6px; background: var(--neutral-200);
    border-radius: 99px; overflow: hidden;
  }
  .vem-progress-fill {
    height: 100%; background: var(--color-primary);
    border-radius: 99px; transition: width 0.5s ease;
  }
  /* Card */
  .vem-card {
    background: var(--bg-surface); border-radius: var(--radius-xl, 16px);
    border: 2px solid var(--border-light);
    padding: var(--space-5); margin-bottom: var(--space-4);
    position: relative; transition: all 0.2s ease;
  }
  .vem-card--active {
    border-color: var(--color-primary);
    box-shadow: 0 4px 20px rgba(37,99,235,0.1);
  }
  .vem-card-seq {
    position: absolute; top: var(--space-3); left: var(--space-3);
    background: var(--color-primary); color: white;
    font-weight: 700; font-size: var(--text-xs);
    padding: 2px 10px; border-radius: 99px;
  }
  .vem-card-body { display: flex; flex-direction: column; gap: var(--space-2); }
  .vem-card-name { font-size: var(--text-lg, 18px); font-weight: 700; margin: 0; color: var(--text-primary); }
  .vem-card-code { font-size: var(--text-xs); color: var(--text-muted); font-family: monospace; }
  .vem-card-row {
    display: flex; align-items: center; gap: var(--space-2);
    font-size: var(--text-sm); color: var(--text-secondary);
  }
  .vem-card-row svg { color: var(--text-muted); flex-shrink: 0; }
  .vem-card-phone {
    color: var(--color-primary); text-decoration: none;
    font-weight: 600; font-size: var(--text-sm);
    display: flex; align-items: center; gap: var(--space-2);
  }
  .vem-card-phone:hover { text-decoration: underline; }
  .vem-nav-btn {
    display: inline-flex; align-items: center; gap: 4px;
    padding: 4px 10px; background: var(--color-primary);
    color: white; border: none; border-radius: var(--radius-sm);
    font-size: 11px; font-weight: 600; cursor: pointer;
    margin-inline-start: auto; font-family: inherit;
  }
  .vem-nav-btn:hover { opacity: 0.9; }
  .vem-priority-badge {
    padding: 2px 8px; background: var(--color-danger-light);
    color: var(--color-danger); border-radius: 99px;
    font-size: 11px; font-weight: 600; margin-inline-start: auto;
  }
  .vem-timer-row {
    display: flex; align-items: center; justify-content: center;
    padding: var(--space-3) 0; margin-top: var(--space-2);
    border-top: 1px solid var(--border-light);
  }
  /* Action buttons */
  .vem-start-btn {
    display: flex; align-items: center; justify-content: center;
    gap: var(--space-2); width: 100%; padding: var(--space-4);
    background: var(--color-success); color: white;
    border: none; border-radius: var(--radius-lg);
    font-size: var(--text-base, 15px); font-weight: 700;
    cursor: pointer; margin-top: var(--space-4);
    min-height: 56px; font-family: inherit;
    transition: all 0.15s ease;
  }
  .vem-start-btn:hover { background: #15803d; transform: translateY(-1px); }
  .vem-active-actions {
    display: flex; flex-direction: column; gap: var(--space-4);
    margin-top: var(--space-4);
    border-top: 1px solid var(--border-light);
    padding-top: var(--space-4);
  }
  .vem-checklist-section {
    display: flex; flex-direction: column; gap: var(--space-3);
  }
  .vem-checklist-title {
    font-size: var(--text-sm); font-weight: 700; margin: 0;
    color: var(--text-primary);
  }
  .vem-complete-btn {
    display: flex; align-items: center; justify-content: center;
    gap: var(--space-2); width: 100%; padding: var(--space-4);
    background: var(--color-primary); color: white;
    border: none; border-radius: var(--radius-lg);
    font-size: var(--text-base, 15px); font-weight: 700;
    cursor: pointer; min-height: 52px; font-family: inherit;
    transition: all 0.15s ease;
  }
  .vem-complete-btn:hover:not(:disabled) { background: var(--color-primary-hover); }
  .vem-complete-btn--disabled {
    opacity: 0.5; cursor: not-allowed;
  }
  .vem-skip-btn {
    display: flex; align-items: center; justify-content: center;
    gap: 6px; width: 100%; padding: var(--space-2);
    background: none; color: var(--text-muted);
    border: none; cursor: pointer;
    font-size: var(--text-sm); font-family: inherit;
    margin-top: var(--space-2);
  }
  .vem-skip-btn:hover { color: var(--color-warning); }
  /* Upcoming */
  .vem-upcoming {
    display: flex; align-items: center; gap: var(--space-2);
    padding: var(--space-3) var(--space-4);
    background: var(--neutral-50); border-radius: var(--radius-md);
    font-size: var(--text-sm); margin-bottom: var(--space-3);
  }
  .vem-upcoming-label { color: var(--text-muted); font-weight: 500; }
  .vem-upcoming-name { font-weight: 600; }
  .vem-upcoming-purpose { color: var(--text-muted); }
  /* Items list */
  .vem-items-list {
    display: flex; flex-direction: column; gap: 2px;
    margin-top: var(--space-4);
  }
  .vem-item-mini {
    display: flex; align-items: center; gap: var(--space-2);
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-sm);
    font-size: var(--text-xs); color: var(--text-secondary);
  }
  .vem-item-mini--current {
    background: var(--color-primary-light);
    color: var(--color-primary); font-weight: 600;
  }
  .vem-item-mini--done { color: var(--color-success); }
  .vem-item-mini--skip { color: var(--text-muted); text-decoration: line-through; }
  .vem-item-mini-seq {
    width: 20px; height: 20px; display: inline-flex;
    align-items: center; justify-content: center;
    border-radius: 50%; background: var(--neutral-100);
    font-size: 10px; font-weight: 700; flex-shrink: 0;
  }
  .vem-item-mini--current .vem-item-mini-seq { background: var(--color-primary); color: white; }
  .vem-item-mini-name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .vem-item-mini-status { font-weight: 700; }
  /* Done */
  .vem-done {
    text-align: center; padding: var(--space-8) var(--space-4);
    background: var(--bg-surface); border-radius: var(--radius-xl, 16px);
  }
  .vem-done h2 { font-size: var(--text-xl, 20px); margin: var(--space-3) 0 var(--space-1); }
  .vem-done p { color: var(--text-muted); margin-bottom: var(--space-4); }
  .vem-done svg { color: var(--color-primary); }
  .vem-done-stats {
    display: flex; justify-content: center; gap: var(--space-4);
    margin-bottom: var(--space-5);
  }
  .vem-done-stat { font-weight: 600; font-size: var(--text-sm); }
  .vem-done-stat--success { color: var(--color-success); }
  .vem-done-stat--skip { color: var(--text-muted); }
  /* Spinner */
  .vpw-spin { animation: vpw-spin 0.8s linear infinite; }
  @keyframes vpw-spin { to { transform: rotate(360deg); } }
  /* Skip reasons reuse */
  .vp-skip-reasons {
    display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-2);
  }
  .vp-skip-reason-btn {
    padding: var(--space-2) var(--space-3);
    border: 1px solid var(--border-primary, #ddd);
    border-radius: var(--radius-md); background: var(--bg-surface);
    color: var(--text-secondary); font-size: var(--text-sm);
    cursor: pointer; font-family: inherit; text-align: center;
    transition: all 0.15s ease;
  }
  .vp-skip-reason-btn:hover { border-color: var(--color-warning); color: var(--color-warning); }
  .vp-skip-reason-btn--active {
    border-color: var(--color-warning); background: var(--color-warning);
    color: #fff; font-weight: 600;
  }
`
