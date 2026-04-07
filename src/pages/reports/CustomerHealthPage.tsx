import { useState } from 'react'
import { useSystemTrustState, useTrustForComponent } from '@/hooks/useSystemTrustState'
import { useCustomerHealthSummary, type CustomerHealthRow } from '@/hooks/useCustomerHealth'
import MetricCard from '@/components/reports/MetricCard'
import SkeletonCard from '@/components/reports/SkeletonCard'
import SystemHealthBar from '@/components/reports/SystemHealthBar'
import TrustStateBadge from '@/components/reports/TrustStateBadge'
import FreshnessIndicator from '@/components/reports/FreshnessIndicator'
import { Users2, UserX, ActivitySquare } from 'lucide-react'

function toISO(d: Date) { return d.toISOString().split('T')[0] }
const today = toISO(new Date())
const FMT = new Intl.NumberFormat('ar-EG', { maximumFractionDigits: 0 })
const fmt = (n: number | undefined | null) => n != null ? FMT.format(n) : '—'
const fmtCur = (n: number | undefined | null) => n != null ? fmt(n) + ' ج.م' : '—'

function RecencyCell({ days }: { days: number | null }) {
  if (days === null) {
    return <span style={{ color: 'var(--text-muted)', fontSize: 'var(--text-xs)' }}>لا توجد مبيعات</span>
  }
  const color = days > 90 ? 'var(--color-danger)' : days > 30 ? 'var(--color-warning)' : 'var(--color-success)'
  return (
    <span style={{ color, fontWeight: 600, fontSize: 'var(--text-xs)', direction: 'ltr', display: 'inline-block' }}>
      {days} يوم
    </span>
  )
}

