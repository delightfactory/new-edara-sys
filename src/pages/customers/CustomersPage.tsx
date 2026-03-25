import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { Plus, Users, ToggleLeft, ToggleRight, Eye } from 'lucide-react'
import { getCustomers, toggleCustomerActive } from '@/lib/services/customers'
import { getGovernorates, getCities } from '@/lib/services/geography'
import { supabase } from '@/lib/supabase/client'
import { useAuthStore } from '@/stores/auth-store'
import type { Customer, Governorate, City } from '@/lib/types/master-data'
import { formatNumber } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import SearchInput from '@/components/shared/SearchInput'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import ConfirmDialog from '@/components/ui/ConfirmDialog'

export default function CustomersPage() {
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const [customers, setCustomers] = useState<Customer[]>([])
  const [governorates, setGovernorates] = useState<Governorate[]>([])
  const [cities, setCities] = useState<City[]>([])
  const [reps, setReps] = useState<{ id: string; full_name: string }[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [typeFilter, setTypeFilter] = useState('')
  const [govFilter, setGovFilter] = useState('')
  const [cityFilter, setCityFilter] = useState('')
  const [repFilter, setRepFilter] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [page, setPage] = useState(1)
  const [totalPages, setTotalPages] = useState(1)
  const [totalCount, setTotalCount] = useState(0)
  const [confirmTarget, setConfirmTarget] = useState<Customer | null>(null)

  const loadData = async () => {
    setLoading(true)
    try {
      const [res, govs] = await Promise.all([
        getCustomers({
          search, type: typeFilter, governorateId: govFilter, cityId: cityFilter,
          repId: repFilter,
          isActive: statusFilter === '' ? undefined : statusFilter === 'active',
          page, pageSize: 25,
        }),
        governorates.length ? Promise.resolve(governorates) : getGovernorates(),
      ])
      setCustomers(res.data)
      setTotalPages(res.totalPages)
      setTotalCount(res.count)
      if (!governorates.length) setGovernorates(govs as Governorate[])
    } catch { toast.error('فشل تحميل العملاء') }
    finally { setLoading(false) }
  }

  useEffect(() => {
    supabase.from('profiles').select('id, full_name').eq('status', 'active').order('full_name')
      .then(({ data }) => { if (data) setReps(data) })
  }, [])

  useEffect(() => {
    if (govFilter) {
      getCities(govFilter).then(setCities).catch(() => {})
    } else {
      setCities([])
      setCityFilter('')
    }
  }, [govFilter])

  useEffect(() => { loadData() }, [search, typeFilter, govFilter, cityFilter, repFilter, statusFilter, page])

  const handleToggle = (c: Customer) => setConfirmTarget(c)
  const executeToggle = async () => {
    if (!confirmTarget) return
    const next = !confirmTarget.is_active
    try {
      await toggleCustomerActive(confirmTarget.id, next)
      toast.success(`تم ${next ? 'تفعيل' : 'إلغاء تفعيل'} العميل`)
      loadData()
    } catch { toast.error('فشلت العملية') }
    finally { setConfirmTarget(null) }
  }

  const typeLabels: Record<string, string> = { retail: 'تجزئة', wholesale: 'جملة', distributor: 'موزع' }
  const typeBadge: Record<string, 'neutral' | 'info' | 'primary'> = { retail: 'neutral', wholesale: 'info', distributor: 'primary' }
  const paymentLabels: Record<string, string> = { cash: 'نقدي', credit: 'آجل', mixed: 'مختلط' }
  const paymentBadge: Record<string, 'success' | 'warning' | 'info'> = { cash: 'success', credit: 'warning', mixed: 'info' }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="العملاء"
        subtitle={loading ? '...' : `${totalCount} عميل`}
        actions={can('customers.create') ? (
          <Button icon={<Plus size={16} />} onClick={() => navigate('/customers/new')}>
            إضافة عميل
          </Button>
        ) : undefined}
      />

      {/* Filters */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="flex gap-3" style={{ flexWrap: 'wrap' }}>
          <div style={{ flex: 2, minWidth: 200 }}>
            <SearchInput
              value={search}
              onChange={val => { setSearch(val); setPage(1) }}
              placeholder="بحث بالاسم أو الكود أو الهاتف..."
            />
          </div>
          <select className="form-select" style={{ width: 110 }} value={typeFilter}
            onChange={e => { setTypeFilter(e.target.value); setPage(1) }}>
            <option value="">كل الأنواع</option>
            <option value="retail">تجزئة</option>
            <option value="wholesale">جملة</option>
            <option value="distributor">موزع</option>
          </select>
          <select className="form-select" style={{ width: 140 }} value={govFilter}
            onChange={e => { setGovFilter(e.target.value); setCityFilter(''); setPage(1) }}>
            <option value="">كل المحافظات</option>
            {governorates.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
          </select>
          {govFilter && cities.length > 0 && (
            <select className="form-select" style={{ width: 140 }} value={cityFilter}
              onChange={e => { setCityFilter(e.target.value); setPage(1) }}>
              <option value="">كل المدن</option>
              {cities.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          )}
          <select className="form-select" style={{ width: 140 }} value={repFilter}
            onChange={e => { setRepFilter(e.target.value); setPage(1) }}>
            <option value="">كل المناديب</option>
            {reps.map(r => <option key={r.id} value={r.id}>{r.full_name}</option>)}
          </select>
          <select className="form-select" style={{ width: 100 }} value={statusFilter}
            onChange={e => { setStatusFilter(e.target.value); setPage(1) }}>
            <option value="">الحالة</option>
            <option value="active">نشط</option>
            <option value="inactive">معطل</option>
          </select>
        </div>
      </div>

      {/* Table */}
      <div className="edara-card" style={{ overflow: 'auto' }}>
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

      <ConfirmDialog
        open={!!confirmTarget}
        title={confirmTarget?.is_active ? 'تعطيل العميل' : 'تفعيل العميل'}
        message={`هل تريد ${confirmTarget?.is_active ? 'تعطيل' : 'تفعيل'} العميل "${confirmTarget?.name}"؟`}
        variant={confirmTarget?.is_active ? 'danger' : 'info'}
        confirmText={confirmTarget?.is_active ? 'تعطيل' : 'تفعيل'}
        onConfirm={executeToggle}
        onCancel={() => setConfirmTarget(null)}
      />
    </div>
  )
}
