import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { Plus, Search, FileText } from 'lucide-react'
import { getPurchaseInvoices } from '@/lib/services/purchases'
import { formatNumber } from '@/lib/utils/format'
import type { PurchaseInvoiceStatus } from '@/lib/types/master-data'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'

const STATUS_LABELS: Record<PurchaseInvoiceStatus, string> = {
  draft:     'مسودة',
  received:  'مستلمة',
  billed:    'معتمدة',
  paid:      'مدفوعة',
  cancelled: 'ملغاة',
}
const STATUS_COLORS: Record<PurchaseInvoiceStatus, { color: string; bg: string }> = {
  draft:     { color: '#92400e', bg: '#fef3c7' },
  received:  { color: '#1e40af', bg: '#dbeafe' },
  billed:    { color: '#6b21a8', bg: '#f3e8ff' },
  paid:      { color: '#166534', bg: '#dcfce7' },
  cancelled: { color: '#991b1b', bg: '#fee2e2' },
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

  const invoices  = data?.data || []
  const totalPages = data?.totalPages || 1

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="فواتير الشراء"
        subtitle="إدارة فواتير الموردين من المسودة حتى السداد"
        actions={
          <Button variant="primary" icon={<Plus size={16} />} onClick={() => navigate('/purchases/invoices/new')}>
            فاتورة جديدة
          </Button>
        }
      />

      {/* Filters */}
      <div className="edara-card" style={{ padding: '14px 20px', marginBottom: 16, display: 'flex', gap: 12, flexWrap: 'wrap', alignItems: 'center' }}>
        <div style={{ position: 'relative', flex: 1, minWidth: 200 }}>
          <Search size={14} style={{ position: 'absolute', right: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
          <input
            className="form-input"
            style={{ paddingRight: 32 }}
            placeholder="بحث بالرقم أو رقم مورد..."
            value={search}
            onChange={e => { setSearch(e.target.value); setPage(1) }}
          />
        </div>
        <select
          className="form-select"
          style={{ width: 160 }}
          value={statusFilter}
          onChange={e => { setStatusFilter(e.target.value as any); setPage(1) }}
        >
          <option value="">كل الحالات</option>
          {(Object.keys(STATUS_LABELS) as PurchaseInvoiceStatus[]).map(s => (
            <option key={s} value={s}>{STATUS_LABELS[s]}</option>
          ))}
        </select>
      </div>

      {/* Table */}
      <div className="edara-card" style={{ overflow: 'hidden' }}>
        {isLoading ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>جاري التحميل...</div>
        ) : invoices.length === 0 ? (
          <div style={{ padding: 60, textAlign: 'center', color: 'var(--text-muted)' }}>
            <FileText size={40} style={{ margin: '0 auto 12px', display: 'block', opacity: 0.3 }} />
            لا توجد فواتير مشتريات
          </div>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.875rem' }}>
              <thead>
                <tr style={{ background: 'var(--bg-surface-2)', textAlign: 'right' }}>
                  {['رقم الفاتورة', 'المورد', 'المخزن', 'التاريخ', 'الإجمالي', 'المدفوع', 'الحالة', ''].map(h => (
                    <th key={h} style={{ padding: '10px 14px', fontWeight: 600, fontSize: '0.8rem', whiteSpace: 'nowrap' }}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {invoices.map(inv => {
                  const sc = STATUS_COLORS[inv.status]
                  return (
                    <tr
                      key={inv.id}
                      style={{ borderBottom: '1px solid var(--border-color)', cursor: 'pointer', transition: 'background 0.12s' }}
                      onClick={() => navigate(`/purchases/invoices/${inv.id}`)}
                      onMouseEnter={e => (e.currentTarget.style.background = 'var(--bg-hover)')}
                      onMouseLeave={e => (e.currentTarget.style.background = '')}
                    >
                      <td style={{ padding: '12px 14px', fontFamily: 'monospace', fontWeight: 700, color: 'var(--color-primary)' }}>
                        {inv.number || '—'}
                      </td>
                      <td style={{ padding: '12px 14px', fontWeight: 600 }}>{(inv as any).supplier?.name || '—'}</td>
                      <td style={{ padding: '12px 14px', color: 'var(--text-muted)' }}>{(inv as any).warehouse?.name || '—'}</td>
                      <td style={{ padding: '12px 14px', color: 'var(--text-muted)', fontVariantNumeric: 'tabular-nums' }}>
                        {new Date(inv.invoice_date).toLocaleDateString('ar-EG')}
                      </td>
                      <td style={{ padding: '12px 14px', fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>
                        {formatNumber(inv.total_amount)} ج.م
                      </td>
                      <td style={{ padding: '12px 14px', color: inv.paid_amount >= inv.total_amount ? 'var(--color-success)' : 'var(--color-danger)', fontVariantNumeric: 'tabular-nums' }}>
                        {formatNumber(inv.paid_amount)} ج.م
                      </td>
                      <td style={{ padding: '12px 14px' }}>
                        <span style={{ padding: '3px 10px', borderRadius: 99, fontWeight: 700, fontSize: '0.75rem', color: sc.color, background: sc.bg }}>
                          {STATUS_LABELS[inv.status]}
                        </span>
                      </td>
                      <td style={{ padding: '12px 14px' }}>
                        <Button variant="ghost" size="sm" onClick={e => { e.stopPropagation(); navigate(`/purchases/invoices/${inv.id}`) }}>
                          عرض
                        </Button>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}

        {/* Pagination */}
        {totalPages > 1 && (
          <div style={{ padding: '12px 20px', borderTop: '1px solid var(--border-color)', display: 'flex', justifyContent: 'center', gap: 8 }}>
            <Button variant="ghost" size="sm" disabled={page === 1} onClick={() => setPage(p => p - 1)}>السابق</Button>
            <span style={{ lineHeight: '32px', fontSize: '0.875rem', color: 'var(--text-muted)' }}>صفحة {page} / {totalPages}</span>
            <Button variant="ghost" size="sm" disabled={page === totalPages} onClick={() => setPage(p => p + 1)}>التالي</Button>
          </div>
        )}
      </div>
    </div>
  )
}
