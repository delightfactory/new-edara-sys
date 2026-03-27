import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { Plus, FileText, Building2, Eye } from 'lucide-react'
import { getPurchaseInvoices } from '@/lib/services/purchases'
import { formatNumber } from '@/lib/utils/format'
import type { PurchaseInvoiceStatus } from '@/lib/types/master-data'
import PageHeader from '@/components/shared/PageHeader'
import SearchInput from '@/components/shared/SearchInput'
import DataTable from '@/components/shared/DataTable'
import DataCard from '@/components/ui/DataCard'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'

const STATUS_LABELS: Record<PurchaseInvoiceStatus, string> = {
  draft:     'مسودة',
  received:  'مستلمة',
  billed:    'معتمدة',
  paid:      'مدفوعة',
  cancelled: 'ملغاة',
}
const STATUS_VARIANTS: Record<PurchaseInvoiceStatus, 'neutral' | 'primary' | 'warning' | 'success' | 'danger'> = {
  draft:     'neutral',
  received:  'primary',
  billed:    'warning',
  paid:      'success',
  cancelled: 'danger',
}

const PAGE_SIZE = 20

export default function PurchaseInvoicesPage() {
  const navigate = useNavigate()
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState<PurchaseInvoiceStatus | ''>('')
  const [page, setPage] = useState(1)

  const { data, isLoading } = useQuery({
    queryKey: ['purchase-invoices', search, statusFilter, page],
    queryFn: () => getPurchaseInvoices({
      search:   search  || undefined,
      status:   (statusFilter as PurchaseInvoiceStatus) || undefined,
      page,
      pageSize: PAGE_SIZE,
    }),
  })

  const invoices   = data?.data || []
  const totalPages = data?.totalPages || 1
  const totalCount = data?.count || invoices.length

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="فواتير الشراء"
        subtitle={isLoading ? '...' : `${totalCount} فاتورة`}
        actions={
          <Button variant="primary" icon={<Plus size={16} />}
            onClick={() => navigate('/purchases/invoices/new')}
            className="desktop-only-btn">
            فاتورة جديدة
          </Button>
        }
      />

      {/* ── Filters ─────────────────────────────────── */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="purch-filter-row">
          <div style={{ flex: 2, minWidth: 180 }}>
            <SearchInput value={search} onChange={val => { setSearch(val); setPage(1) }}
              placeholder="بحث بالرقم أو اسم المورد..." />
          </div>
          <select className="form-select filter-select" value={statusFilter}
            onChange={e => { setStatusFilter(e.target.value as any); setPage(1) }}>
            <option value="">كل الحالات</option>
            {(Object.keys(STATUS_LABELS) as PurchaseInvoiceStatus[]).map(s => (
              <option key={s} value={s}>{STATUS_LABELS[s]}</option>
            ))}
          </select>
        </div>
      </div>

      {/* ── DESKTOP: DataTable ───────────────────────── */}
      <div className="purch-table-view edara-card" style={{ overflow: 'auto' }}>
        <DataTable<any>
          columns={[
            {
              key: 'number', label: 'رقم الفاتورة',
              render: inv => (
                <>
                  <div style={{ fontFamily: 'monospace', fontWeight: 700, color: 'var(--color-primary)', fontSize: 'var(--text-sm)' }} dir="ltr">
                    {inv.number || '—'}
                  </div>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                    {new Date(inv.invoice_date).toLocaleDateString('ar-EG-u-nu-latn')}
                  </div>
                </>
              ),
            },
            {
              key: 'supplier', label: 'المورد',
              render: inv => (
                <>
                  <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{inv.supplier?.name || '—'}</div>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }} dir="ltr">{inv.supplier?.code}</div>
                </>
              ),
            },
            {
              key: 'warehouse', label: 'المخزن', hideOnMobile: true,
              render: inv => <span style={{ color: 'var(--text-muted)' }}>{inv.warehouse?.name || '—'}</span>,
            },
            {
              key: 'total_amount', label: 'الإجمالي', hideOnMobile: true,
              render: inv => (
                <span style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>
                  {formatNumber(inv.total_amount)} ج.م
                </span>
              ),
            },
            {
              key: 'paid_amount', label: 'المدفوع', hideOnMobile: true,
              render: inv => (
                <span style={{
                  fontVariantNumeric: 'tabular-nums',
                  color: inv.paid_amount >= inv.total_amount && inv.total_amount > 0
                    ? 'var(--color-success)' : 'var(--text-muted)',
                }}>
                  {formatNumber(inv.paid_amount)} ج.م
                </span>
              ),
            },
            {
              key: 'status', label: 'الحالة',
              render: inv => (
                <Badge variant={STATUS_VARIANTS[inv.status as PurchaseInvoiceStatus]}>
                  {STATUS_LABELS[inv.status as PurchaseInvoiceStatus]}
                </Badge>
              ),
            },
            {
              key: 'actions', label: '', width: 60,
              render: inv => (
                <div onClick={e => e.stopPropagation()}>
                  <Button variant="ghost" size="sm" onClick={() => navigate(`/purchases/invoices/${inv.id}`)}>
                    <Eye size={14} />
                  </Button>
                </div>
              ),
            },
          ]}
          data={invoices}
          loading={isLoading}
          onRowClick={inv => navigate(`/purchases/invoices/${inv.id}`)}
          emptyIcon={<FileText size={48} />}
          emptyTitle="لا توجد فواتير مشتريات"
          emptyText="أنشئ أول فاتورة شراء من المورد"
          emptyAction={
            <Button icon={<Plus size={16} />} onClick={() => navigate('/purchases/invoices/new')}>
              فاتورة جديدة
            </Button>
          }
          page={page}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setPage}
        />
      </div>

      {/* ── MOBILE: DataCard list ────────────────────── */}
      <div className="purch-card-view">
        {isLoading ? (
          <div className="mobile-card-list">
            {[1, 2, 3].map(i => (
              <div key={i} className="edara-card" style={{ padding: 'var(--space-4)' }}>
                <div className="skeleton" style={{ height: 16, width: '55%', marginBottom: 8 }} />
                <div className="skeleton" style={{ height: 12, width: '35%', marginBottom: 12 }} />
                <div className="skeleton" style={{ height: 12, width: '80%' }} />
              </div>
            ))}
          </div>
        ) : invoices.length === 0 ? (
          <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
            <FileText size={40} className="empty-state-icon" />
            <p className="empty-state-title">لا توجد فواتير مشتريات</p>
          </div>
        ) : (
          <div className="mobile-card-list">
            {invoices.map((inv: any) => (
              <DataCard
                key={inv.id}
                title={inv.supplier?.name || '—'}
                subtitle={
                  <span dir="ltr" style={{ fontFamily: 'monospace', fontSize: '0.7rem' }}>
                    {inv.number || 'مسودة'}
                  </span>
                }
                badge={
                  <Badge variant={STATUS_VARIANTS[inv.status as PurchaseInvoiceStatus]}>
                    {STATUS_LABELS[inv.status as PurchaseInvoiceStatus]}
                  </Badge>
                }
                leading={
                  <div style={{
                    width: 40, height: 40, borderRadius: 'var(--radius-md)',
                    background: 'var(--bg-accent)', display: 'flex', alignItems: 'center', justifyContent: 'center',
                  }}>
                    <Building2 size={18} style={{ color: 'var(--color-primary)' }} />
                  </div>
                }
                metadata={[
                  {
                    label: 'التاريخ',
                    value: new Date(inv.invoice_date).toLocaleDateString('ar-EG-u-nu-latn'),
                  },
                  {
                    label: 'الإجمالي',
                    value: `${formatNumber(inv.total_amount)} ج.م`,
                    highlight: true,
                  },
                  {
                    label: 'المدفوع',
                    value: `${formatNumber(inv.paid_amount)} ج.م`,
                  },
                  ...(inv.warehouse?.name ? [{
                    label: 'المخزن',
                    value: inv.warehouse.name,
                  }] : []),
                ]}
                actions={
                  <Button variant="secondary" size="sm" style={{ width: '100%', justifyContent: 'center' }}
                    onClick={() => navigate(`/purchases/invoices/${inv.id}`)}>
                    <Eye size={14} /> عرض التفاصيل
                  </Button>
                }
                onClick={() => navigate(`/purchases/invoices/${inv.id}`)}
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

      {/* FAB for mobile */}
      <button
        className="mobile-fab"
        onClick={() => navigate('/purchases/invoices/new')}
        aria-label="فاتورة شراء جديدة"
      >
        <Plus size={24} />
      </button>

      <style>{`
        .purch-filter-row { display: flex; gap: var(--space-3); flex-wrap: wrap; align-items: flex-end; }
        .filter-select { min-width: 100px; flex: 1; }

        .purch-table-view { display: block; }
        .purch-card-view  { display: none; }

        @media (max-width: 768px) {
          .purch-table-view { display: none; }
          .purch-card-view  { display: block; }
          .desktop-only-btn { display: none; }
          .mobile-fab {
            position: fixed; bottom: calc(70px + var(--space-4)); left: var(--space-4);
            width: 56px; height: 56px; border-radius: 50%;
            background: var(--color-primary); color: #fff;
            border: none; cursor: pointer; display: flex; align-items: center; justify-content: center;
            box-shadow: 0 4px 20px rgba(37,99,235,0.4);
            z-index: var(--z-modal, 400);
            transition: transform 0.15s, box-shadow 0.15s;
          }
          .mobile-fab:hover { transform: scale(1.06); box-shadow: 0 6px 24px rgba(37,99,235,0.5); }
        }
        @media (min-width: 769px) { .mobile-fab { display: none; } }

        .mobile-card-list { display: flex; flex-direction: column; gap: var(--space-3); padding-bottom: var(--space-2); }
        .mobile-pagination { display: flex; align-items: center; justify-content: center; gap: var(--space-4); padding: var(--space-4) 0; }
      `}</style>
    </div>
  )
}
