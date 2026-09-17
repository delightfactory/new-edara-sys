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
import { CustomerLink } from '@/components/shared/EntityLink'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import ResponsiveCollection from '@/components/patterns/ResponsiveCollection'
import Pagination from '@/components/patterns/Pagination'
import StatePanel from '@/components/patterns/StatePanel'
import type { AppAction } from '@/components/patterns/ActionRegistry'
import { ActivityCard, ActivityOutcomeBadge } from '@/components/activities/ActivityOverviewPresentation'
import type { Activity as ActivityRow } from '@/lib/types/activities'
import '@/styles/field-activities-v2.css'

const CATEGORY_ICON: Record<string, React.ReactNode> = {
  visit: <MapPin size={14} />,
  call: <Phone size={14} />,
  task: <CheckSquare size={14} />,
}

function fmtDate(d: string) {
  return new Date(d).toLocaleDateString('ar-EG-u-nu-latn', { day: 'numeric', month: 'short', year: 'numeric' })
}

export default function ActivitiesPage() {
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)

  const [search, setSearch] = useState('')
  const [categoryFilter, setCategoryFilter] = useState('')
  const [outcomeFilter, setOutcomeFilter] = useState('')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [employeeFilter, setEmployeeFilter] = useState('')
  const [page, setPage] = useState(1)
  const [deleteTarget, setDeleteTarget] = useState<ActivityRow | null>(null)
  const [deleting, setDeleting] = useState(false)

  const [searchParams] = useSearchParams()
  const urlCustomerId = searchParams.get('customerId') ?? ''
  const [customerFilter, setCustomerFilter] = useState(urlCustomerId)

  const { data: activityTypes = [] } = useActivityTypes()
  const deleteActivity = useSoftDeleteActivity()

  const canReadTeam = can(PERMISSIONS.ACTIVITIES_READ_TEAM) || can(PERMISSIONS.ACTIVITIES_READ_ALL)
  const { data: employeesResult } = useHREmployees(canReadTeam ? { status: 'active' } : undefined)
  const teamEmployees = employeesResult?.data ?? []

  const queryParams = useMemo(() => ({
    typeCategory: categoryFilter || undefined,
    outcomeType: outcomeFilter || undefined,
    dateFrom: dateFrom || undefined,
    dateTo: dateTo || undefined,
    employeeId: employeeFilter || undefined,
    customerId: customerFilter || undefined,
    page,
    pageSize: 25,
  }), [categoryFilter, outcomeFilter, dateFrom, dateTo, employeeFilter, customerFilter, page])

  const { data: result, isLoading: loading } = useActivities(queryParams)
  const activities = result?.data ?? []
  const totalPages = result?.totalPages ?? 1
  const totalCount = result?.count ?? 0

  // Client-side text search is intentionally preserved because the existing backend query has no text-search input.
  const filtered = useMemo(() => {
    if (!search) return activities
    const q = search.toLowerCase()
    return activities.filter(a =>
      a.customer?.name.toLowerCase().includes(q) ||
      a.type?.name.toLowerCase().includes(q) ||
      a.outcome_notes?.toLowerCase().includes(q)
    )
  }, [activities, search])

  const canCreate = can(PERMISSIONS.ACTIVITIES_CREATE)
  const canDelete = can(PERMISSIONS.ACTIVITIES_UPDATE_OWN) ||
                    can(PERMISSIONS.ACTIVITIES_READ_TEAM) ||
                    can(PERMISSIONS.ACTIVITIES_READ_ALL)
  const hasActiveFilters = Boolean(
    search || categoryFilter || outcomeFilter || dateFrom || dateTo || employeeFilter || customerFilter,
  )

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

  const activityActions = (activity: ActivityRow): AppAction[] => [
    {
      id: 'view',
      label: 'عرض',
      icon: <Eye size={14} />,
      importance: 'primary',
      tone: 'secondary',
      onSelect: () => navigate(`/activities/${activity.id}`),
    },
    ...(canDelete ? [{
      id: 'delete',
      label: 'حذف',
      icon: <Trash2 size={14} />,
      importance: 'secondary' as const,
      tone: 'danger' as const,
      onSelect: () => setDeleteTarget(activity),
    }] : []),
  ]

  const renderActivityCards = (items: ActivityRow[], mode: 'mobile' | 'tablet') => (
    <div className={`ds-field-activity-grid ds-field-activity-grid--${mode}`}>
      {items.map(activity => (
        <ActivityCard
          key={activity.id}
          mode={mode}
          summary={{
            typeName: activity.type?.name ?? 'نشاط',
            category: activity.type?.category ?? 'task',
            customer: activity.customer,
            date: fmtDate(activity.activity_date),
            notes: activity.outcome_notes ? activity.outcome_notes.slice(0, 60) : undefined,
            gpsVerified: activity.gps_verified,
            outcome: activity.outcome_type,
          }}
          actions={activityActions(activity)}
          onOpen={() => navigate(`/activities/${activity.id}`)}
        />
      ))}
    </div>
  )

  const emptyState = (
    <StatePanel
      kind="empty"
      icon={<Activity size={32} />}
      title={hasActiveFilters ? 'لا توجد نتائج مطابقة' : 'لا توجد أنشطة'}
      description={hasActiveFilters ? 'جرّب تعديل البحث أو فلاتر الأنشطة.' : 'سجّل أول نشاط ميداني.'}
      action={!hasActiveFilters && canCreate ? (
        <Button icon={<Plus size={16} />} onClick={() => navigate('/activities/new')} touchTarget>
          نشاط جديد
        </Button>
      ) : undefined}
    />
  )

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

      <div className="edara-card p-4 mb-4">
        <div className="ds-field-activities__filters">
          <div className="ds-field-activities__search">
            <SearchInput
              value={search}
              onChange={val => { setSearch(val); setPage(1) }}
              placeholder="بحث بالعميل أو النوع أو الملاحظات..."
            />
          </div>
          {canReadTeam && teamEmployees.length > 0 && (
            <select
              className="form-select ds-field-activities__filter-control"
              value={employeeFilter}
              onChange={e => { setEmployeeFilter(e.target.value); setPage(1) }}
              aria-label="المندوب"
            >
              <option value="">كل المندوبين</option>
              {teamEmployees.map(emp => <option key={emp.id} value={emp.id}>{emp.full_name}</option>)}
            </select>
          )}
          <select
            className="form-select ds-field-activities__filter-control"
            value={categoryFilter}
            onChange={e => { setCategoryFilter(e.target.value); setPage(1) }}
            aria-label="فئة النشاط"
          >
            <option value="">كل الفئات</option>
            <option value="visit">زيارات</option>
            <option value="call">مكالمات</option>
            <option value="task">مهام</option>
          </select>
          <select
            className="form-select ds-field-activities__filter-control"
            value={outcomeFilter}
            onChange={e => { setOutcomeFilter(e.target.value); setPage(1) }}
            aria-label="نتيجة النشاط"
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
            className="form-input ds-field-activities__filter-control"
            value={dateFrom}
            onChange={e => { setDateFrom(e.target.value); setPage(1) }}
            title="من تاريخ"
            aria-label="من تاريخ"
          />
          <input
            type="date"
            className="form-input ds-field-activities__filter-control"
            value={dateTo}
            onChange={e => { setDateTo(e.target.value); setPage(1) }}
            title="إلى تاريخ"
            aria-label="إلى تاريخ"
          />
          {customerFilter && (
            <Button
              variant="ghost"
              size="sm"
              touchTarget
              onClick={() => { setCustomerFilter(''); setPage(1) }}
              aria-label="إزالة فلتر العميل"
            >
              ✕ فلتر عميل
            </Button>
          )}
        </div>
      </div>

      <ResponsiveCollection<ActivityRow>
        items={filtered}
        loading={loading}
        emptyState={emptyState}
        renderDesktop={items => (
          <div className="ds-field-activities__desktop-table edara-card">
            <DataTable<ActivityRow>
              columns={[
                {
                  key: 'type', label: 'النوع / العميل',
                  render: activity => (
                    <>
                      <div className="flex items-center gap-2 font-semibold text-sm">
                        <span className="text-muted">{CATEGORY_ICON[activity.type?.category ?? 'task']}</span>
                        {activity.type?.name ?? '—'}
                      </div>
                      {activity.customer && (
                        <div className="text-xs text-muted mt-0.5">
                          <CustomerLink id={activity.customer.id} name={activity.customer.name} />
                        </div>
                      )}
                    </>
                  ),
                },
                {
                  key: 'activity_date', label: 'التاريخ',
                  render: activity => (
                    <>
                      <div className="text-sm">{fmtDate(activity.activity_date)}</div>
                      {activity.start_time && (
                        <div className="text-xs text-muted">
                          {new Date(activity.start_time).toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' })}
                        </div>
                      )}
                    </>
                  ),
                },
                {
                  key: 'outcome_type', label: 'النتيجة',
                  render: activity => <ActivityOutcomeBadge outcome={activity.outcome_type} />,
                },
                {
                  key: 'outcome_notes', label: 'ملاحظات',
                  render: activity => activity.outcome_notes ? (
                    <span className="text-xs text-muted">
                      {activity.outcome_notes.slice(0, 60)}{activity.outcome_notes.length > 60 ? '...' : ''}
                    </span>
                  ) : <span className="text-muted">—</span>,
                },
                {
                  key: 'gps', label: 'GPS', width: 60,
                  render: activity => activity.gps_verified
                    ? <span className="text-success text-xs">✓</span>
                    : <span className="text-muted text-xs">—</span>,
                },
                {
                  key: 'actions', label: 'إجراءات', width: 80,
                  render: activity => (
                    <div className="flex gap-1" onClick={event => event.stopPropagation()}>
                      <Button variant="ghost" size="sm" onClick={() => navigate(`/activities/${activity.id}`)} aria-label="عرض النشاط">
                        <Eye size={14} />
                      </Button>
                      {canDelete && (
                        <Button variant="danger" size="sm" onClick={() => setDeleteTarget(activity)} aria-label="حذف النشاط">
                          <Trash2 size={14} />
                        </Button>
                      )}
                    </div>
                  ),
                },
              ]}
              data={items}
              onRowClick={activity => navigate(`/activities/${activity.id}`)}
            />
          </div>
        )}
        renderTablet={items => renderActivityCards(items, 'tablet')}
        renderMobile={items => renderActivityCards(items, 'mobile')}
      />

      {totalPages > 1 && !loading && (
        <Pagination
          page={page}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setPage}
        />
      )}

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
    </div>
  )
}
