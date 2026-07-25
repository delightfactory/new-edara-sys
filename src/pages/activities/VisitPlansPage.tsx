import { useState, useMemo, useRef } from 'react'
import { useNavigate, Link } from 'react-router-dom'
import { useAuthStore } from '@/stores/auth-store'
import {
  useVisitPlans,
  useConfirmVisitPlan,
  useCancelVisitPlan,
  useConfirmVisitPlanAtomic,
  useCancelVisitPlanAtomic,
  useHREmployees
} from '@/hooks/useQueryHooks'
import { PERMISSIONS } from '@/lib/permissions/constants'
import { VISITS_ATOMIC_EXECUTION } from '@/lib/config/features'
import { toast } from 'sonner'
import { MapPin, Plus, Eye, CheckCircle, XCircle, Calendar, Search, Filter, ChevronDown } from 'lucide-react'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import ActivityStatusBadge, { PLAN_STATUS_CONFIG } from '@/components/shared/ActivityStatusBadge'
import EmptyState from '@/components/shared/EmptyState'
import type { VisitPlan, PlanStatus } from '@/lib/types/activities'

const PLAN_TYPE_LABELS: Record<VisitPlan['plan_type'], string> = {
  daily: 'يومية',
  weekly: 'أسبوعية',
  campaign: 'حملة',
  recurring: 'متكررة',
}

function fmtDate(d: string) {
  return new Date(d).toLocaleDateString('ar-EG-u-nu-latn', { weekday: 'short', day: 'numeric', month: 'short' })
}

