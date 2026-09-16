import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { Plus, FileText, Eye } from 'lucide-react'
import { getPurchaseInvoices } from '@/lib/services/purchases'
import { formatNumber } from '@/lib/utils/format'
import type { PurchaseInvoice, PurchaseInvoiceStatus } from '@/lib/types/master-data'
import PageHeader from '@/components/shared/PageHeader'
import SearchInput from '@/components/shared/SearchInput'
import DataTable from '@/components/shared/DataTable'
import { SupplierLink, WarehouseLink } from '@/components/shared/EntityLink'
import Button from '@/components/ui/Button'
import ResponsiveCollection from '@/components/patterns/ResponsiveCollection'
import StatePanel from '@/components/patterns/StatePanel'
import StatusBadge, { type SemanticTone } from '@/components/patterns/StatusBadge'
import { PurchaseInvoiceCard } from '@/components/purchases/PurchaseInvoiceListPresentation'

const STATUS_LABELS: Record<PurchaseInvoiceStatus, string> = {
  draft:     'مسودة',
  received:  'مستلمة',
  billed:    'معتمدة',
  paid:      'مدفوعة',
  cancelled: 'ملغاة',
}

const STATUS_TONES: Record<PurchaseInvoiceStatus, SemanticTone> = {
  draft:     'neutral',
  received:  'info',
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

  function renderCardPagination(mode: 'mobile' | 'tablet') {
    if (totalPages <= 1) return null

    if (mode === 'tablet') {
      return (
        <nav
          className="pagination"
          aria-label="ترقيم صفحات فواتير الشراء"
          style={{ padding: 'var(--space-4)' }}
        >
          <span className="pagination-info">
            صفحة {page} من {totalPages} ({totalCount})
          </span>
          <div className="pagination-buttons">
            <Button
              variant="ghost"
              size="sm"
              touchTarget
              aria-label="الصفحة السابقة"
              disabled={page <= 1}
              onClick={() => setPage(page - 1)}
            >
              السابق
            </Button>
            {Array.from({ length: Math.min(totalPages, 5) }, (_, i) => {
              const num = page <= 3 ? i + 1 : page + i - 2
              if (num < 1 || num > totalPages) return null
              return (
                <Button
                  key={num}
                  variant={num === page ? 'primary' : 'secondary'}
                  size="sm"
                  touchTarget
                  aria-label={`الصفحة ${num}`}
                  aria-current={num === page ? 'page' : undefined}
                  style={{ minWidth: 'var(--ds-icon-hit-target)' }}
                  onClick={() => setPage(num)}
                >
                  {num}
                </Button>
              )
            })}
            <Button
              variant="ghost"
              size="sm"
              touchTarget
              aria-label="الصفحة التالية"
              disabled={page >= totalPages}
              onClick={() => setPage(page + 1)}
            >
              التالي
            </Button>
          </div>
        </nav>
      )
    }

    return (
      <nav
        aria-label="ترقيم صفحات فواتير الشراء"
        style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 'var(--space-4)', paddingBlock: 'var(--space-4)' }}
      >
        <Button
          variant="ghost"
          size="sm"
          touchTarget
          aria-label="الصفحة السابقة"
          disabled={page <= 1}
          onClick={() => setPage(p => p - 1)}
        >
          السابق
        </Button>
        <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>{page} / {totalPages}</span>
        <Button
          variant="ghost"
          size="sm"
          touchTarget
          aria-label="الصفحة التالية"
          disabled={page >= totalPages}
          onClick={() => setPage(p => p + 1)}
        >
          التالي
        </Button>
      </nav>
    )
  }

  function renderInvoiceCard(inv: PurchaseInvoice, mode: 'mobile' | 'tablet') {
    const invoiceLabel = inv.number || 'المسودة'

    return (
      <PurchaseInvoiceCard
        key={inv.id}
        mode={mode}
        summary={{
          number: inv.number || 'مسودة',
          supplier: (
            <SupplierLink
              id={inv.supplier?.id}
              name={inv.supplier?.name}
              code={inv.supplier?.code}
              style={{ fontSize: 'var(--text-sm)' }}
            />
          ),
          date: new Date(inv.invoice_date).toLocaleDateString('ar-EG-u-nu-latn'),
          warehouse: inv.warehouse?.name ? <WarehouseLink name={inv.warehouse.name} /> : undefined,
          total: <span style={{ fontVariantNumeric: 'tabular-nums' }}>{formatNumber(inv.total_amount)} ج.م</span>,
          paid: (
            <span style={{
              fontVariantNumeric: 'tabular-nums',
              color: inv.paid_amount >= inv.total_amount && inv.total_amount > 0
                ? 'var(--color-success)' : 'var(--text-muted)',
            }}>
              {formatNumber(inv.paid_amount)} ج.م
            </span>
          ),
          statusLabel: STATUS_LABELS[inv.status],
          statusTone: STATUS_TONES[inv.status],
        }}
        openLabel={`عرض تفاصيل فاتورة ${invoiceLabel}`}
        onOpen={() => navigate(`/purchases/invoices/${inv.id}`)}
      />
    )
  }

  function renderCardCollection(items: PurchaseInvoice[], mode: 'mobile' | 'tablet') {
    return (
      <div>
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: mode === 'tablet' ? 'repeat(2, minmax(0, 1fr))' : 'minmax(0, 1fr)',
            gap: 'var(--space-3)',
          }}
        >
          {items.map(item => renderInvoiceCard(item, mode))}
        </div>
        {renderCardPagination(mode)}
      </div>
    )
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="فواتير الشراء"
        subtitle={isLoading ? '...' : `${totalCount} فاتورة`}
        actions={
          <Button
            variant="primary"
            icon={<Plus size={16} />}
            onClick={() => navigate('/purchases/invoices/new')}
            className="desktop-only-btn"
          >
            فاتورة جديدة
          </Button>
        }
      />

      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="purch-filter-row">
          <div style={{ flex: 2, minWidth: 180 }}>
            <SearchInput
              value={search}
              onChange={val => { setSearch(val); setPage(1) }}
              placeholder="بحث بالرقم أو اسم المورد..."
            />
          </div>
          <select
            className="form-select filter-select"
            value={statusFilter}
            onChange={e => { setStatusFilter(e.target.value as PurchaseInvoiceStatus | ''); setPage(1) }}
          >
            <option value="">كل الحالات</option>
            {(Object.keys(STATUS_LABELS) as PurchaseInvoiceStatus[]).map(s => (
              <option key={s} value={s}>{STATUS_LABELS[s]}</option>
            ))}
          </select>
        </div>
      </div>

      <ResponsiveCollection<PurchaseInvoice>
        items={invoices}
        loading={isLoading}
        renderDesktop={items => (
          <div className="edara-card" style={{ overflow: 'auto' }}>
            <DataTable<PurchaseInvoice>
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
                    <SupplierLink
                      id={inv.supplier?.id}
                      name={inv.supplier?.name}
                      code={inv.supplier?.code}
                      style={{ fontSize: 'var(--text-sm)' }}
                    />
                  ),
                },
                {
                  key: 'warehouse', label: 'المخزن', hideOnMobile: true,
                  render: inv => <WarehouseLink name={inv.warehouse?.name} />,
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
                    <StatusBadge
                      label={STATUS_LABELS[inv.status]}
                      tone={STATUS_TONES[inv.status]}
                    />
                  ),
                },
                {
                  key: 'actions', label: '', width: 60,
                  render: inv => (
                    <div onClick={e => e.stopPropagation()}>
                      <Button
                        variant="ghost"
                        size="sm"
                        icon={<Eye size={14} />}
                        aria-label={`عرض تفاصيل فاتورة ${inv.number || 'المسودة'}`}
                        onClick={() => navigate(`/purchases/invoices/${inv.id}`)}
                      />
                    </div>
                  ),
                },
              ]}
              data={items}
              onRowClick={inv => navigate(`/purchases/invoices/${inv.id}`)}
              page={page}
              totalPages={totalPages}
              totalCount={totalCount}
              onPageChange={setPage}
            />
          </div>
        )}
        renderTablet={items => renderCardCollection(items, 'tablet')}
        renderMobile={items => renderCardCollection(items, 'mobile')}
        emptyState={
          <StatePanel
            kind="empty"
            icon={<FileText size={40} />}
            title="لا توجد فواتير مشتريات"
            description="أنشئ أول فاتورة شراء من المورد"
            action={
              <Button icon={<Plus size={16} />} onClick={() => navigate('/purchases/invoices/new')}>
                فاتورة جديدة
              </Button>
            }
          />
        }
      />

      <style>{`
        .purch-filter-row { display: flex; gap: var(--space-3); flex-wrap: wrap; align-items: flex-end; }
        .filter-select { min-width: 100px; flex: 1; }
        @media (max-width: 768px) {
          .desktop-only-btn { display: none; }
        }
      `}</style>
    </div>
  )
}
