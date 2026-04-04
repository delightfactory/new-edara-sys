import { useState, useMemo, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  ShoppingCart, Plus, Eye, FileText, TrendingUp,
  CheckCircle, Truck, XCircle, Clock, Calendar, Loader2, CheckCircle2
} from 'lucide-react'
import { useSalesOrders, useSalesStats, useProfiles } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import type { SalesOrder, SalesOrderStatus } from '@/lib/types/master-data'
import { formatNumber } from '@/lib/utils/format'
import { useMobileInfiniteList } from '@/hooks/useIntersectionObserver'
import PageHeader from '@/components/shared/PageHeader'
import SearchInput from '@/components/shared/SearchInput'
import DataTable from '@/components/shared/DataTable'
import DataCard from '@/components/ui/DataCard'
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

const PAGE_SIZE = 25

export default function SalesOrdersPage() {
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)

  // ── Filters ──────────────────────────────────────────────────────
  const [search,       setSearch]       = useState('')
  const [statusFilter, setStatusFilter] = useState<SalesOrderStatus | ''>('')
  const [repFilter,    setRepFilter]    = useState('')

  // ── Desktop pagination ────────────────────────────────────────────
  const [desktopPage, setDesktopPage] = useState(1)
  // ── Mobile pagination ─────────────────────────────────────────────
  const [mobilePage,  setMobilePage]  = useState(1)

  const filterKey = `${search}|${statusFilter}|${repFilter}`
  const filterParams = useMemo(() => ({
    search:  search       || undefined,
    status:  statusFilter || undefined,
    repId:   repFilter    || undefined,
  }), [search, statusFilter, repFilter])

  const handleFilterChange = useCallback((fn: () => void) => {
    fn()
    setDesktopPage(1)
    setMobilePage(1)
  }, [])

  const { data: reps = [] }  = useProfiles()
  const { data: stats }      = useSalesStats()

  // Desktop query
  const desktopParams = useMemo(() => ({ ...filterParams, page: desktopPage, pageSize: PAGE_SIZE }), [filterParams, desktopPage])
  const { data: desktopResult, isLoading: desktopLoading } = useSalesOrders(desktopParams)
  const desktopOrders = desktopResult?.data ?? []
  const totalPages    = desktopResult?.totalPages ?? 1
  const totalCount    = desktopResult?.count ?? 0

  // Mobile query
  const mobileParams  = useMemo(() => ({ ...filterParams, page: mobilePage,  pageSize: PAGE_SIZE }), [filterParams, mobilePage])
  const { data: mobileResult, isLoading: mobileLoading } = useSalesOrders(mobileParams)
  const mobileData    = mobileResult?.data ?? []
  const hasMoreMobile = mobileData.length === PAGE_SIZE

  const handleLoadMore = useCallback(() => {
    if (!mobileLoading && hasMoreMobile) setMobilePage(p => p + 1)
  }, [mobileLoading, hasMoreMobile])

  const { accumulated: mobileOrders, sentinelRef } = useMobileInfiniteList<SalesOrder>({
    data: mobileData, pageSize: PAGE_SIZE, loading: mobileLoading,
    resetKey: filterKey, hasMore: hasMoreMobile, onLoadMore: handleLoadMore,
  })

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
        subtitle={desktopLoading ? '...' : `${totalCount.toLocaleString('ar-EG')} طلب`}
        actions={can('sales.orders.create') ? (
          <Button icon={<Plus size={16} />} onClick={() => navigate('/sales/orders/new')}
            className="desktop-only-btn">
            طلب جديد
          </Button>
        ) : undefined}
      />

      {/* ── Stat Cards ──────────────────────────────── */}
      {stats && (
        <div className="stat-cards-grid">
          {[
            { label: 'إجمالي المبيعات', value: formatNumber(stats.totalSales) + ' ج.م', icon: <TrendingUp size={18} /> },
            { label: 'مسودة',  value: String(stats.statusCounts.draft      ?? 0), icon: <FileText size={18} /> },
            { label: 'مؤكد',   value: String(stats.statusCounts.confirmed  ?? 0), icon: <CheckCircle size={18} /> },
            { label: 'مُسلّم', value: String(stats.statusCounts.delivered  ?? 0), icon: <Truck size={18} /> },
          ].map((s, i) => (
            <div key={i} className="edara-card stat-card">
              <div className="stat-card-icon">{s.icon}</div>
              <div>
                <div className="stat-card-label">{s.label}</div>
                <div className="stat-card-value">{s.value}</div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* ── Filters ─────────────────────────────────── */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="sales-filter-row">
          <div style={{ flex: 2, minWidth: 180 }}>
            <SearchInput value={search}
              onChange={val => handleFilterChange(() => setSearch(val))}
              placeholder="بحث برقم الطلب أو اسم العميل..." />
          </div>
          <select className="form-select filter-select" value={statusFilter}
            onChange={e => handleFilterChange(() => setStatusFilter(e.target.value as any))}>
            <option value="">كل الحالات</option>
            <option value="draft">مسودة</option>
            <option value="confirmed">مؤكد</option>
            <option value="delivered">مُسلّم</option>
            <option value="completed">مكتمل</option>
            <option value="cancelled">ملغي</option>
          </select>
          <select className="form-select filter-select" value={repFilter}
            onChange={e => handleFilterChange(() => setRepFilter(e.target.value))}>
            <option value="">كل المناديب</option>
            {reps.map(r => <option key={r.id} value={r.id}>{r.full_name}</option>)}
          </select>
        </div>
      </div>

      {/* ══════════════ DESKTOP: Numbered Pagination ══════════════ */}
      <div className="sales-table-view edara-card" style={{ overflow: 'auto' }}>
        <DataTable<SalesOrder>
          columns={[
            {
              key: 'order_number', label: 'رقم الطلب',
              render: o => (
                <>
                  <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)', fontFamily: 'monospace' }} dir="ltr">{o.order_number}</div>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                    {new Date(o.order_date).toLocaleDateString('ar-EG-u-nu-latn')}
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
          data={desktopOrders}
          loading={desktopLoading}
          onRowClick={o => navigate(`/sales/orders/${o.id}`)}
          emptyIcon={<ShoppingCart size={48} />}
          emptyTitle="لا توجد أوامر بيع"
          emptyText="ابدأ بإنشاء أول أمر بيع للعملاء"
          emptyAction={can('sales.orders.create') ? (
            <Button icon={<Plus size={16} />} onClick={() => navigate('/sales/orders/new')}>طلب جديد</Button>
          ) : undefined}
          page={desktopPage}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setDesktopPage}
        />
      </div>

      {/* ══════════════ MOBILE: Infinite Scroll ══════════════════ */}
      <div className="sales-card-view">
        {mobileLoading && mobileOrders.length === 0 ? (
          <div className="mobile-card-list">
            {[1, 2, 3, 4].map(i => (
              <div key={i} className="edara-card" style={{ padding: 'var(--space-4)' }}>
                <div className="skeleton" style={{ height: 16, width: '55%', marginBottom: 8 }} />
                <div className="skeleton" style={{ height: 12, width: '35%', marginBottom: 12 }} />
                <div className="skeleton" style={{ height: 12, width: '80%' }} />
              </div>
            ))}
          </div>
        ) : mobileOrders.length === 0 ? (
          <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
            <ShoppingCart size={40} className="empty-state-icon" />
            <p className="empty-state-title">لا توجد أوامر بيع</p>
          </div>
        ) : (
          <div className="mobile-card-list">
            {mobileOrders.map(o => {
              const paidRatio = o.total_amount > 0 ? ((o.paid_amount + o.returned_amount) / o.total_amount) : 0
              return (
                <DataCard
                  key={o.id}
                  title={(o as any).customer?.name || '—'}
                  subtitle={
                    <span dir="ltr" style={{ fontFamily: 'monospace', fontSize: '0.7rem' }}>
                      {o.order_number}
                    </span>
                  }
                  badge={<Badge variant={statusVariants[o.status]}>{statusLabels[o.status]}</Badge>}
                  leading={
                    <div style={{
                      width: 40, height: 40, borderRadius: 'var(--radius-md)',
                      background: 'var(--bg-accent)', display: 'flex', alignItems: 'center', justifyContent: 'center',
                    }}>
                      <ShoppingCart size={18} style={{ color: 'var(--color-primary)' }} />
                    </div>
                  }
                  metadata={[
                    { label: 'التاريخ',  value: new Date(o.order_date).toLocaleDateString('ar-EG-u-nu-latn') },
                    { label: 'الإجمالي', value: `${formatNumber(o.total_amount)} ج.م`, highlight: true },
                    { label: 'المدفوع',  value: `${formatNumber(o.paid_amount)} ج.م` },
                    ...(o.payment_terms ? [{ label: 'الدفع', value: paymentLabels[o.payment_terms] || o.payment_terms }] : []),
                  ]}
                  actions={
                    <Button variant="secondary" size="sm" style={{ width: '100%', justifyContent: 'center' }}
                      onClick={() => navigate(`/sales/orders/${o.id}`)}>
                      <Eye size={14} /> عرض التفاصيل
                    </Button>
                  }
                  onClick={() => navigate(`/sales/orders/${o.id}`)}
                />
              )
            })}

            {/* Sentinel — يكتشفه الـ IntersectionObserver لتشغيل loadMore */}
            <div ref={sentinelRef} style={{ height: 8, flexShrink: 0 }} />

            {mobileLoading && mobileOrders.length > 0 && (
              <div className="infinite-loading">
                <Loader2 size={18} className="spin-icon" />
                <span>جاري تحميل المزيد...</span>
              </div>
            )}

            {!mobileLoading && !hasMoreMobile && mobileOrders.length > 0 && (
              <div className="infinite-end">
                <CheckCircle2 size={16} />
                <span>جميع الطلبات ({mobileOrders.length.toLocaleString('ar-EG')})</span>
              </div>
            )}
          </div>
        )}
      </div>

      <style>{`
        .stat-cards-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
          gap: var(--space-4);
          margin-bottom: var(--space-4);
        }
        .stat-card {
          padding: var(--space-4);
          display: flex;
          align-items: center;
          gap: var(--space-3);
        }
        .stat-card-icon {
          width: 40px; height: 40px;
          border-radius: var(--radius-lg);
          background: var(--bg-accent);
          display: flex; align-items: center; justify-content: center;
          color: var(--color-primary);
          flex-shrink: 0;
        }
        .stat-card-label { font-size: var(--text-xs); color: var(--text-muted); }
        .stat-card-value { font-size: var(--text-lg); font-weight: 700; font-variant-numeric: tabular-nums; }

        .sales-filter-row {
          display: flex; gap: var(--space-3); flex-wrap: wrap; align-items: flex-end;
        }
        .filter-select { min-width: 100px; flex: 1; }

        .sales-table-view { display: block; }
        .sales-card-view  { display: none; }

        @media (max-width: 768px) {
          .sales-table-view { display: none; }
          .sales-card-view  { display: block; }
          .desktop-only-btn { display: none; }
          .stat-cards-grid  { grid-template-columns: 1fr 1fr; }
          .filter-select { font-size: var(--text-xs); }
        }

        .mobile-card-list {
          display: flex; flex-direction: column; gap: var(--space-3); padding: 0 0 var(--space-4);
        }
        .infinite-loading {
          display: flex; align-items: center; justify-content: center;
          gap: var(--space-2); padding: var(--space-4);
          color: var(--text-muted); font-size: var(--text-sm);
        }
        .spin-icon { animation: spin 1s linear infinite; color: var(--color-primary); }
        @keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
        .infinite-end {
          display: flex; align-items: center; justify-content: center;
          gap: var(--space-2); padding: var(--space-3) var(--space-4);
          color: var(--color-success); font-size: var(--text-sm); font-weight: 600;
          background: var(--color-success-light); border-radius: var(--radius-lg);
          margin-top: var(--space-2);
        }
      `}</style>
    </div>
  )
}
