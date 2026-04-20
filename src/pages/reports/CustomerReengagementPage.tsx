/**
 * CustomerReengagementPage.tsx
 *
 * صفحة قرار تشغيلية: أولويات إعادة الاستهداف
 *
 * معمارية مستقلة:
 *   - لا تعتمد على AnalyticsGate أو analyticsClient
 *   - تُستخدم FilterBar الاحترافي (نفس مكون صفحة العملاء)
 *   - تُستخدم useFilterState (urlSync) للفلاتر
 *   - زر Customer 360 محمي بـ customers.read/customers.read_all
 */

import { useMemo, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { usePageTitle } from '@/components/layout/PageTitleContext'
import {
  useReengagementList,
  useReengagementSummary,
  type ReengagementRow,
  type ReengagementSummary,
  type PriorityLabel,
} from '@/hooks/useCustomerReengagement'
import { useFilterState } from '@/hooks/useFilterState'
import { useGovernorates, useCities, useProfiles } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import { Users, ExternalLink } from 'lucide-react'
import FilterBar from '@/components/shared/FilterBar'
import PageHeader from '@/components/shared/PageHeader'

// ─── Formatters ───────────────────────────────────────────────

const FMT = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 })
const fmt    = (n: number | null | undefined) => n != null ? FMT.format(n) : '—'
const fmtCur = (n: number | null | undefined) => n != null ? fmt(n) + ' ج.م' : '—'

function fmtRecency(days: number | null) {
  if (days === null) return 'لا طلبات'
  if (days === 0) return 'اليوم'
  if (days === 1) return 'أمس'
  return `${days} يوم`
}

// ─── Priority Config ──────────────────────────────────────────

const PRIORITY: Record<PriorityLabel, {
  label: string
  cssClass: string
  icon: string
  accent: string  // للـ KPI border-top فقط (color semantic واضح)
}> = {
  CHAMPION_LOST:  { label: 'Champion Lost', cssClass: 'champion-lost',  icon: '🔴', accent: '#dc2626' },
  DECLINING_HIGH: { label: 'تراجع عالي',    cssClass: 'declining-high', icon: '🟠', accent: '#d97706' },
  MID_LOST:       { label: 'متوسط خامد',    cssClass: 'mid-lost',       icon: '🟡', accent: '#92400e' },
  MID_AT_RISK:    { label: 'متوسط معرض',    cssClass: 'mid-at-risk',    icon: '🟤', accent: '#78350f' },
  OTHER:          { label: 'أخرى',           cssClass: 'other',          icon: '⚫', accent: '#64748b' },
}

const PRIORITY_OPTIONS = [
  { value: 'CHAMPION_LOST',  label: '🔴 Champion Lost' },
  { value: 'DECLINING_HIGH', label: '🟠 تراجع عالي'    },
  { value: 'MID_LOST',       label: '🟡 متوسط خامد'   },
  { value: 'MID_AT_RISK',    label: '🟤 متوسط معرض'   },
  { value: 'OTHER',          label: '⚫ أخرى'           },
]

const TYPE_OPTIONS = [
  { value: 'retail',      label: 'تجزئة' },
  { value: 'wholesale',   label: 'جملة'  },
  { value: 'distributor', label: 'موزع'  },
]

// ─── Filter Defaults ──────────────────────────────────────────

const FILTER_DEFAULTS = {
  dateFrom:      '',
  dateTo:        '',
  repId:         '',
  governorateId: '',
  cityId:        '',
  priority:      '',
  customerType:  '',
  activeOnly:    true,
}

// ─── Sub-components ───────────────────────────────────────────

function PriorityBadge({ label }: { label: PriorityLabel }) {
  const cfg = PRIORITY[label]
  return (
    <span className={`rp-badge rp-badge--${cfg.cssClass}`}>
      {cfg.icon} {cfg.label}
    </span>
  )
}

function RecencyBadge({ days }: { days: number | null }) {
  const cls = days === null ? 'rp-recency--none'
    : days > 90  ? 'rp-recency--lost'
    : days > 45  ? 'rp-recency--risk'
    :               'rp-recency--ok'
  return (
    <span className={`rp-recency ${cls}`} style={{ direction: 'ltr', display: 'inline-block' }}>
      {fmtRecency(days)}
    </span>
  )
}

