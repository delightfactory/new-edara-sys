import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { Plus, Truck, ToggleLeft, ToggleRight, Eye } from 'lucide-react'
import { getSuppliers, toggleSupplierActive } from '@/lib/services/suppliers'
import { getGovernorates } from '@/lib/services/geography'
import { useAuthStore } from '@/stores/auth-store'
import type { Supplier, Governorate } from '@/lib/types/master-data'
import { formatNumber } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import SearchInput from '@/components/shared/SearchInput'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import ConfirmDialog from '@/components/ui/ConfirmDialog'

export default function SuppliersPage() {
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [governorates, setGovernorates] = useState<Governorate[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [govFilter, setGovFilter] = useState('')
  const [page, setPage] = useState(1)
  const [totalPages, setTotalPages] = useState(1)
  const [totalCount, setTotalCount] = useState(0)
  const [confirmTarget, setConfirmTarget] = useState<Supplier | null>(null)

  const loadData = async () => {
    setLoading(true)
    try {
      const [res, govs] = await Promise.all([
        getSuppliers({
          search,
          isActive: statusFilter === '' ? undefined : statusFilter === 'active',
          page, pageSize: 25,
        }),
        governorates.length ? Promise.resolve(governorates) : getGovernorates(),
      ])
      setSuppliers(res.data)
      setTotalPages(res.totalPages)
      setTotalCount(res.count)
      if (!governorates.length) setGovernorates(govs as Governorate[])
    } catch { toast.error('فشل تحميل الموردين') }
    finally { setLoading(false) }
  }

  useEffect(() => { loadData() }, [search, statusFilter, govFilter, page])

  const handleToggle = (s: Supplier) => setConfirmTarget(s)
  const executeToggle = async () => {
    if (!confirmTarget) return
    const next = !confirmTarget.is_active
    try {
      await toggleSupplierActive(confirmTarget.id, next)
      toast.success(`تم ${next ? 'تفعيل' : 'تعطيل'} المورد`)
      loadData()
    } catch { toast.error('فشلت العملية') }
    finally { setConfirmTarget(null) }
  }

  const paymentLabels: Record<string, string> = { cash: 'نقدي', credit: 'آجل' }
  const paymentBadge: Record<string, 'success' | 'warning'> = { cash: 'success', credit: 'warning' }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="الموردين"
        subtitle={loading ? '...' : `${totalCount} مورد`}
        actions={can('suppliers.create') ? (
          <Button icon={<Plus size={16} />} onClick={() => navigate('/suppliers/new')}>
            إضافة مورد
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
          <select className="form-select" style={{ width: 140 }} value={govFilter}
            onChange={e => { setGovFilter(e.target.value); setPage(1) }}>
            <option value="">كل المحافظات</option>
            {governorates.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
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
        <DataTable<Supplier>
          columns={[
            {
              key: 'name', label: 'المورد',
              render: s => (
                <>
                  <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{s.name}</div>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', display: 'flex', gap: 'var(--space-2)', alignItems: 'center', flexWrap: 'wrap' }}>
                    <span dir="ltr" style={{ fontFamily: 'monospace' }}>{s.code}</span>
                    {s.phone && <span dir="ltr">• {s.phone}</span>}
                  </div>
                </>
              ),
            },
            { key: 'gov', label: 'المحافظة', hideOnMobile: true, render: s => s.governorate?.name || '—' },
            { key: 'payment', label: 'الدفع', hideOnMobile: true, render: s => <Badge variant={paymentBadge[s.payment_terms || 'cash'] || 'success'}>{paymentLabels[s.payment_terms || 'cash'] || s.payment_terms}</Badge> },
            { key: 'credit', label: 'حد الائتمان', hideOnMobile: true, render: s => s.credit_limit > 0 ? <span style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{formatNumber(s.credit_limit)}</span> : <span style={{ color: 'var(--text-muted)' }}>—</span> },
            { key: 'status', label: 'الحالة', render: s => <Badge variant={s.is_active ? 'success' : 'danger'}>{s.is_active ? 'نشط' : 'معطل'}</Badge> },
            {
              key: 'actions', label: 'إجراءات', width: 100,
              render: s => (
                <div className="flex gap-1" onClick={e => e.stopPropagation()}>
                  <Button variant="ghost" size="sm" title="عرض/تعديل" onClick={() => navigate(`/suppliers/${s.id}`)}>
                    <Eye size={14} />
                  </Button>
                  {can('suppliers.update') && (
                    <Button variant={s.is_active ? 'danger' : 'success'} size="sm"
                      title={s.is_active ? 'تعطيل' : 'تفعيل'} onClick={() => handleToggle(s)}>
                      {s.is_active ? <ToggleLeft size={14} /> : <ToggleRight size={14} />}
                    </Button>
                  )}
                </div>
              ),
            },
          ]}
          data={suppliers}
          loading={loading}
          onRowClick={s => navigate(`/suppliers/${s.id}`)}
          rowStyle={s => ({ opacity: s.is_active ? 1 : 0.6 })}
          emptyIcon={<Truck size={48} />}
          emptyTitle="لا يوجد موردين"
          emptyText="لم يتم العثور على موردين مطابقين"
          emptyAction={can('suppliers.create') ? (
            <Button icon={<Plus size={16} />} onClick={() => navigate('/suppliers/new')}>إضافة أول مورد</Button>
          ) : undefined}
          page={page}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setPage}
        />
      </div>

      <ConfirmDialog
        open={!!confirmTarget}
        title={confirmTarget?.is_active ? 'تعطيل المورد' : 'تفعيل المورد'}
        message={`هل تريد ${confirmTarget?.is_active ? 'تعطيل' : 'تفعيل'} المورد "${confirmTarget?.name}"؟`}
        variant={confirmTarget?.is_active ? 'danger' : 'info'}
        confirmText={confirmTarget?.is_active ? 'تعطيل' : 'تفعيل'}
        onConfirm={executeToggle}
        onCancel={() => setConfirmTarget(null)}
      />
    </div>
  )
}
