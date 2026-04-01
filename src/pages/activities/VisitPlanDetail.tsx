import { useParams, useNavigate } from 'react-router-dom'
import {
  useVisitPlan, useVisitPlanItems,
  useConfirmVisitPlan, useCancelVisitPlan,
  useAddVisitPlanItem, useUpdateVisitPlanItem,
  useCustomers, useCreateVisitPlan,
  useDeleteVisitPlanItem, useReorderVisitPlanItems,
} from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import { PERMISSIONS } from '@/lib/permissions/constants'
import { toast } from 'sonner'
import { useState } from 'react'
import {
  MapPin, CheckCircle, XCircle, Plus, SkipForward,
  Calendar, Clock, ChevronLeft, Copy, Archive,
  Edit3, Trash2, ArrowUp, ArrowDown, Play, Save, X,
} from 'lucide-react'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'
import PlanItemCard from '@/components/shared/PlanItemCard'
import ActivityStatusBadge from '@/components/shared/ActivityStatusBadge'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import { CardSkeleton } from '@/components/ui/Skeleton'
import type {
  VisitPlanItemInput, PlanItemPurposeType, PlanPriority,
  VisitPlanItem,
} from '@/lib/types/activities'

function fmtDate(d: string) {
  return new Date(d).toLocaleDateString('ar-EG', { weekday: 'long', day: 'numeric', month: 'long' })
}

function tomorrow(): string {
  const d = new Date()
  d.setDate(d.getDate() + 1)
  return d.toISOString().slice(0, 10)
}

// ── Skip reasons
const SKIP_REASONS = [
  'محل مغلق',
  'العميل غير متاح',
  'تأجيل بطلب العميل',
  'ظروف طارئة',
  'مسافة بعيدة / وقت غير كافٍ',
  'أخرى',
]