function BalanceCell({ balance }: { balance: number }) {
  if (balance === 0) return <span className="rp-balance--zero">—</span>
  return (
    <span className={balance > 0 ? 'rp-balance--debt' : 'rp-balance--credit'}>
      {balance < 0 && '('}
      {fmtCur(Math.abs(balance))}
      {balance < 0 && ')'}
    </span>
  )
}

function SkeletonRows({ count = 5 }: { count?: number }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)', padding: 'var(--space-4)' }}>
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="skeleton-row" style={{ height: '48px', borderRadius: '8px' }} />
      ))}
    </div>
  )
}

// ─── KPI Strip ────────────────────────────────────────────────

function KpiStrip({ summary, isLoading }: {
  summary: ReengagementSummary | undefined
  isLoading: boolean
}) {
  // ترتيب الأولوية: الأهم (يمين RTL) → الأقل إلحاحاً (يسار)
  // Champion Lost أعلى أولوية → يظهر في أقصى اليمين (أول بطاقة)
  const cards = [
    {
      label: 'Champion Lost', sublabel: 'عملاء مميزون خمدوا',
      count: summary?.champion_lost_count ?? null,
      text: null as string | null,
      accent: PRIORITY.CHAMPION_LOST.accent, icon: '🔴',
    },
    {
      label: 'تراجع عالي', sublabel: 'عملاء في خطر',
      count: summary?.declining_high_count ?? null,
      text: null as string | null,
      accent: PRIORITY.DECLINING_HIGH.accent, icon: '🟠',
    },
    {
      label: 'متوسط خامد', sublabel: 'فرصة متوسطة',
      count: summary?.mid_lost_count ?? null,
      text: null as string | null,
      accent: PRIORITY.MID_LOST.accent, icon: '🟡',
    },
    {
      label: 'إجمالي العملاء', sublabel: 'في قاعدة البيانات',
      count: summary?.total_customers ?? null,
      text: null as string | null,
      accent: '#0284c7', icon: '👥',
    },
    {
      label: 'صافي الأرصدة',
      sublabel: summary && summary.total_outstanding >= 0 ? 'إجمالي مديونية' : 'رصيد دائن صاف',
      count: null as number | null,
      text: summary ? fmtCur(Math.abs(summary.total_outstanding)) : null,
      accent: summary && summary.total_outstanding < 0 ? '#16a34a' : '#0284c7',
      icon: summary && summary.total_outstanding < 0 ? '🟢' : '💰',
    },
  ]

  return (
    <div className="rp-kpi-grid">
      {cards.map((card, i) => (
        <div
          key={i}
          className="edara-card rp-kpi-card"
          style={{ '--rp-accent': card.accent, borderTop: `3px solid ${card.accent}` } as React.CSSProperties}
        >
          <div className="rp-kpi-icon">{card.icon}</div>
          <div className="rp-kpi-label">{card.label}</div>
          {isLoading ? (
            <div className="skeleton-row rp-kpi-skeleton" />
          ) : (
            <div className="rp-kpi-value rp-kpi-value--accent">
              {card.count != null ? FMT.format(card.count) : (card.text ?? '—')}
            </div>
          )}
          <div className="rp-kpi-sublabel">{card.sublabel}</div>
        </div>
      ))}
    </div>
  )
}

// ─── Mobile Card ──────────────────────────────────────────────

