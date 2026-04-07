import { useState } from 'react'
import { useSystemTrustState, useTrustForComponent } from '@/hooks/useSystemTrustState'
import { useARDailyTotals, useARSummary } from '@/hooks/useARCollections'
import MetricCard from '@/components/reports/MetricCard'
import SkeletonCard from '@/components/reports/SkeletonCard'
import SystemHealthBar from '@/components/reports/SystemHealthBar'
import ReportFilterBar, { type DateRange } from '@/components/reports/ReportFilterBar'
import TrustStateBadge from '@/components/reports/TrustStateBadge'
import FreshnessIndicator from '@/components/reports/FreshnessIndicator'
import { ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Tooltip, CartesianGrid } from 'recharts'
import { BarChart3, ArrowDownToLine, RotateCcw } from 'lucide-react'

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

export default function ReceivablesPage() {
  const [range, setRange] = useState<DateRange>({ from: toISO(monthStart), to: toISO(monthEnd) })
  const filters = { dateFrom: range.from, dateTo: range.to }

  const { data: trustRows, isLoading: trustLoading, error: trustError } = useSystemTrustState('ar')
  const { data: daily, isLoading: dailyLoading } = useARDailyTotals(filters)
  const { data: summary, isLoading: summaryLoading } = useARSummary(filters)

  const arTrust = useTrustForComponent(trustRows, 'fact_ar_collections_attributed_to_origin_sale_date')
  const isBlocked = arTrust?.status === 'BLOCKED' || arTrust?.status === 'FAILED'

  // Chart data — already SQL-aggregated, just remap field names
  const chartData = (daily ?? []).map(r => ({
    date:     r.sale_date,
    receipts: r.receipt_amount,
    refunds:  r.refund_amount,
    net:      r.net_cohort,
  }))

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-6)' }}>

      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', flexWrap: 'wrap', gap: 'var(--space-3)' }}>
        <div>
          <h1 style={{ fontSize: 'var(--text-2xl)', fontWeight: 800, color: 'var(--text-primary)', margin: 0 }}>المستحقات وتحصيل AR</h1>
          <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', margin: '4px 0 0' }}>
            تحصيلات منسوبة إلى تاريخ البيع الأصلي — لتقييم كفاءة التحصيل per cohort
          </p>
        </div>
        <ReportFilterBar value={range} onChange={setRange} />
      </div>

      <SystemHealthBar trustRows={trustRows?.filter(r => r.component_name.includes('ar_collections'))} isLoading={trustLoading} error={trustError} />

      <div className="report-grid">
        {summaryLoading ? [1,2,3].map(i => <SkeletonCard key={i} height={160} />) : (
          <>
            <MetricCard label="صافي التحصيل (Cohort)" subtitle="منسوب لتاريخ البيع الأصلي"
              value={fmtCur(summary?.total_net_cohort)}
              status={arTrust?.status ?? null}
              lastCompletedAt={arTrust?.last_completed_at} isStale={arTrust?.is_stale}
              domain="ar" icon={<BarChart3 size={16} />} />
            <MetricCard label="إجمالي الإيصالات" subtitle="قيمة ما حُصِّل فعلياً"
              value={fmtCur(summary?.total_receipt_amount)}
              status={arTrust?.status ?? null}
              lastCompletedAt={arTrust?.last_completed_at} isStale={arTrust?.is_stale}
              domain="ar" icon={<ArrowDownToLine size={16} />} />
            <MetricCard label="إجمالي المردودات النقدية" subtitle="مسترد من عمليات مرتجع"
              value={fmtCur(summary?.total_refunds)}
              status={arTrust?.status ?? null}
              lastCompletedAt={arTrust?.last_completed_at} isStale={arTrust?.is_stale}
              domain="ar" icon={<RotateCcw size={16} />} />
          </>
        )}
      </div>

      <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-primary)', borderRadius: 'var(--radius-lg)', padding: 'var(--space-5)', boxShadow: 'var(--shadow-sm)' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--space-4)', flexWrap: 'wrap', gap: 'var(--space-2)' }}>
          <div>
            <div style={{ fontWeight: 700, fontSize: 'var(--text-base)', color: 'var(--text-primary)' }}>تحصيلات AR مجمّعة بتاريخ البيع الأصلي</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: '2px' }}>مجمّع في قاعدة البيانات — إيصالات، مردودات، صافي</div>
          </div>
          <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center' }}>
            {arTrust && <TrustStateBadge status={arTrust.status} domain="ar" size="sm" />}
            {arTrust && <FreshnessIndicator lastCompletedAt={arTrust.last_completed_at} isStale={arTrust.is_stale} />}
          </div>
        </div>
        {isBlocked ? (
          <div style={{ height: '260px', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'var(--color-danger-light)', borderRadius: 'var(--radius-md)', flexDirection: 'column', gap: 'var(--space-2)' }}>
            <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', color: 'var(--color-danger)' }}>بيانات AR محجوبة</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }}>يحتاج إلى اكتمال تشغيل محرك AR أولاً</div>
          </div>
        ) : dailyLoading ? <SkeletonCard height={260} /> : chartData.length === 0 ? (
          <div style={{ height: '260px', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-muted)', fontSize: 'var(--text-sm)' }}>لا توجد بيانات تحصيل في هذه الفترة</div>
        ) : (
          <ResponsiveContainer width="100%" height={260}>
            <BarChart data={chartData} margin={{ top: 4, left: -10, right: 4, bottom: 0 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border-primary)" vertical={false} />
              <XAxis dataKey="date" tick={{ fontSize: 10, fill: 'var(--text-muted)', fontFamily: 'var(--font-sans)' }} tickLine={false} axisLine={false} />
              <YAxis tickFormatter={v => fmt(v)} tick={{ fontSize: 10, fill: 'var(--text-muted)', fontFamily: 'var(--font-sans)' }} tickLine={false} axisLine={false} />
              <Tooltip content={<CustomTooltip />} />
              <Bar dataKey="receipts" name="إيصالات" fill="#2563eb" radius={[3, 3, 0, 0]} maxBarSize={20} />
              <Bar dataKey="refunds"  name="مردودات" fill="#dc2626" radius={[3, 3, 0, 0]} maxBarSize={20} />
              <Bar dataKey="net"      name="صافي"    fill="#16a34a" radius={[3, 3, 0, 0]} maxBarSize={20} />
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>
    </div>
  )
}
