import { useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { Plus, Truck, ToggleLeft, ToggleRight, Eye, Phone, MapPin, CreditCard } from 'lucide-react'
import { getSuppliers, toggleSupplierActive } from '@/lib/services/suppliers'
import { useGovernorates, useInvalidate } from '@/hooks/useQueryHooks'
import { useQuery } from '@tanstack/react-query'
import { useAuthStore } from '@/stores/auth-store'
import type { Supplier } from '@/lib/types/master-data'
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
  const invalidate = useInvalidate()
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [govFilter, setGovFilter] = useState('')
  const [page, setPage] = useState(1)
  const [confirmTarget, setConfirmTarget] = useState<Supplier | null>(null)

  const { data: governorates = [] } = useGovernorates()

  const queryParams = useMemo(() => ({
    search,
    isActive: statusFilter === '' ? undefined : statusFilter === 'active',
    page, pageSize: 25,
  }), [search, statusFilter, govFilter, page])

  const { data: result, isLoading: loading } = useQuery({
    queryKey: ['suppliers', queryParams],
    queryFn: () => getSuppliers(queryParams),
  })
  const suppliers = result?.data ?? []
  const totalPages = result?.totalPages ?? 1
  const totalCount = result?.count ?? 0

  const handleToggle = (s: Supplier) => setConfirmTarget(s)
  const executeToggle = async () => {
    if (!confirmTarget) return
    const next = !confirmTarget.is_active
    try {
      await toggleSupplierActive(confirmTarget.id, next)
      toast.success(`تم ${next ? 'تفعيل' : 'تعطيل'} المورد`)
      invalidate('suppliers')
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
          <Button icon={<Plus size={16} />} onClick={() => navigate('/suppliers/new')} className="desktop-only-btn">
            إضافة مورد
          </Button>
        ) : undefined}
      />

      {/* Filters */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div style={{ display: 'flex', gap: 'var(--space-3)', flexWrap: 'wrap' }}>
          <div style={{ flex: 2, minWidth: 180 }}>
            <SearchInput
              value={search}
              onChange={val => { setSearch(val); setPage(1) }}
              placeholder="بحث بالاسم أو الكود أو الهاتف..."
            />
          </div>
          <select className="form-select" style={{ flex: 1, minWidth: 120 }} value={govFilter}
            onChange={e => { setGovFilter(e.target.value); setPage(1) }}>
            <option value="">كل المحافظات</option>
            {governorates.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
          </select>
          <select className="form-select" style={{ width: 110 }} value={statusFilter}
            onChange={e => { setStatusFilter(e.target.value); setPage(1) }}>
            <option value="">الحالة</option>
            <option value="active">نشط</option>
            <option value="inactive">معطل</option>
          </select>
        </div>
      </div>

      {/* ── DESKTOP: DataTable ─────────────────────────────────────── */}
      <div className="sup-table-view edara-card" style={{ overflow: 'auto' }}>
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

      {/* ── MOBILE: Supplier Card List ─────────────────────────────── */}
      <div className="sup-card-view">
        {loading ? (
          <div className="mobile-card-list">
            {[1, 2, 3].map(i => <div key={i} className="edara-card" style={{ height: 100 }}><div className="skeleton" style={{ height: '100%' }} /></div>)}
          </div>
        ) : suppliers.length === 0 ? (
          <div className="edara-card" style={{ padding: 'var(--space-8)', textAlign: 'center', color: 'var(--text-muted)' }}>
            <Truck size={40} style={{ margin: '0 auto 12px', display: 'block', opacity: 0.3 }} />
            <p>لا يوجد موردين</p>
            {can('suppliers.create') && (
              <Button icon={<Plus size={14} />} onClick={() => navigate('/suppliers/new')} style={{ marginTop: 12 }}>
                إضافة أول مورد
              </Button>
            )}
          </div>
        ) : (
          <div className="mobile-card-list">
            {suppliers.map((s: Supplier) => (
              <div key={s.id} className="edara-card sup-mobile-card" style={{ opacity: s.is_active ? 1 : 0.6 }}
                onClick={() => navigate(`/suppliers/${s.id}`)}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 8 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                    <div style={{ width: 38, height: 38, borderRadius: 'var(--radius-md)', background: 'rgba(37,99,235,0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                      <Truck size={16} style={{ color: 'var(--color-primary)' }} />
                    </div>
                    <div>
                      <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)' }}>{s.name}</div>
                      <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }} dir="ltr">{s.code}</div>
                    </div>
                  </div>
                  <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 4 }}>
                    <Badge variant={s.is_active ? 'success' : 'danger'}>{s.is_active ? 'نشط' : 'معطل'}</Badge>
                    <Badge variant={paymentBadge[s.payment_terms || 'cash'] || 'success'}>
                      <CreditCard size={9} /> {paymentLabels[s.payment_terms || 'cash'] || s.payment_terms}
                    </Badge>
                  </div>
                </div>
                <div style={{ display: 'flex', gap: 'var(--space-4)', fontSize: 'var(--text-xs)', color: 'var(--text-muted)', flexWrap: 'wrap' }}>
                  {s.phone && (
                    <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                      <Phone size={10} />
                      <span dir="ltr">{s.phone}</span>
                    </span>
                  )}
                  {s.governorate?.name && (
                    <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                      <MapPin size={10} />
                      {s.governorate.name}
                    </span>
                  )}
                  {s.credit_limit > 0 && (
                    <span>حد ائتمان: <strong style={{ fontVariantNumeric: 'tabular-nums' }}>{formatNumber(s.credit_limit)}</strong></span>
                  )}
                </div>
                {can('suppliers.update') && (
                  <div style={{ marginTop: 10, paddingTop: 10, borderTop: '1px solid var(--border-color)' }}
                    onClick={e => e.stopPropagation()}>
                    <Button
                      variant={s.is_active ? 'danger' : 'success'}
                      size="sm"
                      icon={s.is_active ? <ToggleLeft size={12} /> : <ToggleRight size={12} />}
                      style={{ width: '100%', justifyContent: 'center' }}
                      onClick={() => handleToggle(s)}
                    >
                      {s.is_active ? 'تعطيل المورد' : 'تفعيل المورد'}
                    </Button>
                  </div>
                )}
              </div>
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

      {/* Mobile FAB */}
      {can('suppliers.create') && (
        <button className="fab-btn" onClick={() => navigate('/suppliers/new')} aria-label="إضافة مورد">
          <Plus size={24} />
        </button>
      )}

      <ConfirmDialog
        open={!!confirmTarget}
        title={confirmTarget?.is_active ? 'تعطيل المورد' : 'تفعيل المورد'}
        message={`هل تريد ${confirmTarget?.is_active ? 'تعطيل' : 'تفعيل'} المورد "${confirmTarget?.name}"؟`}
        variant={confirmTarget?.is_active ? 'danger' : 'info'}
        confirmText={confirmTarget?.is_active ? 'تعطيل' : 'تفعيل'}
        onConfirm={executeToggle}
        onCancel={() => setConfirmTarget(null)}
      />

      <style>{`
        .sup-table-view { display: block; }
        .sup-card-view  { display: none; }
        .sup-mobile-card { padding: var(--space-4); cursor: pointer; transition: background 0.12s; }
        .sup-mobile-card:hover { background: var(--bg-hover); }
        .mobile-card-list { display: flex; flex-direction: column; gap: var(--space-3); }
        .mobile-pagination { display: flex; align-items: center; justify-content: center; gap: var(--space-4); padding: var(--space-4) 0; }
        .fab-btn {
          position: fixed; bottom: calc(70px + var(--space-4)); left: var(--space-4);
          width: 56px; height: 56px; border-radius: 50%;
          background: var(--color-primary); color: #fff;
          border: none; cursor: pointer; display: flex; align-items: center; justify-content: center;
          box-shadow: 0 4px 20px rgba(37,99,235,0.35);
          z-index: var(--z-modal, 400); transition: transform 0.15s;
        }
        .fab-btn:hover { transform: scale(1.06); }
        @media (max-width: 768px) {
          .desktop-only-btn { display: none !important; }
          .sup-table-view { display: none; }
          .sup-card-view  { display: block; }
        }
        @media (min-width: 769px) { .fab-btn { display: none; } }
      `}</style>
    </div>
  )
}