export default function VisitPlansPage() {
  const navigate = useNavigate()
  const can      = useAuthStore(s => s.can)

  // ── Filters
  const [statusFilter, setStatusFilter] = useState<PlanStatus | ''>('')
  const [planTypeFilter, setPlanTypeFilter] = useState<VisitPlan['plan_type'] | ''>('')
  const [employeeFilter, setEmployeeFilter] = useState('')
  const [dateFrom,     setDateFrom]     = useState('')
  const [dateTo,       setDateTo]       = useState('')
  const [page,         setPage]         = useState(1)
  const [showMobileFilters, setShowMobileFilters] = useState(false)

  const [cancelTarget, setCancelTarget] = useState<VisitPlan | null>(null)
  const [cancelReason, setCancelReason] = useState('')
  const [confirmTarget, setConfirmTarget] = useState<VisitPlan | null>(null)
  const [processing, setProcessing]     = useState(false)

  // ── Atomic operation and concurrency refs
  const confirmOperationIdRef = useRef<string | null>(null)
  const cancelOperationRef    = useRef<{ operationId: string; reason: string } | null>(null)
  const isMutatingRef         = useRef(false)

  const confirmPlan       = useConfirmVisitPlan()
  const cancelPlan        = useCancelVisitPlan()
  const confirmPlanAtomic = useConfirmVisitPlanAtomic()
  const cancelPlanAtomic  = useCancelVisitPlanAtomic()

  // ── Permissions
  const canCreate   = can(PERMISSIONS.VISIT_PLANS_CREATE)
  const canConfirm  = can(PERMISSIONS.VISIT_PLANS_CONFIRM)
  const canCancel   = can(PERMISSIONS.VISIT_PLANS_CANCEL)
  const canReadTeam = can(PERMISSIONS.VISIT_PLANS_READ_TEAM) || can(PERMISSIONS.VISIT_PLANS_READ_ALL)

  // ── Fetch team employees if manager/supervisor (only if enabled)
  const { data: employeesResult } = useHREmployees(
    canReadTeam ? { status: 'active', pageSize: 300 } : undefined,
    canReadTeam
  )
  const teamEmployees = employeesResult?.data ?? []

  // ── Validation: dateFrom > dateTo
  const isDateRangeInvalid = !!(dateFrom && dateTo && dateFrom > dateTo)

  const queryParams = useMemo(() => ({
    status:   statusFilter || undefined,
    planType: planTypeFilter || undefined,
    employeeId: employeeFilter || undefined,
    dateFrom: (dateFrom && !isDateRangeInvalid) ? dateFrom : undefined,
    dateTo:   (dateTo && !isDateRangeInvalid) ? dateTo : undefined,
    page,
    pageSize: 25,
  }), [statusFilter, planTypeFilter, employeeFilter, dateFrom, dateTo, isDateRangeInvalid, page])

  // Enabled only when date range is valid
  const { data: result, isLoading: loading, error, refetch } = useVisitPlans(queryParams, !isDateRangeInvalid)
  const plans       = result?.data     ?? []
  const totalPages  = result?.totalPages ?? 1
  const totalCount  = result?.count    ?? 0

  const hasActiveFilter = !!statusFilter || !!planTypeFilter || !!employeeFilter || !!dateFrom || !!dateTo

  const activeFiltersCount = useMemo(() => {
    return [
      !!statusFilter,
      !!planTypeFilter,
      !!employeeFilter,
      !!dateFrom,
      !!dateTo,
    ].filter(Boolean).length
  }, [statusFilter, planTypeFilter, employeeFilter, dateFrom, dateTo])

  const clearFilters = () => {
    setStatusFilter('')
    setPlanTypeFilter('')
    setEmployeeFilter('')
    setDateFrom('')
    setDateTo('')
    setPage(1)
  }

  const handleConfirm = async () => {
    if (!confirmTarget || processing || isMutatingRef.current) return
    isMutatingRef.current = true
    setProcessing(true)

    if (VISITS_ATOMIC_EXECUTION) {
      if (!confirmOperationIdRef.current) {
        confirmOperationIdRef.current = crypto.randomUUID()
      }
      const opId = confirmOperationIdRef.current
      confirmPlanAtomic.mutate({ operationId: opId, planId: confirmTarget.id }, {
        onSuccess: () => {
          toast.success('تم تأكيد الخطة ذرياً')
          setConfirmTarget(null)
          confirmOperationIdRef.current = null
        },
        onError: (err: unknown) => {
          const errMsg = err instanceof Error ? err.message : 'فشلت العملية الذرية لتأكيد الخطة'
          toast.error(errMsg)
        },
        onSettled: () => {
          isMutatingRef.current = false
          setProcessing(false)
        },
      })
    } else {
      confirmPlan.mutate(confirmTarget.id, {
        onSuccess: () => {
          toast.success('تم تأكيد الخطة')
          setConfirmTarget(null)
        },
        onError:   () => toast.error('فشل تأكيد الخطة'),
        onSettled: () => {
          isMutatingRef.current = false
          setProcessing(false)
        },
      })
    }
  }

  const handleCancel = async () => {
    if (!cancelTarget || processing || isMutatingRef.current) return

    if (VISITS_ATOMIC_EXECUTION) {
      const activeReason = cancelOperationRef.current ? cancelOperationRef.current.reason : cancelReason.trim()
      if (!activeReason) {
        toast.error('سبب الإلغاء إلزامي في المسار الذري')
        return
      }
      isMutatingRef.current = true
      setProcessing(true)

      if (!cancelOperationRef.current) {
        cancelOperationRef.current = {
          operationId: crypto.randomUUID(),
          reason: activeReason
        }
      }
      const { operationId, reason } = cancelOperationRef.current

      cancelPlanAtomic.mutate({ operationId, planId: cancelTarget.id, reason }, {
        onSuccess: () => {
          toast.success('تم إلغاء الخطة ذرياً')
          setCancelTarget(null)
          setCancelReason('')
          cancelOperationRef.current = null
        },
        onError: (err: unknown) => {
          const errMsg = err instanceof Error ? err.message : 'فشلت العملية الذرية لإلغاء الخطة'
          toast.error(errMsg)
        },
        onSettled: () => {
          isMutatingRef.current = false
          setProcessing(false)
        },
      })
    } else {
      isMutatingRef.current = true
      setProcessing(true)
      cancelPlan.mutate({ id: cancelTarget.id, reason: cancelReason || undefined }, {
        onSuccess: () => {
          toast.success('تم إلغاء الخطة')
          setCancelTarget(null)
          setCancelReason('')
        },
        onError:   () => toast.error('فشل إلغاء الخطة'),
        onSettled: () => {
          isMutatingRef.current = false
          setProcessing(false)
        },
      })
    }
  }

  // ── Custom Loading Skeleton
  if (loading) {
    return (
      <div className="page-container animate-enter">
        <PageHeader
          title="خطط الزيارات"
          subtitle="متابعة وإعداد خطط الزيارات اليومية والأسبوعية للمندوبين الميدانيين."
          actions={
            canCreate && (
              <Button icon={<Plus size={16} />} onClick={() => navigate('/activities/visit-plans/new')}>
                خطة جديدة
              </Button>
            )
          }
        />
        <div className="edara-card" style={{ padding: 'var(--space-6)', marginTop: 'var(--space-4)' }}>
          {[1, 2, 3, 4, 5].map(i => (
            <div key={i} className="skeleton-row-fallback" />
          ))}
        </div>
        <style>{`
          .skeleton-row-fallback {
            height: 52px;
            border-radius: 8px;
            background: linear-gradient(90deg, var(--bg-surface-2) 25%, var(--bg-hover) 50%, var(--bg-surface-2) 75%);
            background-size: 200% 100%;
            animation: shimmer 1.5s infinite;
            margin-bottom: var(--space-3);
          }
          @keyframes shimmer {
            0% { background-position: 200% 0; }
            100% { background-position: -200% 0; }
          }
        `}</style>
      </div>
    )
  }

  // ── Custom Error State
  if (error) {
    return (
      <div className="page-container animate-enter">
        <PageHeader
          title="خطط الزيارات"
          subtitle="متابعة وإعداد خطط الزيارات اليومية والأسبوعية للمندوبين الميدانيين."
        />
        <div className="empty-state" style={{ padding: 'var(--space-12)' }}>
          <p className="empty-state-title" style={{ color: 'var(--color-danger)' }}>فشل تحميل البيانات</p>
          <p className="empty-state-text">حدث خطأ أثناء الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت والمحاولة مرة أخرى.</p>
          <Button variant="secondary" onClick={() => refetch()}>
            إعادة المحاولة
          </Button>
        </div>
      </div>
    )
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="خطط الزيارات"
        subtitle="متابعة وإعداد خطط الزيارات اليومية والأسبوعية للمندوبين الميدانيين."
        actions={
          canCreate && (
            <Button icon={<Plus size={16} />} onClick={() => navigate('/activities/visit-plans/new')} aria-label="إنشاء خطة جديدة">
              خطة جديدة
            </Button>
          )
        }
      />

      {/* Mobile Filter Toggle Button */}
      <div className="vp-mobile-filter-bar">
        <button
          type="button"
          className="vp-mobile-filter-toggle"
          onClick={() => setShowMobileFilters(prev => !prev)}
          aria-expanded={showMobileFilters}
          aria-controls="visit-plans-filter-panel"
        >
          <Filter size={16} />
          <span>تصفية الخطط</span>
          {activeFiltersCount > 0 && (
            <span className="vp-active-filter-badge">{activeFiltersCount}</span>
          )}
          <ChevronDown size={16} className={`vp-chevron ${showMobileFilters ? 'vp-chevron--open' : ''}`} />
        </button>
      </div>

      {/* Filters Area */}
      <div
        id="visit-plans-filter-panel"
        className={`edara-card vp-filter-panel ${showMobileFilters ? 'vp-filter-panel--open' : ''}`}
        style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}
      >
        <div className="act-filter-grid">
          {/* Status Filter */}
          <div className="form-group">
            <label className="form-label" htmlFor="status-filter">الحالة</label>
            <select
              id="status-filter"
              className="form-select filter-select"
              value={statusFilter}
              onChange={e => { setStatusFilter(e.target.value as PlanStatus | ''); setPage(1) }}
            >
              <option value="">كل الحالات</option>
              {Object.entries(PLAN_STATUS_CONFIG).map(([status, cfg]) => (
                <option key={status} value={status}>{cfg.label}</option>
              ))}
            </select>
          </div>

          {/* Plan Type Filter */}
          <div className="form-group">
            <label className="form-label" htmlFor="plantype-filter">نوع الخطة</label>
            <select
              id="plantype-filter"
              className="form-select filter-select"
              value={planTypeFilter}
              onChange={e => { setPlanTypeFilter(e.target.value as VisitPlan['plan_type'] | ''); setPage(1) }}
            >
              <option value="">كل الأنواع</option>
              <option value="daily">يومية</option>
              <option value="weekly">أسبوعية</option>
              <option value="campaign">حملة</option>
              <option value="recurring">متكررة</option>
            </select>
          </div>

          {/* Employee Filter */}
          {canReadTeam && (
            <div className="form-group">
              <label className="form-label" htmlFor="employee-filter">الموظف</label>
              <select
                id="employee-filter"
                className="form-select filter-select"
                value={employeeFilter}
                onChange={e => { setEmployeeFilter(e.target.value); setPage(1) }}
              >
                <option value="">كل الموظفين</option>
                {teamEmployees.map(emp => (
                  <option key={emp.id} value={emp.id}>{emp.full_name}</option>
                ))}
              </select>
            </div>
          )}

          {/* Date From */}
          <div className="form-group">
            <label className="form-label" htmlFor="datefrom-filter">من تاريخ</label>
            <input
              type="date"
              id="datefrom-filter"
              className="form-input filter-select"
              value={dateFrom}
              onChange={e => { setDateFrom(e.target.value); setPage(1) }}
            />
          </div>

          {/* Date To */}
          <div className="form-group">
            <label className="form-label" htmlFor="dateto-filter">إلى تاريخ</label>
            <input
              type="date"
              id="dateto-filter"
              className="form-input filter-select"
              value={dateTo}
              onChange={e => { setDateTo(e.target.value); setPage(1) }}
            />
          </div>
        </div>

        {/* Date Warning */}
        {isDateRangeInvalid && (
          <div className="text-danger text-xs mt-2" style={{ fontWeight: 600 }}>
            ⚠️ تاريخ البدء لا يمكن أن يكون بعد تاريخ الانتهاء
          </div>
        )}
      </div>

      {/* Results Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--space-3)', flexWrap: 'wrap', gap: 'var(--space-2)' }}>
        {!isDateRangeInvalid && (
          <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', fontWeight: 600 }}>
            عدد النتائج الحالية: {totalCount} خطة
          </span>
        )}
        {hasActiveFilter && (
          <Button
            variant="ghost"
            size="sm"
            onClick={clearFilters}
            style={{ color: 'var(--color-danger)', display: 'inline-flex', alignItems: 'center', gap: '4px' }}
            aria-label="مسح كافة الفلاتر النشطة"
          >
            مسح الفلاتر
          </Button>
        )}
      </div>

      {/* Desktop Table & Mobile Cards */}
      {isDateRangeInvalid ? (
        <div className="edara-card" style={{ padding: 'var(--space-8)' }}>
          <EmptyState
            icon={<Calendar size={48} className="text-danger" />}
            title="نطاق تاريخ غير صحيح"
            text="تاريخ البدء لا يمكن أن يكون بعد تاريخ الانتهاء. يرجى تصحيح التواريخ للمتابعة."
            action={
              <Button variant="secondary" onClick={clearFilters}>
                مسح الفلاتر
              </Button>
            }
          />
        </div>
      ) : plans.length === 0 ? (
        <div className="edara-card" style={{ padding: 'var(--space-8)' }}>
          {hasActiveFilter ? (
            <EmptyState
              icon={<Search size={48} />}
              title="لا توجد نتائج مطابقة للفلاتر"
              text="جرّب تغيير خيارات الفلترة أو مسحها لعرض المزيد من الخطط."
              action={
                <Button variant="secondary" onClick={clearFilters}>
                  مسح الفلاتر
                </Button>
              }
            />
          ) : (
            <EmptyState
              icon={<MapPin size={48} />}
              title="لا توجد خطط زيارات مسجلة"
              text="لم يتم إنشاء أي خطة زيارات بعد في النظام."
              action={
                canCreate && (
                  <Button icon={<Plus size={16} />} onClick={() => navigate('/activities/visit-plans/new')}>
                    خطة جديدة
                  </Button>
                )
              }
            />
          )}
        </div>
      ) : (
        <div className="act-table-view edara-card" style={{ overflow: 'auto' }}>
          <DataTable<VisitPlan>
            columns={[
              {
                key: 'plan_date', label: 'التاريخ',
                render: p => (
                  <>
                    <Link
                      to={`/activities/visit-plans/${p.id}`}
                      className="font-bold text-sm text-primary hover:underline focus:outline-none focus:ring-2 focus:ring-primary focus:ring-offset-2"
                    >
                      {fmtDate(p.plan_date)}
                    </Link>
                    <div className="text-xs text-muted">
                      {PLAN_TYPE_LABELS[p.plan_type] || p.plan_type}
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
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => navigate(`/activities/visit-plans/${p.id}`)}
                      title="عرض التفاصيل"
                      aria-label="عرض تفاصيل الخطة"
                    >
                      <Eye size={14} />
                    </Button>
                    {canConfirm && p.status === 'draft' && (
                      <Button
                        variant="success"
                        size="sm"
                        onClick={() => setConfirmTarget(p)}
                        title="تأكيد الخطة"
                        aria-label="تأكيد الخطة"
                      >
                        <CheckCircle size={14} />
                      </Button>
                    )}
                    {canCancel && (p.status === 'draft' || p.status === 'confirmed') && (
                      <Button
                        variant="danger"
                        size="sm"
                        onClick={() => setCancelTarget(p)}
                        title="إلغاء الخطة"
                        aria-label="إلغاء الخطة"
                      >
                        <XCircle size={14} />
                      </Button>
                    )}
                  </div>
                ),
              },
            ]}
            data={plans}
            loading={false}
            onRowClick={p => navigate(`/activities/visit-plans/${p.id}`)}
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
                { label: 'النوع', value: PLAN_TYPE_LABELS[p.plan_type] || p.plan_type },
                ...(p.skipped_count > 0 ? [{ label: 'متخطاة', value: String(p.skipped_count) }] : []),
              ],
              actions: (() => {
                const showConfirm = canConfirm && p.status === 'draft'
                const showCancel = canCancel && (p.status === 'draft' || p.status === 'confirmed')
                if (!showConfirm && !showCancel) return undefined
                return (
                  <div className="flex gap-2 w-full" onClick={e => e.stopPropagation()}>
                    {showConfirm && (
                      <Button
                        variant="success"
                        size="sm"
                        onClick={() => setConfirmTarget(p)}
                        style={{ flex: 1, justifyContent: 'center' }}
                        aria-label="تأكيد الخطة"
                      >
                        <CheckCircle size={14} /> تأكيد الخطة
                      </Button>
                    )}
                    {showCancel && (
                      <Button
                        variant="danger"
                        size="sm"
                        onClick={() => setCancelTarget(p)}
                        style={{ flex: 1, justifyContent: 'center' }}
                        aria-label="إلغاء الخطة"
                      >
                        <XCircle size={14} /> إلغاء الخطة
                      </Button>
                    )}
                  </div>
                )
              })(),
              onClick: () => navigate(`/activities/visit-plans/${p.id}`),
            })}
          />
        </div>
      )}

      {/* Confirm Modal */}
      <ResponsiveModal
        open={!!confirmTarget}
        onClose={() => { setConfirmTarget(null); confirmOperationIdRef.current = null }}
        title="تأكيد خطة الزيارات"
        disableOverlayClose={processing}
        footer={
          <>
            <Button variant="secondary" onClick={() => { setConfirmTarget(null); confirmOperationIdRef.current = null }} disabled={processing}>إلغاء</Button>
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
        onClose={() => { setCancelTarget(null); setCancelReason(''); cancelOperationRef.current = null }}
        title="إلغاء خطة الزيارات"
        disableOverlayClose={processing}
        footer={
          <>
            <Button variant="secondary" onClick={() => { setCancelTarget(null); setCancelReason(''); cancelOperationRef.current = null }} disabled={processing}>
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
            <label className="form-label">سبب الإلغاء (مطلوب)</label>
            <textarea
              className="form-textarea"
              rows={2}
              value={cancelOperationRef.current ? cancelOperationRef.current.reason : cancelReason}
              onChange={e => setCancelReason(e.target.value)}
              placeholder="اذكر سبب الإلغاء وجوباً..."
              disabled={processing || !!cancelOperationRef.current}
            />
          </div>
        </div>
      </ResponsiveModal>

      <style>{`
        .act-filter-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
          gap: var(--space-3);
          align-items: flex-end;
        }
        .filter-select { width: 100%; }
        .act-table-view { display: block; }

        .vp-mobile-filter-bar {
          display: none;
          margin-bottom: var(--space-3);
        }
        .vp-mobile-filter-toggle {
          display: flex;
          align-items: center;
          justify-content: space-between;
          width: 100%;
          padding: var(--space-3) var(--space-4);
          background: var(--bg-surface);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-lg);
          font-family: inherit;
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--text-primary);
          cursor: pointer;
          min-height: 44px;
        }
        .vp-active-filter-badge {
          background: var(--color-primary);
          color: white;
          border-radius: 9999px;
          padding: 2px 8px;
          font-size: var(--text-xs);
          font-weight: 700;
          margin-inline-start: auto;
          margin-inline-end: var(--space-2);
        }
        .vp-chevron {
          transition: transform 0.2s ease;
        }
        .vp-chevron--open {
          transform: rotate(180deg);
        }

        @media (max-width: 768px) {
          .vp-mobile-filter-bar {
            display: block;
          }
          .vp-filter-panel {
            display: none;
          }
          .vp-filter-panel--open {
            display: block !important;
          }
        }
      `}</style>
    </div>
  )
}
