import { useState, useMemo, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { Plus, Users, ToggleLeft, ToggleRight, Eye, Phone, Loader2, CheckCircle2 } from 'lucide-react'
import { toggleCustomerActive } from '@/lib/services/customers'
import { getCities } from '@/lib/services/geography'
import { useCustomers, useGovernorates, useProfiles, useInvalidate } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import type { Customer, City } from '@/lib/types/master-data'
import { formatNumber } from '@/lib/utils/format'
import { useMobileInfiniteList } from '@/hooks/useIntersectionObserver'
import PageHeader from '@/components/shared/PageHeader'
import SearchInput from '@/components/shared/SearchInput'
import DataTable from '@/components/shared/DataTable'
import DataCard from '@/components/ui/DataCard'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'

const typeLabels: Record<string, string> = { retail: 'تجزئة', wholesale: 'جملة', distributor: 'موزع' }
const typeBadge: Record<string, 'neutral' | 'info' | 'primary'> = { retail: 'neutral', wholesale: 'info', distributor: 'primary' }
const paymentLabels: Record<string, string> = { cash: 'نقدي', credit: 'آجل', mixed: 'مختلط' }
const paymentBadge: Record<string, 'success' | 'warning' | 'info'> = { cash: 'success', credit: 'warning', mixed: 'info' }

const PAGE_SIZE = 25

export default function CustomersPage() {
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const invalidate = useInvalidate()

  // ── Filters ───────────────────────────────────────────────────────
  const [cities,       setCities]       = useState<City[]>([])
  const [search,       setSearch]       = useState('')
  const [typeFilter,   setTypeFilter]   = useState('')
  const [govFilter,    setGovFilter]    = useState('')
  const [cityFilter,   setCityFilter]   = useState('')
  const [repFilter,    setRepFilter]    = useState('')
  const [statusFilter, setStatusFilter] = useState('')

  // ── Pagination: Desktop (numbered) ────────────────────────────────
  const [desktopPage, setDesktopPage] = useState(1)

  // ── Pagination: Mobile (infinite scroll via page accumulation) ────
  const [mobilePage, setMobilePage] = useState(1)

  const [confirmTarget, setConfirmTarget] = useState<Customer | null>(null)
  const [toggling,      setToggling]      = useState(false)

  const { data: governorates = [] } = useGovernorates()
  const { data: reps = [] }         = useProfiles()

  // resetKey: أي تغيير في الفلاتر يُعيد ضبط التراكم
  const filterKey = `${search}|${typeFilter}|${govFilter}|${cityFilter}|${repFilter}|${statusFilter}`
  const filterParams = useMemo(() => ({
    search:       search       || undefined,
    type:         typeFilter   || undefined,
    governorateId: govFilter   || undefined,
    cityId:       cityFilter   || undefined,
    repId:        repFilter    || undefined,
    isActive:     statusFilter === '' ? undefined : statusFilter === 'active',
  }), [search, typeFilter, govFilter, cityFilter, repFilter, statusFilter])

  // ── Desktop query (exact count for correct pagination) ───────────
  const desktopParams = useMemo(() => ({
    ...filterParams,
    page: desktopPage,
    pageSize: PAGE_SIZE,
  }), [filterParams, desktopPage])

  const { data: desktopResult, isLoading: desktopLoading } = useCustomers(desktopParams)
  const desktopCustomers = desktopResult?.data ?? []
  const totalCount       = desktopResult?.count ?? 0
  const totalPages       = desktopResult?.totalPages ?? 1

  // ── Mobile query (accumulates across pages) ───────────────────────
  const mobileParams = useMemo(() => ({
    ...filterParams,
    page: mobilePage,
    pageSize: PAGE_SIZE,
  }), [filterParams, mobilePage])

  const { data: mobileResult, isLoading: mobileLoading } = useCustomers(mobileParams)
  const mobileData = mobileResult?.data ?? []
  const hasMoreMobile = mobileData.length === PAGE_SIZE

  const handleLoadMore = useCallback(() => {
    if (!mobileLoading && hasMoreMobile) {
      setMobilePage(p => p + 1)
    }
  }, [mobileLoading, hasMoreMobile])

  // إعادة ضبط صفحة الموبايل عند تغيير الفلاتر
  const handleFilterChange = useCallback((fn: () => void) => {
    fn()
    setDesktopPage(1)
    setMobilePage(1)
  }, [])

  const { accumulated: mobileCustomers, sentinelRef } = useMobileInfiniteList<Customer>({
    data:       mobileData,
    pageSize:   PAGE_SIZE,
    loading:    mobileLoading,
    resetKey:   filterKey,
    hasMore:    hasMoreMobile,
    onLoadMore: handleLoadMore,
  })

  // ── Geography ────────────────────────────────────────────────────
  const handleGovChange = async (govId: string) => {
    handleFilterChange(() => { setGovFilter(govId); setCityFilter('') })
    setCities(govId ? await getCities(govId) : [])
  }

  // ── Toggle active ────────────────────────────────────────────────
  const handleToggle    = (c: Customer) => setConfirmTarget(c)
  const executeToggle   = async () => {
    if (!confirmTarget) return
    const next = !confirmTarget.is_active
    setToggling(true)
    try {
      await toggleCustomerActive(confirmTarget.id, next)
      toast.success(`تم ${next ? 'تفعيل' : 'إلغاء تفعيل'} العميل`)
      invalidate('customers')
    } catch { toast.error('فشلت العملية') }
    finally { setToggling(false); setConfirmTarget(null) }
  }

  // ── Desktop table columns ─────────────────────────────────────────
  const columns = [
    {
      key: 'name', label: 'العميل',
      render: (c: Customer) => (
        <>
          <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{c.name}</div>
          <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', display: 'flex', gap: 'var(--space-2)', alignItems: 'center', flexWrap: 'wrap' }}>
            <span dir="ltr" style={{ fontFamily: 'monospace' }}>{c.code}</span>
            {c.mobile && <span dir="ltr">• {c.mobile}</span>}
          </div>
        </>
      ),
    },
    { key: 'type', label: 'النوع', hideOnMobile: true, render: (c: Customer) => <Badge variant={typeBadge[c.type] || 'neutral'}>{typeLabels[c.type] || c.type}</Badge> },
    {
      key: 'location', label: 'الموقع', hideOnMobile: true,
      render: (c: Customer) => (
        <>
          <div style={{ fontSize: 'var(--text-sm)' }}>{(c as any).governorate?.name || '—'}</div>
          {(c as any).city && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{(c as any).city.name}</div>}
        </>
      ),
    },
    { key: 'rep', label: 'المندوب', hideOnMobile: true, render: (c: Customer) => (c as any).assigned_rep?.full_name || <span style={{ color: 'var(--text-muted)' }}>—</span> },
    { key: 'payment', label: 'الدفع', hideOnMobile: true, render: (c: Customer) => <Badge variant={paymentBadge[c.payment_terms as string] || 'neutral'}>{paymentLabels[c.payment_terms as string] || c.payment_terms}</Badge> },
    { key: 'credit', label: 'حد الائتمان', hideOnMobile: true, render: (c: Customer) => c.credit_limit > 0 ? <span style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{formatNumber(c.credit_limit)}</span> : <span style={{ color: 'var(--text-muted)' }}>—</span> },
    { key: 'status', label: 'الحالة', render: (c: Customer) => <Badge variant={c.is_active ? 'success' : 'danger'}>{c.is_active ? 'نشط' : 'معطل'}</Badge> },
    {
      key: 'actions', label: 'إجراءات', width: 100,
      render: (c: Customer) => (
        <div className="flex gap-1" onClick={e => e.stopPropagation()}>
          <Button variant="ghost" size="sm" title="عرض/تعديل" onClick={() => navigate(`/customers/${c.id}`)}>
            <Eye size={14} />
          </Button>
          {can('customers.update') && (
            <Button variant={c.is_active ? 'danger' : 'success'} size="sm"
              title={c.is_active ? 'تعطيل' : 'تفعيل'} onClick={() => handleToggle(c)}>
              {c.is_active ? <ToggleLeft size={14} /> : <ToggleRight size={14} />}
            </Button>
          )}
        </div>
      ),
    },
  ]

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="العملاء"
        subtitle={desktopLoading ? '...' : `${totalCount.toLocaleString('ar-EG')} عميل`}
        actions={can('customers.create') ? (
          <Button icon={<Plus size={16} />} onClick={() => navigate('/customers/new')}
            className="desktop-only-btn">
            إضافة عميل
          </Button>
        ) : undefined}
      />

      {/* ── Filters ──────────────────────────────────────── */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="customers-filter-row">
          <div style={{ flex: 2, minWidth: 180 }}>
            <SearchInput
              value={search}
              onChange={val => handleFilterChange(() => setSearch(val))}
              placeholder="بحث بالاسم أو الكود أو الهاتف..."
            />
          </div>
          <select className="form-select filter-select" value={typeFilter}
            onChange={e => handleFilterChange(() => setTypeFilter(e.target.value))}>
            <option value="">كل الأنواع</option>
            <option value="retail">تجزئة</option>
            <option value="wholesale">جملة</option>
            <option value="distributor">موزع</option>
          </select>
          <select className="form-select filter-select" value={govFilter}
            onChange={e => handleGovChange(e.target.value)}>
            <option value="">كل المحافظات</option>
            {governorates.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
          </select>
          {govFilter && cities.length > 0 && (
            <select className="form-select filter-select" value={cityFilter}
              onChange={e => handleFilterChange(() => setCityFilter(e.target.value))}>
              <option value="">كل المدن</option>
              {cities.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          )}
          <select className="form-select filter-select" value={repFilter}
            onChange={e => handleFilterChange(() => setRepFilter(e.target.value))}>
            <option value="">كل المناديب</option>
            {reps.map(r => <option key={r.id} value={r.id}>{r.full_name}</option>)}
          </select>
          <select className="form-select filter-select" value={statusFilter}
            onChange={e => handleFilterChange(() => setStatusFilter(e.target.value))}>
            <option value="">الحالة</option>
            <option value="active">نشط</option>
            <option value="inactive">معطل</option>
          </select>
        </div>
      </div>

      {/* ══════════════════ DESKTOP: Numbered Pagination ═══════════════════ */}
      <div className="customers-table-view edara-card" style={{ overflow: 'auto' }}>
        <DataTable<Customer>
          columns={columns}
          data={desktopCustomers}
          loading={desktopLoading}
          onRowClick={c => navigate(`/customers/${c.id}`)}
          rowStyle={c => ({ opacity: c.is_active ? 1 : 0.6 })}
          emptyIcon={<Users size={48} />}
          emptyTitle="لا يوجد عملاء"
          emptyText="لم يتم العثور على عملاء مطابقين للبحث"
          emptyAction={can('customers.create') ? (
            <Button icon={<Plus size={16} />} onClick={() => navigate('/customers/new')}>إضافة أول عميل</Button>
          ) : undefined}
          page={desktopPage}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setDesktopPage}
        />
      </div>

      {/* ══════════════════ MOBILE: Infinite Scroll ═══════════════════════ */}
      <div className="customers-card-view">
        {/* Loading: first page */}
        {mobileLoading && mobileCustomers.length === 0 ? (
          <div className="mobile-card-list">
            {[1, 2, 3, 4].map(i => (
              <div key={i} className="edara-card" style={{ padding: 'var(--space-4)' }}>
                <div className="skeleton" style={{ height: 16, width: '60%', marginBottom: 8 }} />
                <div className="skeleton" style={{ height: 12, width: '40%', marginBottom: 12 }} />
                <div className="skeleton" style={{ height: 12, width: '80%' }} />
              </div>
            ))}
          </div>
        ) : mobileCustomers.length === 0 ? (
          <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
            <Users size={40} className="empty-state-icon" />
            <p className="empty-state-title">لا يوجد عملاء</p>
            <p className="empty-state-text">لم يتم العثور على عملاء مطابقين للبحث</p>
          </div>
        ) : (
          <div className="mobile-card-list">
            {mobileCustomers.map(c => (
              <DataCard
                key={c.id}
                title={c.name}
                subtitle={
                  <span style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-1)' }}>
                    <span dir="ltr" style={{ fontFamily: 'monospace', fontSize: '0.7rem' }}>{c.code}</span>
                    {c.mobile && (
                      <>
                        <span>•</span>
                        <Phone size={11} />
                        <span dir="ltr">{c.mobile}</span>
                      </>
                    )}
                  </span>
                }
                badge={<Badge variant={c.is_active ? 'success' : 'danger'}>{c.is_active ? 'نشط' : 'معطل'}</Badge>}
                metadata={[
                  { label: 'نوع العميل', value: typeLabels[c.type] || c.type },
                  { label: 'طريقة الدفع', value: paymentLabels[c.payment_terms as string] || c.payment_terms },
                  ...(c.credit_limit > 0 ? [{ label: 'حد الائتمان', value: formatNumber(c.credit_limit), highlight: true }] : []),
                  ...((c as any).governorate?.name ? [{ label: 'المحافظة', value: (c as any).governorate.name }] : []),
                ]}
                actions={
                  <div className="flex gap-2" style={{ width: '100%' }}>
                    <Button variant="secondary" size="sm" onClick={() => navigate(`/customers/${c.id}`)}
                      style={{ flex: 1, justifyContent: 'center' }}>
                      <Eye size={14} /> عرض
                    </Button>
                    {can('customers.update') && (
                      <Button variant={c.is_active ? 'danger' : 'success'} size="sm"
                        onClick={() => handleToggle(c)}
                        style={{ flex: 1, justifyContent: 'center' }}>
                        {c.is_active ? <><ToggleLeft size={14} /> تعطيل</> : <><ToggleRight size={14} /> تفعيل</>}
                      </Button>
                    )}
                  </div>
                }
                onClick={() => navigate(`/customers/${c.id}`)}
              />
            ))}

            {/* Sentinel — يكتشفه الـ IntersectionObserver لتشغيل loadMore */}
            <div ref={sentinelRef} style={{ height: 8, flexShrink: 0 }} />

            {mobileLoading && mobileCustomers.length > 0 && (
              <div className="infinite-loading">
                <Loader2 size={18} className="spin-icon" />
                <span>جاري تحميل المزيد...</span>
              </div>
            )}

            {!mobileLoading && !hasMoreMobile && mobileCustomers.length > 0 && (
              <div className="infinite-end">
                <CheckCircle2 size={16} />
                <span>جميع العملاء ({mobileCustomers.length.toLocaleString('ar-EG')})</span>
              </div>
            )}
          </div>
        )}
      </div>

      {/* ── Confirm Modal ──────────────────────────────────────── */}
      <ResponsiveModal
        open={!!confirmTarget}
        onClose={() => setConfirmTarget(null)}
        title={confirmTarget?.is_active ? 'تعطيل العميل' : 'تفعيل العميل'}
        disableOverlayClose={toggling}
        footer={
          <>
            <Button variant="secondary" onClick={() => setConfirmTarget(null)} disabled={toggling}>إلغاء</Button>
            <Button variant={confirmTarget?.is_active ? 'danger' : 'success'}
              onClick={executeToggle} disabled={toggling}>
              {toggling ? 'جاري التنفيذ...' : confirmTarget?.is_active ? 'تعطيل' : 'تفعيل'}
            </Button>
          </>
        }
      >
        <p style={{ margin: 0, color: 'var(--text-secondary)', fontSize: 'var(--text-sm)', lineHeight: 1.7 }}>
          هل تريد {confirmTarget?.is_active ? 'تعطيل' : 'تفعيل'} العميل{' '}
          <strong style={{ color: 'var(--text-primary)' }}>"{confirmTarget?.name}"</strong>؟
        </p>
      </ResponsiveModal>

      <style>{`
        .customers-filter-row {
          display: flex;
          gap: var(--space-3);
          flex-wrap: wrap;
          align-items: flex-end;
        }
        .filter-select { min-width: 100px; flex: 1; }

        /* Desktop shows table, Mobile shows infinite cards */
        .customers-table-view { display: block; }
        .customers-card-view  { display: none; }

        @media (max-width: 768px) {
          .customers-table-view { display: none; }
          .customers-card-view  { display: block; }
          .desktop-only-btn     { display: none; }
          .customers-filter-row {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: var(--space-2);
          }
          .customers-filter-row > div:first-child { grid-column: 1 / -1; }
          .filter-select { font-size: var(--text-xs); width: 100%; flex: none; }
        }

        .mobile-card-list {
          display: flex;
          flex-direction: column;
          gap: var(--space-3);
          padding: 0 0 var(--space-4);
        }

        /* ── Infinite Scroll indicators ── */
        .infinite-loading {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: var(--space-2);
          padding: var(--space-4);
          color: var(--text-muted);
          font-size: var(--text-sm);
        }
        .spin-icon {
          animation: spin 1s linear infinite;
          color: var(--color-primary);
        }
        @keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }

        .infinite-end {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: var(--space-2);
          padding: var(--space-3) var(--space-4);
          color: var(--color-success);
          font-size: var(--text-sm);
          font-weight: 600;
          background: var(--color-success-light);
          border-radius: var(--radius-lg);
          margin-top: var(--space-2);
        }
      `}</style>
    </div>
  )
}
