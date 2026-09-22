import { useState } from 'react'
import { useSystemTrustState, useTrustForComponent, type TrustStatus } from '@/hooks/useSystemTrustState'
import { useGeographySummary, useGeographyTable, type GeographyRow, type GeoLevel } from '@/hooks/useGeographyPerformance'
import MetricCard from '@/components/reports/MetricCard'
import SkeletonCard from '@/components/reports/SkeletonCard'
import SystemHealthBar from '@/components/reports/SystemHealthBar'
import ReportFilterBar, { type DateRange } from '@/components/reports/ReportFilterBar'
import TrustStateBadge from '@/components/reports/TrustStateBadge'
import FreshnessIndicator from '@/components/reports/FreshnessIndicator'
import ResponsiveCollection from '@/components/patterns/ResponsiveCollection'
import Card from '@/components/patterns/Card'
import KeyValueList from '@/components/patterns/KeyValueList'
import MetricGrid from '@/components/patterns/MetricGrid'
import Select from '@/components/ui/Select'
import { TrendingUp, MapPin } from 'lucide-react'

function toISO(d: Date) { return d.toISOString().split('T')[0] }
const today = new Date()
const monthStart = new Date(today.getFullYear(), today.getMonth(), 1)
const monthEnd = new Date(today.getFullYear(), today.getMonth() + 1, 0)
const FMT = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 })
const fmt = (n: number | undefined | null) => n != null ? FMT.format(n) : '—'
const fmtCur = (n: number | undefined | null) => n != null ? fmt(n) + ' ج.م' : '—'
const fmtPct = (n: number | undefined | null) => n != null ? FMT.format(n) + '%' : '—'

const LEVEL_LABELS: Record<GeoLevel, string> = {
  governorate: 'محافظة',
  city: 'مدينة',
  area: 'منطقة',
}

function GeographyDetailCards({ items, device, level }: { items: GeographyRow[]; device: 'mobile' | 'tablet'; level: GeoLevel }) {
  return (
    <div className={`ds-responsive-card-grid ds-responsive-card-grid--${device}`}>
      {items.map(row => (
        <Card key={row.geo_id} padding="md">
          <div style={{ marginBlockEnd: 'var(--space-4)', minWidth: 0 }}>
            <div style={{ color: 'var(--ds-text-primary)', fontWeight: 700, overflowWrap: 'anywhere', minWidth: 0 }}>
              {row.geo_name}
            </div>
          </div>
          <KeyValueList
            columns={device === 'tablet' ? 2 : 1}
            compact
            items={[
              ...(level !== 'governorate'
                ? [{
                    key: 'parent',
                    label: 'الأم',
                    value: <span style={{ overflowWrap: 'anywhere', minWidth: 0 }}>{row.parent_name ?? '—'}</span>,
                  }]
                : []),
              { key: 'revenue', label: 'صافى الإيراد', value: <span dir="ltr">{fmt(row.net_revenue)} ج.م</span> },
              { key: 'customers', label: 'عملاء', value: <span dir="ltr">{row.customer_count}</span> },
              { key: 'transactions', label: 'صفقات', value: <span dir="ltr">{row.transaction_count}</span> },
              { key: 'share', label: 'الحصة%', value: <span dir="ltr">{fmtPct(row.revenue_share_pct)}</span> },
            ]}
          />
        </Card>
      ))}
    </div>
  )
}

