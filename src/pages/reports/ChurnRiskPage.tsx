import { useState } from 'react'
import { useSystemTrustState, useTrustForComponent, type TrustStatus } from '@/hooks/useSystemTrustState'
import { useCustomerRiskSummary, useCustomerRiskList, type CustomerRiskRow, type CustomerRiskStats } from '@/hooks/useCustomerRisk'
import SkeletonCard from '@/components/reports/SkeletonCard'
import SystemHealthBar from '@/components/reports/SystemHealthBar'
import TrustStateBadge from '@/components/reports/TrustStateBadge'
import FreshnessIndicator from '@/components/reports/FreshnessIndicator'
import { ResponsiveContainer, PieChart, Pie, Cell, Tooltip, Legend } from 'recharts'

function toISO(d: Date) { return d.toISOString().split('T')[0] }
const today = toISO(new Date())
const FMT = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 })
const fmt    = (n: number | undefined | null) => n != null ? FMT.format(n) : '—'
const fmtCur = (n: number | undefined | null) => n != null ? fmt(n) + ' ج.م' : '—'

const RISK_CONFIG = {
  VIP:     { label: 'VIP',         color: '#f59e0b', bg: '#f59e0b18' },
  LOYAL:   { label: 'مخلص',        color: '#10b981', bg: '#10b98118' },
  ENGAGED: { label: 'متفاعل',      color: '#3b82f6', bg: '#3b82f618' },
  AT_RISK: { label: 'معرض للخطر', color: '#f97316', bg: '#f9731618' },
  DORMANT: { label: 'خامد',        color: '#ef4444', bg: '#ef444418' },
} as const

function RiskBadge({ label }: { label: string }) {
  const cfg = RISK_CONFIG[label as keyof typeof RISK_CONFIG]
  if (!cfg) return <span>{label}</span>
  return (
    <span style={{ display: 'inline-block', padding: '2px 8px', borderRadius: '999px', background: cfg.bg, color: cfg.color, fontWeight: 700, fontSize: '11px' }}>
      {cfg.label}
    </span>
  )
}

function RecencyCell({ days }: { days: number | null }) {
  if (days === null) return <span style={{ color: 'var(--text-muted)', fontSize: 'var(--text-xs)' }}>لا توجد مبيعات</span>
  const color = days > 90 ? 'var(--color-danger)' : days > 30 ? 'var(--color-warning)' : 'var(--color-success)'
  return <span style={{ color, fontWeight: 600, fontSize: 'var(--text-xs)', direction: 'ltr', display: 'inline-block' }}>{days} يوم</span>
}

