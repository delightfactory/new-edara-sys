import { useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  ShoppingCart, Plus, Eye, FileText, TrendingUp,
  CheckCircle, Truck, XCircle, Clock
} from 'lucide-react'
import { useSalesOrders, useSalesStats, useProfiles } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import type { SalesOrder, SalesOrderStatus } from '@/lib/types/master-data'
import { formatNumber } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import SearchInput from '@/components/shared/SearchInput'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'

const statusLabels: Record<SalesOrderStatus, string> = {
  draft: 'مسودة', confirmed: 'مؤكد', partially_delivered: 'مسلّم جزئياً',
  delivered: 'مُسلّم', completed: 'مكتمل', cancelled: 'ملغي',
}
const statusVariants: Record<SalesOrderStatus, 'neutral' | 'primary' | 'info' | 'success' | 'danger' | 'warning'> = {
  draft: 'neutral', confirmed: 'primary', partially_delivered: 'info',
  delivered: 'success', completed: 'success', cancelled: 'danger',
}
const paymentLabels: Record<string, string> = { cash: 'نقدي', credit: 'آجل', mixed: 'مختلط' }
const paymentVariants: Record<string, 'success' | 'warning' | 'info'> = { cash: 'success', credit: 'warning', mixed: 'info' }

export default function SalesOrdersPage() {
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)

  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState<SalesOrderStatus | ''>('')
  const [repFilter, setRepFilter] = useState('')
  const [page, setPage] = useState(1)

  const { data: reps = [] } = useProfiles()
  const { data: stats } = useSalesStats()

  const queryParams = useMemo(() => ({
    search: search || undefined,
    status: statusFilter || undefined,
    repId: repFilter || undefined,
    page,
    pageSize: 25,
  }), [search, statusFilter, repFilter, page])

  const { data: result, isLoading: loading } = useSalesOrders(queryParams)
  const orders = result?.data ?? []
  const totalPages = result?.totalPages ?? 1
  const totalCount = result?.count ?? 0

  const statCards = stats ? [
    { label: 'إجمالي المبيعات', value: formatNumber(stats.totalSales) + ' ج.م', icon: <TrendingUp size={18} /> },
    { label: 'مسودة', value: String(stats.statusCounts.draft ?? 0), icon: <FileText size={18} /> },
    { label: 'مؤكد', value: String(stats.statusCounts.confirmed ?? 0), icon: <CheckCircle size={18} /> },
    { label: 'مُسلّم', value: String(stats.statusCounts.delivered ?? 0), icon: <Truck size={18} /> },
  ] : undefined

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="أوامر البيع"
        subtitle={loading ? '...' : `${totalCount} طلب`}
        actions={can('sales.orders.create') ? (
          <Button icon={<Plus size={16} />} onClick={() => navigate('/sales/orders/new')}>
            طلب جديد
          </Button>
        ) : undefined}
      />

      {/* Stat Cards */}
      {statCards && (
        <div style={{
          display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
          gap: 'var(--space-4)', marginBottom: 'var(--space-4)',
        }}>
          {statCards.map((s, i) => (
            <div key={i} className="edara-card" style={{
              padding: 'var(--space-4)',
              display: 'flex', alignItems: 'center', gap: 'var(--space-3)',
            }}>
              <div style={{
                width: 40, height: 40, borderRadius: 'var(--radius-lg)',
                background: 'var(--color-primary-light)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: 'var(--color-primary)',
              }}>
                {s.icon}
              </div>
              <div>
                <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{s.label}</div>
                <div style={{ fontSize: 'var(--text-lg)', fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>{s.value}</div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Filters */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="flex gap-3" style={{ flexWrap: 'wrap' }}>
          <div style={{ flex: 2, minWidth: 200 }}>
            <SearchInput
              value={search}
              onChange={val => { setSearch(val); setPage(1) }}
              placeholder="بحث برقم الطلب أو اسم العميل..."
            />
          </div>
          <select className="form-select" style={{ width: 130 }} value={statusFilter}
            onChange={e => { setStatusFilter(e.target.value as any); setPage(1) }}>
            <option value="">كل الحالات</option>
            <option value="draft">مسودة</option>
            <option value="confirmed">مؤكد</option>
            <option value="delivered">مُسلّم</option>
            <option value="completed">مكتمل</option>
            <option value="cancelled">ملغي</option>
          </select>
          <select className="form-select" style={{ width: 140 }} value={repFilter}
            onChange={e => { setRepFilter(e.target.value); setPage(1) }}>
            <option value="">كل المناديب</option>
            {reps.map(r => <option key={r.id} value={r.id}>{r.full_name}</option>)}
          </select>
        </div>
      </div>

      {/* Table */}
      <div className="edara-card" style={{ overflow: 'auto' }}>
        <DataTable<SalesOrder>
          columns={[
            {
              key: 'order_number', label: 'رقم الطلب',
              render: o => (
                <>
                  <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)', fontFamily: 'monospace' }} dir="ltr">{o.order_number}</div>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                    {new Date(o.order_date).toLocaleDateString('ar-EG')}
                  </div>
                </>
              ),
            },
            {
              key: 'customer', label: 'العميل',
              render: o => (
                <>
                  <div style={{ fontWeight: 500, fontSize: 'var(--text-sm)' }}>{o.customer?.name || '—'}</div>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }} dir="ltr">{o.customer?.code}</div>
                </>
              ),
            },
            {
              key: 'rep', label: 'المندوب', hideOnMobile: true,
              render: o => o.rep?.full_name || <span style={{ color: 'var(--text-muted)' }}>—</span>,
            },
            {
              key: 'total', label: 'الإجمالي', hideOnMobile: true,
              render: o => (
                <span style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>
                  {formatNumber(o.total_amount)} ج.م
                </span>
              ),
            },
            {
              key: 'paid', label: 'المدفوع', hideOnMobile: true,
              render: o => {
                const paidRatio = o.total_amount > 0 ? ((o.paid_amount + o.returned_amount) / o.total_amount) : 0
                const color = paidRatio >= 1 ? 'var(--color-success)' : paidRatio > 0 ? 'var(--color-warning)' : 'var(--text-muted)'
                return (
                  <span style={{ fontVariantNumeric: 'tabular-nums', color }}>
                    {formatNumber(o.paid_amount)} ج.م
                  </span>
                )
              },
            },
            {
              key: 'payment_terms', label: 'الدفع', hideOnMobile: true,
              render: o => o.payment_terms ? (
                <Badge variant={paymentVariants[o.payment_terms] || 'neutral'}>
                  {paymentLabels[o.payment_terms] || o.payment_terms}
                </Badge>
              ) : <span style={{ color: 'var(--text-muted)' }}>—</span>,
            },
            {
              key: 'status', label: 'الحالة',
              render: o => (
                <Badge variant={statusVariants[o.status]}>
                  {statusLabels[o.status]}
                </Badge>
              ),
            },
            {
              key: 'actions', label: '', width: 50,
              render: o => (
                <div onClick={e => e.stopPropagation()}>
                  <Button variant="ghost" size="sm" onClick={() => navigate(`/sales/orders/${o.id}`)}>
                    <Eye size={14} />
                  </Button>
                </div>
              ),
            },
          ]}
          data={orders}
          loading={loading}
          onRowClick={o => navigate(`/sales/orders/${o.id}`)}
          emptyIcon={<ShoppingCart size={48} />}
          emptyTitle="لا توجد أوامر بيع"
          emptyText="ابدأ بإنشاء أول أمر بيع للعملاء"
          emptyAction={can('sales.orders.create') ? (
            <Button icon={<Plus size={16} />} onClick={() => navigate('/sales/orders/new')}>طلب جديد</Button>
          ) : undefined}
          page={page}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setPage}
        />
      </div>
    </div>
  )
}
