import { useParams, useNavigate } from 'react-router-dom'
import {
  useCallPlan, useCallPlanItems,
  useConfirmCallPlan, useCancelCallPlan,
  useAddCallPlanItem, useUpdateCallPlanItem,
  useCustomers, useCreateCallPlan,
} from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import { PERMISSIONS } from '@/lib/permissions/constants'
import { toast } from 'sonner'
import { useState } from 'react'
import { Phone, CheckCircle, XCircle, Plus, Archive, Copy } from 'lucide-react'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'
import PlanItemCard from '@/components/shared/PlanItemCard'
import ActivityStatusBadge from '@/components/shared/ActivityStatusBadge'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import { CardSkeleton } from '@/components/ui/Skeleton'
import type { CallPlanItemInput, PlanItemPurposeType, PlanPriority } from '@/lib/types/activities'

function fmtDate(d: string) {
  return new Date(d).toLocaleDateString('ar-EG', { weekday: 'long', day: 'numeric', month: 'long' })
}

function tomorrow(): string {
  const d = new Date()
  d.setDate(d.getDate() + 1)
  return d.toISOString().slice(0, 10)
}

export default function CallPlanDetail() {
  const { id }   = useParams<{ id: string }>()
  const navigate = useNavigate()
  const can      = useAuthStore(s => s.can)

  // Modal state
  const [confirmOpen,  setConfirmOpen]  = useState(false)
  const [cancelOpen,   setCancelOpen]   = useState(false)
  const [cancelReason, setCancelReason] = useState('')
  const [processing,   setProcessing]   = useState(false)

  // Add item state
  const [addItemOpen,      setAddItemOpen]      = useState(false)
  const [itemCustomerId,   setItemCustomerId]   = useState('')
  const [itemContactName,  setItemContactName]  = useState('')
  const [itemPhoneNumber,  setItemPhoneNumber]  = useState('')
  const [itemPurposeType,  setItemPurposeType]  = useState<PlanItemPurposeType | ''>('')
  const [itemPriority,     setItemPriority]     = useState<PlanPriority>('normal')
  const [itemPlannedTime,  setItemPlannedTime]  = useState('')
  const [itemDuration,     setItemDuration]     = useState(10)
  const [addingItem,       setAddingItem]       = useState(false)
  // toggle: عميل مسجل أم جهة خارجية
  const [useCustomer, setUseCustomer] = useState(true)

  // ── Modal: Bulk Close
  const [bulkCloseOpen, setBulkCloseOpen] = useState(false)
  const [bulkReason,    setBulkReason]    = useState('تخطي جماعي')

  // ── Modal: Clone Plan
  const [cloneOpen, setCloneOpen] = useState(false)
  const [cloneDate, setCloneDate] = useState(tomorrow())

  // Data
  const { data: plan,  isLoading: planLoading  } = useCallPlan(id)
  const { data: items = [], isLoading: itemsLoading } = useCallPlanItems(id)
  const { data: customersRes } = useCustomers({ pageSize: 200 })
  const customers = customersRes?.data ?? []

  // Mutations
  const confirmPlan = useConfirmCallPlan()
  const cancelPlan  = useCancelCallPlan()
  const addPlanItem = useAddCallPlanItem()
  const updatePlanItem = useUpdateCallPlanItem()
  const createPlan  = useCreateCallPlan()

  // Permissions
  const canConfirm = can(PERMISSIONS.CALL_PLANS_CONFIRM) || can(PERMISSIONS.CALL_PLANS_READ_ALL)
  const canCreate  = can(PERMISSIONS.ACTIVITIES_CREATE)
  const canAddItem = can(PERMISSIONS.CALL_PLANS_CREATE) && plan?.status === 'draft'

  // Handlers
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

  const handleAddItem = () => {
    if (!id) return
    // تحقق: إما customer أو phone_number
    if (useCustomer && !itemCustomerId) { toast.error('اختر العميل'); return }
    if (!useCustomer && !itemPhoneNumber.trim()) { toast.error('أدخل رقم الهاتف'); return }
    setAddingItem(true)

    const itemInput: CallPlanItemInput = {
      customer_id:            useCustomer ? itemCustomerId : null,
      contact_name:           !useCustomer ? (itemContactName || null) : null,
      phone_number:           !useCustomer ? itemPhoneNumber.trim() : null,
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
          setItemCustomerId(''); setItemContactName(''); setItemPhoneNumber('')
          setItemPurposeType(''); setItemPriority('normal')
          setItemPlannedTime(''); setItemDuration(10)
        },
        onError:   (e: any) => toast.error(e?.message || 'فشل إضافة البند'),
        onSettled: () => setAddingItem(false),
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
    if (errs > 0) toast.warning(`تم إقفال البعض، ولكن فشل ${errs} بند`)
    else toast.success('تم إقفال اليومية بنجاح')
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
        notes: `نسخة مستنسخة من خطة اتصالات يوم ${plan.plan_date}`,
      })
      
      let copied = 0
      for (const item of items) {
        try {
          await addPlanItem.mutateAsync({
            planId: newPlan.id,
            item: {
              customer_id: item.customer_id,
              contact_name: item.contact_name || null,
              phone_number: item.phone_number || null,
              sequence: item.sequence,
              purpose_type: item.purpose_type || null,
              priority: item.priority,
              planned_time: item.planned_time || null,
              estimated_duration_min: item.estimated_duration_min || 10,
            }
          })
          copied++
        } catch { /* ignore individual errors */ }
      }
      
      toast.success(`تم الاستنساخ (نسخ ${copied} مكالمة)`)
      setCloneOpen(false)
      navigate(`/activities/call-plans/${newPlan.id}`)
    } catch {
      toast.error('فشل استنساخ الخطة')
    }
    setProcessing(false)
  }

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
          <Button variant="secondary" onClick={() => navigate('/activities/call-plans')}>العودة</Button>
        </div>
      </div>
    )
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title={`خطة مكالمات — ${fmtDate(plan.plan_date)}`}
        subtitle={plan.employee?.full_name}
        breadcrumbs={[
          { label: 'خطط المكالمات', path: '/activities/call-plans' },
          { label: fmtDate(plan.plan_date) },
        ]}
        actions={
          <div className="flex gap-2">
            {canAddItem && (
              <Button icon={<Plus size={16} />} variant="secondary" onClick={() => setAddItemOpen(true)}>
                إضافة بند
              </Button>
            )}
            {canConfirm && plan.status === 'draft' && items.length > 0 && (
              <Button onClick={() => setConfirmOpen(true)} icon={<CheckCircle size={16} />}>
                تأكيد واعتماد
              </Button>
            )}

            {/* Bulk Close */}
            {canConfirm && plan.status === 'in_progress' && pendingItems.length > 0 && (
              <Button onClick={() => setBulkCloseOpen(true)} variant="secondary" icon={<Archive size={16} />} className="desktop-only-btn">
                إنهاء اليومية المتبقية
              </Button>
            )}

            {/* Clone Plan */}
            {canCreate && (
              <Button onClick={() => setCloneOpen(true)} variant="secondary" icon={<Copy size={16} />} className="desktop-only-btn">
                استنساخ القائمة
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

      {/* Summary */}
      <div className="edara-card cp-summary">
        <div className="cp-summary-item">
          <div className="cp-summary-value">{plan.total_calls}</div>
          <div className="cp-summary-label">إجمالي المكالمات</div>
        </div>
        <div className="cp-summary-item">
          <div className="cp-summary-value" style={{ color: 'var(--color-success)' }}>{plan.completed_count}</div>
          <div className="cp-summary-label">مكتملة</div>
        </div>
        <div className="cp-summary-item">
          <div className="cp-summary-value" style={{ color: 'var(--color-warning)' }}>
            {plan.total_calls - plan.completed_count - (plan.skipped_count ?? 0)}
          </div>
          <div className="cp-summary-label">متبقية</div>
        </div>
        <div className="cp-summary-item cp-summary-item--status">
          <ActivityStatusBadge planStatus={plan.status} />
        </div>
      </div>

      {/* Progress Bar */}
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

      {/* Plan Items */}
      <div className="cp-items">
        {itemsLoading ? (
          [1, 2, 3].map(i => <CardSkeleton key={i} />)
        ) : items.length === 0 ? (
          <div className="empty-state" style={{ padding: 'var(--space-6)' }}>
            <Phone size={36} className="empty-state-icon" />
            <p className="empty-state-title">لا توجد بنود في هذه الخطة</p>
            {canAddItem && (
              <Button icon={<Plus size={14} />} variant="secondary" onClick={() => setAddItemOpen(true)}>
                إضافة أول بند
              </Button>
            )}
          </div>
        ) : (
          items.map(item => (
            <PlanItemCard
              key={item.id}
              item={item}
              type="call"
              onStart={canCreate ? () => navigate(
                `/activities/new?callPlanItemId=${item.id}&customerId=${item.customer_id ?? ''}`
              ) : undefined}
              onViewActivity={item.activity_id ? () => navigate(`/activities/${item.activity_id}`) : undefined}
            />
          ))
        )}
      </div>

      {/* ─── Modal: إضافة بند مكالمة ─── */}
      <ResponsiveModal
        open={addItemOpen}
        onClose={() => setAddItemOpen(false)}
        title="إضافة بند مكالمة"
        disableOverlayClose={addingItem}
        footer={<>
          <Button variant="secondary" onClick={() => setAddItemOpen(false)} disabled={addingItem}>إلغاء</Button>
          <Button onClick={handleAddItem} disabled={addingItem}>
            {addingItem ? 'جاري الإضافة...' : 'إضافة'}
          </Button>
        </>}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>

          {/* Toggle: عميل مسجل / جهة خارجية */}
          <div className="cp-item-toggle">
            <button
              type="button"
              className={`cp-toggle-btn${useCustomer ? ' cp-toggle-btn--active' : ''}`}
              onClick={() => setUseCustomer(true)}
            >
              👤 عميل مسجل
            </button>
            <button
              type="button"
              className={`cp-toggle-btn${!useCustomer ? ' cp-toggle-btn--active' : ''}`}
              onClick={() => setUseCustomer(false)}
            >
              📱 جهة خارجية
            </button>
          </div>

          {useCustomer ? (
            <div className="form-group">
              <label className="form-label">العميل <span className="form-required">*</span></label>
              <select className="form-select" value={itemCustomerId} onChange={e => setItemCustomerId(e.target.value)}>
                <option value="">-- اختر العميل --</option>
                {customers.map((c: any) => (
                  <option key={c.id} value={c.id}>{c.name}{c.code ? ` (${c.code})` : ''}</option>
                ))}
              </select>
            </div>
          ) : (
            <>
              <div className="form-group">
                <label className="form-label">رقم الهاتف <span className="form-required">*</span></label>
                <input
                  className="form-input"
                  dir="ltr"
                  value={itemPhoneNumber}
                  onChange={e => setItemPhoneNumber(e.target.value)}
                  placeholder="+20..."
                  type="tel"
                />
              </div>
              <div className="form-group">
                <label className="form-label">اسم جهة الاتصال</label>
                <input
                  className="form-input"
                  value={itemContactName}
                  onChange={e => setItemContactName(e.target.value)}
                  placeholder="اختياري..."
                />
              </div>
            </>
          )}

          <div className="form-group">
            <label className="form-label">الغرض</label>
            <select className="form-select" value={itemPurposeType} onChange={e => setItemPurposeType(e.target.value as PlanItemPurposeType)}>
              <option value="">-- غير محدد --</option>
              <option value="sales">مبيعات</option>
              <option value="collection">تحصيل</option>
              <option value="activation">تفعيل</option>
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
            <input type="number" className="form-input" value={itemDuration} min={1} max={120}
              onChange={e => setItemDuration(Number(e.target.value))} />
          </div>
        </div>
      </ResponsiveModal>

      {/* ─── Modal: تأكيد ─── */}
      <ResponsiveModal open={confirmOpen} onClose={() => setConfirmOpen(false)} title="تأكيد خطة المكالمات"
        disableOverlayClose={processing}
        footer={<>
          <Button variant="secondary" onClick={() => setConfirmOpen(false)} disabled={processing}>إلغاء</Button>
          <Button variant="success" onClick={handleConfirm} disabled={processing}>
            {processing ? 'جاري التأكيد...' : 'تأكيد'}
          </Button>
        </>}>
        <p style={{ margin: 0, color: 'var(--text-secondary)', fontSize: 'var(--text-sm)', lineHeight: 1.7 }}>
          تأكيد خطة {fmtDate(plan.plan_date)}؟
        </p>
      </ResponsiveModal>

      {/* ─── Modal: إلغاء ─── */}
      <ResponsiveModal open={cancelOpen} onClose={() => { setCancelOpen(false); setCancelReason('') }} title="إلغاء خطة المكالمات"
        disableOverlayClose={processing}
        footer={<>
          <Button variant="secondary" onClick={() => { setCancelOpen(false); setCancelReason('') }} disabled={processing}>تراجع</Button>
          <Button variant="danger" onClick={handleCancel} disabled={processing}>
            {processing ? 'جاري الإلغاء...' : 'إلغاء الخطة'}
          </Button>
        </>}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <p style={{ margin: 0, color: 'var(--text-secondary)', fontSize: 'var(--text-sm)' }}>
            إلغاء خطة {fmtDate(plan.plan_date)}؟
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
        title="إنهاء يومية الاتصالات"
        disableOverlayClose={processing}
        footer={<>
          <Button variant="secondary" onClick={() => setBulkCloseOpen(false)} disabled={processing}>إلغاء</Button>
          <Button onClick={handleBulkClose} disabled={processing || !bulkReason.trim()}>
            {processing ? 'جاري التنفيذ...' : 'تسجيل كافة المعلقات كفائتة'}
          </Button>
        </>}
      >
        <div style={{ padding: 'var(--space-2) 0' }}>
          <p style={{ margin: '0 0 var(--space-4)', fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>
            يوجد <strong>{pendingItems.length}</strong> مكالمة معلقة. سيتم تسجيلها جميعاً كفائتة وإغلاقها.
          </p>
          <div className="form-group">
            <label className="form-label">سبب التخطي الجماعي للبنود المتبقية <span className="form-required">*</span></label>
            <input
              className="form-input"
              value={bulkReason}
              onChange={e => setBulkReason(e.target.value)}
              placeholder="مثال: انتهاء دوام، أو طارئ..."
            />
          </div>
        </div>
      </ResponsiveModal>

      {/* ─── Modal: Clone Plan ─── */}
      <ResponsiveModal
        open={cloneOpen}
        onClose={() => setCloneOpen(false)}
        title="استنساخ قائمة المكالمات"
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
            سيتم استنساخ هذه القائمة لتاريخ جديد كمسودة لمندوبك <strong>{plan.employee?.full_name}</strong>.
          </p>
          <div className="form-group">
            <label className="form-label">تاريخ خطة المكالمات الجديدة <span className="form-required">*</span></label>
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
        .cp-summary {
          display: grid;
          grid-template-columns: repeat(3, 1fr) auto;
          gap: var(--space-4);
          padding: var(--space-4);
          align-items: center;
        }
        .cp-summary-item { text-align: center; }
        .cp-summary-value { font-size: var(--text-xl); font-weight: 700; }
        .cp-summary-label { font-size: var(--text-xs); color: var(--text-muted); margin-top: 2px; }
        .cp-items {
          display: flex;
          flex-direction: column;
          gap: var(--space-3);
          margin-top: var(--space-4);
        }
        .cp-item-toggle {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--space-2);
        }
        .cp-toggle-btn {
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
        .cp-toggle-btn--active {
          border-color: var(--color-primary);
          background: var(--color-primary);
          color: #fff;
          font-weight: 700;
        }
        @media (max-width: 480px) {
          .cp-summary { grid-template-columns: repeat(2, 1fr); }
        }
      `}</style>
    </div>
  )
}
