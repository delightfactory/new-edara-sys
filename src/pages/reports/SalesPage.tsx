import { useState } from 'react'
import { useSystemTrustState, useTrustForComponent } from '@/hooks/useSystemTrustState'
import { useSalesDailyTotals, useSalesSummary } from '@/hooks/useSalesGrain'
import MetricCard from '@/components/reports/MetricCard'
import SkeletonCard from '@/components/reports/SkeletonCard'
import SystemHealthBar from '@/components/reports/SystemHealthBar'
import ReportFilterBar, { type DateRange } from '@/components/reports/ReportFilterBar'
import TrustStateBadge from '@/components/reports/TrustStateBadge'
import FreshnessIndicator from '@/components/reports/FreshnessIndicator'
import { ResponsiveContainer, AreaChart, Area, XAxis, YAxis, Tooltip, CartesianGrid, BarChart, Bar } from 'recharts'
import { TrendingUp, TrendingDown, ShoppingBag } from 'lucide-react'

function toISO(d: Date) { return d.toISOString().split('T')[0] }
const today = new Date()
const monthStart = new Date(today.getFullYear(), today.getMonth(), 1)
const monthEnd = new Date(today.getFullYear(), today.getMonth() + 1, 0)
const FMT = new Intl.NumberFormat('ar-EG', { maximumFractionDigits: 0 })
const fmt = (n: number | undefined | null) => n != null ? FMT.format(n) : '—'
const fmtCur = (n: number | undefined | null) => n != null ? fmt(n) + ' ج.م' : '—'

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

