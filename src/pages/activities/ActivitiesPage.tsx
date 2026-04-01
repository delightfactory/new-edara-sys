import { useState, useMemo } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { Activity, Plus, Eye, Trash2, MapPin, Phone, CheckSquare } from 'lucide-react'
import { toast } from 'sonner'
import { useAuthStore } from '@/stores/auth-store'
import { useActivities, useSoftDeleteActivity, useActivityTypes, useHREmployees } from '@/hooks/useQueryHooks'
import { PERMISSIONS } from '@/lib/permissions/constants'
import PageHeader from '@/components/shared/PageHeader'
import SearchInput from '@/components/shared/SearchInput'
import DataTable from '@/components/shared/DataTable'
import PermissionGuard from '@/components/shared/PermissionGuard'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import ActivityStatusBadge from '@/components/shared/ActivityStatusBadge'
import type { Activity as ActivityRow } from '@/lib/types/activities'

const CATEGORY_ICON: Record<string, React.ReactNode> = {
  visit:  <MapPin    size={14} />,
  call:   <Phone     size={14} />,
  task:   <CheckSquare size={14} />,
}

function fmtDate(d: string) {
  return new Date(d).toLocaleDateString('ar-EG', { day: 'numeric', month: 'short', year: 'numeric' })
}

export default function ActivitiesPage() {
  const navigate = useNavigate()
  const can      = useAuthStore(s => s.can)

  const [search,         setSearch]         = useState('')
  const [categoryFilter, setCategoryFilter]  = useState('')
  const [outcomeFilter,  setOutcomeFilter]   = useState('')
  const [dateFrom,       setDateFrom]        = useState('')
  const [dateTo,         setDateTo]          = useState('')
  const [employeeFilter, setEmployeeFilter]  = useState('')
  const [page,           setPage]            = useState(1)
  const [deleteTarget,   setDeleteTarget]    = useState<ActivityRow | null>(null)
  const [deleting,       setDeleting]        = useState(false)

  // Read customerId from URL (deep link from customer detail)
  const [searchParams] = useSearchParams()
  const urlCustomerId = searchParams.get('customerId') ?? ''
  const [customerFilter, setCustomerFilter] = useState(urlCustomerId)

  const { data: activityTypes = [] } = useActivityTypes()
  const deleteActivity = useSoftDeleteActivity()

  // فلتر الموظف: يظهر فقط للمديرين
  const canReadTeam = can(PERMISSIONS.ACTIVITIES_READ_TEAM) || can(PERMISSIONS.ACTIVITIES_READ_ALL)
  const { data: employeesResult } = useHREmployees(canReadTeam ? { status: 'active' } : undefined)
  const teamEmployees = employeesResult?.data ?? []

  const queryParams = useMemo(() => ({
    typeCategory: categoryFilter || undefined,
    outcomeType:  outcomeFilter  || undefined,
    dateFrom:     dateFrom       || undefined,
    dateTo:       dateTo         || undefined,
    employeeId:   employeeFilter || undefined,
    customerId:   customerFilter || undefined,
    page,
    pageSize: 25,
  }), [categoryFilter, outcomeFilter, dateFrom, dateTo, employeeFilter, customerFilter, page])

  const { data: result, isLoading: loading } = useActivities(queryParams)
  const activities  = result?.data     ?? []
  const totalPages  = result?.totalPages ?? 1
  const totalCount  = result?.count    ?? 0

  // فلترة الـ search (client-side لأن backend لا يدعم text search مباشرة)
  const filtered = useMemo(() => {
    if (!search) return activities
    const q = search.toLowerCase()
    return activities.filter(a =>
      a.customer?.name.toLowerCase().includes(q) ||
      a.type?.name.toLowerCase().includes(q)     ||
      a.outcome_notes?.toLowerCase().includes(q)
    )
  }, [activities, search])

  const canCreate = can(PERMISSIONS.ACTIVITIES_CREATE)
  // Wave A Final Fix: align with backend soft_delete_activity() RLS authority:
  //   - UPDATE_OWN → rep can delete their own activities (24h window enforced server-side)
  //   - READ_TEAM / READ_ALL → supervisor/manager can delete team activities (48h window server-side)
  // UI shows the button; the actual time-window check is enforced by the RPC — not duplicated here.
  const canDelete = can(PERMISSIONS.ACTIVITIES_UPDATE_OWN) ||
                    can(PERMISSIONS.ACTIVITIES_READ_TEAM)  ||
                    can(PERMISSIONS.ACTIVITIES_READ_ALL)

  const handleDelete = async () => {
    if (!deleteTarget) return
    setDeleting(true)
    try {
      deleteActivity.mutate(deleteTarget.id, {
        onSuccess: () => {
          toast.success('تم حذف النشاط')
          setDeleteTarget(null)
        },
        onError: () => toast.error('فشل حذف النشاط'),
        onSettled: () => setDeleting(false),
      })
    } catch {
      setDeleting(false)
    }
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="الأنشطة الميدانية"
        subtitle={loading ? '...' : `${totalCount} نشاط`}
        actions={
          <PermissionGuard permission={PERMISSIONS.ACTIVITIES_CREATE}>
            <Button icon={<Plus size={16} />} onClick={() => navigate('/activities/new')} className="desktop-only-btn">
              نشاط جديد
            </Button>
          </PermissionGuard>
        }
      />

      {/* ── Filters ─────────────────────────────────────────────── */}
      <div className="edara-card p-4 mb-4">
        <div className="act-filter-row">
          <div className="flex-[2] min-w-[180px]">
            <SearchInput
              value={search}
              onChange={val => { setSearch(val); setPage(1) }}
              placeholder="بحث بالعميل أو النوع أو الملاحظات..."
            />
          </div>
          {canReadTeam && teamEmployees.length > 0 && (
            <select
              className="form-select filter-select"
              value={employeeFilter}
              onChange={e => { setEmployeeFilter(e.target.value); setPage(1) }}
            >
              <option value="">كل المندوبين</option>
              {teamEmployees.map(emp => (
                <option key={emp.id} value={emp.id}>{emp.full_name}</option>
              ))}
            </select>
          )}
          <select
            className="form-select filter-select"
            value={categoryFilter}
            onChange={e => { setCategoryFilter(e.target.value); setPage(1) }}
          >
            <option value="">كل الفئات</option>
            <option value="visit">زيارات</option>
            <option value="call">مكالمات</option>
            <option value="task">مهام</option>
          </select>
          <select
            className="form-select filter-select"
            value={outcomeFilter}
            onChange={e => { setOutcomeFilter(e.target.value); setPage(1) }}
          >
            <option value="">كل النتائج</option>
            <option value="order_placed">طلب مبيعات</option>
            <option value="agreed_order">اتفاق على طلب</option>
            <option value="collection">تحصيل</option>
            <option value="promised_payment">وعد بالدفع</option>
            <option value="refused">رفض</option>
            <option value="not_interested">غير مهتم</option>
            <option value="followup_scheduled">متابعة مجدولة</option>
            <option value="closed">مغلق</option>
          </select>
          <input
            type="date"
            className="form-input filter-select"
            value={dateFrom}
            onChange={e => { setDateFrom(e.target.value); setPage(1) }}
            title="من تاريخ"
          />
          <input
            type="date"
            className="form-input filter-select"
            value={dateTo}
            onChange={e => { setDateTo(e.target.value); setPage(1) }}
            title="إلى تاريخ"
          />
          {customerFilter && (
            <button
              className="btn btn--ghost btn--sm flex items-center gap-1 whitespace-nowrap text-xs"
              onClick={() => { setCustomerFilter(''); setPage(1) }}
              title="إزالة فلتر العميل"
            >
              ✕ فلتر عميل
            </button>
          )}
        </div>
      </div>

      {/* ── DESKTOP: DataTable ─────────────────────────────────── */}
      <div className="act-table-view edara-card overflow-auto">
        <DataTable<ActivityRow>
          columns={[
            {
              key: 'type', label: 'النوع / العميل',
              render: a => (
                <>
                  <div className="flex items-center gap-2 font-semibold text-sm">
                    <span className="text-muted">
                      {CATEGORY_ICON[a.type?.category ?? 'task']}
                    </span>
                    {a.type?.name ?? '—'}
                  </div>
                  {a.customer && (
                    <div className="text-xs text-muted mt-0.5">
                      {a.customer.name}
                    </div>
                  )}
                </>
              ),
            },
            {
              key: 'activity_date', label: 'التاريخ',
              render: a => (
                <>
                  <div className="text-sm">{fmtDate(a.activity_date)}</div>
                  {a.start_time && (
                    <div className="text-xs text-muted">
                      {new Date(a.start_time).toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' })}
                    </div>
                  )}
                </>
              ),
            },
            {
              key: 'outcome_type', label: 'النتيجة',
              render: a => <ActivityStatusBadge outcomeType={a.outcome_type} size="sm" />,
            },
            {
              key: 'outcome_notes', label: 'ملاحظات', hideOnMobile: true,
              render: a => a.outcome_notes ? (
                <span className="text-xs text-muted">
                  {a.outcome_notes.slice(0, 60)}{a.outcome_notes.length > 60 ? '...' : ''}
                </span>
              ) : <span className="text-muted">—</span>,
            },
            {
              key: 'gps', label: 'GPS', hideOnMobile: true, width: 60,
              render: a => a.gps_verified ? (
                <span className="text-success text-xs">✓</span>
              ) : (
                <span className="text-muted text-xs">—</span>
              ),
            },
            {
              key: 'actions', label: 'إجراءات', width: 80,
              render: a => (
                <div className="flex gap-1" onClick={e => e.stopPropagation()}>
                  <Button variant="ghost" size="sm" onClick={() => navigate(`/activities/${a.id}`)}>
                    <Eye size={14} />
                  </Button>
                  {canDelete && (
                    <Button variant="danger" size="sm" onClick={() => setDeleteTarget(a)}>
                      <Trash2 size={14} />
                    </Button>
                  )}
                </div>
              ),
            },
          ]}
          data={filtered}
          loading={loading}
          onRowClick={a => navigate(`/activities/${a.id}`)}
          emptyIcon={<Activity size={48} />}
          emptyTitle="لا توجد أنشطة"
          emptyText="سجّل أول نشاط ميداني"
          emptyAction={
            <PermissionGuard permission={PERMISSIONS.ACTIVITIES_CREATE}>
              <Button icon={<Plus size={16} />} onClick={() => navigate('/activities/new')}>
                نشاط جديد
              </Button>
            </PermissionGuard>
          }
          page={page}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setPage}
          dataCardMapping={a => ({
            title: a.type?.name ?? 'نشاط',
            subtitle: a.customer?.name,
            badge: <ActivityStatusBadge outcomeType={a.outcome_type} size="sm" />,
            metadata: [
              { label: 'التاريخ', value: fmtDate(a.activity_date) },
              ...(a.outcome_notes ? [{ label: 'ملاحظات', value: a.outcome_notes.slice(0, 60) }] : []),
            ],
            actions: (
              <div className="flex gap-2 w-full">
                <Button variant="secondary" size="sm" onClick={() => navigate(`/activities/${a.id}`)}
                  className="flex-1 justify-center">
                  <Eye size={14} /> عرض
                </Button>
                {canDelete && (
                  <Button variant="danger" size="sm" onClick={() => setDeleteTarget(a)}
                    className="justify-center">
                    <Trash2 size={14} />
                  </Button>
                )}
              </div>
            ),
            onClick: () => navigate(`/activities/${a.id}`),
          })}
        />
      </div>

      {/* ── Mobile FAB ── */}
      <PermissionGuard permission={PERMISSIONS.ACTIVITIES_CREATE}>
        <button className="fab-button" onClick={() => navigate('/activities/new')} aria-label="نشاط جديد">
          <Plus size={24} />
        </button>
      </PermissionGuard>

      {/* ── Delete Modal ──────────────────────────────────────── */}
      <ResponsiveModal
        open={!!deleteTarget}
        onClose={() => setDeleteTarget(null)}
        title="حذف النشاط"
        disableOverlayClose={deleting}
        footer={
          <>
            <Button variant="secondary" onClick={() => setDeleteTarget(null)} disabled={deleting}>إلغاء</Button>
            <Button variant="danger" onClick={handleDelete} disabled={deleting}>
              {deleting ? 'جاري الحذف...' : 'حذف'}
            </Button>
          </>
        }
      >
        <p className="text-secondary text-sm m-0 leading-relaxed">
          هل تريد حذف هذا النشاط؟ لا يمكن التراجع عن هذا الإجراء.
        </p>
      </ResponsiveModal>

      <style>{`
        .act-filter-row { display: flex; gap: var(--space-3); flex-wrap: wrap; align-items: flex-end; }
        .filter-select { min-width: 120px; flex: 1; }
        .act-table-view { display: block; }
        .fab-button { display: none; }
        @media (max-width: 768px) {
          .desktop-only-btn { display: none; }
          .fab-button {
            display: flex; align-items: center; justify-content: center;
            position: fixed; bottom: calc(var(--bottom-nav-height, 64px) + var(--space-4)); inset-inline-end: var(--space-4);
            width: 56px; height: 56px; border-radius: 28px;
            background: var(--color-primary); color: white;
            box-shadow: var(--shadow-lg); z-index: 160; border: none;
            transition: transform 0.2s;
          }
          .fab-button:active { transform: scale(0.95); }
        }
      `}</style>
    </div>
  )
}
