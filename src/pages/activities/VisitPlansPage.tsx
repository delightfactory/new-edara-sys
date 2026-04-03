import { useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuthStore } from '@/stores/auth-store'
import { useVisitPlans, useConfirmVisitPlan, useCancelVisitPlan } from '@/hooks/useQueryHooks'
import { PERMISSIONS } from '@/lib/permissions/constants'
import { toast } from 'sonner'
import { MapPin, Plus, Eye, CheckCircle, XCircle, Calendar } from 'lucide-react'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import PermissionGuard from '@/components/shared/PermissionGuard'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import ActivityStatusBadge from '@/components/shared/ActivityStatusBadge'
import type { VisitPlan, PlanStatus } from '@/lib/types/activities'

function fmtDate(d: string) {
  return new Date(d).toLocaleDateString('ar-EG', { weekday: 'short', day: 'numeric', month: 'short' })
}

export default function VisitPlansPage() {
  const navigate = useNavigate()
  const can      = useAuthStore(s => s.can)

  const [statusFilter, setStatusFilter] = useState<PlanStatus | ''>('')
  const [dateFrom,     setDateFrom]     = useState('')
  const [dateTo,       setDateTo]       = useState('')
  const [page,         setPage]         = useState(1)
  const [cancelTarget, setCancelTarget] = useState<VisitPlan | null>(null)
  const [cancelReason, setCancelReason] = useState('')
  const [confirmTarget, setConfirmTarget] = useState<VisitPlan | null>(null)
  const [processing, setProcessing]     = useState(false)

  const confirmPlan = useConfirmVisitPlan()
  const cancelPlan  = useCancelVisitPlan()

  const queryParams = useMemo(() => ({
    status:   statusFilter || undefined,
    dateFrom: dateFrom     || undefined,
    dateTo:   dateTo       || undefined,
    page,
    pageSize: 25,
  }), [statusFilter, dateFrom, dateTo, page])

  const { data: result, isLoading: loading } = useVisitPlans(queryParams)
  const plans       = result?.data     ?? []
  const totalPages  = result?.totalPages ?? 1
  const totalCount  = result?.count    ?? 0

  const canCreate   = can(PERMISSIONS.VISIT_PLANS_CREATE)
  const canConfirm  = can(PERMISSIONS.VISIT_PLANS_CONFIRM) || can(PERMISSIONS.VISIT_PLANS_READ_ALL)

  const handleConfirm = async () => {
    if (!confirmTarget) return
    setProcessing(true)
    confirmPlan.mutate(confirmTarget.id, {
      onSuccess: () => { toast.success('تم تأكيد الخطة'); setConfirmTarget(null) },
      onError:   () => toast.error('فشل تأكيد الخطة'),
      onSettled: () => setProcessing(false),
    })
  }

  const handleCancel = async () => {
    if (!cancelTarget) return
    setProcessing(true)
    cancelPlan.mutate({ id: cancelTarget.id, reason: cancelReason }, {
      onSuccess: () => { toast.success('تم إلغاء الخطة'); setCancelTarget(null); setCancelReason('') },
      onError:   () => toast.error('فشل إلغاء الخطة'),
      onSettled: () => setProcessing(false),
    })
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="خطط الزيارات"
        subtitle={loading ? '...' : `${totalCount} خطة`}
        actions={
          <PermissionGuard permission={PERMISSIONS.VISIT_PLANS_CREATE}>
            <Button icon={<Plus size={16} />} onClick={() => navigate('/activities/visit-plans/new')} className="desktop-only-btn">
              خطة جديدة
            </Button>
          </PermissionGuard>
        }
      />

      {/* Filters */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="act-filter-row">
          <select
            className="form-select filter-select"
            value={statusFilter}
            onChange={e => { setStatusFilter(e.target.value as PlanStatus | ''); setPage(1) }}
          >
            <option value="">كل الحالات</option>
            <option value="draft">مسودة</option>
            <option value="confirmed">مؤكدة</option>
            <option value="in_progress">جارية</option>
            <option value="completed">مكتملة</option>
            <option value="partial">جزئية</option>
            <option value="cancelled">ملغاة</option>
            <option value="missed">فائتة</option>
          </select>
          <input type="date" className="form-input filter-select" value={dateFrom}
            onChange={e => { setDateFrom(e.target.value); setPage(1) }} title="من تاريخ" />
          <input type="date" className="form-input filter-select" value={dateTo}
            onChange={e => { setDateTo(e.target.value); setPage(1) }} title="إلى تاريخ" />
        </div>
      </div>

      {/* Desktop Table */}
      <div className="act-table-view edara-card" style={{ overflow: 'auto' }}>
        <DataTable<VisitPlan>
          columns={[
            {
              key: 'plan_date', label: 'التاريخ',
              render: p => (
                <>
                  <div className="font-bold text-sm">{fmtDate(p.plan_date)}</div>
                  <div className="text-xs text-muted">
                    {p.plan_type === 'daily' ? 'يومية' : p.plan_type === 'weekly' ? 'أسبوعية' : 'حملة'}
                  </div>
                </>
              ),
            },
            {
              key: 'employee', label: 'المندوب', hideOnMobile: true,
              render: p => p.employee?.full_name || '—',
            },
            {
              key: 'status', label: 'الحالة',
              render: p => <ActivityStatusBadge planStatus={p.status} size="sm" />,
            },
            {
              key: 'progress', label: 'التقدم',
              render: p => (
                <div>
                  <div className="font-bold text-sm">
                    {p.completed_count}/{p.total_customers}
                    <span className="text-xs text-muted" style={{ marginInlineEnd: 4 }}>
                      ({p.completion_pct.toFixed(0)}%)
                    </span>
                  </div>
                  <div style={{ height: 4, background: 'var(--bg-surface-2)', borderRadius: 99, marginTop: 4, overflow: 'hidden', width: 80 }}>
                    <div style={{ height: '100%', width: `${Math.min(p.completion_pct, 100)}%`, background: 'var(--color-primary)', borderRadius: 99 }} />
                  </div>
                </div>
              ),
            },
            {
              key: 'actions', label: '', width: 120,
              render: p => (
                <div className="flex gap-1" onClick={e => e.stopPropagation()}>
                  <Button variant="ghost" size="sm" onClick={() => navigate(`/activities/visit-plans/${p.id}`)}>
                    <Eye size={14} />
                  </Button>
                  {canConfirm && p.status === 'draft' && (
                    <Button variant="success" size="sm" onClick={() => setConfirmTarget(p)}>
                      <CheckCircle size={14} />
                    </Button>
                  )}
                  {p.status !== 'completed' && p.status !== 'cancelled' && (
                    <Button variant="danger" size="sm" onClick={() => setCancelTarget(p)}>
                      <XCircle size={14} />
                    </Button>
                  )}
                </div>
              ),
            },
          ]}
          data={plans}
          loading={loading}
          onRowClick={p => navigate(`/activities/visit-plans/${p.id}`)}
          emptyIcon={<MapPin size={48} />}
          emptyTitle="لا توجد خطط زيارات"
          emptyAction={
            <PermissionGuard permission={PERMISSIONS.VISIT_PLANS_CREATE}>
              <Button icon={<Plus size={16} />} onClick={() => navigate('/activities/visit-plans/new')}>
                خطة جديدة
              </Button>
            </PermissionGuard>
          }
          page={page}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setPage}
          dataCardMapping={p => ({
            title: fmtDate(p.plan_date),
            subtitle: p.employee?.full_name,
            badge: <ActivityStatusBadge planStatus={p.status} size="sm" />,
            metadata: [
              { label: 'التقدم', value: `${p.completed_count}/${p.total_customers} (${p.completion_pct.toFixed(0)}%)`, highlight: p.completion_pct >= 100 },
              ...(p.skipped_count > 0 ? [{ label: 'متخطاة', value: String(p.skipped_count) }] : []),
            ],
            actions: (
              <div className="flex gap-2" style={{ width: '100%' }}>
                <Button variant="secondary" size="sm" onClick={() => navigate(`/activities/visit-plans/${p.id}`)}
                  style={{ flex: 1, justifyContent: 'center' }}>
                  <Eye size={14} /> تفاصيل
                </Button>
                {canConfirm && p.status === 'draft' && (
                  <Button variant="success" size="sm" onClick={() => setConfirmTarget(p)}>
                    <CheckCircle size={14} />
                  </Button>
                )}
              </div>
            ),
            onClick: () => navigate(`/activities/visit-plans/${p.id}`),
          })}
        />
      </div>

      {/* Confirm Modal */}
      <ResponsiveModal
        open={!!confirmTarget}
        onClose={() => setConfirmTarget(null)}
        title="تأكيد خطة الزيارات"
        disableOverlayClose={processing}
        footer={
          <>
            <Button variant="secondary" onClick={() => setConfirmTarget(null)} disabled={processing}>إلغاء</Button>
            <Button variant="success" onClick={handleConfirm} disabled={processing}>
              {processing ? 'جاري التأكيد...' : 'تأكيد'}
            </Button>
          </>
        }
      >
        <p className="text-secondary text-sm m-0" style={{ lineHeight: 1.7 }}>
          تأكيد خطة {confirmTarget && fmtDate(confirmTarget.plan_date)}؟ لن تتمكن من تعديل البنود بعد التأكيد.
        </p>
      </ResponsiveModal>

      {/* Cancel Modal */}
      <ResponsiveModal
        open={!!cancelTarget}
        onClose={() => { setCancelTarget(null); setCancelReason('') }}
        title="إلغاء خطة الزيارات"
        disableOverlayClose={processing}
        footer={
          <>
            <Button variant="secondary" onClick={() => { setCancelTarget(null); setCancelReason('') }} disabled={processing}>
              تراجع
            </Button>
            <Button variant="danger" onClick={handleCancel} disabled={processing}>
              {processing ? 'جاري الإلغاء...' : 'إلغاء الخطة'}
            </Button>
          </>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <p className="text-secondary text-sm m-0" style={{ lineHeight: 1.7 }}>
            إلغاء خطة {cancelTarget && fmtDate(cancelTarget.plan_date)}؟
          </p>
          <div className="form-group">
            <label className="form-label">سبب الإلغاء (اختياري)</label>
            <textarea className="form-textarea" rows={2} value={cancelReason}
              onChange={e => setCancelReason(e.target.value)} placeholder="اذكر سبب الإلغاء..." />
          </div>
        </div>
      </ResponsiveModal>

      <style>{`
        .act-filter-row { display: flex; gap: var(--space-3); flex-wrap: wrap; align-items: flex-end; }
        .filter-select { min-width: 120px; flex: 1; }
        .act-table-view { display: block; }
        @media (max-width: 768px) {
          .desktop-only-btn { display: none; }
        }
      `}</style>
    </div>
  )
}
