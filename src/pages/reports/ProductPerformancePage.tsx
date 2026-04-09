import { useState, useEffect } from 'react'
import { useSystemTrustState, useTrustForComponent, type TrustStatus } from '@/hooks/useSystemTrustState'
import { useProductPerformanceSummary, useProductPerformanceTable, type ProductPerformanceRow } from '@/hooks/useProductPerformance'
import MetricCard from '@/components/reports/MetricCard'
import SkeletonCard from '@/components/reports/SkeletonCard'
import SystemHealthBar from '@/components/reports/SystemHealthBar'
import ReportFilterBar, { type DateRange } from '@/components/reports/ReportFilterBar'
import TrustStateBadge from '@/components/reports/TrustStateBadge'
import FreshnessIndicator from '@/components/reports/FreshnessIndicator'
import { ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Tooltip, CartesianGrid } from 'recharts'
import { TrendingUp, TrendingDown, Package, BarChart3 } from 'lucide-react'
import { supabase } from '@/lib/supabase/client'

function toISO(d: Date) { return d.toISOString().split('T')[0] }
const today = new Date()
const monthStart = new Date(today.getFullYear(), today.getMonth(), 1)
const monthEnd = new Date(today.getFullYear(), today.getMonth() + 1, 0)
const FMT = new Intl.NumberFormat('ar-EG', { maximumFractionDigits: 0 })
const fmt = (n: number | undefined | null) => n != null ? FMT.format(n) : '—'
const fmtCur = (n: number | undefined | null) => n != null ? fmt(n) + ' ج.م' : '—'
const fmtPct = (n: number | undefined | null) => n != null ? FMT.format(n) + '%' : '—'

function CustomTooltip({ active, payload, label }: any) {
  if (!active || !payload?.length) return null
  return (
    <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-primary)', borderRadius: 'var(--radius-md)', padding: '10px 14px', fontSize: '12px', boxShadow: 'var(--shadow-md)', direction: 'rtl' }}>
      <div style={{ fontWeight: 700, color: 'var(--text-primary)', marginBottom: '6px' }}>{label}</div>
      {payload.map((p: any) => (
        <div key={p.name} style={{ color: p.color, display: 'flex', justifyContent: 'space-between', gap: '16px' }}>
          <span>{p.name}</span>
          <span style={{ fontWeight: 600, direction: 'ltr' }}>{fmt(p.value)} ج.م</span>
        </div>
      ))}
    </div>
  )
}

