import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  AlertTriangle,
  CalendarClock,
  FileWarning,
  RefreshCw,
  Search,
  SlidersHorizontal,
  UserRound,
} from 'lucide-react'

import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import { DocumentActions } from '@/features/output/components/DocumentActions'
import {
  getOverdueSalesInvoices,
  type OverdueInvoiceSortBy,
  type OverdueSalesInvoiceRow,
} from '@/lib/services/credit'
import { supabase } from '@/lib/supabase/client'
import { formatCurrency, formatDate, formatNumber } from '@/lib/utils/format'

type FilterState = {
  search: string
  repId: string
  minDaysOverdue: string
  sortBy: OverdueInvoiceSortBy
}

const DEFAULT_FILTERS: FilterState = {
  search: '',
  repId: '',
  minDaysOverdue: '',
  sortBy: 'days_overdue_desc',
}

const PAGE_SIZE = 25

function filtersToParams(f: FilterState): Record<string, string> {
  const p: Record<string, string> = {}
  if (f.search) p.search = f.search
  if (f.repId) p.repId = f.repId
  if (f.minDaysOverdue) p.minDaysOverdue = f.minDaysOverdue
  if (f.sortBy !== DEFAULT_FILTERS.sortBy) p.sortBy = f.sortBy
  return p
}