export default function ChurnRiskPage() {
  const [asOfDate, setAsOfDate] = useState(today)
  const [riskLabel, setRiskLabel] = useState<string | undefined>(undefined)

  const { data: trustRows, isLoading: trustLoading, error: trustError } = useSystemTrustState('customers')
  const { data: stats, isLoading: statsLoading }  = useCustomerRiskSummary({ asOfDate, riskLabel })
  const { data: rows = [], isLoading: listLoading } = useCustomerRiskList({ asOfDate, riskLabel })

  const riskTrust = useTrustForComponent(trustRows, 'snapshot_customer_risk')
  const isBlocked = riskTrust?.status === 'BLOCKED' || riskTrust?.status === 'FAILED'

  const pieData = stats ? [
    { name: 'VIP',         value: stats.vip     },
    { name: 'مخلص',        value: stats.loyal   },
    { name: 'متفاعل',      value: stats.engaged },
    { name: 'معرض للخطر', value: stats.at_risk  },
    { name: 'خامد',        value: stats.dormant  },
  ].filter(d => d.value > 0) : []

  const PIE_COLORS = ['#f59e0b', '#10b981', '#3b82f6', '#f97316', '#ef4444']

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-6)' }}>

      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', flexWrap: 'wrap', gap: 'var(--space-3)' }}>
        <div>
          <h1 style={{ fontSize: 'var(--text-2xl)', fontWeight: 800, color: 'var(--text-primary)', margin: 0 }}>خطر الخمود — RFM</h1>
          <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', margin: '4px 0 0' }}>
            تصنيف العملاء: VIP — مخلص — متفاعل — معرض للخطر — خامد
          </p>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
          <select value={riskLabel ?? ''} onChange={e => setRiskLabel(e.target.value || undefined)}
            style={{ padding: '5px 8px', borderRadius: 'var(--radius-sm)', border: '1px solid var(--border-primary)', background: 'var(--bg-input)', color: 'var(--text-primary)', fontSize: 'var(--text-xs)', fontFamily: 'var(--font-sans)', outline: 'none' }}>
            <option value="">كل التصنيفات</option>
            <option value="VIP">VIP</option>
            <option value="LOYAL">مخلص</option>
            <option value="ENGAGED">متفاعل</option>
            <option value="AT_RISK">معرض للخطر</option>
            <option value="DORMANT">خامد</option>
          </select>
          <label style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', fontWeight: 500 }}>بتاريخ:</label>
          <input type="date" value={asOfDate} max={today} onChange={e => setAsOfDate(e.target.value)}
            style={{ padding: '5px 8px', borderRadius: 'var(--radius-sm)', border: '1px solid var(--border-primary)', background: 'var(--bg-input)', color: 'var(--text-primary)', fontSize: 'var(--text-xs)', fontFamily: 'var(--font-sans)', outline: 'none' }} />
        </div>
      </div>

      <SystemHealthBar trustRows={trustRows} isLoading={trustLoading} error={trustError} />

      {/* KPI Grid */}
      {statsLoading ? (
        <div className="report-grid">{[1,2,3,4,5].map(i => <SkeletonCard key={i} height={120} />)}</div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(160px, 1fr))', gap: 'var(--space-3)' }}>
          {(Object.entries(RISK_CONFIG) as [string, typeof RISK_CONFIG[keyof typeof RISK_CONFIG]][]).map(([key, cfg]) => {
            const KEY_MAP: Record<string, keyof CustomerRiskStats> = {
              VIP: 'vip', LOYAL: 'loyal', ENGAGED: 'engaged', AT_RISK: 'at_risk', DORMANT: 'dormant',
            }
            const val = stats ? (stats[KEY_MAP[key]] as number) ?? null : null
            return (
              <div key={key} style={{ background: 'var(--bg-surface)', border: `1px solid ${cfg.color}40`, borderRadius: 'var(--radius-lg)', padding: 'var(--space-4)', boxShadow: 'var(--shadow-sm)' }}>
                <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', fontWeight: 500 }}>{cfg.label}</div>
                <div style={{ fontSize: 'var(--text-2xl)', fontWeight: 800, color: cfg.color, margin: '4px 0 0' }}>{val != null ? FMT.format(val) : '—'}</div>
              </div>
            )
          })}
        </div>
      )}

      {/* Pie Chart */}
      {!statsLoading && pieData.length > 0 && (
        <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-primary)', borderRadius: 'var(--radius-lg)', padding: 'var(--space-5)', boxShadow: 'var(--shadow-sm)' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--space-4)', flexWrap: 'wrap', gap: 'var(--space-2)' }}>
            <div style={{ fontWeight: 700, fontSize: 'var(--text-base)', color: 'var(--text-primary)' }}>توزيع تصنيف العملاء</div>
            <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center' }}>
              {riskTrust && <TrustStateBadge status={riskTrust.status as TrustStatus} domain="customers" size="sm" />}
              {riskTrust && <FreshnessIndicator lastCompletedAt={riskTrust.last_completed_at} isStale={riskTrust.is_stale} />}
            </div>
          </div>
          <ResponsiveContainer width="100%" height={260}>
            <PieChart>
              <Pie data={pieData} dataKey="value" nameKey="name" cx="50%" cy="50%" innerRadius={60} outerRadius={100} paddingAngle={2}>
                {pieData.map((_, i) => <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />)}
              </Pie>
              <Tooltip formatter={(v: any) => [FMT.format(v), 'عملاء']} />
              <Legend />
            </PieChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Table */}
      <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-primary)', borderRadius: 'var(--radius-lg)', overflow: 'hidden', boxShadow: 'var(--shadow-sm)' }}>
        <div style={{ padding: 'var(--space-4) var(--space-5)', borderBottom: '1px solid var(--border-primary)', display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 'var(--space-2)' }}>
          <div style={{ fontWeight: 700, fontSize: 'var(--text-base)', color: 'var(--text-primary)' }}>
            تفاصيل العملاء — مرتب: معرض للخطر أولاً
          </div>
          <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center' }}>
            {riskTrust && <TrustStateBadge status={riskTrust.status as TrustStatus} domain="customers" size="sm" />}
            {riskTrust && <FreshnessIndicator lastCompletedAt={riskTrust.last_completed_at} isStale={riskTrust.is_stale} />}
          </div>
        </div>

        {isBlocked ? (
          <div style={{ padding: 'var(--space-8)', textAlign: 'center' }}>
            <div style={{ fontSize: 'var(--text-sm)', fontWeight: 700, color: 'var(--color-danger)' }}>بيانات الخطر محجوبة</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', marginTop: 'var(--space-2)' }}>snapshot_customer_risk يحتاج تشغيل ناجح أولاً</div>
          </div>
        ) : listLoading ? (
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
                  {['العميل', 'التصنيف', 'RFM Score', 'أيام منذ آخر شراء', 'تكرار (90 يوم)', 'قيمة (90 يوم)'].map(h => (
                    <th key={h} style={{ padding: '10px 14px', textAlign: 'right', fontWeight: 600, color: 'var(--text-secondary)', fontSize: 'var(--text-xs)', borderBottom: '1px solid var(--border-primary)', whiteSpace: 'nowrap' }}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map((row: CustomerRiskRow) => (
                  <tr key={row.customer_id}
                    style={{ borderBottom: '1px solid var(--divider)', transition: 'background 0.1s' }}
                    onMouseEnter={e => (e.currentTarget.style.background = 'var(--bg-hover)')}
                    onMouseLeave={e => (e.currentTarget.style.background = '')}>
                    <td style={{ padding: '10px 14px', color: 'var(--text-primary)', fontWeight: row.customer_name ? 600 : 400, fontSize: 'var(--text-xs)' }}>
                      {row.customer_name ?? <span style={{ fontFamily: 'monospace', color: 'var(--text-muted)' }}>{row.customer_id.slice(0, 8)}…</span>}
                    </td>
                    <td style={{ padding: '10px 14px' }}><RiskBadge label={row.risk_label} /></td>
                    <td style={{ padding: '10px 14px', color: 'var(--text-primary)', fontWeight: 600, direction: 'ltr', textAlign: 'right', fontSize: 'var(--text-xs)' }}>{row.rfm_score}</td>
                    <td style={{ padding: '10px 14px' }}><RecencyCell days={row.recency_days} /></td>
                    <td style={{ padding: '10px 14px', color: 'var(--text-primary)', fontWeight: 600, direction: 'ltr', textAlign: 'right', fontSize: 'var(--text-xs)' }}>{row.frequency_l90d}×</td>
                    <td style={{ padding: '10px 14px', color: 'var(--text-primary)', direction: 'ltr', textAlign: 'right', fontSize: 'var(--text-xs)' }}>{fmtCur(row.monetary_l90d)}</td>
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