function MobileCard({ row, canSee360 }: { row: ReengagementRow; canSee360: boolean }) {
  const cfg = PRIORITY[row.priority_label]
  return (
    <div className="rp-mcard">

      {/* خط لوني يعكس الأولوية */}
      <div className="rp-mcard-stripe" style={{ background: cfg.accent }} />

      <div className="rp-mcard-body">

        {/* Row 1: الاسم + priority badge */}
        <div className="rp-mcard-row1">
          <div className="rp-mcard-identity">
            <div className="rp-mcard-name">{row.customer_name}</div>
            <div className="rp-mcard-sub">
              {row.customer_code && <span className="rp-mcard-code">{row.customer_code}</span>}
              {row.customer_code && <span> · </span>}
              <span>{row.rep_name || 'بدون مندوب'}</span>
            </div>
          </div>
          <div style={{ flexShrink: 0 }}>
            <PriorityBadge label={row.priority_label} />
          </div>
        </div>

        {/* Row 2: Metrics 2×2 */}
        <div className="rp-mcard-metrics">
          <div className="rp-metric">
            <div className="rp-metric-label">القيمة التاريخية</div>
            <div className="rp-metric-value rp-metric-ltr rp-metric-strong">
              {fmtCur(row.historical_revenue)}
            </div>
            <div className="rp-metric-sub">{row.order_count} طلب</div>
          </div>
          <div className="rp-metric">
            <div className="rp-metric-label">آخر شراء</div>
            <RecencyBadge days={row.recency_days} />
            {row.last_order_date && (
              <div className="rp-metric-sub">
                {new Date(row.last_order_date).toLocaleDateString('en-GB')}
              </div>
            )}
          </div>
          <div className="rp-metric">
            <div className="rp-metric-label">الرصيد</div>
            <div className="rp-metric-value rp-metric-ltr">
              <BalanceCell balance={row.outstanding_balance} />
            </div>
          </div>
          <div className="rp-metric">
            <div className="rp-metric-label">المنطقة</div>
            <div className="rp-metric-value rp-metric-geo">
              {row.governorate_name || row.city_name || '—'}
            </div>
          </div>
        </div>

        {/* Row 3: CTA */}
        {canSee360 && (
          <Link
            to={`/customers/${row.customer_id}`}
            className="rp-mcard-cta"
            style={{ '--rp-cta-color': cfg.accent } as React.CSSProperties}
          >
            <ExternalLink size={15} aria-hidden="true" />
            عرض الملف الكامل 360°
          </Link>
        )}
      </div>
    </div>
  )
}

// ─── Main Page ────────────────────────────────────────────────

