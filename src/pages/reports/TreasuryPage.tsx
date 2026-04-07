import { useState } from 'react'
import { useSystemTrustState, useTrustForComponent } from '@/hooks/useSystemTrustState'
import { useTreasuryDailyTotals, useTreasurySummary } from '@/hooks/useTreasuryCashflow'
import MetricCard from '@/components/reports/MetricCard'
import SkeletonCard from '@/components/reports/SkeletonCard'
import SystemHealthBar from '@/components/reports/SystemHealthBar'
import ReportFilterBar, { type DateRange } from '@/components/reports/ReportFilterBar'
import TrustStateBadge from '@/components/reports/TrustStateBadge'
import FreshnessIndicator from '@/components/reports/FreshnessIndicator'
import { ResponsiveContainer, AreaChart, Area, XAxis, YAxis, Tooltip, CartesianGrid, ReferenceLine } from 'recharts'
import { Wallet, ArrowDownToLine, ArrowUpFromLine } from 'lucide-react'

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
          <span>{p.name}</span><span style={{ fontWeight: 600, direction: 'ltr' }}>{fmt(p.value)} ج.م</span>
        </div>
      ))}
    </div>
  )
}

export default function TreasuryPage() {
  const [range, setRange] = useState<DateRange>({ from: toISO(monthStart), to: toISO(monthEnd) })
  const filters = { dateFrom: range.from, dateTo: range.to }

  const { data: trustRows, isLoading: trustLoading, error: trustError } = useSystemTrustState('treasury')
  const { data: daily, isLoading: dailyLoading } = useTreasuryDailyTotals(filters)
  const { data: summary, isLoading: summaryLoading } = useTreasurySummary(filters)

  // Trust naming: backend stores metric key as net_collection, fact column is net_cashflow (P2 fix — match fact column)
  const trsTrust = useTrustForComponent(trustRows, 'fact_treasury_cashflow_daily.net_collection')
    ?? useTrustForComponent(trustRows, 'fact_treasury_cashflow_daily')

  const isBlocked = trsTrust?.status === 'BLOCKED' || trsTrust?.status === 'FAILED'

  // Chart data — already date-aggregated by SQL, just remap field names
  const chartData = (daily ?? []).map(r => ({
    date:    r.treasury_date,
    inflow:  r.gross_inflow,
    outflow: r.gross_outflow,
    // net_cashflow is the correct fact column name
    net:     r.net_cashflow,
  }))

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-6)' }}>

      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', flexWrap: 'wrap', gap: 'var(--space-3)' }}>
        <div>
          <h1 style={{ fontSize: 'var(--text-2xl)', fontWeight: 800, color: 'var(--text-primary)', margin: 0 }}>التدفق النقدي الخزيني</h1>
          <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', margin: '4px 0 0' }}>
            تحصيلات نقدية موثقة مباشرةً من حركات الخزائن والعُهد — الشيكات مستبعدة تلقائياً
          </p>
        </div>
        <ReportFilterBar value={range} onChange={setRange} />
      </div>

      {/* Semantic contract notice */}
      <div style={{ background: 'rgba(37,99,235,0.04)', border: '1px solid rgba(37,99,235,0.15)', borderRadius: 'var(--radius-md)', padding: 'var(--space-3) var(--space-4)', fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', display: 'flex', alignItems: 'flex-start', gap: 'var(--space-2)' }}>
        <span style={{ flexShrink: 0 }}>ℹ️</span>
        <span>
          حالة <strong>مطابق لسجلات الخزينة</strong> تعني: تطابق كامل مع سجلات التنفيذ التشغيلية في
          EDARA (<code>vault_transactions / custody_transactions</code>) — وليس تدقيقاً خارجياً مستقلاً.
          عمود الفاكت المُراجَع: <code>net_cashflow</code>.
        </span>
      </div>

      <SystemHealthBar trustRows={trustRows?.filter(r => r.component_name.includes('treasury'))} isLoading={trustLoading} error={trustError} />

      <div className="report-grid">
        {summaryLoading ? [1,2,3].map(i => <SkeletonCard key={i} height={160} />) : (
          <>
            <MetricCard label="صافي التدفق الخزيني" subtitle="net_cashflow — مطابق لسجلات الخزينة والعُهد"
              value={fmtCur(summary?.net_cashflow)}
              status={trsTrust?.status ?? null}
              lastCompletedAt={trsTrust?.last_completed_at} isStale={trsTrust?.is_stale}
              domain="treasury" icon={<Wallet size={16} />} />
            <MetricCard label="إجمالي التحصيل الداخل" subtitle="نقد وعُهد مدفوعة فعلياً"
              value={fmtCur(summary?.total_inflow)}
              status={trsTrust?.status ?? null}
              lastCompletedAt={trsTrust?.last_completed_at} isStale={trsTrust?.is_stale}
              domain="treasury" icon={<ArrowDownToLine size={16} />} />
            <MetricCard label="إجمالي المسترد" subtitle="مردودات نقدية للعملاء"
              value={fmtCur(summary?.total_outflow)}
              status={trsTrust?.status ?? null}
              lastCompletedAt={trsTrust?.last_completed_at} isStale={trsTrust?.is_stale}
              domain="treasury" icon={<ArrowUpFromLine size={16} />} />
          </>
        )}
      </div>

      <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-primary)', borderRadius: 'var(--radius-lg)', padding: 'var(--space-5)', boxShadow: 'var(--shadow-sm)' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--space-4)', flexWrap: 'wrap', gap: 'var(--space-2)' }}>
          <div>
            <div style={{ fontWeight: 700, fontSize: 'var(--text-base)', color: 'var(--text-primary)' }}>التدفق النقدي اليومي</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: '2px' }}>net_cashflow — مجمّع يومياً في قاعدة البيانات</div>
          </div>
          <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center' }}>
            {trsTrust && <TrustStateBadge status={trsTrust.status} domain="treasury" size="sm" />}
            {trsTrust && <FreshnessIndicator lastCompletedAt={trsTrust.last_completed_at} isStale={trsTrust.is_stale} />}
          </div>
        </div>
        {isBlocked ? (
          <div style={{ height: '280px', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'var(--color-danger-light)', borderRadius: 'var(--radius-md)', flexDirection: 'column', gap: 'var(--space-2)' }}>
            <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', color: 'var(--color-danger)' }}>التدفق النقدي محجوب</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }}>يظهر عند اكتمال المطابقة مع سجلات الخزائن والعُهد</div>
          </div>
        ) : dailyLoading ? <SkeletonCard height={280} /> : chartData.length === 0 ? (
          <div style={{ height: '280px', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-muted)', fontSize: 'var(--text-sm)' }}>لا توجد تدفقات خزينية في هذه الفترة</div>
        ) : (
          <ResponsiveContainer width="100%" height={280}>
            <AreaChart data={chartData} margin={{ top: 4, left: -10, right: 4, bottom: 0 }}>
              <defs>
                <linearGradient id="inflowGrad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#16a34a" stopOpacity={0.25} /><stop offset="95%" stopColor="#16a34a" stopOpacity={0.02} />
                </linearGradient>
                <linearGradient id="outflowGrad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#dc2626" stopOpacity={0.2} /><stop offset="95%" stopColor="#dc2626" stopOpacity={0.02} />
                </linearGradient>
                <linearGradient id="netGrad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#2563eb" stopOpacity={0.3} /><stop offset="95%" stopColor="#2563eb" stopOpacity={0.02} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border-primary)" vertical={false} />
              <XAxis dataKey="date" tick={{ fontSize: 10, fill: 'var(--text-muted)', fontFamily: 'var(--font-sans)' }} tickLine={false} axisLine={false} />
              <YAxis tickFormatter={v => fmt(v)} tick={{ fontSize: 10, fill: 'var(--text-muted)', fontFamily: 'var(--font-sans)' }} tickLine={false} axisLine={false} />
              <Tooltip content={<CustomTooltip />} />
              <ReferenceLine y={0} stroke="var(--border-primary)" strokeDasharray="4 4" />
              <Area type="monotone" dataKey="inflow"  name="داخل"  stroke="#16a34a" strokeWidth={2}   fill="url(#inflowGrad)"  dot={false} />
              <Area type="monotone" dataKey="outflow" name="مستردّ" stroke="#dc2626" strokeWidth={1.5} fill="url(#outflowGrad)" dot={false} />
              <Area type="monotone" dataKey="net"     name="صافي"  stroke="#2563eb" strokeWidth={2.5} fill="url(#netGrad)"     dot={false} />
            </AreaChart>
          </ResponsiveContainer>
        )}
      </div>
    </div>
  )
}