export default function GeographyPage() {
  const [range, setRange] = useState<DateRange>({ from: toISO(monthStart), to: toISO(monthEnd) })
  const [level, setLevel] = useState<GeoLevel>('governorate')
  const filters = { dateFrom: range.from, dateTo: range.to, level }

  const { data: trustRows, isLoading: trustLoading, error: trustError } = useSystemTrustState('sales')
  const { data: summary, isLoading: summaryLoading } = useGeographySummary(filters)
  const { data: rows = [], isLoading: tableLoading } = useGeographyTable(filters)

  const salesTrust = useTrustForComponent(trustRows, 'fact_geography_daily')
  const isLoading = summaryLoading || tableLoading

  const maxRev = rows.length > 0 ? rows[0].net_revenue : 1

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-6)' }}>

      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', flexWrap: 'wrap', gap: 'var(--space-3)' }}>
        <div>
          <h1 style={{ fontSize: 'var(--text-2xl)', fontWeight: 800, color: 'var(--text-primary)', margin: 0 }}>التحليل الجغرافى</h1>
          <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', margin: '4px 0 0' }}>
            توزيع الإيراد على المحافظات — المدن — المناطق
          </p>
        </div>
        <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', flexWrap: 'wrap' }}>
          <Select
            aria-label="مستوى التحليل الجغرافي"
            value={level}
            onChange={e => setLevel(e.target.value as GeoLevel)}
          >
            <option value="governorate">محافظة</option>
            <option value="city">مدينة</option>
            <option value="area">منطقة</option>
          </Select>
          <ReportFilterBar value={range} onChange={setRange} />
        </div>
      </div>

      <SystemHealthBar trustRows={trustRows} isLoading={trustLoading} error={trustError} />

      <MetricGrid columns={2}>
        {isLoading ? [1, 2].map(i => <SkeletonCard key={i} height={160} />) : (
          <>
            <MetricCard label="إجمالى الإيراد" subtitle="من جميع المناطق الجغرافية"
              value={fmtCur(summary?.total_revenue)}
              status={salesTrust?.status ?? null}
              lastCompletedAt={salesTrust?.last_completed_at} isStale={salesTrust?.is_stale}
              domain="sales" icon={<TrendingUp size={16} />} />
            <MetricCard label={`${LEVEL_LABELS[level]} مغطاة`} subtitle="بها مبيعات فى الفترة"
              value={summary?.covered_areas ?? null}
              status={salesTrust?.status ?? null}
              lastCompletedAt={salesTrust?.last_completed_at} isStale={salesTrust?.is_stale}
              domain="sales" icon={<MapPin size={16} />} />
          </>
        )}
      </MetricGrid>

      {/* Table with heatmap rows */}
      <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-primary)', borderRadius: 'var(--radius-lg)', overflow: 'hidden', boxShadow: 'var(--shadow-sm)' }}>
        <div style={{ padding: 'var(--space-4) var(--space-5)', borderBottom: '1px solid var(--border-primary)', display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 'var(--space-2)' }}>
          <div style={{ fontWeight: 700, fontSize: 'var(--text-base)', color: 'var(--text-primary)' }}>
            التوزيع حسب {LEVEL_LABELS[level]}
          </div>
          <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center' }}>
            {salesTrust && <TrustStateBadge status={salesTrust.status as TrustStatus} domain="sales" size="sm" />}
            {salesTrust && <FreshnessIndicator lastCompletedAt={salesTrust.last_completed_at} isStale={salesTrust.is_stale} />}
          </div>
        </div>

        <ResponsiveCollection<GeographyRow>
          items={rows}
          loading={tableLoading}
          loadingState={(
            <div style={{ padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
              {[1, 2, 3, 4, 5].map(i => <SkeletonCard key={i} height={44} />)}
            </div>
          )}
          emptyState={(
            <div style={{ padding: 'var(--space-8)', textAlign: 'center', color: 'var(--text-muted)', fontSize: 'var(--text-sm)' }}>
              لا توجد بيانات — شغّل watermark sweep أولاً
            </div>
          )}
          renderDesktop={desktopRows => (
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 'var(--text-sm)' }}>
                <thead>
                  <tr style={{ background: 'var(--bg-surface-2)' }}>
                    {[LEVEL_LABELS[level], level !== 'governorate' ? 'الأم' : null, 'صافى الإيراد', 'عملاء', 'صفقات', 'الحصة%'].filter(Boolean).map(h => (
                      <th scope="col" key={h!} style={{ padding: '10px 14px', textAlign: 'right', fontWeight: 600, color: 'var(--text-secondary)', fontSize: 'var(--text-xs)', borderBottom: '1px solid var(--border-primary)', whiteSpace: 'nowrap' }}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {desktopRows.map((row: GeographyRow) => {
                    const isZero = row.net_revenue === 0
                    const opacity = isZero ? 0 : Math.min(row.net_revenue / maxRev, 1)
                    const rowBg = isZero ? 'var(--bg-surface-2)' : `rgba(37,99,235,${opacity * 0.12})`
                    return (
                      <tr key={row.geo_id}
                        style={{ borderBottom: '1px solid var(--divider)', background: rowBg, transition: 'background 0.1s' }}
                        onMouseEnter={e => (e.currentTarget.style.background = 'var(--bg-hover)')}
                        onMouseLeave={e => (e.currentTarget.style.background = rowBg)}>
                        <td style={{ padding: '10px 14px', color: isZero ? 'var(--text-muted)' : 'var(--text-primary)', fontWeight: isZero ? 400 : 600, fontSize: 'var(--text-xs)' }}>{row.geo_name}</td>
                        {level !== 'governorate' && (
                          <td style={{ padding: '10px 14px', color: 'var(--text-secondary)', fontSize: 'var(--text-xs)' }}>{row.parent_name ?? '—'}</td>
                        )}
                        <td style={{ padding: '10px 14px', color: isZero ? 'var(--text-muted)' : 'var(--text-primary)', direction: 'ltr', textAlign: 'right', fontSize: 'var(--text-xs)' }}>{fmt(row.net_revenue)} ج.م</td>
                        <td style={{ padding: '10px 14px', color: 'var(--text-primary)', direction: 'ltr', textAlign: 'right', fontSize: 'var(--text-xs)' }}>{row.customer_count}</td>
                        <td style={{ padding: '10px 14px', color: 'var(--text-primary)', direction: 'ltr', textAlign: 'right', fontSize: 'var(--text-xs)' }}>{row.transaction_count}</td>
                        <td style={{ padding: '10px 14px', color: 'var(--text-secondary)', direction: 'ltr', textAlign: 'right', fontSize: 'var(--text-xs)' }}>{fmtPct(row.revenue_share_pct)}</td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
          renderTablet={tabletRows => <GeographyDetailCards items={tabletRows} device="tablet" level={level} />}
          renderMobile={mobileRows => <GeographyDetailCards items={mobileRows} device="mobile" level={level} />}
        />
      </div>
    </div>
  )
}
