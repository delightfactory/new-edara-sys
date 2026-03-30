import { useParams, useNavigate } from 'react-router-dom'
import {
  useVisitPlan, useVisitPlanItems,
  useConfirmVisitPlan, useCancelVisitPlan,
  useAddVisitPlanItem,
  useCustomers,
} from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import { PERMISSIONS } from '@/lib/permissions/constants'
import { toast } from 'sonner'
import { useState } from 'react'
import { MapPin, CheckCircle, XCircle, Plus } from 'lucide-react'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'
import PlanItemCard from '@/components/shared/PlanItemCard'
import ActivityStatusBadge from '@/components/shared/ActivityStatusBadge'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import type { VisitPlanItemInput, PlanItemPurposeType, PlanPriority } from '@/lib/types/activities'

function fmtDate(d: string) {
  return new Date(d).toLocaleDateString('ar-EG', { weekday: 'long', day: 'numeric', month: 'long' })
}

export default function VisitPlanDetail() {
  const { id }   = useParams<{ id: string }>()
  const navigate = useNavigate()
  const can      = useAuthStore(s => s.can)

  // Modal state
  const [confirmOpen,  setConfirmOpen]  = useState(false)
  const [cancelOpen,   setCancelOpen]   = useState(false)
  const [cancelReason, setCancelReason] = useState('')
  const [processing,   setProcessing]   = useState(false)

  // Add item state
  const [addItemOpen,    setAddItemOpen]    = useState(false)
  const [itemCustomerId, setItemCustomerId] = useState('')
  const [itemPurposeType,setItemPurposeType]= useState<PlanItemPurposeType | ''>('')
  const [itemPriority,   setItemPriority]   = useState<PlanPriority>('normal')
  const [itemPlannedTime,setItemPlannedTime]= useState('')
  const [itemDuration,   setItemDuration]   = useState(30)
  const [addingItem,     setAddingItem]     = useState(false)

  // Data
  const { data: plan,  isLoading: planLoading  } = useVisitPlan(id)
  const { data: items = [], isLoading: itemsLoading } = useVisitPlanItems(id)
  const { data: customersRes } = useCustomers({ pageSize: 200 })
  const customers = customersRes?.data ?? []

  // Mutations
  const confirmPlan = useConfirmVisitPlan()
  const cancelPlan  = useCancelVisitPlan()
  const addPlanItem = useAddVisitPlanItem()

  // Permissions
  const canConfirm = can(PERMISSIONS.VISIT_PLANS_CONFIRM) || can(PERMISSIONS.VISIT_PLANS_READ_ALL)
  const canCreate  = can(PERMISSIONS.ACTIVITIES_CREATE)
  const canAddItem = can(PERMISSIONS.VISIT_PLANS_CREATE) && plan?.status === 'draft'

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
          setItemPriority('normal'); setItemPlannedTime('')
          setItemDuration(30)
        },
        onError:   (e: any) => toast.error(e?.message || 'فشل إضافة البند'),
        onSettled: () => setAddingItem(false),
      }
    )
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
          <Button variant="secondary" onClick={() => navigate('/activities/visit-plans')}>العودة</Button>
        </div>
      </div>
    )
  }

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
            {canAddItem && (
              <Button icon={<Plus size={16} />} variant="secondary" onClick={() => setAddItemOpen(true)}>
                إضافة بند
              </Button>
            )}
            {canConfirm && plan.status === 'draft' && (
              <Button variant="success" icon={<CheckCircle size={16} />} onClick={() => setConfirmOpen(true)}>
                تأكيد
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
        <div className="vp-summary-item vp-summary-item--status">
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
      <div className="vp-items">
        {itemsLoading ? (
          [1, 2, 3].map(i => (
            <div key={i} className="edara-card" style={{ padding: 'var(--space-4)' }}>
              <div className="skeleton" style={{ height: 16, width: '60%', marginBottom: 8 }} />
              <div className="skeleton" style={{ height: 12, width: '40%' }} />
            </div>
          ))
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
          items.map(item => (
            <PlanItemCard
              key={item.id}
              item={item}
              type="visit"
              onStart={canCreate ? () => navigate(
                `/activities/new?visitPlanItemId=${item.id}&customerId=${item.customer_id ?? ''}`
              ) : undefined}
            />
          ))
        )}
      </div>

      {/* ─── Modal: إضافة بند زيارة ─── */}
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
              <option value="activation">تفعيل</option>
              <option value="promotion">ترويج</option>
              <option value="followup">متابعة</option>
              <option value="service">خدمة</option>
            </select>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)' }}>
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

      {/* ─── Modal: تأكيد ─── */}
      <ResponsiveModal open={confirmOpen} onClose={() => setConfirmOpen(false)} title="تأكيد خطة الزيارات"
        disableOverlayClose={processing}
        footer={<>
          <Button variant="secondary" onClick={() => setConfirmOpen(false)} disabled={processing}>إلغاء</Button>
          <Button variant="success" onClick={handleConfirm} disabled={processing}>
            {processing ? 'جاري التأكيد...' : 'تأكيد'}
          </Button>
        </>}>
        <p style={{ margin: 0, color: 'var(--text-secondary)', fontSize: 'var(--text-sm)', lineHeight: 1.7 }}>
          تأكيد خطة {fmtDate(plan.plan_date)}؟ لن تتمكن من تعديل البنود بعد التأكيد.
        </p>
      </ResponsiveModal>

      {/* ─── Modal: إلغاء ─── */}
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
            إلغاء خطة {fmtDate(plan.plan_date)}؟
          </p>
          <div className="form-group">
            <label className="form-label">سبب الإلغاء (اختياري)</label>
            <textarea className="form-textarea" rows={2} value={cancelReason}
              onChange={e => setCancelReason(e.target.value)} placeholder="اذكر سبب الإلغاء..." />
          </div>
        </div>
      </ResponsiveModal>

      <style>{`
        .vp-summary {
          display: grid;
          grid-template-columns: repeat(3, 1fr) auto;
          gap: var(--space-4);
          padding: var(--space-4);
          align-items: center;
        }
        .vp-summary-item { text-align: center; }
        .vp-summary-value { font-size: var(--text-xl); font-weight: 700; }
        .vp-summary-label { font-size: var(--text-xs); color: var(--text-muted); margin-top: 2px; }
        .vp-items {
          display: flex;
          flex-direction: column;
          gap: var(--space-3);
          margin-top: var(--space-4);
        }
        @media (max-width: 480px) {
          .vp-summary { grid-template-columns: repeat(2, 1fr); }
        }
      `}</style>
    </div>
  )
}
