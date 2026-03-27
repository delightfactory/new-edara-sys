import { useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { Plus, Users, ToggleLeft, ToggleRight, Eye, Phone } from 'lucide-react'
import { toggleCustomerActive } from '@/lib/services/customers'
import { getCities } from '@/lib/services/geography'
import { useCustomers, useGovernorates, useProfiles, useInvalidate } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import type { Customer, City } from '@/lib/types/master-data'
import { formatNumber } from '@/lib/utils/format'
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

export default function CustomersPage() {
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const invalidate = useInvalidate()
  const [cities, setCities] = useState<City[]>([])
  const [search, setSearch] = useState('')
  const [typeFilter, setTypeFilter] = useState('')
  const [govFilter, setGovFilter] = useState('')
  const [cityFilter, setCityFilter] = useState('')
  const [repFilter, setRepFilter] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [page, setPage] = useState(1)
  const [confirmTarget, setConfirmTarget] = useState<Customer | null>(null)
  const [toggling, setToggling] = useState(false)

  const { data: governorates = [] } = useGovernorates()
  const { data: reps = [] } = useProfiles()

  const queryParams = useMemo(() => ({
    search, type: typeFilter, governorateId: govFilter, cityId: cityFilter,
    repId: repFilter,
    isActive: statusFilter === '' ? undefined : statusFilter === 'active',
    page, pageSize: 25,
  }), [search, typeFilter, govFilter, cityFilter, repFilter, statusFilter, page])

  const { data: result, isLoading: loading } = useCustomers(queryParams)
  const customers = result?.data ?? []
  const totalPages = result?.totalPages ?? 1
  const totalCount = result?.count ?? 0

  const handleGovChange = async (govId: string) => {
    setGovFilter(govId); setCityFilter(''); setPage(1)
    setCities(govId ? await getCities(govId) : [])
  }

  const handleToggle = (c: Customer) => setConfirmTarget(c)
  const executeToggle = async () => {
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

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="العملاء"
        subtitle={loading ? '...' : `${totalCount} عميل`}
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
            <SearchInput value={search} onChange={val => { setSearch(val); setPage(1) }}
              placeholder="بحث بالاسم أو الكود أو الهاتف..." />
          </div>
          <select className="form-select filter-select" value={typeFilter}
            onChange={e => { setTypeFilter(e.target.value); setPage(1) }}>
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
              onChange={e => { setCityFilter(e.target.value); setPage(1) }}>
              <option value="">كل المدن</option>
              {cities.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          )}
          <select className="form-select filter-select" value={repFilter}
            onChange={e => { setRepFilter(e.target.value); setPage(1) }}>
            <option value="">كل المناديب</option>
            {reps.map(r => <option key={r.id} value={r.id}>{r.full_name}</option>)}
          </select>
          <select className="form-select filter-select" value={statusFilter}
            onChange={e => { setStatusFilter(e.target.value); setPage(1) }}>
            <option value="">الحالة</option>
            <option value="active">نشط</option>
            <option value="inactive">معطل</option>
          </select>
        </div>
      </div>

      {/* ── DESKTOP: Data Table ───────────────────────────── */}
      <div className="customers-table-view edara-card" style={{ overflow: 'auto' }}>
        <DataTable<Customer>
          columns={[
            {
              key: 'name', label: 'العميل',
              render: c => (
                <>
                  <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{c.name}</div>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', display: 'flex', gap: 'var(--space-2)', alignItems: 'center', flexWrap: 'wrap' }}>
                    <span dir="ltr" style={{ fontFamily: 'monospace' }}>{c.code}</span>
                    {c.mobile && <span dir="ltr">• {c.mobile}</span>}
                  </div>
                </>
              ),
            },
            { key: 'type', label: 'النوع', hideOnMobile: true, render: c => <Badge variant={typeBadge[c.type] || 'neutral'}>{typeLabels[c.type] || c.type}</Badge> },
            {
              key: 'location', label: 'الموقع', hideOnMobile: true,
              render: c => (
                <>
                  <div style={{ fontSize: 'var(--text-sm)' }}>{c.governorate?.name || '—'}</div>
                  {c.city && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{c.city.name}</div>}
                </>
              ),
            },
            { key: 'rep', label: 'المندوب', hideOnMobile: true, render: c => c.assigned_rep?.full_name || <span style={{ color: 'var(--text-muted)' }}>—</span> },
            { key: 'payment', label: 'الدفع', hideOnMobile: true, render: c => <Badge variant={paymentBadge[c.payment_terms] || 'neutral'}>{paymentLabels[c.payment_terms] || c.payment_terms}</Badge> },
            { key: 'credit', label: 'حد الائتمان', hideOnMobile: true, render: c => c.credit_limit > 0 ? <span style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{formatNumber(c.credit_limit)}</span> : <span style={{ color: 'var(--text-muted)' }}>—</span> },
            { key: 'status', label: 'الحالة', render: c => <Badge variant={c.is_active ? 'success' : 'danger'}>{c.is_active ? 'نشط' : 'معطل'}</Badge> },
            {
              key: 'actions', label: 'إجراءات', width: 100,
              render: c => (
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
          ]}
          data={customers}
          loading={loading}
          onRowClick={c => navigate(`/customers/${c.id}`)}
          rowStyle={c => ({ opacity: c.is_active ? 1 : 0.6 })}
          emptyIcon={<Users size={48} />}
          emptyTitle="لا يوجد عملاء"
          emptyText="لم يتم العثور على عملاء مطابقين للبحث"
          emptyAction={can('customers.create') ? (
            <Button icon={<Plus size={16} />} onClick={() => navigate('/customers/new')}>إضافة أول عميل</Button>
          ) : undefined}
          page={page}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setPage}
        />
      </div>

      {/* ── MOBILE: DataCard list ──────────────────────────── */}
      <div className="customers-card-view">
        {loading ? (
          <div className="mobile-card-list">
            {[1, 2, 3, 4].map(i => (
              <div key={i} className="edara-card" style={{ padding: 'var(--space-4)' }}>
                <div className="skeleton" style={{ height: 16, width: '60%', marginBottom: 8 }} />
                <div className="skeleton" style={{ height: 12, width: '40%', marginBottom: 12 }} />
                <div className="skeleton" style={{ height: 12, width: '80%' }} />
              </div>
            ))}
          </div>
        ) : customers.length === 0 ? (
          <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
            <Users size={40} className="empty-state-icon" />
            <p className="empty-state-title">لا يوجد عملاء</p>
            <p className="empty-state-text">لم يتم العثور على عملاء مطابقين للبحث</p>
          </div>
        ) : (
          <div className="mobile-card-list">
            {customers.map(c => (
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
                  { label: 'طريقة الدفع', value: paymentLabels[c.payment_terms] || c.payment_terms },
                  ...(c.credit_limit > 0 ? [{ label: 'حد الائتمان', value: formatNumber(c.credit_limit), highlight: true }] : []),
                  ...(c.governorate?.name ? [{ label: 'المحافظة', value: c.governorate.name }] : []),
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
          </div>
        )}

        {/* Pagination on mobile */}
        {totalPages > 1 && (
          <div className="mobile-pagination">
            <Button variant="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(p => p - 1)}>السابق</Button>
            <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>
              {page} / {totalPages}
            </span>
            <Button variant="ghost" size="sm" disabled={page >= totalPages} onClick={() => setPage(p => p + 1)}>التالي</Button>
          </div>
        )}
      </div>

      {/* ── Responsive Confirm Modal ──────────────────────── */}
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

        /* ── Desktop shows table, Mobile shows cards ── */
        .customers-table-view { display: block; }
        .customers-card-view  { display: none; }

        @media (max-width: 768px) {
          .customers-table-view { display: none; }
          .customers-card-view  { display: block; }
          .desktop-only-btn     { display: none; }
          .filter-select { font-size: var(--text-xs); }
        }

        .mobile-card-list {
          display: flex;
          flex-direction: column;
          gap: var(--space-3);
          padding: 0 0 var(--space-2);
        }

        .mobile-pagination {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: var(--space-4);
          padding: var(--space-4) 0;
        }
      `}</style>
    </div>
  )
}
