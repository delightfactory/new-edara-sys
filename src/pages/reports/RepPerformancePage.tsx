import { useState } from 'react'
import { useSystemTrustState, useTrustForComponent, type TrustStatus } from '@/hooks/useSystemTrustState'
import { useRepPerformanceSummary, useRepPerformanceTable, type RepPerformanceRow } from '@/hooks/useRepPerformance'
import MetricCard from '@/components/reports/MetricCard'
import SkeletonCard from '@/components/reports/SkeletonCard'
import SystemHealthBar from '@/components/reports/SystemHealthBar'
import ReportFilterBar, { type DateRange } from '@/components/reports/ReportFilterBar'
import TrustStateBadge from '@/components/reports/TrustStateBadge'
import FreshnessIndicator from '@/components/reports/FreshnessIndicator'
import MetricGrid from '@/components/patterns/MetricGrid'
import ChartPanel from '@/components/patterns/ChartPanel'
import ChartTooltip from '@/components/patterns/ChartTooltip'
import ResponsiveCollection from '@/components/patterns/ResponsiveCollection'
import Card from '@/components/patterns/Card'
import KeyValueList from '@/components/patterns/KeyValueList'
import StatePanel from '@/components/patterns/StatePanel'
import { ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Tooltip, CartesianGrid } from 'recharts'
import { TrendingUp, TrendingDown, Users2, Award } from 'lucide-react'

function toISO(d: Date) { return d.toISOString().split('T')[0] }
const today = new Date()
const monthStart = new Date(today.getFullYear(), today.getMonth(), 1)
const monthEnd   = new Date(today.getFullYear(), today.getMonth() + 1, 0)
const FMT = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 })
const fmt    = (n: number | undefined | null) => n != null ? FMT.format(n) : '—'
const fmtCur = (n: number | undefined | null) => n != null ? fmt(n) + ' ج.م' : '—'
const fmtPct = (n: number | undefined | null) => n != null ? FMT.format(n) + '%' : '—'

export function CustomTooltip({ active, payload, label }: any) {
  if (!active || !payload?.length) return null
  return (
    <ChartTooltip
      label={label}
      items={payload.map((p: any) => ({
        key: p.name,
        label: p.name,
        value: `${fmt(p.value)} ج.م`,
        color: p.color,
        valueDirection: 'ltr' as const,
      }))}
    />
  )
}

function RepPerformanceDetailCards({ items, device }: { items: RepPerformanceRow[]; device: 'mobile' | 'tablet' }) {
  return (
    <div className={`ds-responsive-card-grid ds-responsive-card-grid--${device}`}>
      {items.map((row, idx) => {
        const isFirst = idx === 0
        const isLast = idx === items.length - 1
        const rowColor = isFirst ? 'var(--color-success)' : isLast ? 'var(--color-danger)' : 'var(--text-primary)'
        const returnsColor = row.returns_value > 0 ? 'var(--color-danger)' : 'var(--text-muted)'
        const returnRateColor = row.return_rate_pct > 10
          ? 'var(--color-danger)'
          : row.return_rate_pct > 5
            ? 'var(--color-warning)'
            : 'var(--color-success)'

        return (
          <Card key={row.rep_id} padding="md">
            <div style={{ marginBlockEnd: 'var(--space-4)', minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 'var(--space-2)', flexWrap: 'wrap', minWidth: 0 }}>
                <div style={{ color: rowColor, fontWeight: isFirst ? 700 : 600, overflowWrap: 'anywhere', minWidth: 0 }}>
                  {row.rep_name}
                </div>
                <span dir="ltr" style={{ color: rowColor, fontWeight: isFirst ? 700 : 600, fontSize: 'var(--text-xs)' }}>
                  #{row.rank}
                </span>
              </div>
              <div style={{ color: 'var(--text-secondary)', fontSize: 'var(--text-xs)', marginBlockStart: 'var(--space-1)', overflowWrap: 'anywhere', minWidth: 0 }}>
                {row.branch_name}
              </div>
            </div>
            <KeyValueList
              columns={device === 'tablet' ? 2 : 1}
              compact
              items={[
                { key: 'revenue', label: 'صافى الإيراد', value: <span dir="ltr">{fmt(row.net_revenue)} ج.م</span> },
                { key: 'returns', label: 'المرتجعات', value: <span dir="ltr" style={{ color: returnsColor }}>{fmt(row.returns_value)} ج.م</span> },
                { key: 'return-rate', label: 'نسبة المرتجع', value: <span dir="ltr" style={{ color: returnRateColor, fontWeight: 600 }}>{fmtPct(row.return_rate_pct)}</span> },
                { key: 'customers', label: 'عملاء', value: <span dir="ltr">{row.distinct_customers}</span> },
              ]}
            />
          </Card>
        )
      })}
    </div>
  )
}