export default function CustomerReengagementPage() {
  const { setTitle } = usePageTitle()
  useEffect(() => setTitle('إعادة الاستهداف'), [])

  const can = useAuthStore(s => s.can)
  const canSee360 = can('customers.read') || can('customers.read_all')

  // ── Filter State (URL-synced) ─────────────────────────────
  const { filters, setFilter, setFilters, reset, activeCount } = useFilterState({
    defaults: FILTER_DEFAULTS,
    urlSync:  true,
    countFields: ['repId', 'governorateId', 'cityId', 'priority', 'customerType', 'dateFrom', 'dateTo'],
  })

  // ── Reference Data ────────────────────────────────────────
  const { data: governorates = [] } = useGovernorates()
  const { data: cities = [] }       = useCities(filters.governorateId || undefined)
  const { data: profiles = [] }     = useProfiles()

  function handleGovernorateChange(govId: string) {
    setFilters({ governorateId: govId, cityId: '' })
  }

  // ── FilterBar options ─────────────────────────────────────
  const govOptions = useMemo(() =>
    governorates.map(g => ({ value: g.id, label: g.name })),
    [governorates]
  )
  const cityOptions = useMemo(() =>
    cities.map(c => ({ value: c.id, label: c.name })),
    [cities]
  )
  const repOptions = useMemo(() =>
    profiles.map(p => ({ value: p.id, label: p.full_name })),
    [profiles]
  )

  // ── Data Queries ──────────────────────────────────────────
  const dataFilters = {
    dateFrom:      filters.dateFrom      || undefined,
    dateTo:        filters.dateTo        || undefined,
    repId:         filters.repId         || undefined,
    governorateId: filters.governorateId || undefined,
    cityId:        filters.cityId        || undefined,
    priority:      (filters.priority || undefined) as PriorityLabel | undefined,
    customerType:  filters.customerType  || undefined,
    activeOnly:    filters.activeOnly,
    limit:         100,
  }

  const { data: rows = [], isLoading: listLoading, error: listError } =
    useReengagementList(dataFilters)
  const { data: summary, isLoading: summaryLoading } =
    useReengagementSummary(dataFilters)

  // ── FilterBar Stats ───────────────────────────────────────
  const filterStats = useMemo(() => [
    {
      label:   'عميل مستهدف',
      value:   listLoading ? '...' : rows.length >= 100 ? '100+' : rows.length.toLocaleString('en-US'),
      variant: 'info' as const,
      loading: listLoading,
    },
    ...(summary && !summaryLoading ? [
      {
        label:   'Champion Lost',
        value:   FMT.format(summary.champion_lost_count),
        variant: 'danger' as const,
      },
      {
        label:   'في تراجع',
        value:   FMT.format(summary.declining_high_count),
        variant: 'warning' as const,
      },
    ] : []),
  ], [rows.length, listLoading, summary, summaryLoading])

  // ── Error State ───────────────────────────────────────────
  if (listError) {
    const msg = (listError as Error).message || ''
    const unauthorized = msg.includes('reengagement_unauthorized')
    return (
      <div className="rp-error-state">
        <div className="rp-error-title">
          {unauthorized ? 'لا تملك صلاحية عرض هذه الصفحة' : 'خطأ في جلب البيانات'}
        </div>
        {!unauthorized && (
          <div className="rp-error-detail">{msg}</div>
        )}
      </div>
    )
  }

  return (
    <div className="page-container animate-enter">

      {/* ── Page Header ──────────────────────────────────── */}
      <PageHeader
        title="أولويات إعادة الاستهداف"
        subtitle={
          listLoading
            ? 'جاري التحميل...'
            : `${rows.length >= 100 ? 'أول 100' : rows.length.toLocaleString('en-US')} عميل مُحدَّد`
        }
      />

      {/* ── KPI Strip ──────────────────────────────────── */}
      <KpiStrip summary={summary} isLoading={summaryLoading} />

      {/* ── FilterBar الاحترافي ──────────────────────────── */}
      <FilterBar
        title="فلاتر إعادة الاستهداف"
        activeCount={activeCount}
        onReset={reset}
        stats={filterStats}
      >
        {/* الأولوية */}
        <FilterBar.Select
          label="الأولوية"
          value={filters.priority}
          onChange={v => setFilter('priority', v)}
          options={PRIORITY_OPTIONS}
          allLabel="كل الأولويات"
        />

        {/* نوع العميل */}
        <FilterBar.Select
          label="نوع العميل"
          value={filters.customerType}
          onChange={v => setFilter('customerType', v)}
          options={TYPE_OPTIONS}
          allLabel="كل الأنواع"
        />

        {/* المندوب */}
        <FilterBar.Select
          label="المندوب"
          value={filters.repId}
          onChange={v => setFilter('repId', v)}
          options={repOptions}
          allLabel="كل المندوبين"
        />

        {/* المحافظة */}
        <FilterBar.Select
          label="المحافظة"
          value={filters.governorateId}
          onChange={handleGovernorateChange}
          options={govOptions}
          allLabel="كل المحافظات"
        />

        {/* المدينة — تظهر فقط عند اختيار محافظة */}
        {filters.governorateId && cityOptions.length > 0 && (
          <FilterBar.Select
            label="المدينة"
            value={filters.cityId}
            onChange={v => setFilter('cityId', v)}
            options={cityOptions}
            allLabel="كل المدن"
          />
        )}

        {/* الفترة الزمنية للقيمة التاريخية */}
        <FilterBar.DateRange
          label="القيمة التاريخية"
          from={filters.dateFrom}
          to={filters.dateTo}
          onFromChange={v => setFilter('dateFrom', v)}
          onToChange={v => setFilter('dateTo', v)}
          fullWidth
        />

        {/* النشطون فقط */}
        <FilterBar.Toggle
          label="النشطون فقط"
          value={filters.activeOnly}
          onChange={v => setFilter('activeOnly', v)}
        />
      </FilterBar>

      {/* ── Data Table Card ─────────────────────────────── */}
      <div className="rp-table-card edara-card">

        {/* Table sub-header */}
        <div className="rp-table-header">
          <span className="rp-table-title">قائمة العملاء — مرتبة بالأولوية</span>
          {!listLoading && (
            <span className="rp-table-count">
              {rows.length} عميل {rows.length >= 100 ? '(أول 100)' : ''}
            </span>
          )}
        </div>

        {/* States */}
        {listLoading ? (
          <SkeletonRows count={8} />
        ) : rows.length === 0 ? (
          <div className="rp-empty">
            <Users size={40} className="rp-empty-icon" aria-hidden="true" />
            <div className="rp-empty-title">لا يوجد عملاء يطابقون الفلاتر المحددة</div>
            <div className="rp-empty-hint">جرّب تغيير الفلاتر أو إلغاء تفعيل «النشطون فقط»</div>
          </div>
        ) : (
          <>
            {/* Desktop Table */}
            <div className="rp-desktop-table">
              <table className="rp-table">
                <thead className="rp-thead">
                  <tr>
                    {[
                      { label: 'العميل',           w: 'auto'  },
                      { label: 'الأولوية',          w: '140px' },
                      { label: 'القيمة التاريخية', w: '140px' },
                      { label: 'آخر شراء',          w: '110px' },
                      { label: 'الرصيد',            w: '120px' },
                      { label: 'المندوب',           w: '110px' },
                      { label: 'المحافظة',          w: '100px' },
                      { label: '',                  w: '80px'  },
                    ].map(({ label, w }) => (
                      <th key={label} className="rp-th" style={{ width: w, minWidth: w === 'auto' ? '160px' : undefined }}>{label}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {rows.map(row => (
                    <tr key={row.customer_id} className="rp-tr">
                      <td className="rp-td">
                        <div className="rp-customer-name">{row.customer_name}</div>
                        <div className="rp-customer-meta">
                          {row.customer_code && `${row.customer_code} · `}
                          {row.customer_type === 'retail' ? 'تجزئة'
                            : row.customer_type === 'wholesale' ? 'جملة' : 'موزع'}
                        </div>
                      </td>
                      <td className="rp-td">
                        <PriorityBadge label={row.priority_label} />
                      </td>
                      <td className="rp-td rp-td--ltr">
                        <span className="rp-amount">{fmtCur(row.historical_revenue)}</span>
                        <div className="rp-customer-meta">{row.order_count} طلب</div>
                      </td>
                      <td className="rp-td">
                        <RecencyBadge days={row.recency_days} />
                        {row.last_order_date && (
                          <div className="rp-customer-meta">
                            {new Date(row.last_order_date).toLocaleDateString('en-GB')}
                          </div>
                        )}
                      </td>
                      <td className="rp-td rp-td--ltr">
                        <BalanceCell balance={row.outstanding_balance} />
                      </td>
                      <td className="rp-td rp-td--secondary">
                        {row.rep_name || <span className="rp-unassigned">غير معين</span>}
                      </td>
                      <td className="rp-td rp-td--secondary">
                        {row.governorate_name || row.city_name || '—'}
                      </td>
                      <td className="rp-td">
                        {canSee360 && (
                          <Link to={`/customers/${row.customer_id}`} className="rp-360-btn">
                            <ExternalLink size={11} aria-hidden="true" />
                            360°
                          </Link>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Mobile Cards */}
            <div className="rp-mobile-cards">
              {rows.map(row => (
                <MobileCard key={row.customer_id} row={row} canSee360={canSee360} />
              ))}
            </div>
          </>
        )}
      </div>

      {/* Scoped Styles */}
      <style>{STYLES}</style>
    </div>
  )
}

// ─── CSS Styles ───────────────────────────────────────────────

const STYLES = `
/* ── KPI Grid ────────────────────────────────────── */
.rp-kpi-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
  gap: var(--space-3);
}
@media (max-width: 480px) {
  .rp-kpi-grid { grid-template-columns: repeat(2, 1fr); }
}
.rp-kpi-card {
  padding: var(--space-4);
  display: flex;
  flex-direction: column;
  gap: 2px;
  border-radius: var(--radius-lg, 12px);
  border: 1px solid var(--border-primary);
  background: var(--bg-surface);
  box-shadow: var(--shadow-sm);
  transition: box-shadow 0.2s, transform 0.2s;
}
.rp-kpi-card:hover { box-shadow: var(--shadow-md); transform: translateY(-1px); }
.rp-kpi-icon  { font-size: 1.1rem; margin-bottom: var(--space-1); }
.rp-kpi-label { font-size: var(--text-xs); color: var(--text-secondary); font-weight: 600; line-height: 1.4; }
.rp-kpi-value {
  font-size: var(--text-xl);
  font-weight: 700;
  direction: ltr;
  text-align: start;
  margin: var(--space-1) 0;
  line-height: 1.2;
  color: var(--text-primary);
}
/* يستخدم CSS custom property --rp-accent المُضاف على الـ element مباشرة */
.rp-kpi-value--accent { color: var(--rp-accent, var(--color-primary)); }
.rp-kpi-sublabel { font-size: 11px; color: var(--text-muted); }
.rp-kpi-skeleton { height: 28px; width: 65%; border-radius: 6px; margin: var(--space-1) 0; }

/* ── Table Card ──────────────────────────────────── */
.rp-table-card {
  overflow: hidden;
  border-radius: var(--radius-lg, 12px);
  border: 1px solid var(--border-primary);
  background: var(--bg-surface);
  box-shadow: var(--shadow-sm);
}
.rp-table-header {
  padding: var(--space-4) var(--space-5);
  border-bottom: 1px solid var(--border-primary);
  display: flex;
  justify-content: space-between;
  align-items: center;
  flex-wrap: wrap;
  gap: var(--space-2);
}
.rp-table-title { font-weight: 700; font-size: var(--text-base); color: var(--text-primary); }
.rp-table-count { font-size: var(--text-xs); color: var(--text-muted); }

/* ── Responsive Switch ───────────────────────────── */
.rp-desktop-table { display: block; overflow-x: auto; }
.rp-mobile-cards  { display: none; }
@media (max-width: 768px) {
  .rp-desktop-table { display: none; }
  .rp-mobile-cards  { display: flex; flex-direction: column; }
}

/* ── Table ───────────────────────────────────────── */
.rp-table {
  width: 100%;
  border-collapse: collapse;
  font-size: var(--text-sm);
  font-family: var(--font-sans);
  table-layout: fixed;
}
.rp-thead th {
  position: sticky;
  top: 0;
  z-index: 1;
}
.rp-th {
  padding: 10px 14px;
  text-align: start;     /* RTL-correct: يمين في RTL، يسار في LTR */
  font-weight: 600;
  color: var(--text-secondary);
  font-size: var(--text-xs);
  background: var(--bg-surface-2);
  border-bottom: 2px solid var(--border-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.rp-tr { border-bottom: 1px solid var(--border-primary); transition: background 0.1s; }
.rp-tr:hover { background: var(--bg-hover); }
.rp-tr:last-child { border-bottom: none; }
.rp-td { padding: 10px 14px; vertical-align: middle; }
.rp-td--ltr { direction: ltr; text-align: right; }
.rp-td--secondary { font-size: var(--text-xs); color: var(--text-secondary); }
.rp-customer-name { font-weight: 700; font-size: var(--text-sm); color: var(--text-primary); margin-bottom: 2px; }
.rp-customer-meta { font-size: 11px; color: var(--text-muted); }
.rp-amount { font-weight: 700; color: var(--text-primary); font-size: var(--text-xs); }
.rp-unassigned { color: var(--text-muted); font-style: italic; }

/* ── 360 Button ──────────────────────────────────── */
.rp-360-btn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 5px 10px;
  border-radius: var(--radius-sm, 6px);
  border: 1px solid var(--border-primary);
  background: var(--bg-surface-2);
  color: var(--color-primary);
  font-size: var(--text-xs);
  font-weight: 600;
  text-decoration: none;
  white-space: nowrap;
  transition: background 0.15s, border-color 0.15s;
}
.rp-360-btn:hover { background: var(--color-primary-light); border-color: var(--color-primary); }

/* ── Balance ─────────────────────────────────────── */
.rp-balance--zero   { color: var(--text-muted); font-size: var(--text-xs); }
.rp-balance--debt   { font-weight: 600; font-size: var(--text-xs); color: var(--color-danger); }
.rp-balance--credit { font-weight: 600; font-size: var(--text-xs); color: var(--color-success); }

/* ── Recency ─────────────────────────────────────── */
.rp-recency        { font-weight: 600; font-size: var(--text-xs); }
.rp-recency--lost  { color: var(--color-danger); }
.rp-recency--risk  { color: var(--color-warning); }
.rp-recency--ok    { color: var(--color-success); }
.rp-recency--none  { color: var(--text-muted); }

/* ── Priority Badge — light + dark ──────────────── */
.rp-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 3px 10px;
  border-radius: 999px;
  font-size: var(--text-xs);
  font-weight: 700;
  white-space: nowrap;
  border: 1px solid;
}
.rp-badge--champion-lost  { background: #fef2f2; color: #991b1b; border-color: #fecaca; }
.rp-badge--declining-high { background: #fffbeb; color: #92400e; border-color: #fde68a; }
.rp-badge--mid-lost       { background: #fef3c7; color: #78350f; border-color: #fde68a; }
.rp-badge--mid-at-risk    { background: #fefce8; color: #713f12; border-color: #fef08a; }
.rp-badge--other          { background: var(--bg-surface-2); color: var(--text-secondary); border-color: var(--border-primary); }
[data-theme="dark"] .rp-badge--champion-lost  { background: rgba(220,38,38,0.15);  color: #fca5a5; border-color: rgba(220,38,38,0.3); }
[data-theme="dark"] .rp-badge--declining-high { background: rgba(217,119,6,0.15);  color: #fcd34d; border-color: rgba(217,119,6,0.3); }
[data-theme="dark"] .rp-badge--mid-lost       { background: rgba(146,64,14,0.15);  color: #fde68a; border-color: rgba(146,64,14,0.3); }
[data-theme="dark"] .rp-badge--mid-at-risk    { background: rgba(120,53,15,0.15);  color: #fef08a; border-color: rgba(120,53,15,0.3); }

/* ── Empty / Error States ────────────────────────── */
.rp-empty { padding: var(--space-12) var(--space-6); text-align: center; display: flex; flex-direction: column; align-items: center; gap: var(--space-2); }
.rp-empty-icon  { color: var(--text-muted); margin-bottom: var(--space-2); }
.rp-empty-title { font-size: var(--text-sm); font-weight: 700; color: var(--text-primary); }
.rp-empty-hint  { font-size: var(--text-xs); color: var(--text-muted); }
.rp-error-state { padding: var(--space-8); text-align: center; }
.rp-error-title { font-size: var(--text-sm); font-weight: 700; color: var(--color-danger); }
.rp-error-detail { font-size: var(--text-xs); color: var(--text-muted); margin-top: var(--space-2); direction: ltr; }

/* ── Mobile Cards ────────────────────────────────── */
.rp-mcard {
  display: flex;
  flex-direction: row;
  border-bottom: 1px solid var(--border-primary);
  overflow: hidden;
}
.rp-mcard:last-child { border-bottom: none; }

/* الخط اللوني الجانبي */
.rp-mcard-stripe {
  width: 4px;
  flex-shrink: 0;
  border-radius: 0;
}

/* Body يأخذ باقي العرض */
.rp-mcard-body {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  padding: var(--space-4);
}

/* Row 1: الاسم + badge */
.rp-mcard-row1 {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: var(--space-2);
}
.rp-mcard-identity { flex: 1; min-width: 0; }
.rp-mcard-name {
  font-weight: 700;
  font-size: var(--text-sm);
  color: var(--text-primary);
  margin-bottom: 2px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.rp-mcard-sub  {
  font-size: 11px;
  color: var(--text-muted);
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 2px;
}
.rp-mcard-code {
  font-family: monospace;
  font-size: 10px;
  color: var(--text-secondary);
  background: var(--bg-surface-2);
  padding: 0 4px;
  border-radius: 3px;
}

/* Metrics grid 2×2 */
.rp-mcard-metrics {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: var(--space-2) var(--space-3);
  background: var(--bg-surface-2);
  border-radius: var(--radius-sm, 6px);
  padding: var(--space-3);
}
.rp-metric { display: flex; flex-direction: column; gap: 2px; }
.rp-metric-label { font-size: 11px; color: var(--text-muted); white-space: nowrap; }
.rp-metric-value {
  font-weight: 600;
  font-size: var(--text-sm);
  color: var(--text-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.rp-metric-sub  { font-size: 10px; color: var(--text-muted); }
.rp-metric-ltr  { direction: ltr; }
.rp-metric-strong { font-weight: 700; font-size: var(--text-base); }
.rp-metric-geo  { font-size: var(--text-xs); }

/* CTA — يستخدم --rp-cta-color للـ accent */
.rp-mcard-cta {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: var(--space-2);
  padding: 10px var(--space-4);
  border-radius: var(--radius-md, 8px);
  border: 1.5px solid color-mix(in srgb, var(--rp-cta-color, var(--color-primary)) 40%, transparent);
  background: color-mix(in srgb, var(--rp-cta-color, var(--color-primary)) 8%, var(--bg-surface));
  color: var(--rp-cta-color, var(--color-primary));
  font-size: var(--text-sm);
  font-weight: 700;
  text-decoration: none;
  min-height: 44px;
  transition: background 0.15s, border-color 0.15s;
}
.rp-mcard-cta:hover {
  background: color-mix(in srgb, var(--rp-cta-color, var(--color-primary)) 16%, var(--bg-surface));
}


/* ── Mobile bottom safe area ─────────────────────── */
@media (max-width: 768px) {
  .page-container { padding-bottom: max(var(--bottom-nav-height, 64px), env(safe-area-inset-bottom, 16px)); }
}
`