export default function ProductPerformancePage() {
  const [range, setRange] = useState<DateRange>({ from: toISO(monthStart), to: toISO(monthEnd) })
  const [categoryId, setCategoryId] = useState<string | undefined>(undefined)
  const [categories, setCategories] = useState<{ id: string; name: string }[]>([])
  const filters = { dateFrom: range.from, dateTo: range.to, categoryId }

  useEffect(() => {
    supabase.rpc('analytics_product_categories')
      .then(({ data, error }) => {
        if (!error && data) setCategories(data as { id: string; name: string }[])
      })
  }, [])

  const { data: trustRows, isLoading: trustLoading, error: trustError } = useSystemTrustState('sales')
  const { data: summary, isLoading: summaryLoading } = useProductPerformanceSummary(filters)
  const { data: rows = [], isLoading: tableLoading } = useProductPerformanceTable(filters)

  const salesTrust = useTrustForComponent(trustRows, 'fact_sales_daily_grain')
  const isLoading = summaryLoading || tableLoading

  const avgReturnRate = rows.length > 0
    ? rows.reduce((s, r) => s + r.return_rate_pct, 0) / rows.length
    : null

  const chartData = rows.slice(0, 15).map(r => ({
    name: r.product_name.length > 20 ? r.product_name.slice(0, 20) + '…' : r.product_name,
    revenue: r.net_revenue,
  }))

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-6)' }}>

      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', flexWrap: 'wrap', gap: 'var(--space-3)' }}>
        <div>
          <h1 style={{ fontSize: 'var(--text-2xl)', fontWeight: 800, color: 'var(--text-primary)', margin: 0 }}>أداء المنتجات</h1>
          <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', margin: '4px 0 0' }}>
            إيراد — كميات — نسبة المرتجع — حصة السوق
          </p>
        </div>
        <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', flexWrap: 'wrap' }}>
          <select
            value={categoryId ?? ''}
            onChange={e => setCategoryId(e.target.value || undefined)}
            style={{ padding: '5px 8px', borderRadius: 'var(--radius-sm)', border: '1px solid var(--border-primary)', background: 'var(--bg-input)', color: 'var(--text-primary)', fontSize: 'var(--text-xs)', fontFamily: 'var(--font-sans)', outline: 'none' }}>
            <option value="">كل التصنيفات</option>
            {categories.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
          <ReportFilterBar value={range} onChange={setRange} />
        </div>
      </div>

      <SystemHealthBar trustRows={trustRows} isLoading={trustLoading} error={trustError} />

      <div className="report-grid">
        {isLoading ? [1, 2, 3, 4].map(i => <SkeletonCard key={i} height={160} />) : (
          <>
            <MetricCard label="إجمالى الإيراد" subtitle="صافى — مرتجعات مستبعدة"
              value={fmtCur(summary?.total_revenue)}
              status={salesTrust?.status ?? null}
              lastCompletedAt={salesTrust?.last_completed_at} isStale={salesTrust?.is_stale}
              domain="sales" icon={<TrendingUp size={16} />} />
            <MetricCard label="منتجات نشطة" subtitle="لديها مبيعات فى الفترة"
              value={summary?.total_products ?? null}
              status={salesTrust?.status ?? null}
              lastCompletedAt={salesTrust?.last_completed_at} isStale={salesTrust?.is_stale}
              domain="sales" icon={<Package size={16} />} />
            <MetricCard label="أعلى منتج" subtitle="إيراد المنتج الأول"
              value={fmtCur(summary?.top_product_revenue)}
              status={salesTrust?.status ?? null}
              lastCompletedAt={salesTrust?.last_completed_at} isStale={salesTrust?.is_stale}
              domain="sales" icon={<BarChart3 size={16} />} />
            <MetricCard label="متوسط نسبة المرتجع" subtitle="متوسط لكل المنتجات"
              value={avgReturnRate != null ? fmtPct(avgReturnRate) : null}
              status={salesTrust?.status ?? null}
              lastCompletedAt={salesTrust?.last_completed_at} isStale={salesTrust?.is_stale}
              domain="sales" icon={<TrendingDown size={16} />} />
          </>
        )}
      </div>

      {/* Chart */}
      <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-primary)', borderRadius: 'var(--radius-lg)', padding: 'var(--space-5)', boxShadow: 'var(--shadow-sm)' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--space-4)', flexWrap: 'wrap', gap: 'var(--space-2)' }}>
          <div>
            <div style={{ fontWeight: 700, fontSize: 'var(--text-base)', color: 'var(--text-primary)' }}>أعلى 15 منتجاً بالإيراد</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: '2px' }}>مرتب تنازلياً حسب صافى الإيراد</div>
          </div>
          <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center' }}>
            {salesTrust && <TrustStateBadge status={salesTrust.status as TrustStatus} domain="sales" size="sm" />}
            {salesTrust && <FreshnessIndicator lastCompletedAt={salesTrust.last_completed_at} isStale={salesTrust.is_stale} />}
          </div>
        </div>
        {tableLoading ? <SkeletonCard height={240} /> : chartData.length === 0 ? (
          <div style={{ height: 240, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-muted)', fontSize: 'var(--text-sm)' }}>لا توجد بيانات</div>
        ) : (
          <ResponsiveContainer width="100%" height={240}>
            <BarChart data={chartData} margin={{ top: 4, left: -10, right: 4, bottom: 60 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border-primary)" vertical={false} />
              <XAxis dataKey="name" tick={{ fontSize: 10, fill: 'var(--text-muted)', fontFamily: 'var(--font-sans)' }} tickLine={false} axisLine={false} angle={-30} textAnchor="end" interval={0} />
              <YAxis tickFormatter={v => fmt(v)} tick={{ fontSize: 10, fill: 'var(--text-muted)', fontFamily: 'var(--font-sans)' }} tickLine={false} axisLine={false} />
              <Tooltip content={<CustomTooltip />} />
              <Bar dataKey="revenue" name="الإيراد" fill="#2563eb" radius={[3, 3, 0, 0]} maxBarSize={32} />
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* Table */}
      <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-primary)', borderRadius: 'var(--radius-lg)', overflow: 'hidden', boxShadow: 'var(--shadow-sm)' }}>
        <div style={{ padding: 'var(--space-4) var(--space-5)', borderBottom: '1px solid var(--border-primary)', fontWeight: 700, fontSize: 'var(--text-base)', color: 'var(--text-primary)' }}>
          تفاصيل المنتجات — أعلى 50 حسب الإيراد
        </div>
        {tableLoading ? (
          <div style={{ padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
            {[1, 2, 3, 4, 5].map(i => <SkeletonCard key={i} height={44} />)}
          </div>
        ) : rows.length === 0 ? (
          <div style={{ padding: 'var(--space-8)', textAlign: 'center', color: 'var(--text-muted)', fontSize: 'var(--text-sm)' }}>لا توجد بيانات</div>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 'var(--text-sm)' }}>
              <thead>
                <tr style={{ background: 'var(--bg-surface-2)' }}>
                  {['المنتج', 'التصنيف', 'الإيراد', 'الكمية', 'نسبة المرتجع', 'عملاء', 'الحصة%'].map(h => (
                    <th key={h} style={{ padding: '10px 14px', textAlign: 'right', fontWeight: 600, color: 'var(--text-secondary)', fontSize: 'var(--text-xs)', borderBottom: '1px solid var(--border-primary)', whiteSpace: 'nowrap' }}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map((row: ProductPerformanceRow) => (
                  <tr key={row.product_id}
                    style={{ borderBottom: '1px solid var(--divider)', transition: 'background 0.1s' }}
                    onMouseEnter={e => (e.currentTarget.style.background = 'var(--bg-hover)')}
                    onMouseLeave={e => (e.currentTarget.style.background = '')}>
                    <td style={{ padding: '10px 14px', color: 'var(--text-primary)', fontWeight: 600, fontSize: 'var(--text-xs)' }}>{row.product_name}</td>
                    <td style={{ padding: '10px 14px', color: 'var(--text-secondary)', fontSize: 'var(--text-xs)' }}>{row.category_name}</td>
                    <td style={{ padding: '10px 14px', color: 'var(--text-primary)', direction: 'ltr', textAlign: 'right', fontSize: 'var(--text-xs)' }}>{fmt(row.net_revenue)} ج.م</td>
                    <td style={{ padding: '10px 14px', color: 'var(--text-primary)', direction: 'ltr', textAlign: 'right', fontSize: 'var(--text-xs)' }}>{fmt(row.net_qty)}</td>
                    <td style={{ padding: '10px 14px', color: row.return_rate_pct > 10 ? 'var(--color-danger)' : row.return_rate_pct > 5 ? 'var(--color-warning)' : 'var(--color-success)', fontWeight: 600, direction: 'ltr', textAlign: 'right', fontSize: 'var(--text-xs)' }}>{fmtPct(row.return_rate_pct)}</td>
                    <td style={{ padding: '10px 14px', color: 'var(--text-primary)', direction: 'ltr', textAlign: 'right', fontSize: 'var(--text-xs)' }}>{row.distinct_customers}</td>
                    <td style={{ padding: '10px 14px', color: 'var(--text-secondary)', direction: 'ltr', textAlign: 'right', fontSize: 'var(--text-xs)' }}>{fmtPct(row.revenue_share_pct)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}