export default function RepPerformancePage() {
  const [range, setRange] = useState<DateRange>({ from: toISO(monthStart), to: toISO(monthEnd) })
  const filters = { dateFrom: range.from, dateTo: range.to }

  const { data: trustRows, isLoading: trustLoading, error: trustError } = useSystemTrustState('sales')
  const { data: summary, isLoading: summaryLoading } = useRepPerformanceSummary(filters)
  const { data: rows = [], isLoading: tableLoading } = useRepPerformanceTable(filters)

  const salesTrust = useTrustForComponent(trustRows, 'fact_sales_daily_grain')
  const isLoading  = summaryLoading || tableLoading

  const chartData = rows.slice(0, 15).map(r => ({
    name:    r.rep_name,
    revenue: r.net_revenue,
    returns: r.returns_value,
  }))

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-6)' }}>

      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', flexWrap: 'wrap', gap: 'var(--space-3)' }}>
        <div>
          <h1 style={{ fontSize: 'var(--text-2xl)', fontWeight: 800, color: 'var(--text-primary)', margin: 0 }}>أداء المندوبين</h1>
          <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', margin: '4px 0 0' }}>
            إيراد — مرتجعات — عملاء — ترتيب بالأداء
          </p>
        </div>
        <ReportFilterBar value={range} onChange={setRange} />
      </div>

      <SystemHealthBar trustRows={trustRows} isLoading={trustLoading} error={trustError} />

      <MetricGrid columns={4}>
        {isLoading ? [1,2,3,4].map(i => <SkeletonCard key={i} height={160} />) : (
          <>
            <MetricCard label="إجمالى الإيراد الصافى" subtitle="جميع المندوبين مجمّعاً"
              value={fmtCur(summary?.total_revenue)}
              status={salesTrust?.status ?? null}
              lastCompletedAt={salesTrust?.last_completed_at} isStale={salesTrust?.is_stale}
              domain="sales" icon={<TrendingUp size={16} />} />
            <MetricCard label="مندوبون نشطون" subtitle="لديهم مبيعات فى الفترة"
              value={summary?.total_reps ?? null}
              status={salesTrust?.status ?? null}
              lastCompletedAt={salesTrust?.last_completed_at} isStale={salesTrust?.is_stale}
              domain="sales" icon={<Users2 size={16} />} />
            <MetricCard label="متوسط إيراد المندوب" subtitle="الإيراد الصافى / عدد المندوبين"
              value={fmtCur(summary?.avg_revenue_per_rep)}
              status={salesTrust?.status ?? null}
              lastCompletedAt={salesTrust?.last_completed_at} isStale={salesTrust?.is_stale}
              domain="sales" icon={<Award size={16} />} />
            <MetricCard label="إجمالى المرتجعات" subtitle="قيمة المرتجعات لجميع المندوبين"
              value={fmtCur(summary?.total_returns_value)}
              status={salesTrust?.status ?? null}
              lastCompletedAt={salesTrust?.last_completed_at} isStale={salesTrust?.is_stale}
              domain="sales" icon={<TrendingDown size={16} />} />
          </>
        )}
      </MetricGrid>

      {/* Horizontal Bar Chart */}
      <ChartPanel
        title="مقارنة المندوبين — أعلى 15"
        description="صافى الإيراد مقابل المرتجعات"
        action={(
          <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', flexWrap: 'wrap' }}>
            {salesTrust && <TrustStateBadge status={salesTrust.status as TrustStatus} domain="sales" size="sm" />}
            {salesTrust && <FreshnessIndicator lastCompletedAt={salesTrust.last_completed_at} isStale={salesTrust.is_stale} />}
          </div>
        )}
      >
        {tableLoading ? <SkeletonCard height={300} /> : chartData.length === 0 ? (
          <div style={{ height: 300, display: 'grid', alignItems: 'center' }}>
            <StatePanel kind="empty" title="لا توجد بيانات فى النطاق الزمني المحدد" compact />
          </div>
        ) : (
          <ResponsiveContainer width="100%" height={Math.max(chartData.length * 40, 200)}>
            <BarChart data={chartData} layout="vertical" margin={{ top: 4, left: 10, right: 20, bottom: 0 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border-primary)" horizontal={false} />
              <XAxis type="number" tickFormatter={v => fmt(v)} tick={{ fontSize: 10, fill: 'var(--text-muted)', fontFamily: 'var(--font-sans)' }} tickLine={false} axisLine={false} />
              <YAxis type="category" dataKey="name" width={120} tick={{ fontSize: 11, fill: 'var(--text-primary)', fontFamily: 'var(--font-sans)' }} tickLine={false} axisLine={false} />
              <Tooltip content={<CustomTooltip />} />
              <Bar dataKey="revenue" name="الإيراد الصافى" fill="#2563eb" radius={[0, 3, 3, 0]} maxBarSize={20} />
              <Bar dataKey="returns" name="المرتجعات"      fill="#dc2626" radius={[0, 3, 3, 0]} maxBarSize={10} />
            </BarChart>
          </ResponsiveContainer>
        )}
      </ChartPanel>

      {/* Table */}
      <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-primary)', borderRadius: 'var(--radius-lg)', overflow: 'hidden', boxShadow: 'var(--shadow-sm)' }}>
        <div style={{ padding: 'var(--space-4) var(--space-5)', borderBottom: '1px solid var(--border-primary)', fontWeight: 700, fontSize: 'var(--text-base)', color: 'var(--text-primary)' }}>
          تفصيل الأداء — جميع المندوبين
        </div>
        <ResponsiveCollection<RepPerformanceRow>
          items={rows}
          loading={tableLoading}
          loadingState={(
            <div style={{ padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
              {[1,2,3,4,5].map(i => <SkeletonCard key={i} height={44} />)}
            </div>
          )}
          emptyState={<StatePanel kind="empty" title="لا توجد بيانات فى النطاق الزمني المحدد" />}
          renderDesktop={desktopRows => (
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 'var(--text-sm)' }}>
                <thead>
                  <tr style={{ background: 'var(--bg-surface-2)' }}>
                    {['#', 'المندوب', 'الفرع', 'صافى الإيراد', 'المرتجعات', 'نسبة المرتجع', 'عملاء'].map(h => (
                      <th scope="col" key={h} style={{ padding: '10px 14px', textAlign: 'right', fontWeight: 600, color: 'var(--text-secondary)', fontSize: 'var(--text-xs)', borderBottom: '1px solid var(--border-primary)', whiteSpace: 'nowrap' }}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {desktopRows.map((row: RepPerformanceRow, idx) => {
                    const isFirst = idx === 0
                    const isLast  = idx === desktopRows.length - 1
                    const rowColor = isFirst ? 'var(--color-success)' : isLast ? 'var(--color-danger)' : 'var(--text-primary)'
                    return (
                      <tr key={row.rep_id}
                        style={{ borderBottom: '1px solid var(--divider)', transition: 'background 0.1s' }}
                        onMouseEnter={e => (e.currentTarget.style.background = 'var(--bg-hover)')}
                        onMouseLeave={e => (e.currentTarget.style.background = '')}>
                        <td style={{ padding: '10px 14px', color: rowColor, fontWeight: isFirst ? 700 : 400, fontSize: 'var(--text-xs)', direction: 'ltr', textAlign: 'center' }}>{row.rank}</td>
                        <td style={{ padding: '10px 14px', color: rowColor, fontWeight: isFirst ? 700 : 600, fontSize: 'var(--text-xs)' }}>{row.rep_name}</td>
                        <td style={{ padding: '10px 14px', color: 'var(--text-secondary)', fontSize: 'var(--text-xs)' }}>{row.branch_name}</td>
                        <td style={{ padding: '10px 14px', color: rowColor, fontWeight: 600, direction: 'ltr', textAlign: 'right', fontSize: 'var(--text-xs)' }}>{fmt(row.net_revenue)} ج.م</td>
                        <td style={{ padding: '10px 14px', color: row.returns_value > 0 ? 'var(--color-danger)' : 'var(--text-muted)', direction: 'ltr', textAlign: 'right', fontSize: 'var(--text-xs)' }}>{fmt(row.returns_value)} ج.م</td>
                        <td style={{ padding: '10px 14px', color: row.return_rate_pct > 10 ? 'var(--color-danger)' : row.return_rate_pct > 5 ? 'var(--color-warning)' : 'var(--color-success)', fontWeight: 600, direction: 'ltr', textAlign: 'right', fontSize: 'var(--text-xs)' }}>{fmtPct(row.return_rate_pct)}</td>
                        <td style={{ padding: '10px 14px', color: 'var(--text-primary)', direction: 'ltr', textAlign: 'right', fontSize: 'var(--text-xs)' }}>{row.distinct_customers}</td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
          renderTablet={tabletRows => <RepPerformanceDetailCards items={tabletRows} device="tablet" />}
          renderMobile={mobileRows => <RepPerformanceDetailCards items={mobileRows} device="mobile" />}
        />
      </div>
    </div>
  )
}