export default function SalesPage() {
  const [range, setRange] = useState<DateRange>({ from: toISO(monthStart), to: toISO(monthEnd) })
  const filters = { dateFrom: range.from, dateTo: range.to }

  const { data: trustRows, isLoading: trustLoading, error: trustError } = useSystemTrustState('sales')
  const { data: daily, isLoading: dailyLoading } = useSalesDailyTotals(filters)
  const { data: summary, isLoading: summaryLoading } = useSalesSummary(filters)

  const salesTrust = useTrustForComponent(trustRows, 'fact_sales_daily_grain')
  const revTrust   = useTrustForComponent(trustRows, 'fact_sales_daily_grain.revenue')
  const taxTrust   = useTrustForComponent(trustRows, 'fact_sales_daily_grain.tax')
  const arTrust    = useTrustForComponent(trustRows, 'fact_sales_daily_grain.ar_creation')

  const isBlocked = revTrust?.status === 'BLOCKED' || revTrust?.status === 'FAILED'
  const isLoading = dailyLoading || summaryLoading

  // Chart data — already aggregated by SQL, just map field names
  const chartData = (daily ?? []).map(r => ({
    date:    r.sale_date,
    revenue: r.net_revenue,
    returns: r.returns_value,
    tax:     r.tax_amount,
  }))

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-6)' }}>

      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', flexWrap: 'wrap', gap: 'var(--space-3)' }}>
        <div>
          <h1 style={{ fontSize: 'var(--text-2xl)', fontWeight: 800, color: 'var(--text-primary)', margin: 0 }}>إيرادات المبيعات</h1>
          <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', margin: '4px 0 0' }}>
            تحليل الأداء البيعي — صافي إيراد، ضريبة، مرتجعات، وذمم عملاء
          </p>
        </div>
        <ReportFilterBar value={range} onChange={setRange} />
      </div>

      <SystemHealthBar trustRows={trustRows} isLoading={trustLoading} error={trustError} />

      <div className="report-grid">
        {isLoading ? [1,2,3,4].map(i => <SkeletonCard key={i} height={160} />) : (
          <>
            <MetricCard label="صافي الإيراد" subtitle="ضريبة مستبعدة · مرتجعات مستبعدة"
              value={fmtCur(summary?.total_revenue)}
              status={revTrust?.status ?? salesTrust?.status ?? null}
              lastCompletedAt={salesTrust?.last_completed_at} isStale={salesTrust?.is_stale}
              domain="sales" icon={<TrendingUp size={16} />} />
            <MetricCard label="إجمالي الضريبة المحصلة" subtitle="ضريبة القيمة المضافة (2200)"
              value={fmtCur(summary?.total_tax)}
              status={taxTrust?.status ?? salesTrust?.status ?? null}
              lastCompletedAt={salesTrust?.last_completed_at} isStale={salesTrust?.is_stale}
              domain="sales" icon={<ShoppingBag size={16} />} />
            <MetricCard label="قيمة المرتجعات" subtitle="صافي قيمة ما تم رده"
              value={fmtCur(summary?.total_returns_value)}
              status={revTrust?.status ?? salesTrust?.status ?? null}
              lastCompletedAt={salesTrust?.last_completed_at} isStale={salesTrust?.is_stale}
              domain="sales" icon={<TrendingDown size={16} />} />
            <MetricCard label="ذمم عملاء منشأة" subtitle="قيمة الجزء الآجل من الفواتير"
              value={fmtCur(summary?.total_ar_credit)}
              status={arTrust?.status ?? salesTrust?.status ?? null}
              lastCompletedAt={salesTrust?.last_completed_at} isStale={salesTrust?.is_stale}
              domain="ar" />
          </>
        )}
      </div>

      {/* Revenue Chart */}
      <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-primary)', borderRadius: 'var(--radius-lg)', padding: 'var(--space-5)', boxShadow: 'var(--shadow-sm)' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--space-4)', flexWrap: 'wrap', gap: 'var(--space-2)' }}>
          <div>
            <div style={{ fontWeight: 700, fontSize: 'var(--text-base)', color: 'var(--text-primary)' }}>تطور الإيراد اليومي</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: '2px' }}>صافي إيراد + قيمة مرتجعات — مجمّع يومياً في قاعدة البيانات</div>
          </div>
          <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', flexWrap: 'wrap' }}>
            {revTrust && <TrustStateBadge status={revTrust.status} domain="sales" size="sm" />}
            {salesTrust && <FreshnessIndicator lastCompletedAt={salesTrust.last_completed_at} isStale={salesTrust.is_stale} />}
          </div>
        </div>
        {isBlocked ? (
          <div style={{ height: '240px', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'var(--color-danger-light)', borderRadius: 'var(--radius-md)', flexDirection: 'column', gap: 'var(--space-2)' }}>
            <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', color: 'var(--color-danger)' }}>المخطط محجوب</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }}>لا يمكن عرض بيانات الإيراد حتى اكتمال المطابقة المحاسبية</div>
          </div>
        ) : dailyLoading ? <SkeletonCard height={240} /> : chartData.length === 0 ? (
          <div style={{ height: '240px', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-muted)', fontSize: 'var(--text-sm)' }}>لا توجد بيانات في النطاق الزمني المحدد</div>
        ) : (
          <ResponsiveContainer width="100%" height={240}>
            <AreaChart data={chartData} margin={{ top: 4, left: -10, right: 4, bottom: 0 }}>
              <defs>
                <linearGradient id="revGrad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#2563eb" stopOpacity={0.25} /><stop offset="95%" stopColor="#2563eb" stopOpacity={0.02} />
                </linearGradient>
                <linearGradient id="retGrad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#dc2626" stopOpacity={0.2} /><stop offset="95%" stopColor="#dc2626" stopOpacity={0.02} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border-primary)" vertical={false} />
              <XAxis dataKey="date" tick={{ fontSize: 10, fill: 'var(--text-muted)', fontFamily: 'var(--font-sans)' }} tickLine={false} axisLine={false} />
              <YAxis tickFormatter={v => fmt(v)} tick={{ fontSize: 10, fill: 'var(--text-muted)', fontFamily: 'var(--font-sans)' }} tickLine={false} axisLine={false} />
              <Tooltip content={<CustomTooltip />} />
              <Area type="monotone" dataKey="revenue" name="الإيراد الصافي" stroke="#2563eb" strokeWidth={2} fill="url(#revGrad)" dot={false} />
              <Area type="monotone" dataKey="returns" name="المرتجعات" stroke="#dc2626" strokeWidth={1.5} fill="url(#retGrad)" dot={false} />
            </AreaChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* Bar chart */}
      <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-primary)', borderRadius: 'var(--radius-lg)', padding: 'var(--space-5)', boxShadow: 'var(--shadow-sm)' }}>
        <div style={{ fontWeight: 700, fontSize: 'var(--text-base)', color: 'var(--text-primary)', marginBottom: 'var(--space-4)' }}>توزيع الإيرادات اليومي (إيراد + ضريبة)</div>
        {dailyLoading ? <SkeletonCard height={200} /> : (
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={chartData} margin={{ top: 4, left: -10, right: 4, bottom: 0 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border-primary)" vertical={false} />
              <XAxis dataKey="date" tick={{ fontSize: 10, fill: 'var(--text-muted)', fontFamily: 'var(--font-sans)' }} tickLine={false} axisLine={false} />
              <YAxis tickFormatter={v => fmt(v)} tick={{ fontSize: 10, fill: 'var(--text-muted)', fontFamily: 'var(--font-sans)' }} tickLine={false} axisLine={false} />
              <Tooltip content={<CustomTooltip />} />
              <Bar dataKey="revenue" name="الإيراد" fill="#2563eb" radius={[3, 3, 0, 0]} maxBarSize={24} />
              <Bar dataKey="tax" name="الضريبة" fill="#0284c7" radius={[3, 3, 0, 0]} maxBarSize={24} />
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>
    </div>
  )
}
