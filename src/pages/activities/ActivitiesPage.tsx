import { useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { Activity, Plus, Eye, Trash2, MapPin, Phone, CheckSquare } from 'lucide-react'
import { toast } from 'sonner'
import { useAuthStore } from '@/stores/auth-store'
import { useActivities, useSoftDeleteActivity, useActivityTypes } from '@/hooks/useQueryHooks'
import { PERMISSIONS } from '@/lib/permissions/constants'
import PageHeader from '@/components/shared/PageHeader'
import SearchInput from '@/components/shared/SearchInput'
import DataTable from '@/components/shared/DataTable'
import DataCard from '@/components/ui/DataCard'
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

  const [search,       setSearch]       = useState('')
  const [categoryFilter, setCategoryFilter] = useState('')
  const [outcomeFilter, setOutcomeFilter]  = useState('')
  const [dateFrom,     setDateFrom]     = useState('')
  const [dateTo,       setDateTo]       = useState('')
  const [page,         setPage]         = useState(1)
  const [deleteTarget, setDeleteTarget] = useState<ActivityRow | null>(null)
  const [deleting,     setDeleting]     = useState(false)

  const { data: activityTypes = [] } = useActivityTypes()
  const deleteActivity = useSoftDeleteActivity()

  const queryParams = useMemo(() => ({
    typeCategory: categoryFilter || undefined,
    outcomeType:  outcomeFilter  || undefined,
    dateFrom:     dateFrom       || undefined,
    dateTo:       dateTo         || undefined,
    page,
    pageSize: 25,
  }), [categoryFilter, outcomeFilter, dateFrom, dateTo, page])

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
  const canDelete = can(PERMISSIONS.ACTIVITIES_UPDATE_OWN) || can(PERMISSIONS.ACTIVITIES_READ_TEAM)

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
        actions={canCreate ? (
          <Button icon={<Plus size={16} />} onClick={() => navigate('/activities/new')} className="desktop-only-btn">
            نشاط جديد
          </Button>
        ) : undefined}
      />

      {/* ── Filters ─────────────────────────────────────────────── */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="act-filter-row">
          <div style={{ flex: 2, minWidth: 180 }}>
            <SearchInput
              value={search}
              onChange={val => { setSearch(val); setPage(1) }}
              placeholder="بحث بالعميل أو النوع أو الملاحظات..."
            />
          </div>
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
        </div>
      </div>

      {/* ── DESKTOP: DataTable ─────────────────────────────────── */}
      <div className="act-table-view edara-card" style={{ overflow: 'auto' }}>
        <DataTable<ActivityRow>
          columns={[
            {
              key: 'type', label: 'النوع / العميل',
              render: a => (
                <>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', fontWeight: 600, fontSize: 'var(--text-sm)' }}>
                    <span style={{ color: 'var(--text-muted)' }}>
                      {CATEGORY_ICON[a.type?.category ?? 'task']}
                    </span>
                    {a.type?.name ?? '—'}
                  </div>
                  {a.customer && (
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 2 }}>
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
                  <div style={{ fontSize: 'var(--text-sm)' }}>{fmtDate(a.activity_date)}</div>
                  {a.start_time && (
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
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
                <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                  {a.outcome_notes.slice(0, 60)}{a.outcome_notes.length > 60 ? '...' : ''}
                </span>
              ) : <span style={{ color: 'var(--text-muted)' }}>—</span>,
            },
            {
              key: 'gps', label: 'GPS', hideOnMobile: true, width: 60,
              render: a => a.gps_verified ? (
                <span style={{ color: 'var(--color-success)', fontSize: 12 }}>✓</span>
              ) : (
                <span style={{ color: 'var(--text-muted)', fontSize: 12 }}>—</span>
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
          emptyAction={canCreate ? (
            <Button icon={<Plus size={16} />} onClick={() => navigate('/activities/new')}>
              نشاط جديد
            </Button>
          ) : undefined}
          page={page}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setPage}
        />
      </div>

      {/* ── MOBILE: DataCards ──────────────────────────────────── */}
      <div className="act-card-view">
        {loading ? (
          <div className="mobile-card-list">
            {[1, 2, 3].map(i => (
              <div key={i} className="edara-card" style={{ padding: 'var(--space-4)' }}>
                <div className="skeleton" style={{ height: 16, width: '60%', marginBottom: 8 }} />
                <div className="skeleton" style={{ height: 12, width: '40%' }} />
              </div>
            ))}
          </div>
        ) : filtered.length === 0 ? (
          <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
            <Activity size={40} className="empty-state-icon" />
            <p className="empty-state-title">لا توجد أنشطة</p>
          </div>
        ) : (
          <div className="mobile-card-list">
            {filtered.map(a => (
              <DataCard
                key={a.id}
                title={a.type?.name ?? 'نشاط'}
                subtitle={a.customer?.name ?? undefined}
                badge={<ActivityStatusBadge outcomeType={a.outcome_type} size="sm" />}
                metadata={[
                  { label: 'التاريخ', value: fmtDate(a.activity_date) },
                  ...(a.outcome_notes ? [{ label: 'ملاحظات', value: a.outcome_notes.slice(0, 60) }] : []),
                ]}
                actions={
                  <div className="flex gap-2" style={{ width: '100%' }}>
                    <Button variant="secondary" size="sm" onClick={() => navigate(`/activities/${a.id}`)}
                      style={{ flex: 1, justifyContent: 'center' }}>
                      <Eye size={14} /> عرض
                    </Button>
                    {canDelete && (
                      <Button variant="danger" size="sm" onClick={() => setDeleteTarget(a)}
                        style={{ justifyContent: 'center' }}>
                        <Trash2 size={14} />
                      </Button>
                    )}
                  </div>
                }
                onClick={() => navigate(`/activities/${a.id}`)}
              />
            ))}
          </div>
        )}
        {totalPages > 1 && (
          <div className="mobile-pagination">
            <Button variant="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(p => p - 1)}>السابق</Button>
            <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>{page} / {totalPages}</span>
            <Button variant="ghost" size="sm" disabled={page >= totalPages} onClick={() => setPage(p => p + 1)}>التالي</Button>
          </div>
        )}
      </div>

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
        <p style={{ margin: 0, color: 'var(--text-secondary)', fontSize: 'var(--text-sm)', lineHeight: 1.7 }}>
          هل تريد حذف هذا النشاط؟ لا يمكن التراجع عن هذا الإجراء.
        </p>
      </ResponsiveModal>

      <style>{`
        .act-filter-row { display: flex; gap: var(--space-3); flex-wrap: wrap; align-items: flex-end; }
        .filter-select { min-width: 120px; flex: 1; }
        .act-table-view { display: block; }
        .act-card-view  { display: none; }
        @media (max-width: 768px) {
          .act-table-view { display: none; }
          .act-card-view  { display: block; }
          .desktop-only-btn { display: none; }
        }
        .mobile-card-list { display: flex; flex-direction: column; gap: var(--space-3); padding: 0 0 var(--space-2); }
        .mobile-pagination { display: flex; align-items: center; justify-content: center; gap: var(--space-4); padding: var(--space-4) 0; }
      `}</style>
    </div>
  )
}