export default function OverdueInvoicesPage() {
  const navigate = useNavigate()
  const qc = useQueryClient()
  const [filters, setFilters] = useState<FilterState>(DEFAULT_FILTERS)
  const [searchInput, setSearchInput] = useState('')
  const [page, setPage] = useState(1)
  const [paper, setPaper] = useState<'a4-landscape' | 'a4-portrait'>('a4-landscape')
  const searchTimer = useRef<ReturnType<typeof setTimeout>>()

  useEffect(() => {
    clearTimeout(searchTimer.current)
    searchTimer.current = setTimeout(() => {
      setFilters(prev => ({ ...prev, search: searchInput.trim() }))
      setPage(1)
    }, 350)
    return () => clearTimeout(searchTimer.current)
  }, [searchInput])

  const { data: reps } = useQuery({
    queryKey: ['profiles-for-overdue-invoices'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('profiles')
        .select('id, full_name')
        .eq('status', 'active')
        .order('full_name')
      if (error) throw error
      return data || []
    },
    staleTime: 10 * 60_000,
  })

  const { data: result, isLoading, isFetching } = useQuery({
    queryKey: ['overdue-sales-invoices', filters, page],
    queryFn: () => getOverdueSalesInvoices({
      search: filters.search || undefined,
      repId: filters.repId || undefined,
      minDaysOverdue: filters.minDaysOverdue ? Number(filters.minDaysOverdue) : undefined,
      sortBy: filters.sortBy,
      page,
      pageSize: PAGE_SIZE,
    }),
    staleTime: 90_000,
    placeholderData: prev => prev,
  })

  const rows = result?.data ?? []
  const hasFilters = Boolean(filters.search || filters.repId || filters.minDaysOverdue || filters.sortBy !== DEFAULT_FILTERS.sortBy)
  const printParams = useMemo(() => filtersToParams(filters), [filters])

  const setFilter = useCallback(<K extends keyof FilterState>(key: K, value: FilterState[K]) => {
    setFilters(prev => ({ ...prev, [key]: value }))
    setPage(1)
  }, [])

  const resetFilters = useCallback(() => {
    setSearchInput('')
    setFilters(DEFAULT_FILTERS)
    setPage(1)
  }, [])

  const columns = useMemo(() => [
    {
      key: 'order_number',
      label: 'الفاتورة',
      render: (row: OverdueSalesInvoiceRow) => (
        <div className="oi-primary-cell">
          <span className="oi-order-number">{row.order_number}</span>
          <span className="oi-muted">{translateTerms(row.payment_terms)}</span>
        </div>
      ),
    },
    {
      key: 'customer_name',
      label: 'العميل',
      render: (row: OverdueSalesInvoiceRow) => (
        <div className="oi-primary-cell">
          <span>{row.customer_name}</span>
          <span className="oi-muted">{row.customer_code || 'بدون كود'}</span>
        </div>
      ),
    },
    {
      key: 'assigned_rep_name',
      label: 'المندوب',
      hideOnMobile: true,
      render: (row: OverdueSalesInvoiceRow) => row.assigned_rep_name || row.order_rep_name || 'غير مسند',
    },
    {
      key: 'due_date',
      label: 'الاستحقاق',
      hideOnMobile: true,
      render: (row: OverdueSalesInvoiceRow) => (
        <div className="oi-primary-cell">
          <span>{formatDate(row.due_date)}</span>
          {row.last_due_date_changed_at && (
            <span className="badge badge-info">معدل</span>
          )}
        </div>
      ),
    },
    {
      key: 'days_overdue',
      label: 'أيام التأخير',
      align: 'center' as const,
      render: (row: OverdueSalesInvoiceRow) => (
        <span className={`oi-risk-pill oi-risk-${row.overdue_bucket}`}>
          {formatNumber(row.days_overdue)} يوم
        </span>
      ),
    },
    {
      key: 'net_remaining',
      label: 'الصافي المتبقي',
      align: 'end' as const,
      render: (row: OverdueSalesInvoiceRow) => (
        <strong className="oi-amount">{formatCurrency(row.net_remaining)} ج.م</strong>
      ),
    },
    {
      key: 'actions',
      label: '',
      align: 'end' as const,
      render: (row: OverdueSalesInvoiceRow) => (
        <button
          className="btn btn-sm btn-secondary"
          onClick={event => {
            event.stopPropagation()
            navigate(`/sales/orders/${row.id}`)
          }}
        >
          فتح
        </button>
      ),
    },
  ], [navigate])

  return (
    <div className="page-container overdue-invoices-page">
      <PageHeader
        title="الفواتير المتأخرة"
        subtitle="قائمة تشغيلية تعتمد على تاريخ الاستحقاق المعدل وصافي المبلغ غير المسدد"
        breadcrumbs={[
          { label: 'العملاء', path: '/customers' },
          { label: 'إدارة الائتمان', path: '/credit' },
          { label: 'الفواتير المتأخرة' },
        ]}
        actions={
          <div className="oi-header-actions">
            <select
              className="form-select oi-paper-select"
              value={paper}
              onChange={event => setPaper(event.target.value as typeof paper)}
              title="اختر مقاس الورقة للطباعة"
            >
              <option value="a4-landscape">A4 بالعرض</option>
              <option value="a4-portrait">A4 بالطول</option>
            </select>
            <DocumentActions
              kind="overdue-invoices-report"
              entityId="all"
              paperProfileId={paper}
              params={printParams}
              compact
            />
            <button
              className="btn btn-secondary"
              onClick={() => qc.invalidateQueries({ queryKey: ['overdue-sales-invoices'] })}
              disabled={isFetching}
            >
              <RefreshCw size={16} />
              تحديث
            </button>
          </div>
        }
      />

      <section className="oi-kpis" aria-label="مؤشرات الفواتير المتأخرة">
        <MetricCard
          label="عدد الفواتير"
          value={formatNumber(result?.count ?? 0)}
          icon={<FileWarning size={18} />}
          tone="danger"
        />
        <MetricCard
          label="الصافي المتأخر"
          value={`${formatCurrency(result?.totalOverdueAmount ?? 0)} ج.م`}
          icon={<AlertTriangle size={18} />}
          tone="warning"
        />
        <MetricCard
          label="العملاء المتأثرون"
          value={formatNumber(result?.overdueCustomersCount ?? 0)}
          icon={<UserRound size={18} />}
          tone="info"
        />
        <MetricCard
          label="أكبر تأخير"
          value={`${formatNumber(result?.maxDaysOverdue ?? 0)} يوم`}
          icon={<CalendarClock size={18} />}
          tone="neutral"
        />
      </section>

      <section className="edara-card oi-filters" aria-label="فلاتر الفواتير المتأخرة">
        <div className="search-input-wrapper oi-search">
          <Search className="search-icon" size={16} />
          <input
            className="form-input search-input"
            value={searchInput}
            onChange={event => setSearchInput(event.target.value)}
            placeholder="ابحث برقم الفاتورة أو العميل أو الكود"
          />
        </div>

        <select
          className="form-select"
          value={filters.repId}
          onChange={event => setFilter('repId', event.target.value)}
        >
          <option value="">كل المندوبين</option>
          {(reps ?? []).map((rep: any) => (
            <option key={rep.id} value={rep.id}>{rep.full_name}</option>
          ))}
        </select>

        <select
          className="form-select"
          value={filters.minDaysOverdue}
          onChange={event => setFilter('minDaysOverdue', event.target.value)}
        >
          <option value="">كل مدد التأخير</option>
          <option value="7">7 أيام فأكثر</option>
          <option value="30">30 يوم فأكثر</option>
          <option value="60">60 يوم فأكثر</option>
        </select>

        <select
          className="form-select"
          value={filters.sortBy}
          onChange={event => setFilter('sortBy', event.target.value as OverdueInvoiceSortBy)}
        >
          <option value="days_overdue_desc">الأكثر تأخيرا</option>
          <option value="due_date_asc">الأقدم استحقاقا</option>
          <option value="remaining_desc">الأعلى مبلغا</option>
          <option value="customer_name">اسم العميل</option>
        </select>

        <button className="btn btn-ghost oi-reset" onClick={resetFilters} disabled={!hasFilters}>
          <SlidersHorizontal size={16} />
          مسح
        </button>
      </section>

      <section className="edara-card oi-table-card">
        <DataTable
          columns={columns}
          data={rows}
          loading={isLoading}
          onRowClick={row => navigate(`/sales/orders/${row.id}`)}
          emptyIcon={<FileWarning size={42} />}
          emptyTitle="لا توجد فواتير متأخرة"
          emptyText={hasFilters ? 'لا توجد نتائج مطابقة للفلاتر الحالية.' : 'كل الفواتير الآجلة المفتوحة داخل تاريخ الاستحقاق أو مسددة.'}
          page={result?.page}
          totalPages={result?.totalPages}
          totalCount={result?.count}
          onPageChange={setPage}
          rowClassName={row => `oi-row oi-row-${row.overdue_bucket}`}
          dataCardMapping={row => ({
            title: row.order_number,
            subtitle: `${row.customer_name}${row.customer_code ? ` · ${row.customer_code}` : ''}`,
            badge: <span className={`oi-risk-pill oi-risk-${row.overdue_bucket}`}>{formatNumber(row.days_overdue)} يوم</span>,
            onClick: () => navigate(`/sales/orders/${row.id}`),
            metadata: [
              { label: 'المتبقي', value: `${formatCurrency(row.net_remaining)} ج.م`, highlight: true },
              { label: 'الاستحقاق', value: formatDate(row.due_date) },
              { label: 'المندوب', value: row.assigned_rep_name || row.order_rep_name || 'غير مسند' },
              { label: 'المدة', value: row.credit_days_effective != null ? `${formatNumber(row.credit_days_effective)} يوم` : 'غير محدد' },
            ],
            actions: row.last_due_date_changed_at
              ? <span className="badge badge-info">استحقاق معدل</span>
              : undefined,
          })}
        />
      </section>

      <style>{`
        .overdue-invoices-page {
          display: flex;
          flex-direction: column;
          gap: var(--space-4);
        }

        .oi-kpis {
          display: grid;
          grid-template-columns: repeat(4, minmax(0, 1fr));
          gap: var(--space-3);
        }

        .oi-header-actions {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          flex-wrap: wrap;
        }

        .oi-paper-select {
          width: auto;
          min-width: 130px;
          min-height: 36px;
        }

        .oi-metric {
          min-height: 96px;
          padding: var(--space-4);
          display: flex;
          align-items: center;
          gap: var(--space-3);
          background: var(--bg-surface);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-md);
          box-shadow: var(--shadow-sm);
        }

        .oi-metric-icon {
          width: 38px;
          height: 38px;
          border-radius: var(--radius-md);
          display: inline-flex;
          align-items: center;
          justify-content: center;
          flex-shrink: 0;
        }

        .oi-tone-danger .oi-metric-icon { color: var(--color-danger); background: var(--color-danger-light); }
        .oi-tone-warning .oi-metric-icon { color: var(--color-warning); background: var(--color-warning-light); }
        .oi-tone-info .oi-metric-icon { color: var(--color-info); background: var(--color-info-light); }
        .oi-tone-neutral .oi-metric-icon { color: var(--text-secondary); background: var(--bg-surface-2); }

        .oi-metric-label {
          font-size: var(--text-xs);
          color: var(--text-muted);
          font-weight: 600;
        }

        .oi-metric-value {
          margin-top: 2px;
          font-size: var(--text-xl);
          line-height: 1.3;
          color: var(--text-primary);
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }

        .oi-filters {
          padding: var(--space-4);
          display: grid;
          grid-template-columns: minmax(260px, 1.5fr) minmax(160px, 0.75fr) minmax(150px, 0.7fr) minmax(160px, 0.75fr) auto;
          gap: var(--space-3);
          align-items: center;
        }

        .oi-search {
          min-width: 0;
        }

        .oi-reset {
          min-height: 42px;
        }

        .oi-table-card {
          overflow: hidden;
        }

        .oi-primary-cell {
          display: flex;
          flex-direction: column;
          gap: 2px;
          min-width: 0;
        }

        .oi-order-number {
          font-weight: 700;
          color: var(--text-primary);
        }

        .oi-muted {
          font-size: var(--text-xs);
          color: var(--text-muted);
        }

        .oi-amount {
          color: var(--color-danger);
          font-variant-numeric: tabular-nums;
          white-space: nowrap;
        }

        .oi-risk-pill {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          min-width: 74px;
          padding: 0.2rem 0.55rem;
          border-radius: var(--radius-full);
          font-size: var(--text-xs);
          font-weight: 700;
          white-space: nowrap;
          font-variant-numeric: tabular-nums;
        }

        .oi-risk-new {
          color: var(--color-warning);
          background: var(--color-warning-light);
        }

        .oi-risk-medium {
          color: #b45309;
          background: rgba(180, 83, 9, 0.12);
        }

        .oi-risk-high {
          color: var(--color-danger);
          background: var(--color-danger-light);
        }

        .oi-risk-critical {
          color: #fff;
          background: var(--color-danger);
        }

        .oi-row-high td,
        .oi-row-critical td {
          background-image: linear-gradient(to left, rgba(220, 38, 38, 0.04), transparent 36%);
        }

        @media (max-width: 1100px) {
          .oi-kpis {
            grid-template-columns: repeat(2, minmax(0, 1fr));
          }

          .oi-filters {
            grid-template-columns: 1fr 1fr;
          }

          .oi-reset {
            grid-column: span 2;
          }
        }

        @media (max-width: 768px) {
          .oi-kpis {
            grid-template-columns: 1fr 1fr;
            gap: var(--space-2);
          }

          .oi-metric {
            min-height: 86px;
            padding: var(--space-3);
          }

          .oi-metric-value {
            font-size: var(--text-base);
          }

          .oi-filters {
            grid-template-columns: 1fr;
          }

          .oi-reset {
            grid-column: auto;
          }
        }
      `}</style>
    </div>
  )
}

function MetricCard({
  label,
  value,
  icon,
  tone,
}: {
  label: string
  value: string
  icon: ReactNode
  tone: 'danger' | 'warning' | 'info' | 'neutral'
}) {
  return (
    <div className={`oi-metric oi-tone-${tone}`}>
      <div className="oi-metric-icon">{icon}</div>
      <div>
        <div className="oi-metric-label">{label}</div>
        <div className="oi-metric-value">{value}</div>
      </div>
    </div>
  )
}

function translateTerms(terms: string) {
  const map: Record<string, string> = {
    cash: 'نقدي',
    credit: 'آجل',
    mixed: 'مختلط',
  }
  return map[terms] || terms
}
