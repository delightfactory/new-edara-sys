/**
 * VisitExecutionMode — وضع التنفيذ الذكي للمندوب
 * شاشة مخصصة للتنفيذ الميداني (Mobile-first):
 *
 * - بطاقة الزيارة الحالية (اسم + هاتف + عنوان + رصيد + غرض)
 * - زر "بدء الزيارة" → GPS + Timer
 * - استبيان إجباري (حسب purpose_type)
 * - زر "إنهاء الزيارة" → GPS مزدوج
 * - زر "تخطي" + سبب
 * - شريط تقدم علوي
 * - زر التوجه 🗺️
 */
import { useState, useMemo, useCallback, useRef, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import {
  useVisitPlan, useVisitPlanItems,
  useChecklistTemplates,
} from '@/hooks/useQueryHooks'
import useGeoPermission from '@/hooks/useGeoPermission'
import type { VisitPlanItem, VisitCompletionChecklistResponseInput } from '@/lib/types/activities'
import GeoPermissionBanner from '@/components/shared/GeoPermissionBanner'
import VisitTimer from '@/components/shared/VisitTimer'
import ChecklistForm from '@/components/shared/ChecklistForm'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import {
  Play, CheckCircle, SkipForward, Phone, MapPin,
  Navigation, Target, ArrowLeft, Loader2, PartyPopper,
  RefreshCw, Trash2
} from 'lucide-react'

// Atomic feature flag & hook
import { VISITS_ATOMIC_EXECUTION } from '@/lib/config/features'
import { useVisitExecutionSession, mapChecklistResponses } from '@/hooks/useVisitExecutionSession'
import { visitsDb, type PendingVisitOperation, type LocalBlobRecord } from '@/lib/db/visitsDb'
import { useAuthStore } from '@/stores/auth-store'
import { PERMISSIONS } from '@/lib/permissions/constants'
import { subscribeToSyncChanges, resumeUploads, retrySingleUpload } from '@/lib/services/photoSyncService'

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
  const can = useAuthStore(s => s.can)

  // ── Data (react-query)
  const { data: plan, isLoading: planLoading } = useVisitPlan(id)
  const { data: items = [], isLoading: itemsLoading } = useVisitPlanItems(id)
  const geo = useGeoPermission()

  // ── Session & Operation hook (IndexedDB)
  const atomic = useVisitExecutionSession(id, items, VISITS_ATOMIC_EXECUTION)

  const canExecuteAtomic = can(PERMISSIONS.VISIT_PLANS_UPDATE_OWN) && can(PERMISSIONS.ACTIVITIES_CREATE)
  const canExecuteLegacy = can(PERMISSIONS.VISIT_PLANS_CREATE)
  const canExecute = VISITS_ATOMIC_EXECUTION ? canExecuteAtomic : canExecuteLegacy

  // ── Common UI State
  const [activeTab,          setActiveTab]          = useState<'checklists' | 'customer'>('checklists')
  const [skipModal,          setSkipModal]          = useState<VisitPlanItem | null>(null)
  const [skipReason,         setSkipReason]         = useState('')
  const [skipCustom,         setSkipCustom]         = useState('')
  const [skipping,           setSkipping]           = useState(false)
  const [completing,         setCompleting]         = useState(false)
  const [showGeoDialog,      setShowGeoDialog]      = useState(false)

  // ── Sorted items
  const sortedItems = useMemo(
    () => [...items].sort((a, b) => (a.sequence ?? 0) - (b.sequence ?? 0)),
    [items]
  )

  // ── Current item (first pending or active item)
  const currentItem = useMemo(() => {
    const sess = atomic.session
    if (sess) {
      return sortedItems.find(i => i.id === sess.itemId)
    }
    return sortedItems.find(i => i.status === 'in_progress' || i.status === 'pending')
  }, [sortedItems, atomic.session])

  const currentIndex = currentItem ? sortedItems.indexOf(currentItem) : -1
  const nextItem = currentIndex >= 0 ? sortedItems[currentIndex + 1] : null

  const [localBlobs, setLocalBlobs] = useState<LocalBlobRecord[]>([])
  const profile = useAuthStore(s => s.profile)

  const loadLocalBlobs = useCallback(async () => {
    if (!profile?.id || !id || !currentItem?.id) {
      setLocalBlobs([])
      return
    }
    try {
      const records = await visitsDb.localBlobs
        .where('[userId+planId+itemId]')
        .equals([profile.id, id, currentItem.id])
        .toArray()
      setLocalBlobs(records)
    } catch (err) {
      console.error('Failed to load local blobs for UI status', err)
    }
  }, [profile?.id, id, currentItem?.id])

  useEffect(() => {
    loadLocalBlobs()
    const unsubscribe = subscribeToSyncChanges(() => {
      loadLocalBlobs()
    })
    return () => {
      unsubscribe()
    }
  }, [loadLocalBlobs])

  // ── Checklist templates for current visit purpose
  const purposeType = currentItem?.purpose_type || undefined
  const { data: templates = [] } = useChecklistTemplates(
    currentItem ? { category: 'visit', purposeType } : undefined
  )

  const mandatoryTemplates = templates.filter(t => t.is_mandatory)

  const isSyncActive = useMemo(() => {
    return localBlobs.some(b => b.uploadState === 'uploading')
  }, [localBlobs])

  const getQuestionText = useCallback((questionId: string) => {
    for (const tpl of templates) {
      const q = tpl.questions?.find(qi => qi.id === questionId)
      if (q) return q.question_text
    }
    return 'صورة الاستبيان'
  }, [templates])

  // ── Progress stats
  const stats = useMemo(() => {
    const completed = sortedItems.filter(i => i.status === 'completed').length
    const skipped = sortedItems.filter(i => i.status === 'skipped').length
    const total = sortedItems.length
    const done = completed + skipped
    const pct = total > 0 ? Math.round((done / total) * 100) : 0
    return { completed, skipped, total, done, pct }
  }, [sortedItems])

  // IsActive
  const isActive = useMemo(() => {
    return !!atomic.session
  }, [atomic.session])

  // Timer start time
  const timerStartTime = useMemo(() => {
    return atomic.session?.serverStartedAt || atomic.session?.clientStartedAt || null
  }, [atomic.session])

  // Derived Checklist Responses & Complete Status (Atomic Mode)
  const atomicChecklistResponses = useMemo(() => {
    if (!atomic.session) return []
    return Object.values(atomic.session.checklistDrafts).flatMap(d => d.responses)
  }, [atomic.session?.checklistDrafts])

  const atomicChecklistReady = useMemo(() => {
    return templates.every(tpl => {
      if (!tpl.is_mandatory) return true
      return atomic.session?.checklistDrafts[tpl.id]?.isComplete ?? false
    })
  }, [templates, atomic.session?.checklistDrafts])

  // Operation State helpers - Filtered strictly by current item and sorted by status priority
  const currentOp = useMemo(() => {
    if (!currentItem) return null
    const ops = atomic.pendingOps.filter(op => op.itemId === currentItem.id)
    if (ops.length === 0) return null
    const statePriority: Record<PendingVisitOperation['state'], number> = {
      sending: 5,
      pending: 4,
      conflict: 3,
      failed: 2,
      retryable: 1
    }
    return [...ops].sort((a, b) => {
      const aPri = statePriority[a.state]
      const bPri = statePriority[b.state]
      if (aPri !== bPri) return bPri - aPri
      if (a.updatedAt !== b.updatedAt) return b.updatedAt - a.updatedAt
      if (a.createdAt !== b.createdAt) return b.createdAt - a.createdAt
      return a.operationId.localeCompare(b.operationId)
    })[0]
  }, [atomic.pendingOps, currentItem])

  const isPendingActive = useMemo(() => {
    return currentOp !== null
  }, [currentOp])

  // ── Start Visit
  const [isStarting, setIsStarting] = useState(false)
  const [retryingOpId, setRetryingOpId] = useState<string | null>(null)
  const isActionExecutingRef = useRef(false)

  const ERROR_TRANSLATIONS: Record<string, string> = {
    CORRUPTED_PAYLOAD: 'تم الكشف عن تلف في بيانات العملية المحلية المحفوظة في المتصفح. يرجى بدء محاولة جديدة.',
    SYNC_CONFLICT: 'تعارض في التزامن: تم تحديث حالة هذه الزيارة بالفعل على الخادم من جهاز آخر.',
    IDEMPOTENCY_KEY_CONFLICT: 'تعارض في مفتاح الارسال: هذه العملية تم إرسالها مسبقاً وجاري معالجتها.',
    CONNECTION_ERROR: 'فشل الاتصال بالشبكة: تم حفظ العملية محلياً وجاري المزامنة فور توفر الإنترنت.',
    RETRYABLE_ERROR: 'خطأ مؤقت في الاتصال: سيتم إعادة المحاولة تلقائياً بعد قليل.',
    LOCKED: 'العملية قيد الإرسال والمعالجة حالياً. يرجى الانتظار.',
    MISSING_PARAMS: 'بيانات غير مكتملة للعملية الجارية.',
    CLIENT_ERROR: 'حدث خطأ غير متوقع في المتصفح أثناء المعالجة.',
    SURVEY_VALIDATION_FAILED: 'تعذر إنهاء الزيارة بسبب إجابة غير صالحة في الاستبيان. راجع الإجابات وحاول مرة أخرى.',
    GPS_VALIDATION_FAILED: 'تعذر إنهاء الزيارة بسبب مشكلة في التحقق الجغرافي. راجع الموقع أو مبرر الاستثناء.',
    LINKED_DOCUMENT_VALIDATION_FAILED: 'تعذر التحقق من طلب المبيعات أو سند التحصيل المرتبط بالزيارة.',
    VISIT_STATE_INVALID: 'حالة الزيارة أو إحدى بياناتها لم تعد صالحة للإكمال. راجع البيانات وابدأ محاولة جديدة.',
    INTERNAL_ERROR: 'حدث خطأ داخلي أثناء معالجة الزيارة. لم تُفقد المسودة ويمكن إعادة المحاولة.',
    LOCAL_PHOTO_MISSING: 'عذراً، بعض الصور المطلوبة لهذا الاستبيان مفقودة من التخزين المحلي. يرجى التقاط الصورة من جديد.',
    LOCAL_PHOTOS_PENDING_UPLOAD: 'تم حفظ الصور محليًا، ولا يمكن إنهاء الزيارة قبل مزامنتها مع الخادم.',
  }

  const hasLocalPhotoReferences = useMemo(() => {
    return atomicChecklistResponses.some(r => {
      if (r.answer_json && typeof r.answer_json === 'object') {
        const json = r.answer_json as Record<string, unknown>
        return typeof json.local_blob_id === 'string' && json.local_blob_id
      }
      return false
    })
  }, [atomicChecklistResponses])

  const isGpsInvalid = useMemo(() => {
    const status = atomic.session?.gpsValidationStatus
    return status === 'failed_distance' || status === 'failed_accuracy' || status === 'no_coordinates'
  }, [atomic.session?.gpsValidationStatus])

  const isCompleteDisabled = useMemo(() => {
    if (completing || isPendingActive || isStarting || skipping || retryingOpId !== null) return true
    if (mandatoryTemplates.length > 0 && !atomicChecklistReady) return true
    if (isGpsInvalid && !atomic.session?.gpsExceptionReason?.trim()) return true
    if (hasLocalPhotoReferences) return true
    return false
  }, [completing, isPendingActive, isStarting, skipping, retryingOpId, mandatoryTemplates.length, atomicChecklistReady, isGpsInvalid, atomic.session?.gpsExceptionReason, hasLocalPhotoReferences])

  const handleRetryOperation = useCallback(async (opId: string) => {
    if (isActionExecutingRef.current || isStarting || completing || skipping || retryingOpId !== null) return
    const op = atomic.pendingOps.find(o => o.operationId === opId)
    if (op && (op.state === 'sending' || op.state === 'pending')) return

    isActionExecutingRef.current = true
    setRetryingOpId(opId)
    try {
      await atomic.retryOperation(opId)
    } catch (err: unknown) {
      const errMsg = err instanceof Error ? err.message : 'حدث خطأ ما أثناء إعادة محاولة العملية'
      toast.error(errMsg)
    } finally {
      setRetryingOpId(null)
      isActionExecutingRef.current = false
    }
  }, [atomic, isStarting, completing, skipping, retryingOpId])

  const handleStartVisit = useCallback(async () => {
    if (!VISITS_ATOMIC_EXECUTION) {
      toast.error('التنفيذ الميداني للزيارات متوقف حالياً للصيانة. يرجى مراجعة الإدارة.')
      return
    }
    if (isActionExecutingRef.current || isPendingActive || completing || skipping) return
    if (!currentItem || !id) return
    if (geo.status === 'prompt') {
      setShowGeoDialog(true)
      return
    }

    isActionExecutingRef.current = true
    setIsStarting(true)
    try {
      const geoResult = await geo.requestLocation()
      if (!geoResult.ok && geoResult.reason === 'denied') {
        setIsStarting(false)
        isActionExecutingRef.current = false
        return
      }
      const coords = geoResult.ok ? geoResult.coords : null
      const accuracy = geoResult.ok && geoResult.coords ? geoResult.coords.accuracy : null

      const res = await atomic.startVisit(currentItem.id, coords, accuracy)
      if (res.ok) {
        toast.success('✓ تم بدء الزيارة بنجاح')
      }
    } catch (err: unknown) {
      const errMsg = err instanceof Error ? err.message : 'حدث خطأ ما أثناء بدء الزيارة'
      toast.error(errMsg)
    } finally {
      setIsStarting(false)
      isActionExecutingRef.current = false
    }
  }, [currentItem, id, geo, atomic, isPendingActive, completing, skipping])

  // ── GPS Explanatory allow
  const handleGeoDialogAllow = useCallback(async () => {
    setShowGeoDialog(false)
    if (!VISITS_ATOMIC_EXECUTION) {
      toast.error('التنفيذ الميداني للزيارات متوقف حالياً للصيانة. يرجى مراجعة الإدارة.')
      return
    }
    if (isActionExecutingRef.current || isPendingActive || completing || skipping) return
    if (!currentItem || !id) return
    isActionExecutingRef.current = true
    setIsStarting(true)
    try {
      const geoResult = await geo.requestLocation()
      if (!geoResult.ok && geoResult.reason === 'denied') {
        setIsStarting(false)
        isActionExecutingRef.current = false
        return
      }
      const coords = geoResult.ok ? geoResult.coords : null
      const accuracy = geoResult.ok && geoResult.coords ? geoResult.coords.accuracy : null

      const res = await atomic.startVisit(currentItem.id, coords, accuracy)
      if (res.ok) {
        toast.success('✓ تم بدء الزيارة بنجاح')
      }
    } catch (err: unknown) {
      const errMsg = err instanceof Error ? err.message : 'حدث خطأ ما أثناء بدء الزيارة'
      toast.error(errMsg)
    } finally {
      setIsStarting(false)
      isActionExecutingRef.current = false
    }
  }, [currentItem, id, geo, atomic, isPendingActive, completing, skipping])

  // ── Complete Visit
  const handleCompleteVisit = useCallback(async () => {
    if (!VISITS_ATOMIC_EXECUTION) {
      toast.error('التنفيذ الميداني للزيارات متوقف حالياً للصيانة. يرجى مراجعة الإدارة.')
      return
    }
    if (isActionExecutingRef.current || isPendingActive || isStarting || skipping) return
    if (!currentItem || !id || !plan) return

    if (isGpsInvalid && !atomic.session?.gpsExceptionReason?.trim()) {
      toast.error('يلزم إدخال مبرر لتجاوز النطاق الجغرافي للعميل قبل إنهاء الزيارة')
      return
    }

    isActionExecutingRef.current = true
    setCompleting(true)

    try {
      // 1) End GPS
      const geoResultEnd = await geo.requestLocation()
      const endCoords = geoResultEnd.ok ? geoResultEnd.coords : null
      const accuracy = geoResultEnd.ok && geoResultEnd.coords ? geoResultEnd.coords.accuracy : null

      // Check if any response contains a local photo reference
      const hasLocalPhotos = atomicChecklistResponses.some(
        r => r.answer_json && typeof r.answer_json === 'object' && 'local_blob_id' in r.answer_json
      )

      let validatedResponses: VisitCompletionChecklistResponseInput[] = []
      if (!hasLocalPhotos) {
        const allLoadedQuestions = templates.flatMap(t => t.questions ?? [])
        validatedResponses = mapChecklistResponses(atomicChecklistResponses, allLoadedQuestions)
      }

      const res = await atomic.completeVisit(
        currentItem.id,
        endCoords,
        accuracy,
        'visited',
        null,
        validatedResponses,
        null,
        null,
        atomic.session?.gpsExceptionReason || null
      )
      if (res.ok) {
        toast.success('✓ تم إنهاء الزيارة بنجاح')
      } else {
        const msg = res.errorCode ? (ERROR_TRANSLATIONS[res.errorCode] || res.errorCode) : 'فشل إنهاء الزيارة'
        toast.error(msg)
      }
    } catch (err: unknown) {
      const errMsg = err instanceof Error ? err.message : 'حدث خطأ ما أثناء إنهاء الزيارة'
      toast.error(errMsg)
    } finally {
      setCompleting(false)
      isActionExecutingRef.current = false
    }
  }, [currentItem, id, plan, geo, atomic, atomicChecklistResponses, templates, isPendingActive, isStarting, skipping, isGpsInvalid])

  // ── Skip
  const handleSkip = useCallback(async () => {
    if (!VISITS_ATOMIC_EXECUTION) {
      toast.error('التنفيذ الميداني للزيارات متوقف حالياً للصيانة. يرجى مراجعة الإدارة.')
      return
    }
    if (isActionExecutingRef.current || isPendingActive || isStarting || completing) return
    if (!skipModal || !id) return
    const reason = skipReason === 'أخرى' ? (skipCustom || 'أخرى') : skipReason
    if (!reason) { toast.error('اختر سبب التخطي'); return }
    isActionExecutingRef.current = true
    setSkipping(true)

    try {
      const res = await atomic.skipVisit(skipModal.id, reason)
      if (res.ok) {
        toast.success('✓ تم تخطي الزيارة بنجاح')
        setSkipModal(null)
        setSkipReason('')
        setSkipCustom('')
      }
    } catch (err: unknown) {
      const errMsg = err instanceof Error ? err.message : 'حدث خطأ ما أثناء تخطي الزيارة'
      toast.error(errMsg)
    } finally {
      setSkipping(false)
      isActionExecutingRef.current = false
    }
  }, [skipModal, id, skipReason, skipCustom, atomic, isPendingActive, isStarting, completing])

  // ── Navigate to Google Maps
  const openNavigation = useCallback((item: VisitPlanItem) => {
    const cust = item.customer
    if (!cust) return
    if (cust.latitude && cust.longitude) {
      window.open(`https://www.google.com/maps/dir/?api=1&destination=${cust.latitude},${cust.longitude}`, '_blank')
    }
  }, [])

  // ── Blocker Page
  if (!VISITS_ATOMIC_EXECUTION) {
    return (
      <div className="page-container animate-enter flex-1 flex flex-col items-center justify-center min-h-[50vh]">
        <div className="edara-card p-8 text-center border-amber-200 bg-amber-50 max-w-md mx-auto">
          <div style={{ fontSize: 32, marginBottom: 'var(--space-3)' }}>⚠️</div>
          <h2 className="text-xl font-bold mb-2" style={{ color: 'var(--color-warning)' }}>وضع التنفيذ غير متاح</h2>
          <p className="text-sm mb-3" style={{ color: 'var(--text-secondary)', lineHeight: 1.7 }}>
            مسار التنفيذ الميداني غير مفعّل حالياً من قبل مدير النظام.
          </p>
          <p className="text-xs mb-6" style={{ color: 'var(--text-muted)' }}>
            يرجى مراجعة الإدارة لتفعيل التنفيذ أو العودة لاحقاً.
          </p>
          <Button variant="secondary" onClick={() => navigate(-1)}>العودة للخطة</Button>
        </div>
      </div>
    )
  }

  if (VISITS_ATOMIC_EXECUTION && !canExecute) {
    return (
      <div className="page-container animate-enter flex-1 flex flex-col items-center justify-center min-h-[50vh]">
        <div className="edara-card p-8 text-center border-amber-200 bg-amber-50 max-w-md mx-auto">
          <div style={{ fontSize: 32, marginBottom: 'var(--space-3)' }}>⚠️</div>
          <h2 className="text-xl font-bold mb-2" style={{ color: 'var(--color-warning)' }}>غير مصرح بالدخول</h2>
          <p className="text-sm mb-3" style={{ color: 'var(--text-secondary)', lineHeight: 1.7 }}>
            ليس لديك الصلاحيات الكافية لبدء أو تنفيذ الزيارات الميدانية.
          </p>
          <p className="text-xs mb-6" style={{ color: 'var(--text-muted)' }}>
            تتطلب هذه العملية صلاحية تعديل خطتك وإنشاء الأنشطة الميدانية.
          </p>
          <Button variant="secondary" onClick={() => navigate(-1)}>العودة للخطة</Button>
        </div>
      </div>
    )
  }

  // ── Loading
  if (planLoading || itemsLoading || atomic.loading) {
    return (
      <div className="page-container animate-enter">
        <div className="edara-card p-6 text-center">
          <Loader2 size={32} className="animate-spin mx-auto mb-3 text-primary" />
          <p className="text-muted">جاري تحضير بيانات الخطة...</p>
          <p className="text-xs" style={{ color: 'var(--text-muted)', marginTop: 4 }}>يرجى الانتظار لحظة</p>
        </div>
      </div>
    )
  }

  if (atomic.error) {
    return (
      <div className="page-container animate-enter">
        <div className="edara-card p-6 text-center text-red-500">
          <p>{atomic.error}</p>
          <Button variant="secondary" onClick={() => atomic.reloadFromDb()} className="mt-3">أعد المحاولة</Button>
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
          <span className="vem-header-title">خطة {new Date(plan.plan_date).toLocaleDateString('ar-EG-u-nu-latn', { day: 'numeric', month: 'short' })}</span>
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

      {/* ── Operation Status Banner (Aria-live) ── */}
      {currentOp && (
        <div className={`vem-op-banner vem-op-banner--${currentOp.state}`} aria-live="polite">
          <span className="flex items-center gap-2">
            {currentOp.state === 'sending' && (
              <>
                <Loader2 size={16} className="animate-spin" />
                جاري إرسال العملية إلى الخادم...
              </>
            )}
            {currentOp.state === 'pending' && '⏳ العملية قيد الانتظار...'}
            {currentOp.state === 'retryable' && (
              <span>
                ⚠️ {ERROR_TRANSLATIONS[currentOp.lastErrorCode || ''] || 'فشل الاتصال بالشبكة. العملية معلقة ومحفوظة لإعادة المحاولة.'}
                {currentOp.attemptCount > 0 && ` (محاولة رقم ${currentOp.attemptCount})`}
              </span>
            )}
            {currentOp.state === 'conflict' && (
              <span>
                ❌ {ERROR_TRANSLATIONS[currentOp.lastErrorCode || ''] || 'تعارض في البيانات! يرجى مراجعة الخطة والبيانات الحالية.'}
              </span>
            )}
            {currentOp.state === 'failed' && (
              <span>
                ❌ {ERROR_TRANSLATIONS[currentOp.lastErrorCode || ''] || 'فشلت العملية. يرجى مراجعة تفاصيل الخطأ وبدء محاولة جديدة.'}
              </span>
            )}
          </span>
          <div className="vem-op-banner-actions">
            {currentOp.state === 'retryable' && (
              <button className="vem-op-action-btn" onClick={() => handleRetryOperation(currentOp.operationId)} disabled={isStarting || completing || skipping || retryingOpId !== null}>
                <RefreshCw size={14} className={(isStarting || completing || skipping || retryingOpId !== null) ? 'animate-spin' : ''} /> إعادة المحاولة
              </button>
            )}
            {currentOp.state === 'failed' && (
              <button className="vem-op-action-btn vem-op-action-btn--danger" onClick={() => atomic.discardFailedOperation(currentOp.operationId)}>
                <Trash2 size={14} /> بدء محاولة جديدة
              </button>
            )}
          </div>
        </div>
      )}

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
          {/* ── Tabs during ongoing visit ── */}
          {isActive && (
            <div className="vem-tabs" role="tablist">
              <button
                type="button"
                role="tab"
                aria-selected={activeTab === 'checklists'}
                aria-controls="vem-tab-checklists"
                className={`vem-tab ${activeTab === 'checklists' ? 'vem-tab--active' : ''}`}
                onClick={() => setActiveTab('checklists')}
              >
                📋 الاستبيانات والإثبات
              </button>
              <button
                type="button"
                role="tab"
                aria-selected={activeTab === 'customer'}
                aria-controls="vem-tab-customer"
                className={`vem-tab ${activeTab === 'customer' ? 'vem-tab--active' : ''}`}
                onClick={() => setActiveTab('customer')}
              >
                👤 العميل والتوجه
              </button>
            </div>
          )}

          {/* ── Current Visit Card ── */}
          <div className={`vem-card ${isActive ? 'vem-card--active' : ''}`}>
            <div className="vem-card-seq">#{currentIndex + 1}</div>

            {/* Tab Panel 1: العميل والتوجه */}
            <div id="vem-tab-customer" role="tabpanel" hidden={isActive && activeTab !== 'customer'} className="vem-card-body">
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
              {isActive && timerStartTime && (
                <div className="vem-timer-row">
                  <VisitTimer startTime={timerStartTime} isRunning={true} size="lg" />
                </div>
              )}
            </div>

            {/* Tab Panel 2: الاستبيانات والإثبات (Mounted & hidden when tab is customer so draft previews are never lost) */}
            <div id="vem-tab-checklists" role="tabpanel" hidden={isActive && activeTab !== 'checklists'}>
              {isActive && (
                <div className="vem-active-actions">
                  {/* Checklist (Multiple forms rendered independently in Atomic Mode) */}
                  {templates.length > 0 && (
                     <div className="vem-checklist-section">
                       <h4 className="vem-checklist-title">📋 استبيانات الزيارة الجارية</h4>
                       {templates.map(tpl => {
                         const draft = atomic.session?.checklistDrafts[tpl.id]
                         const initialValues = draft ? draft.responses.reduce((acc, curr) => {
                           acc[curr.question_id] = curr.answer_value || curr.answer_json
                           return acc
                         }, {} as Record<string, unknown>) : undefined

                         return (
                           <div key={tpl.id} className="vem-checklist-template-group animate-enter">
                             <h5 className="vem-checklist-template-name flex items-center justify-between">
                               <span>
                                 {tpl.name} {tpl.is_mandatory && <span className="vem-mandatory-star">* (إلزامي)</span>}
                               </span>
                               {draft && (
                                 <span className="vem-draft-status">
                                   {draft.isComplete ? '✓ مكتمل ومحفوظ' : '📝 مسودة محفوظة'}
                                 </span>
                               )}
                             </h5>
                              <ChecklistForm
                                photoMode="local-blob"
                                onPhotoCapture={(questionId, blob, meta) => atomic.saveLocalPhoto(tpl.id, questionId, blob, meta)}
                                loadLocalPhoto={atomic.loadLocalPhoto}
                               questions={tpl.questions ?? []}
                               activityId={currentItem.id}
                               templateId={tpl.id}
                               initialValues={initialValues}
                               onChange={(responses, complete) => {
                                 atomic.saveChecklistDraft(tpl.id, responses, tpl.questions ?? [], complete)
                               }}
                             />
                           </div>
                         )
                       })}
                     </div>
                  )}

                  {/* Photo upload status panel */}
                  {localBlobs.length > 0 && (
                    <div className="vem-photo-sync-panel" aria-live="polite">
                      <h6 className="vem-photo-sync-header">
                        <span>حالة رفع الصور المرفقة:</span>
                        <button
                          type="button"
                          onClick={() => profile?.id && resumeUploads(profile.id)}
                          className="vem-photo-sync-retry-all-btn"
                          disabled={isSyncActive}
                        >
                          <RefreshCw size={12} className={isSyncActive ? "vpw-spin" : ""} /> إعادة محاولة الكل
                        </button>
                      </h6>
                      <div className="vem-photo-sync-list">
                        {localBlobs.map(blob => {
                          let statusText = 'محفوظة محليًا'
                          let statusClass = 'vem-photo-sync-status--pending'
                          let showRetry = false

                          switch (blob.uploadState) {
                            case 'uploading':
                              statusText = 'جاري الرفع...'
                              statusClass = 'vem-photo-sync-status--uploading'
                              break
                            case 'retryable':
                              statusText = 'ستتم إعادة المحاولة تلقائياً'
                              statusClass = 'vem-photo-sync-status--retryable'
                              break
                            case 'uploaded':
                              statusText = 'تم الرفع بنجاح'
                              statusClass = 'vem-photo-sync-status--uploaded'
                              break
                            case 'failed':
                              statusText = 'فشل الرفع'
                              statusClass = 'vem-photo-sync-status--failed'
                              showRetry = true
                              break
                          }

                          return (
                            <div key={blob.localBlobId} className="vem-photo-sync-item">
                              <span className="vem-photo-sync-name">
                                {getQuestionText(blob.questionId)} ({Math.round(blob.sizeBytes / 1024)} KB)
                              </span>
                              <div className="vem-photo-sync-status-group">
                                <span className={`vem-photo-sync-status-text ${statusClass}`}>{statusText}</span>
                                {showRetry && (
                                  <button
                                    type="button"
                                    onClick={() => profile?.id && retrySingleUpload(profile.id, blob.localBlobId)}
                                    className="vem-photo-sync-retry-btn"
                                  >
                                    إعادة محاولة
                                  </button>
                                )}
                              </div>
                            </div>
                          )
                        })}
                      </div>
                    </div>
                  )}

                  {/* GPS Exception Input & Warning — يظهر فقط عند وجود مشكلة في النطاق الجغرافي — */}
                  <div className="vem-gps-exception-container">
                    {isGpsInvalid ? (
                      <div className="vem-gps-warning animate-enter vem-gps-quiet-pulse">
                        <p className="text-sm font-bold text-red-600">⚠️ أنت خارج النطاق الجغرافي المسموح به للعميل.</p>
                        <p className="text-xs text-red-500">يلزم كتابة مبرر منطقي للاستثناء الجغرافي أدناه لتتمكن من إنهاء الزيارة.</p>
                      </div>
                    ) : (
                      atomic.session?.startGPSAccuracy !== null && atomic.session?.startGPSAccuracy !== undefined && (
                        <div className={`vem-gps-accuracy-badge vem-gps-quiet-pulse ${atomic.session.startGPSAccuracy > 50 ? 'vem-gps-accuracy-badge--low' : 'vem-gps-accuracy-badge--good'}`}>
                          {atomic.session.startGPSAccuracy > 50 ? `⚠️ دقة موقع منخفضة: ${Math.round(atomic.session.startGPSAccuracy)} متر` : `✓ دقة موقع جيدة: ${Math.round(atomic.session.startGPSAccuracy)} متر`}
                        </div>
                      )
                    )}
                    {/* حقل المبرر يظهر فقط عند isGpsInvalid (Quick Wins UX) */}
                    {isGpsInvalid && (
                      <>
                        <label className="vem-gps-exception-label">
                          مبرر تجاوز موقع العميل الجغرافي <span className="vem-mandatory-star">* (مطلوب)</span>
                        </label>
                        <textarea
                          className="form-input vem-gps-exception-textarea"
                          placeholder="اكتب التبرير هنا لإنهاء الزيارة..."
                          value={atomic.session?.gpsExceptionReason || ''}
                          onChange={e => atomic.saveGpsExceptionReason(e.target.value)}
                          disabled={isPendingActive}
                        />
                      </>
                    )}
                  </div>
                </div>
              )}
            </div>

            {/* ── Sticky Local Action Bar (Start / Complete Button) ── */}
            <div className="vem-sticky-action-bar">
              {!isActive ? (
                <button
                  className="vem-start-btn"
                  onClick={handleStartVisit}
                  disabled={isStarting || isPendingActive || completing || skipping || retryingOpId !== null}
                >
                  {isStarting || (currentOp?.kind === 'start' && (currentOp.state === 'sending' || currentOp.state === 'pending')) ? (
                    <><Loader2 size={22} className="vpw-spin" /> جاري التحضير...</>
                  ) : (
                    <><Play size={22} /> بدء الزيارة</>
                  )}
                </button>
              ) : (
                <button
                  className={`vem-complete-btn ${isCompleteDisabled ? 'vem-complete-btn--disabled' : ''}`}
                  onClick={handleCompleteVisit}
                  disabled={isCompleteDisabled}
                >
                  {completing || (currentOp?.kind === 'complete' && (currentOp.state === 'sending' || currentOp.state === 'pending')) ? (
                    <><Loader2 size={18} className="vpw-spin" /> جاري الإنهاء...</>
                  ) : (
                    <><CheckCircle size={18} /> إنهاء الزيارة</>
                  )}
                </button>
              )}
            </div>

            {/* Skip is hidden/disabled during active visit */}
            {!isActive && (
              <button
                className="vem-skip-btn"
                onClick={() => { setSkipModal(currentItem); setSkipReason('') }}
                disabled={isPendingActive || isStarting || completing || skipping || retryingOpId !== null}
              >
                {skipping || (currentOp?.kind === 'skip' && (currentOp.state === 'sending' || currentOp.state === 'pending')) ? (
                  <><Loader2 size={14} className="vpw-spin" /> جاري التخطي...</>
                ) : (
                  <><SkipForward size={14} /> تخطي</>
                )}
              </button>
            )}
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

          <div className="flex gap-2 justify-end mt-4">
            <Button variant="secondary" onClick={() => setSkipModal(null)}>إلغاء</Button>
            <Button
              variant="secondary"
              onClick={handleSkip}
              disabled={skipping || !skipReason || isPendingActive}
            >
              {skipping || (currentOp?.kind === 'skip' && (currentOp.state === 'sending' || currentOp.state === 'pending')) ? (
                <span className="flex items-center gap-2">
                  <Loader2 size={14} className="vpw-spin" /> جاري الحفظ...
                </span>
              ) : 'تأكيد التخطي'}
            </Button>
          </div>
        </div>
      </ResponsiveModal>

      <style>{`
        .vem-header {
          display: flex; align-items: center; gap: var(--space-3);
          padding: var(--space-4); background: var(--bg-surface);
          border-bottom: 1px solid var(--border-light);
          position: relative;
        }
        .vem-back {
          background: none; border: none; color: var(--text-primary);
          cursor: pointer; padding: var(--space-1); min-height: 44px; min-width: 44px;
          display: flex; align-items: center; justify-content: center;
        }
        .vem-header-info {
          display: flex; flex-direction: column; flex: 1;
        }
        .vem-header-title { font-weight: 700; font-size: var(--text-base); }
        .vem-header-progress { font-size: var(--text-xs); color: var(--text-muted); }
        .vem-progress-bar {
          position: absolute; bottom: 0; inset-inline-start: 0; inset-inline-end: 0; height: 3px;
          background: var(--neutral-100);
        }
        .vem-progress-fill { height: 100%; background: var(--color-primary); transition: width 0.3s ease; }

        .vem-op-banner {
          display: flex; align-items: center; justify-content: space-between;
          padding: var(--space-3) var(--space-4); margin-bottom: var(--space-3);
          border-radius: var(--radius-md); font-size: var(--text-sm); font-weight: 600;
          position: sticky; top: 0; z-index: 10;
        }
        .vem-op-banner--sending, .vem-op-banner--pending { background: var(--color-primary-light); color: var(--color-primary); }
        .vem-op-banner--retryable { background: var(--neutral-100); color: var(--text-secondary); }
        .vem-op-banner--conflict { background: rgba(239, 68, 68, 0.1); color: rgb(239, 68, 68); }
        .vem-op-banner--failed { background: rgba(239, 68, 68, 0.15); color: rgb(220, 38, 38); }

        .vem-op-banner-actions { display: flex; gap: var(--space-2); }
        .vem-op-action-btn {
          display: flex; align-items: center; gap: 4px; padding: 4px 8px;
          background: var(--bg-surface); border: 1px solid currentColor;
          border-radius: var(--radius-sm); font-size: var(--text-xs); font-weight: 700;
          cursor: pointer; min-height: 36px;
        }
        .vem-op-action-btn--danger { color: rgb(220, 38, 38); }

        .vem-card {
          position: relative; background: var(--bg-surface);
          border-radius: var(--radius-xl, 16px); padding: var(--space-5);
          box-shadow: var(--shadow-sm); border: 1px solid var(--border-light);
          margin-bottom: var(--space-4); display: flex; flex-direction: column;
        }
        .vem-card--active { border-color: var(--color-primary); }
        .vem-card-seq {
          position: absolute; top: var(--space-4); inset-inline-start: var(--space-4);
          background: var(--neutral-100); color: var(--text-secondary);
          font-size: var(--text-xs); font-weight: 700; padding: var(--space-1) var(--space-2);
          border-radius: var(--radius-sm);
        }
        .vem-card-body { display: flex; flex-direction: column; gap: var(--space-2); }
        .vem-card-name { font-size: var(--text-lg); font-weight: 700; margin: 0; margin-inline-start: var(--space-12); text-align: start; }
        .vem-card-code { font-size: var(--text-xs); color: var(--text-muted); align-self: flex-start; }

        .vem-card-row {
          display: flex; align-items: center; gap: var(--space-2);
          font-size: var(--text-sm); color: var(--text-secondary);
        }
        .vem-card-phone { color: var(--color-primary); text-decoration: none; min-height: 44px; }
        .vem-nav-btn {
          display: inline-flex; align-items: center; gap: 4px; padding: 2px 8px;
          border-radius: var(--radius-sm); border: 1px solid var(--border-primary);
          background: var(--bg-surface); cursor: pointer; min-height: 44px;
        }
        .vem-priority-badge {
          background: rgba(239, 68, 68, 0.1); color: rgb(239, 68, 68);
          font-size: 10px; font-weight: 700; padding: 1px 4px; border-radius: 4px;
        }
        .vem-timer-row {
          margin-top: var(--space-2); display: flex; justify-content: center;
        }

        .vem-start-btn {
          display: flex; align-items: center; justify-content: center;
          gap: var(--space-2); width: 100%; padding: var(--space-4);
          background: var(--color-primary); color: white;
          border: none; border-radius: var(--radius-lg);
          font-size: var(--text-base); font-weight: 700;
          cursor: pointer; min-height: 52px; font-family: inherit;
          margin-top: var(--space-4);
        }
        .vem-start-btn:disabled { opacity: 0.6; cursor: not-allowed; }

        .vem-active-actions {
          display: flex; flex-direction: column; gap: var(--space-4);
          margin-top: var(--space-4);
          border-top: 1px solid var(--border-light);
          padding-top: var(--space-4);
        }
        .vem-checklist-section {
          display: flex; flex-direction: column; gap: var(--space-4);
        }
        .vem-checklist-title {
          font-size: var(--text-sm); font-weight: 700; margin: 0;
          color: var(--text-primary);
        }
        .vem-checklist-template-group {
          border: 1px solid var(--border-light); border-radius: var(--radius-md);
          padding: var(--space-3); background: var(--neutral-50);
        }
        .vem-checklist-template-name {
          font-size: var(--text-xs); font-weight: 700; margin-bottom: var(--space-2);
          color: var(--text-secondary);
        }
        .vem-mandatory-star { color: rgb(239, 68, 68); margin-inline-end: 4px; }

        .vem-gps-exception-container {
          display: flex; flex-direction: column; gap: 4px;
        }
        .vem-gps-exception-label {
          font-size: var(--text-xs); font-weight: 600; color: var(--text-secondary);
        }
        .vem-gps-exception-textarea {
          min-height: 60px; font-family: inherit; font-size: var(--text-sm);
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
          border: none; cursor: pointer; min-height: 44px;
          font-size: var(--text-sm); font-family: inherit;
          margin-top: var(--space-2);
        }
        .vem-skip-btn:hover { color: var(--color-warning); }

        .vem-upcoming {
          display: flex; align-items: center; gap: var(--space-2);
          padding: var(--space-3) var(--space-4);
          background: var(--neutral-50); border-radius: var(--radius-md);
          font-size: var(--text-sm); margin-bottom: var(--space-3);
        }
        .vem-upcoming-label { color: var(--text-muted); font-weight: 500; }
        .vem-upcoming-name { font-weight: 600; }
        .vem-upcoming-purpose { color: var(--text-muted); }

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

        .vpw-spin { animation: vpw-spin 0.8s linear infinite; }
        @keyframes vpw-spin { to { transform: rotate(360deg); } }

        .vem-tabs {
          display: flex;
          gap: var(--space-2);
          margin-bottom: var(--space-3);
          background: var(--bg-surface-2, var(--neutral-100));
          padding: var(--space-1);
          border-radius: var(--radius-lg);
          border: 1px solid var(--border-primary);
        }
        .vem-tab {
          flex: 1;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          gap: var(--space-2);
          min-height: 44px;
          padding: var(--space-2) var(--space-3);
          border-radius: var(--radius-md);
          border: none;
          background: transparent;
          color: var(--text-secondary);
          font-family: inherit;
          font-size: var(--text-sm);
          font-weight: 600;
          cursor: pointer;
          transition: all 0.15s ease;
        }
        .vem-tab--active {
          background: var(--bg-surface);
          color: var(--color-primary);
          box-shadow: var(--shadow-sm);
        }

        .vem-sticky-action-bar {
          position: sticky;
          bottom: calc(var(--bottom-nav-height, 64px) + env(safe-area-inset-bottom, 0px));
          z-index: 10;
          margin-block-start: var(--space-4);
          background: var(--bg-surface);
          padding: var(--space-3);
          border-radius: var(--radius-lg);
          border: 1px solid var(--border-primary);
          box-shadow: var(--shadow-sm);
        }

        .vem-gps-quiet-pulse {
          animation: vem-quiet-pulse 2.5s cubic-bezier(0.4, 0, 0.6, 1) infinite;
        }
        @keyframes vem-quiet-pulse {
          0%, 100% { opacity: 1; transform: scale(1); }
          50% { opacity: 0.85; transform: scale(1.015); }
        }
        @media (prefers-reduced-motion: reduce) {
          .vem-gps-quiet-pulse {
            animation: none !important;
          }
        }

        .vp-skip-reasons {
          display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-2);
        }
        .vp-skip-reason-btn {
          border-radius: var(--radius-md); background: var(--bg-surface);
          color: var(--text-secondary); font-size: var(--text-sm);
          cursor: pointer; font-family: inherit; text-align: center;
          transition: all 0.15s ease;
          min-height: 44px;
        }
        .vp-skip-reason-btn:hover { border-color: var(--color-warning); color: var(--color-warning); }
        .vp-skip-reason-btn--active {
          border-color: var(--color-warning); background: var(--color-warning);
          color: #fff; font-weight: 600;
        }

        .vem-gps-warning {
          background: rgba(239, 68, 68, 0.1); border: 1px solid rgba(239, 68, 68, 0.2);
          border-radius: var(--radius-md); padding: var(--space-3); margin-bottom: var(--space-2);
        }
        .vem-gps-warning p { margin: 0; }
        .vem-gps-accuracy-badge {
          display: inline-block; font-size: 10px; font-weight: 700; padding: 2px 6px;
          border-radius: 4px; margin-bottom: var(--space-2); align-self: flex-start;
        }
        .vem-gps-accuracy-badge--good { background: rgba(16, 185, 129, 0.1); color: var(--color-success, green); }
        .vem-gps-accuracy-badge--low { background: rgba(245, 158, 11, 0.1); color: var(--color-warning, orange); }
        .vem-draft-status {
          font-size: 10px; color: var(--color-success, green); font-weight: normal;
          background: rgba(16, 185, 129, 0.1); padding: 2px 6px; border-radius: 4px;
        }
      `}</style>
    </div>
  )
}