export default function CustomerHealthPage() {
  const [asOfDate, setAsOfDate] = useState(today)

  const { data: trustRows, isLoading: trustLoading, error: trustError } = useSystemTrustState('customers')
  const { data: health, isLoading } = useCustomerHealthSummary({ asOfDate })

  const custTrust = useTrustForComponent(trustRows, 'snapshot_customer_health')
  const isBlocked = custTrust?.status === 'BLOCKED' || custTrust?.status === 'FAILED'

  const stats = health?.stats
  const rows  = health?.rows ?? []

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-6)' }}>

      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', flexWrap: 'wrap', gap: 'var(--space-3)' }}>
        <div>
          <h1 style={{ fontSize: 'var(--text-2xl)', fontWeight: 800, color: 'var(--text-primary)', margin: 0 }}>صحة قاعدة العملاء</h1>
          <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', margin: '4px 0 0' }}>
            خمول — تكرار — قيمة (RFM) — بناءً على snapshot يومي
          </p>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
          <label style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', fontWeight: 500 }}>بتاريخ:</label>
          <input
            type="date" value={asOfDate} max={today}
            onChange={e => setAsOfDate(e.target.value)}
            style={{ padding: '5px 8px', borderRadius: 'var(--radius-sm)', border: '1px solid var(--border-primary)', background: 'var(--bg-input)', color: 'var(--text-primary)', fontSize: 'var(--text-xs)', fontFamily: 'var(--font-sans)', outline: 'none' }}
          />
        </div>
      </div>

      <SystemHealthBar trustRows={trustRows?.filter(r => r.component_name.includes('customer_health'))} isLoading={trustLoading} error={trustError} />

      <div className="report-grid">
        {isLoading ? [1,2,3].map(i => <SkeletonCard key={i} height={150} />) : (
          <>
            <MetricCard label="نشطون" subtitle="تعاملوا خلال آخر 90 يوماً"
              value={stats?.active ?? null}
              status={custTrust?.status ?? null}
              lastCompletedAt={custTrust?.last_completed_at} isStale={custTrust?.is_stale}
              domain="customers" icon={<ActivitySquare size={16} />} />
            <MetricCard label="خامدون" subtitle="لا تعاملات منذ أكثر من 90 يوماً"
              value={stats?.dormant ?? null}
              status={custTrust?.status ?? null}
              lastCompletedAt={custTrust?.last_completed_at} isStale={custTrust?.is_stale}
              domain="customers" icon={<UserX size={16} />} />
            <MetricCard label="متوسط القيمة (90 يوم)" subtitle="متوسط مشتريات العميل في آخر ربع"
              value={fmtCur(stats?.avg_monetary)}
              status={custTrust?.status ?? null}
              lastCompletedAt={custTrust?.last_completed_at} isStale={custTrust?.is_stale}
              domain="customers" icon={<Users2 size={16} />}
              secondary={stats?.avg_recency != null ? { label: 'متوسط أيام الخمود', value: `${Math.round(stats.avg_recency)} يوم` } : undefined} />
          </>
        )}
      </div>

      {/* Customer table */}
      <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-primary)', borderRadius: 'var(--radius-lg)', overflow: 'hidden', boxShadow: 'var(--shadow-sm)' }}>
        <div style={{ padding: 'var(--space-4) var(--space-5)', borderBottom: '1px solid var(--border-primary)', display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 'var(--space-2)' }}>
          <div style={{ fontWeight: 700, fontSize: 'var(--text-base)', color: 'var(--text-primary)' }}>
            تفاصيل العملاء — أعلى 50 حسب القيمة
          </div>
          <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', flexWrap: 'wrap' }}>
            {custTrust && <TrustStateBadge status={custTrust.status} domain="customers" size="sm" />}
            {custTrust && <FreshnessIndicator lastCompletedAt={custTrust.last_completed_at} isStale={custTrust.is_stale} />}
          </div>
        </div>

        {isBlocked ? (
          <div style={{ padding: 'var(--space-8)', textAlign: 'center' }}>
            <div style={{ fontSize: 'var(--text-sm)', fontWeight: 700, color: 'var(--color-danger)' }}>بيانات العملاء محجوبة</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', marginTop: 'var(--space-2)' }}>snapshot_customer_health يحتاج إلى تشغيل ناجح أولاً</div>
          </div>
        ) : isLoading ? (
          <div style={{ padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
            {[1,2,3,4,5].map(i => <SkeletonCard key={i} height={44} />)}
          </div>
        ) : rows.length === 0 ? (
          <div style={{ padding: 'var(--space-8)', textAlign: 'center', color: 'var(--text-muted)', fontSize: 'var(--text-sm)' }}>
            لا توجد بيانات snapshot لهذا التاريخ — شغّل watermark sweep أولاً
          </div>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 'var(--text-sm)' }}>
              <thead>
                <tr style={{ background: 'var(--bg-surface-2)' }}>
                  {['العميل', 'أيام منذ آخر بيع', 'تكرار (90 يوم)', 'قيمة (90 يوم)', 'الحالة'].map(h => (
                    <th key={h} style={{ padding: '10px 14px', textAlign: 'right', fontWeight: 600, color: 'var(--text-secondary)', fontSize: 'var(--text-xs)', borderBottom: '1px solid var(--border-primary)', whiteSpace: 'nowrap' }}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map((row: CustomerHealthRow) => (
                  <tr key={row.customer_id} style={{ borderBottom: '1px solid var(--divider)', transition: 'background 0.1s' }}
                    onMouseEnter={e => (e.currentTarget.style.background = 'var(--bg-hover)')}
                    onMouseLeave={e => (e.currentTarget.style.background = '')}>
                    <td style={{ padding: '10px 14px', color: 'var(--text-primary)', fontWeight: row.customer_name ? 600 : 400, fontSize: 'var(--text-xs)' }}>
                      {row.customer_name ? row.customer_name : <span style={{ fontFamily: 'monospace', color: 'var(--text-muted)' }}>{row.customer_id.slice(0, 8)}…</span>}
                    </td>
                    <td style={{ padding: '10px 14px' }}><RecencyCell days={row.recency_days} /></td>
                    <td style={{ padding: '10px 14px', color: 'var(--text-primary)', fontWeight: 600, direction: 'ltr', textAlign: 'right' }}>{row.frequency_l90d}×</td>
                    <td style={{ padding: '10px 14px', color: 'var(--text-primary)', direction: 'ltr', textAlign: 'right' }}>{fmt(row.monetary_l90d)} ج.م</td>
                    <td style={{ padding: '10px 14px' }}>
                      {row.is_dormant
                        ? <span style={{ color: 'var(--color-danger)', fontSize: '11px', fontWeight: 600 }}>خامد</span>
                        : <span style={{ color: 'var(--color-success)', fontSize: '11px', fontWeight: 600 }}>نشط</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            {stats && stats.total > 50 && (
              <div style={{ padding: 'var(--space-3) var(--space-5)', fontSize: 'var(--text-xs)', color: 'var(--text-muted)', borderTop: '1px solid var(--divider)' }}>
                يعرض أعلى 50 عميلاً حسب القيمة — {stats.total} إجمالاً (مُجمَّعة في قاعدة البيانات)
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  )
}