export default function VisitPlanDetail() {
  const { id }   = useParams<{ id: string }>()
  const navigate = useNavigate()
  const can      = useAuthStore(s => s.can)

  // ── Modal: Confirm
  const [confirmOpen,  setConfirmOpen]  = useState(false)
  const [cancelOpen,   setCancelOpen]   = useState(false)
  const [cancelReason, setCancelReason] = useState('')
  const [processing,   setProcessing]   = useState(false)

  // ── Modal: Add item
  const [addItemOpen,     setAddItemOpen]     = useState(false)
  const [itemCustomerId,  setItemCustomerId]  = useState('')
  const [itemPurposeType, setItemPurposeType] = useState<PlanItemPurposeType | ''>('')
  const [itemPriority,    setItemPriority]    = useState<PlanPriority>('normal')
  const [itemPlannedTime, setItemPlannedTime] = useState('')
  const [itemDuration,    setItemDuration]    = useState(30)
  const [addingItem,      setAddingItem]      = useState(false)

  // ── Modal: Skip item
  const [skipItem,       setSkipItem]       = useState<VisitPlanItem | null>(null)
  const [skipReason,     setSkipReason]     = useState('')
  const [skipCustom,     setSkipCustom]     = useState('')
  const [skipping,       setSkipping]       = useState(false)

  // ── Modal: Reschedule item
  const [rescheduleItem, setRescheduleItem] = useState<VisitPlanItem | null>(null)
  const [rescheduleDate, setRescheduleDate] = useState(tomorrow())
  const [rescheduling,   setRescheduling]   = useState(false)

  // ── Modal: Bulk Close
  const [bulkCloseOpen, setBulkCloseOpen] = useState(false)
  const [bulkReason,    setBulkReason]    = useState('انتهاء الدوام الزمني')

  // ── Modal: Clone Plan
  const [cloneOpen, setCloneOpen] = useState(false)
  const [cloneDate, setCloneDate] = useState(tomorrow())

  // ── Data
  const { data: plan,  isLoading: planLoading  } = useVisitPlan(id)
  const { data: items = [], isLoading: itemsLoading } = useVisitPlanItems(id)
  const { data: customersRes } = useCustomers({ pageSize: 200 })
  const customers = customersRes?.data ?? []

  // ── Mutations
  const confirmPlan   = useConfirmVisitPlan()
  const cancelPlan    = useCancelVisitPlan()
  const addPlanItem   = useAddVisitPlanItem()
  const updatePlanItem = useUpdateVisitPlanItem()
  const createPlan    = useCreateVisitPlan()
  const deleteItemMut = useDeleteVisitPlanItem()
  const reorderMut    = useReorderVisitPlanItems()

  // ── Edit Mode State
  const [editMode, setEditMode] = useState(false)

  // ── Permissions
  const canConfirm = can(PERMISSIONS.VISIT_PLANS_CONFIRM) || can(PERMISSIONS.VISIT_PLANS_READ_ALL)
  const canCreate  = can(PERMISSIONS.ACTIVITIES_CREATE)
  const canAddItem = can(PERMISSIONS.VISIT_PLANS_CREATE) && plan?.status === 'draft'
  const canSkip    = plan?.status === 'confirmed' || plan?.status === 'in_progress'

  // مصفوفة التعديل المرن
  const canEditPlan = (() => {
    if (!plan) return false
    const isDraft = plan.status === 'draft'
    const isActive = plan.status === 'confirmed' || plan.status === 'in_progress'
    const hasUpdatePerm = can(PERMISSIONS.VISIT_PLANS_UPDATE)
    const hasUpdateOwn = can(PERMISSIONS.VISIT_PLANS_UPDATE_OWN)
    // المندوب يعدل المسودة فقط
    if (isDraft && hasUpdateOwn) return true
    // المشرف/المدير يعدل المسودة + المؤكدة + الجارية
    if ((isDraft || isActive) && hasUpdatePerm) return true
    return false
  })()

  // هل يمكن بدء التنفيذ?
  const canExecute = canCreate && (plan?.status === 'confirmed' || plan?.status === 'in_progress')

  // ── Handlers: Confirm / Cancel
  const handleConfirm = () => {
    if (!id) return
    setProcessing(true)
    confirmPlan.mutate(id, {
      onSuccess: () => { toast.success('تم تأكيد الخطة'); setConfirmOpen(false) },
      onError:   () => toast.error('فشل التأكيد'),
      onSettled: () => setProcessing(false),
    })
  }

  const handleCancel = () => {
    if (!id) return
    setProcessing(true)
    cancelPlan.mutate({ id, reason: cancelReason }, {
      onSuccess: () => { toast.success('تم إلغاء الخطة'); setCancelOpen(false) },
      onError:   () => toast.error('فشل الإلغاء'),
      onSettled: () => setProcessing(false),
    })
  }

  // ── Handler: Add Item
  const handleAddItem = () => {
    if (!id || !itemCustomerId) { toast.error('اختر العميل'); return }
    setAddingItem(true)
    const itemInput: VisitPlanItemInput = {
      customer_id:            itemCustomerId,
      sequence:               items.length + 1,
      purpose_type:           itemPurposeType || null,
      priority:               itemPriority,
      planned_time:           itemPlannedTime || null,
      estimated_duration_min: itemDuration,
    }
    addPlanItem.mutate(
      { planId: id, item: itemInput },
      {
        onSuccess: () => {
          toast.success('تم إضافة البند')
          setAddItemOpen(false)
          setItemCustomerId(''); setItemPurposeType('')
          setItemPriority('normal'); setItemPlannedTime(''); setItemDuration(30)
        },
        onError:   (e: any) => toast.error(e?.message || 'فشل إضافة البند'),
        onSettled: () => setAddingItem(false),
      }
    )
  }

  // ── Handler: Skip Item
  const handleSkip = () => {
    if (!skipItem || !id) return
    const reason = skipReason === 'أخرى' ? (skipCustom || 'أخرى') : skipReason
    if (!reason) { toast.error('اختر سبب التخطي'); return }
    setSkipping(true)
    updatePlanItem.mutate(
      {
        itemId: skipItem.id,
        planId:  id,
        input:   { status: 'skipped', skip_reason: reason },
      },
      {
        onSuccess: () => {
          toast.success('تم تخطي البند')
          setSkipItem(null); setSkipReason(''); setSkipCustom('')
        },
        onError:   (e: any) => toast.error(e?.message || 'فشل تخطي البند'),
        onSettled: () => setSkipping(false),
      }
    )
  }

  // ── Handler: Reschedule Item
  const handleReschedule = () => {
    if (!rescheduleItem || !id || !rescheduleDate) return
    setRescheduling(true)
    updatePlanItem.mutate(
      {
        itemId: rescheduleItem.id,
        planId:  id,
        input:   { status: 'rescheduled', reschedule_to: rescheduleDate },
      },
      {
        onSuccess: () => {
          toast.success(`تمت إعادة الجدولة إلى ${new Date(rescheduleDate).toLocaleDateString('ar-EG')}`)
          setRescheduleItem(null)
        },
        onError:   (e: any) => toast.error(e?.message || 'فشل إعادة الجدولة'),
        onSettled: () => setRescheduling(false),
      }
    )
  }

  // ── Handler: Bulk Close
  const pendingItems = items.filter(i => i.status === 'pending')
  const handleBulkClose = async () => {
    if (!id || pendingItems.length === 0) return
    setProcessing(true)
    let errs = 0
    for (const item of pendingItems) {
      try {
        await updatePlanItem.mutateAsync({
          itemId: item.id,
          planId: id,
          input: { status: 'missed', skip_reason: bulkReason }
        })
      } catch {
        errs++
      }
    }
    setProcessing(false)
    setBulkCloseOpen(false)
    if (errs > 0) toast.warning(`تم تحويل البعض لزائفة، ولكن فشل ${errs} بند`)
    else toast.success('تم إنهاء اليومية وتحديث البنود المعلقة')
  }

  // ── Handler: Clone Plan
  const handleClone = async () => {
    if (!plan) return
    setProcessing(true)
    try {
      const newPlan = await createPlan.mutateAsync({
        employee_id: plan.employee_id,
        plan_date: cloneDate,
        plan_type: plan.plan_type,
        notes: `نسخة مستنسخة من مسار يوم ${plan.plan_date}`,
      })
      
      let copied = 0
      for (const item of items) {
        try {
          await addPlanItem.mutateAsync({
            planId: newPlan.id,
            item: {
              customer_id: item.customer_id,
              sequence: item.sequence,
              purpose_type: item.purpose_type || null,
              priority: item.priority,
              planned_time: item.planned_time || null,
              estimated_duration_min: item.estimated_duration_min || 30,
            }
          })
          copied++
        } catch { /* ignore individual item errors in clone */ }
      }
      
      toast.success(`تم إنشاء نسخة بخطة جديدة (تم نسخ ${copied} بند)`)
      setCloneOpen(false)
      navigate(`/activities/visit-plans/${newPlan.id}`)
    } catch {
      toast.error('فشل استنساخ الخطة')
    }
    setProcessing(false)
  }

  // ── Loading
  if (planLoading) {
    return (
      <div className="page-container animate-enter">
        <div className="edara-card" style={{ padding: 'var(--space-6)' }}>
          {[1, 2, 3].map(i => (
            <div key={i} className="skeleton" style={{ height: 24, marginBottom: 'var(--space-3)', width: `${80 - i * 15}%` }} />
          ))}
        </div>
      </div>
    )
  }

  if (!plan) {
    return (
      <div className="page-container animate-enter">
        <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
          <p className="empty-state-title">لم يتم العثور على الخطة</p>
          <Button variant="secondary" onClick={() => navigate('/activities/visit-plans')}>العودة</Button>
        </div>
      </div>
    )
  }

  // counters
  const highPriority = pendingItems.filter(i => i.priority === 'high')

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title={`خطة زيارات — ${fmtDate(plan.plan_date)}`}
        subtitle={plan.employee?.full_name}
        breadcrumbs={[
          { label: 'خطط الزيارات', path: '/activities/visit-plans' },
          { label: fmtDate(plan.plan_date) },
        ]}
        actions={
          <div className="flex gap-2">
            {/* زر بدء التنفيذ */}
            {canExecute && (
              <Button
                onClick={() => navigate(`/activities/visit-plans/${id}/execute`)}
                icon={<Play size={16} />}
                style={{ background: 'var(--color-success)', borderColor: 'var(--color-success)' }}
              >
                بدء التنفيذ
              </Button>
            )}

            {/* زر وضع التعديل */}
            {canEditPlan && !editMode && (
              <Button variant="secondary" icon={<Edit3 size={16} />} onClick={() => setEditMode(true)}>
                تعديل الخطة
              </Button>
            )}
            {editMode && (
              <Button variant="secondary" icon={<X size={16} />} onClick={() => setEditMode(false)}>
                إلغاء التعديل
              </Button>
            )}

            {(canAddItem || (editMode && canEditPlan)) && (
              <Button icon={<Plus size={16} />} variant="secondary" onClick={() => setAddItemOpen(true)}>
                إضافة بند
              </Button>
            )}
            {canConfirm && plan.status === 'draft' && items.length > 0 && (
              <Button onClick={() => setConfirmOpen(true)} icon={<CheckCircle size={16} />}>
                تأكيد واعتماد
              </Button>
            )}
            {canConfirm && plan.status === 'in_progress' && pendingItems.length > 0 && (
              <Button onClick={() => setBulkCloseOpen(true)} variant="secondary" icon={<Archive size={16} />} className="desktop-only-btn">
                إنهاء اليومية المتبقية
              </Button>
            )}
            {canCreate && (
              <Button onClick={() => setCloneOpen(true)} variant="secondary" icon={<Copy size={16} />} className="desktop-only-btn">
                استنساخ المسار
              </Button>
            )}
            {plan.status !== 'completed' && plan.status !== 'cancelled' && (
              <Button variant="danger" icon={<XCircle size={16} />} onClick={() => setCancelOpen(true)}>
                إلغاء
              </Button>
            )}
          </div>
        }
      />

      {/* ── Summary ──────────────────────────────────────────────── */}
      <div className="edara-card vp-summary">
        <div className="vp-summary-item">
          <div className="vp-summary-value">{plan.total_customers}</div>
          <div className="vp-summary-label">إجمالي الزيارات</div>
        </div>
        <div className="vp-summary-item">
          <div className="vp-summary-value" style={{ color: 'var(--color-success)' }}>{plan.completed_count}</div>
          <div className="vp-summary-label">مكتملة</div>
        </div>
        <div className="vp-summary-item">
          <div className="vp-summary-value" style={{ color: 'var(--color-warning)' }}>{plan.skipped_count}</div>
          <div className="vp-summary-label">متخطاة</div>
        </div>
        <div className="vp-summary-item">
          <div className="vp-summary-value" style={{ color: 'var(--text-muted)' }}>{pendingItems.length}</div>
          <div className="vp-summary-label">معلّقة</div>
        </div>
        <div className="vp-summary-item vp-summary-item--status">
          <ActivityStatusBadge planStatus={plan.status} />
        </div>
      </div>

      {/* ── High Priority Alert ──────────────────────────────────── */}
      {highPriority.length > 0 && canSkip && (
        <div className="vp-alert-high">
          <span>⚠</span>
          <span>{highPriority.length} بند عالي الأولوية معلّق</span>
        </div>
      )}

      {/* ── Progress Bar ─────────────────────────────────────────── */}
      <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 'var(--space-2)', fontSize: 'var(--text-sm)' }}>
          <span style={{ color: 'var(--text-muted)' }}>التقدم</span>
          <span style={{ fontWeight: 700 }}>{plan.completion_pct.toFixed(0)}%</span>
        </div>
        <div style={{ height: 8, background: 'var(--bg-surface-2)', borderRadius: 99, overflow: 'hidden' }}>
          <div style={{
            height: '100%',
            width: `${Math.min(plan.completion_pct, 100)}%`,
            background: plan.completion_pct >= 100 ? 'var(--color-success)' : 'var(--color-primary)',
            borderRadius: 99,
            transition: 'width 0.5s ease',
          }} />
        </div>
      </div>

      {/* ── Plan Items ───────────────────────────────────────────── */}
      <div className="vp-items">
        {itemsLoading ? (
          [1, 2, 3].map(i => <CardSkeleton key={i} />)
        ) : items.length === 0 ? (
          <div className="empty-state" style={{ padding: 'var(--space-6)' }}>
            <MapPin size={36} className="empty-state-icon" />
            <p className="empty-state-title">لا توجد بنود في هذه الخطة</p>
            {canAddItem && (
              <Button icon={<Plus size={14} />} variant="secondary" onClick={() => setAddItemOpen(true)}>
                إضافة أول بند
              </Button>
            )}
          </div>
        ) : (
          items.map((item, idx) => (
            <div key={item.id} className="vp-item-wrapper">
              {/* Edit mode controls */}
              {editMode && (
                <div className="vp-edit-controls">
                  <button
                    className="vp-edit-btn"
                    disabled={idx === 0}
                    onClick={() => {
                      const ids = items.map(i => i.id)
                      ;[ids[idx - 1], ids[idx]] = [ids[idx], ids[idx - 1]]
                      reorderMut.mutate({ planId: id!, orderedItemIds: ids })
                    }}
                    title="تحريك للأعلى"
                  >
                    <ArrowUp size={14} />
                  </button>
                  <span className="vp-edit-seq">{idx + 1}</span>
                  <button
                    className="vp-edit-btn"
                    disabled={idx === items.length - 1}
                    onClick={() => {
                      const ids = items.map(i => i.id)
                      ;[ids[idx], ids[idx + 1]] = [ids[idx + 1], ids[idx]]
                      reorderMut.mutate({ planId: id!, orderedItemIds: ids })
                    }}
                    title="تحريك للأسفل"
                  >
                    <ArrowDown size={14} />
                  </button>
                  <button
                    className="vp-edit-btn vp-edit-btn--delete"
                    onClick={() => {
                      if (confirm('هل أنت متأكد من حذف هذا البند؟')) {
                        deleteItemMut.mutate(item.id, {
                          onSuccess: () => toast.success('تم حذف البند'),
                          onError: () => toast.error('فشل حذف البند'),
                        })
                      }
                    }}
                    title="حذف البند"
                  >
                    <Trash2 size={14} />
                  </button>
                </div>
              )}
              <PlanItemCard
                item={item}
                type="visit"
                onStart={canCreate && item.status === 'pending' ? () => navigate(
                  `/activities/new?visitPlanItemId=${item.id}&customerId=${item.customer_id ?? ''}`
                ) : undefined}
                onViewActivity={item.activity_id ? () => navigate(`/activities/${item.activity_id}`) : undefined}
              />
              {/* Skip + Reschedule */}
              {canSkip && item.status === 'pending' && (
                <div className="vp-item-actions">
                  <button
                    className="vp-action-btn vp-action-btn--skip"
                    onClick={() => { setSkipItem(item); setSkipReason('') }}
                  >
                    <SkipForward size={13} />
                    تخطي
                  </button>
                  <button
                    className="vp-action-btn vp-action-btn--reschedule"
                    onClick={() => { setRescheduleItem(item); setRescheduleDate(tomorrow()) }}
                  >
                    <Calendar size={13} />
                    إعادة جدولة
                  </button>
                  {item.planned_time && (
                    <span className="vp-item-time">
                      <Clock size={12} />
                      {item.planned_time}
                    </span>
                  )}
                </div>
              )}
              {/* Reschedule info */}
              {item.status === 'rescheduled' && item.reschedule_to && (
                <div className="vp-item-reschedule-badge">
                  <Calendar size={11} />
                  أُعيدت جدولته إلى: {new Date(item.reschedule_to).toLocaleDateString('ar-EG')}
                </div>
              )}
              {/* Skip reason */}
              {item.status === 'skipped' && item.skip_reason && (
                <div className="vp-item-skip-badge">
                  <XCircle size={11} />
                  سبب التخطي: {item.skip_reason}
                </div>
              )}
            </div>
          ))
        )}
      </div>

      {/* ─── Modal: إضافة بند ─── */}
      <ResponsiveModal
        open={addItemOpen}
        onClose={() => setAddItemOpen(false)}
        title="إضافة بند زيارة"
        disableOverlayClose={addingItem}
        footer={<>
          <Button variant="secondary" onClick={() => setAddItemOpen(false)} disabled={addingItem}>إلغاء</Button>
          <Button onClick={handleAddItem} disabled={addingItem || !itemCustomerId}>
            {addingItem ? 'جاري الإضافة...' : 'إضافة'}
          </Button>
        </>}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
          <div className="form-group">
            <label className="form-label">العميل <span className="form-required">*</span></label>
            <select className="form-select" value={itemCustomerId} onChange={e => setItemCustomerId(e.target.value)}>
              <option value="">-- اختر العميل --</option>
              {customers.map((c: any) => (
                <option key={c.id} value={c.id}>{c.name}{c.code ? ` (${c.code})` : ''}</option>
              ))}
            </select>
          </div>
          <div className="form-group">
            <label className="form-label">الغرض</label>
            <select className="form-select" value={itemPurposeType} onChange={e => setItemPurposeType(e.target.value as PlanItemPurposeType)}>
              <option value="">-- غير محدد --</option>
              <option value="sales">مبيعات</option>
              <option value="collection">تحصيل</option>
              <option value="activation">تنشيط</option>
              <option value="promotion">ترويج</option>
              <option value="followup">متابعة</option>
              <option value="service">خدمة</option>
            </select>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="form-group">
              <label className="form-label">الأولوية</label>
              <select className="form-select" value={itemPriority} onChange={e => setItemPriority(e.target.value as PlanPriority)}>
                <option value="high">عالية</option>
                <option value="normal">عادية</option>
                <option value="low">منخفضة</option>
              </select>
            </div>
            <div className="form-group">
              <label className="form-label">الوقت المخطط</label>
              <input type="time" className="form-input" value={itemPlannedTime} onChange={e => setItemPlannedTime(e.target.value)} />
            </div>
          </div>
          <div className="form-group">
            <label className="form-label">المدة المتوقعة (دقيقة)</label>
            <input type="number" className="form-input" value={itemDuration} min={5} max={480}
              onChange={e => setItemDuration(Number(e.target.value))} />
          </div>
        </div>
      </ResponsiveModal>

      {/* ─── Modal: Skip ─── */}
      <ResponsiveModal
        open={!!skipItem}
        onClose={() => { setSkipItem(null); setSkipReason(''); setSkipCustom('') }}
        title={`تخطي: ${skipItem?.customer?.name ?? '...'}`}
        disableOverlayClose={skipping}
        footer={<>
          <Button variant="secondary" onClick={() => setSkipItem(null)} disabled={skipping}>إلغاء</Button>
          <Button variant="danger" onClick={handleSkip} disabled={skipping || !skipReason}>
            {skipping ? 'جاري التخطي...' : 'تخطي البند'}
          </Button>
        </>}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <p style={{ margin: 0, fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>
            اختر سبب تخطي هذه الزيارة — سيُسجَّل للمراجعة.
          </p>
          <div className="vp-skip-reasons">
            {SKIP_REASONS.map(r => (
              <button
                key={r}
                type="button"
                className={`vp-skip-reason-btn${skipReason === r ? ' vp-skip-reason-btn--active' : ''}`}
                onClick={() => setSkipReason(r)}
              >
                {r}
              </button>
            ))}
          </div>
          {skipReason === 'أخرى' && (
            <div className="form-group">
              <label className="form-label">اذكر السبب</label>
              <input
                className="form-input"
                value={skipCustom}
                onChange={e => setSkipCustom(e.target.value)}
                placeholder="سبب التخطي..."
                autoFocus
              />
            </div>
          )}
        </div>
      </ResponsiveModal>

      {/* ─── Modal: Reschedule ─── */}
      <ResponsiveModal
        open={!!rescheduleItem}
        onClose={() => setRescheduleItem(null)}
        title={`إعادة جدولة: ${rescheduleItem?.customer?.name ?? '...'}`}
        disableOverlayClose={rescheduling}
        footer={<>
          <Button variant="secondary" onClick={() => setRescheduleItem(null)} disabled={rescheduling}>إلغاء</Button>
          <Button onClick={handleReschedule} disabled={rescheduling || !rescheduleDate}>
            {rescheduling ? 'جاري الجدولة...' : 'تأكيد إعادة الجدولة'}
          </Button>
        </>}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
          <p style={{ margin: 0, fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', lineHeight: 1.7 }}>
            اختر تاريخاً جديداً لزيارة <strong>{rescheduleItem?.customer?.name}</strong>.
            سيُحوَّل البند تلقائياً إلى الخطة المقابلة لذلك اليوم.
          </p>
          <div className="form-group">
            <label className="form-label">التاريخ الجديد <span className="form-required">*</span></label>
            <input
              type="date"
              className="form-input"
              value={rescheduleDate}
              min={tomorrow()}
              onChange={e => setRescheduleDate(e.target.value)}
            />
          </div>
        </div>
      </ResponsiveModal>

      {/* ─── Modal: تأكيد الخطة ─── */}
      <ResponsiveModal open={confirmOpen} onClose={() => setConfirmOpen(false)} title="تأكيد خطة الزيارات"
        disableOverlayClose={processing}
        footer={<>
          <Button variant="secondary" onClick={() => setConfirmOpen(false)} disabled={processing}>إلغاء</Button>
          <Button variant="success" onClick={handleConfirm} disabled={processing}>
            {processing ? 'جاري التأكيد...' : 'تأكيد'}
          </Button>
        </>}>
        <p style={{ margin: 0, color: 'var(--text-secondary)', fontSize: 'var(--text-sm)', lineHeight: 1.7 }}>
          تأكيد خطة {fmtDate(plan.plan_date)}؟ سيتلقى المندوب إشعاراً فورياً.
          لن تتمكن من تعديل البنود بعد التأكيد.
        </p>
      </ResponsiveModal>

      {/* ─── Modal: إلغاء الخطة ─── */}
      <ResponsiveModal open={cancelOpen} onClose={() => setCancelOpen(false)} title="إلغاء خطة الزيارات"
        disableOverlayClose={processing}
        footer={<>
          <Button variant="secondary" onClick={() => setCancelOpen(false)} disabled={processing}>تراجع</Button>
          <Button variant="danger" onClick={handleCancel} disabled={processing}>
            {processing ? 'جاري الإلغاء...' : 'إلغاء الخطة'}
          </Button>
        </>}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <p style={{ margin: 0, color: 'var(--text-secondary)', fontSize: 'var(--text-sm)' }}>
            إلغاء خطة {fmtDate(plan.plan_date)}؟ الزيارات المنجزة تبقى كما هي.
          </p>
          <div className="form-group">
            <label className="form-label">سبب الإلغاء (اختياري)</label>
            <textarea className="form-textarea" rows={2} value={cancelReason}
              onChange={e => setCancelReason(e.target.value)} placeholder="اذكر سبب الإلغاء..." />
          </div>
        </div>
      </ResponsiveModal>

      {/* ─── Modal: Bulk Close ─── */}
      <ResponsiveModal
        open={bulkCloseOpen}
        onClose={() => setBulkCloseOpen(false)}
        title="إنهاء يومية الخطة وتحويل المعلقات"
        disableOverlayClose={processing}
        footer={<>
          <Button variant="secondary" onClick={() => setBulkCloseOpen(false)} disabled={processing}>إلغاء</Button>
          <Button onClick={handleBulkClose} disabled={processing || !bulkReason.trim()}>
            {processing ? 'جاري التنفيذ...' : 'تسجيل كافة المعلقات كزيارات فائتة'}
          </Button>
        </>}
      >
        <div style={{ padding: 'var(--space-2) 0' }}>
          <p style={{ margin: '0 0 var(--space-4)', fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>
            يوجد <strong>{pendingItems.length}</strong> بنود معلقة. سيتم تسجيلها جميعاً كزيارات فائتة (Missed) وإغلاقها.
          </p>
          <div className="form-group">
            <label className="form-label">سبب التخطي الجماعي للبنود المتبقية <span className="form-required">*</span></label>
            <input
              className="form-input"
              value={bulkReason}
              onChange={e => setBulkReason(e.target.value)}
              placeholder="مثال: انتهاء دوام، ظروف جوية..."
            />
          </div>
        </div>
      </ResponsiveModal>

      {/* ─── Modal: Clone Plan ─── */}
      <ResponsiveModal
        open={cloneOpen}
        onClose={() => setCloneOpen(false)}
        title="استنساخ مسار خطة الزيارات"
        disableOverlayClose={processing}
        footer={<>
          <Button variant="secondary" onClick={() => setCloneOpen(false)} disabled={processing}>إلغاء</Button>
          <Button onClick={handleClone} disabled={processing || !cloneDate}>
            {processing ? 'جاري الاستنساخ...' : 'تأكيد العملية'}
          </Button>
        </>}
      >
        <div style={{ padding: 'var(--space-2) 0' }}>
          <p style={{ margin: '0 0 var(--space-4)', fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>
            سيتم استنساخ هذه الخطة ومسار العملاء لليوم الذي تختاره لمندوبك: <strong>{plan.employee?.full_name}</strong>. ستكون النسخة مسودة قابلة للتعديل.
          </p>
          <div className="form-group">
            <label className="form-label">تاريخ الخطة الجديدة <span className="form-required">*</span></label>
            <input
              type="date"
              className="form-input"
              value={cloneDate}
              onChange={e => setCloneDate(e.target.value)}
              required
            />
          </div>
        </div>
      </ResponsiveModal>

      <style>{`
        .vp-summary {
          display: grid;
          grid-template-columns: repeat(4, 1fr) auto;
          gap: var(--space-4);
          padding: var(--space-4);
          align-items: center;
        }
        .vp-summary-item { text-align: center; }
        .vp-summary-value { font-size: var(--text-xl); font-weight: 700; }
        .vp-summary-label { font-size: var(--text-xs); color: var(--text-muted); margin-top: 2px; }
        .vp-alert-high {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          padding: var(--space-3) var(--space-4);
          background: var(--color-warning-light);
          border: 1px solid var(--color-warning);
          border-radius: var(--radius-md);
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--color-warning);
        }
        .vp-items {
          display: flex;
          flex-direction: column;
          gap: var(--space-3);
          margin-top: var(--space-4);
        }
        .vp-item-wrapper {
          display: flex;
          flex-direction: column;
          gap: 0;
        }
        .vp-item-actions {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          padding: var(--space-2) var(--space-3);
          background: var(--bg-surface-2);
          border: 1px solid var(--border-primary);
          border-top: none;
          border-radius: 0 0 var(--radius-md) var(--radius-md);
          flex-wrap: wrap;
        }
        .vp-action-btn {
          display: inline-flex;
          align-items: center;
          gap: 4px;
          padding: 4px 10px;
          border-radius: var(--radius-sm);
          font-size: var(--text-xs);
          font-weight: 600;
          cursor: pointer;
          border: 1px solid;
          transition: all var(--transition-fast);
          font-family: inherit;
        }
        .vp-action-btn--skip {
          background: var(--color-warning-light);
          border-color: var(--color-warning);
          color: var(--color-warning);
        }
        .vp-action-btn--skip:hover { background: var(--color-warning); color: #fff; }
        .vp-action-btn--reschedule {
          background: var(--color-primary-light);
          border-color: var(--color-primary);
          color: var(--color-primary);
        }
        .vp-action-btn--reschedule:hover { background: var(--color-primary); color: #fff; }
        .vp-item-time {
          display: inline-flex;
          align-items: center;
          gap: 4px;
          font-size: var(--text-xs);
          color: var(--text-muted);
          margin-inline-start: auto;
        }
        .vp-item-reschedule-badge,
        .vp-item-skip-badge {
          display: flex;
          align-items: center;
          gap: 4px;
          font-size: 11px;
          padding: 3px var(--space-3);
          border-radius: 0 0 var(--radius-md) var(--radius-md);
          border: 1px solid;
          border-top: none;
        }
        .vp-item-reschedule-badge {
          background: var(--color-primary-light);
          border-color: var(--color-primary);
          color: var(--color-primary);
        }
        .vp-item-skip-badge {
          background: var(--color-warning-light);
          border-color: var(--color-warning);
          color: var(--color-warning);
        }
        /* Skip reasons grid */
        .vp-skip-reasons {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--space-2);
        }
        .vp-skip-reason-btn {
          padding: var(--space-2) var(--space-3);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-md);
          background: var(--bg-surface);
          color: var(--text-secondary);
          font-size: var(--text-sm);
          cursor: pointer;
          transition: all var(--transition-fast);
          font-family: inherit;
          text-align: center;
        }
        .vp-skip-reason-btn:hover { border-color: var(--color-warning); color: var(--color-warning); }
        .vp-skip-reason-btn--active {
          border-color: var(--color-warning);
          background: var(--color-warning);
          color: #fff;
          font-weight: 600;
        }
        /* Edit mode controls */
        .vp-edit-controls {
          display: flex;
          align-items: center;
          gap: var(--space-1);
          padding: var(--space-2) var(--space-3);
          background: var(--color-primary-light);
          border-radius: var(--radius-md) var(--radius-md) 0 0;
          border: 1px solid rgba(37,99,235,0.15);
          border-bottom: none;
        }
        .vp-edit-btn {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 28px;
          height: 28px;
          border: 1px solid var(--border-light);
          border-radius: var(--radius-sm);
          background: var(--bg-surface);
          cursor: pointer;
          color: var(--text-secondary);
          transition: all 0.15s ease;
          padding: 0;
        }
        .vp-edit-btn:hover:not(:disabled) {
          border-color: var(--color-primary);
          color: var(--color-primary);
          background: white;
        }
        .vp-edit-btn:disabled {
          opacity: 0.3;
          cursor: not-allowed;
        }
        .vp-edit-btn--delete {
          margin-inline-start: auto;
        }
        .vp-edit-btn--delete:hover:not(:disabled) {
          border-color: var(--color-danger);
          color: var(--color-danger);
          background: var(--color-danger-light);
        }
        .vp-edit-seq {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 22px;
          height: 22px;
          background: var(--color-primary);
          color: white;
          border-radius: 50%;
          font-size: 11px;
          font-weight: 700;
        }
        @media (max-width: 480px) {
          .vp-summary { grid-template-columns: repeat(2, 1fr); }
          .vp-skip-reasons { grid-template-columns: 1fr; }
        }
      `}</style>
    </div>
  )
}
