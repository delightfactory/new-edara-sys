import { useState } from 'react'
import { useSystemTrustState, useTrustForComponent, type TrustStatus } from '@/hooks/useSystemTrustState'
import { useTargetAttainmentSummary, useTargetAttainmentTable, type TargetAttainmentRow } from '@/hooks/useTargetAttainment'
import MetricCard from '@/components/reports/MetricCard'
import SkeletonCard from '@/components/reports/SkeletonCard'
import SystemHealthBar from '@/components/reports/SystemHealthBar'
import TrustStateBadge from '@/components/reports/TrustStateBadge'
import FreshnessIndicator from '@/components/reports/FreshnessIndicator'
import { ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Tooltip, CartesianGrid, ReferenceLine, Cell } from 'recharts'
import { CheckCircle2, Circle, AlertTriangle, XCircle } from 'lucide-react'

function toISO(d: Date) { return d.toISOString().split('T')[0] }
const today = toISO(new Date())
const FMT = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 })
const fmt    = (n: number | undefined | null) => n != null ? FMT.format(n) : '—'
const fmtCur = (n: number | undefined | null) => n != null ? fmt(n) + ' ج.م' : '—'
const fmtPct = (n: number | undefined | null) => n != null ? FMT.format(n) + '%' : '—'

const TREND_CONFIG = {
  achieved:  { label: 'محقق',        color: 'var(--color-success)', bg: 'var(--color-success-light)' },
  exceeded:  { label: 'تجاوز الهدف', color: 'var(--color-success)', bg: 'var(--color-success-light)' },
  on_track:  { label: 'على المسار',  color: 'var(--color-info)',    bg: 'var(--color-info-light)'    },
  at_risk:   { label: 'معرض للخطر', color: 'var(--color-warning)', bg: 'var(--color-warning-light)' },
  behind:    { label: 'متأخر',       color: 'var(--color-danger)',  bg: 'var(--color-danger-light)'  },
} as const

function TrendBadge({ trend }: { trend: string }) {
  const cfg = TREND_CONFIG[trend as keyof typeof TREND_CONFIG]
  if (!cfg) return <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{trend}</span>
  return (
    <span style={{ display: 'inline-block', padding: '2px 8px', borderRadius: '999px', background: cfg.bg, color: cfg.color, fontWeight: 700, fontSize: '11px' }}>
      {cfg.label}
    </span>
  )
}

function barColor(pct: number) {
  if (pct >= 100) return '#10b981'
  if (pct >= 80)  return '#f59e0b'
  return '#ef4444'
}

export default function TargetAttainmentPage() {
  const [asOfDate, setAsOfDate] = useState(today)
  const [scope, setScope]       = useState<string | undefined>(undefined)

  const { data: trustRows, isLoading: trustLoading, error: trustError } = useSystemTrustState('targets')
  const { data: stats, isLoading: statsLoading }   = useTargetAttainmentSummary({ asOfDate })
  const { data: rows = [], isLoading: tableLoading } = useTargetAttainmentTable({ asOfDate, scope })

  const targetTrust = useTrustForComponent(trustRows, 'snapshot_target_attainment')
  const isBlocked   = targetTrust?.status === 'BLOCKED' || targetTrust?.status === 'FAILED'

  const individualRows = rows.filter(r => r.scope === 'individual' && r.rep_name)
  const chartData = individualRows.map(r => ({
    name: r.rep_name!,
    pct:  Math.round(r.achievement_pct ?? 0),
  }))

  const behindCount = (stats?.behind ?? 0) + (stats?.at_risk ?? 0)

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-6)' }}>

      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', flexWrap: 'wrap', gap: 'var(--space-3)' }}>
        <div>
          <h1 style={{ fontSize: 'var(--text-2xl)', fontWeight: 800, color: 'var(--text-primary)', margin: 0 }}>إنجاز الأهداف</h1>
          <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', margin: '4px 0 0' }}>
            فعلى مقابل مستهدف — اتجاه الأداء — فردى وفرع وشركة
          </p>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
          <select value={scope ?? ''} onChange={e => setScope(e.target.value || undefined)}
            style={{ padding: '5px 8px', borderRadius: 'var(--radius-sm)', border: '1px solid var(--border-primary)', background: 'var(--bg-input)', color: 'var(--text-primary)', fontSize: 'var(--text-xs)', fontFamily: 'var(--font-sans)', outline: 'none' }}>
            <option value="">كل النطاقات</option>
            <option value="individual">فردى</option>
            <option value="branch">فرع</option>
            <option value="company">الشركة</option>
          </select>
          <label style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', fontWeight: 500 }}>بتاريخ:</label>
          <input type="date" value={asOfDate} max={today} onChange={e => setAsOfDate(e.target.value)}
            style={{ padding: '5px 8px', borderRadius: 'var(--radius-sm)', border: '1px solid var(--border-primary)', background: 'var(--bg-input)', color: 'var(--text-primary)', fontSize: 'var(--text-xs)', fontFamily: 'var(--font-sans)', outline: 'none' }} />
        </div>
      </div>

      <SystemHealthBar trustRows={trustRows?.filter(r => r.component_name === 'snapshot_target_attainment')} isLoading={trustLoading} error={trustError} />

      <div className="report-grid">
        {statsLoading ? [1,2,3,4].map(i => <SkeletonCard key={i} height={160} />) : (
          <>
            <MetricCard label="أهداف محققة" subtitle="تجاوزت أو حققت الهدف"
              value={stats?.achieved ?? null}
              status={targetTrust?.status ?? null}
              lastCompletedAt={targetTrust?.last_completed_at} isStale={targetTrust?.is_stale}
              domain="sales" icon={<CheckCircle2 size={16} />} />
            <MetricCard label="على المسار" subtitle="تسير وفق الخطة"
              value={stats?.on_track ?? null}
              status={targetTrust?.status ?? null}
              lastCompletedAt={targetTrust?.last_completed_at} isStale={targetTrust?.is_stale}
              domain="sales" icon={<Circle size={16} />} />
            <MetricCard label="متأخرة أو معرضة للخطر" subtitle="تحتاج تدخلاً"
              value={behindCount}
              status={targetTrust?.status ?? null}
              lastCompletedAt={targetTrust?.last_completed_at} isStale={targetTrust?.is_stale}
              domain="sales" icon={<XCircle size={16} />}
              secondary={stats?.total_targets ? { label: 'إجمالى الأهداف', value: String(stats.total_targets) } : undefined} />
            <MetricCard label="متوسط الإنجاز%" subtitle="متوسط نسبة التحقق"
              value={stats?.avg_achievement_pct != null ? fmtPct(stats.avg_achievement_pct) : null}
              status={targetTrust?.status ?? null}
              lastCompletedAt={targetTrust?.last_completed_at} isStale={targetTrust?.is_stale}
              domain="sales" icon={<AlertTriangle size={16} />} />
          </>
        )}
      </div>

      {/* Individual Rep Chart */}
      {chartData.length > 0 && (
        <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-primary)', borderRadius: 'var(--radius-lg)', padding: 'var(--space-5)', boxShadow: 'var(--shadow-sm)' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--space-4)', flexWrap: 'wrap', gap: 'var(--space-2)' }}>
            <div>
              <div style={{ fontWeight: 700, fontSize: 'var(--text-base)', color: 'var(--text-primary)' }}>نسبة الإنجاز — المندوبون الفرديون</div>
              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: '2px' }}>الخط المنقط عند 100% هو الهدف</div>
            </div>
            <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center' }}>
              {targetTrust && <TrustStateBadge status={targetTrust.status as TrustStatus} domain="sales" size="sm" />}
              {targetTrust && <FreshnessIndicator lastCompletedAt={targetTrust.last_completed_at} isStale={targetTrust.is_stale} />}
            </div>
          </div>
          <ResponsiveContainer width="100%" height={Math.max(chartData.length * 40, 200)}>
            <BarChart data={chartData} layout="vertical" margin={{ top: 4, left: 10, right: 40, bottom: 0 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border-primary)" horizontal={false} />
              <XAxis type="number" tickFormatter={v => v + '%'} tick={{ fontSize: 10, fill: 'var(--text-muted)', fontFamily: 'var(--font-sans)' }} tickLine={false} axisLine={false} domain={[0, 'dataMax + 10']} />
              <YAxis type="category" dataKey="name" width={120} tick={{ fontSize: 11, fill: 'var(--text-primary)', fontFamily: 'var(--font-sans)' }} tickLine={false} axisLine={false} />
              <Tooltip formatter={(v: any) => [v + '%', 'الإنجاز']} />
              <ReferenceLine x={100} stroke="var(--color-warning)" strokeDasharray="4 4" strokeWidth={2} />
              <Bar dataKey="pct" name="الإنجاز%" radius={[0, 3, 3, 0]} maxBarSize={20}>
                {chartData.map((entry, i) => (
                  <Cell key={i} fill={barColor(entry.pct)} />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Table */}
      <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-primary)', borderRadius: 'var(--radius-lg)', overflow: 'hidden', boxShadow: 'var(--shadow-sm)' }}>
        <div style={{ padding: 'var(--space-4) var(--space-5)', borderBottom: '1px solid var(--border-primary)', display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 'var(--space-2)' }}>
          <div style={{ fontWeight: 700, fontSize: 'var(--text-base)', color: 'var(--text-primary)' }}>تفاصيل الأهداف</div>
          <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center' }}>
            {targetTrust && <TrustStateBadge status={targetTrust.status as TrustStatus} domain="sales" size="sm" />}
            {targetTrust && <FreshnessIndicator lastCompletedAt={targetTrust.last_completed_at} isStale={targetTrust.is_stale} />}
          </div>
        </div>

        {isBlocked ? (
          <div style={{ padding: 'var(--space-8)', textAlign: 'center' }}>
            <div style={{ fontSize: 'var(--text-sm)', fontWeight: 700, color: 'var(--color-danger)' }}>بيانات الأهداف محجوبة</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', marginTop: 'var(--space-2)' }}>snapshot_target_attainment يحتاج تشغيل ناجح أولاً</div>
          </div>
        ) : tableLoading ? (
          <div style={{ padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
            {[1,2,3,4,5].map(i => <SkeletonCard key={i} height={44} />)}
          </div>
        ) : rows.length === 0 ? (
          <div style={{ padding: 'var(--space-8)', textAlign: 'center', color: 'var(--text-muted)', fontSize: 'var(--text-sm)' }}>
            لا توجد بيانات — شغّل watermark sweep أولاً
          </div>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 'var(--text-sm)' }}>
              <thead>
                <tr style={{ background: 'var(--bg-surface-2)' }}>
                  {['الهدف', 'النوع', 'المسؤول', 'الفرع', 'المستهدف', 'المحقق', 'إنجاز%', 'الاتجاه'].map(h => (
                    <th key={h} style={{ padding: '10px 14px', textAlign: 'right', fontWeight: 600, color: 'var(--text-secondary)', fontSize: 'var(--text-xs)', borderBottom: '1px solid var(--border-primary)', whiteSpace: 'nowrap' }}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map((row: TargetAttainmentRow) => (
                  <tr key={row.target_id}
                    style={{ borderBottom: '1px solid var(--divider)', transition: 'background 0.1s' }}
                    onMouseEnter={e => (e.currentTarget.style.background = 'var(--bg-hover)')}
                    onMouseLeave={e => (e.currentTarget.style.background = '')}>
                    <td style={{ padding: '10px 14px', color: 'var(--text-primary)', fontWeight: 600, fontSize: 'var(--text-xs)' }}>{row.target_name}</td>
                    <td style={{ padding: '10px 14px', color: 'var(--text-secondary)', fontSize: 'var(--text-xs)' }}>{row.type_code}</td>
                    <td style={{ padding: '10px 14px', color: 'var(--text-primary)', fontSize: 'var(--text-xs)' }}>{row.rep_name ?? '—'}</td>
                    <td style={{ padding: '10px 14px', color: 'var(--text-secondary)', fontSize: 'var(--text-xs)' }}>{row.branch_name ?? '—'}</td>
                    <td style={{ padding: '10px 14px', color: 'var(--text-primary)', direction: 'ltr', textAlign: 'right', fontSize: 'var(--text-xs)' }}>{fmtCur(row.target_value)}</td>
                    <td style={{ padding: '10px 14px', color: 'var(--text-primary)', direction: 'ltr', textAlign: 'right', fontSize: 'var(--text-xs)' }}>{fmtCur(row.achieved_value)}</td>
                    <td style={{ padding: '10px 14px', fontWeight: 700, direction: 'ltr', textAlign: 'right', fontSize: 'var(--text-xs)',
                        color: (row.achievement_pct ?? 0) >= 100 ? 'var(--color-success)' : (row.achievement_pct ?? 0) >= 80 ? 'var(--color-warning)' : 'var(--color-danger)' }}>
                      {fmtPct(row.achievement_pct)}
                    </td>
                    <td style={{ padding: '10px 14px' }}><TrendBadge trend={row.trend} /></td>
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
