/**
 * CreditKPIBar — شريط مؤشرات المحفظة الائتمانية (6 مؤشرات)
 *
 * التصحيح الجذري (v2):
 *   السبب الجذري لعدم التجاوب: inline style تتفوق دائماً على CSS <style> قواعد.
 *   الحل: gridTemplateColumns مُدارة حصراً عبر CSS class — لا inline style.
 *
 * المؤشرات:
 *   - إجمالي الحد الائتماني
 *   - إجمالي الرصيد المستخدم
 *   - إجمالي المتاح
 *   - عدد المتجاوزين للحد
 *   - عدد القريبين من الحد (≥80%)
 *   - إجمالي العملاء الائتمانيين
 *
 * المصدر: getCreditPortfolioKPIs() — من جدول customers فقط (لا SUM على customer_ledger)
 * staleTime: 5 دقائق — يُعاد تحميله بعد أي حفظ
 */

import { useQuery } from '@tanstack/react-query'
import { getCreditPortfolioKPIs } from '@/lib/services/credit'
import { formatNumber } from '@/lib/utils/format'

// ─────────────────────────────────────────────────────────────
// Shared styles — مشتركة بين الـ Bar والـ Skeleton
// ─────────────────────────────────────────────────────────────
const KPI_STYLES = `
  /* ── KPI Grid ─────────────────────────────────────────────── */
  /* IMPORTANT: gridTemplateColumns مُدارة هنا فقط — لا inline style */
  .credit-kpi-grid {
    display: grid;
    grid-template-columns: repeat(6, 1fr);
    gap: var(--space-3);
    margin-bottom: var(--space-4);
  }
  @media (max-width: 900px) {
    .credit-kpi-grid { grid-template-columns: repeat(3, 1fr); }
  }
  @media (max-width: 600px) {
    .credit-kpi-grid { grid-template-columns: repeat(2, 1fr); }
  }

  /* ── KPI Card ─────────────────────────────────────────────── */
  .credit-kpi-card {
    background:    var(--kpi-bg, transparent);
    border:        1px solid var(--kpi-border, var(--border-primary));
    border-radius: 12px;
    padding:       12px 14px;
    display:       flex;
    flex-direction: column;
    gap:           4px;
    position:      relative;
    overflow:      hidden;
    transition:    transform 0.15s, box-shadow 0.15s;
    min-height:    76px;
  }
  .credit-kpi-card:hover {
    transform:  translateY(-1px);
    box-shadow: var(--shadow-md);
  }

  /* Mobile: أصغر قليلاً لضمان قراءة أفضل في 2 columns */
  @media (max-width: 600px) {
    .credit-kpi-card {
      padding:    10px 12px;
      min-height: 70px;
    }
    .credit-kpi-label { font-size: 0.7rem !important; }
    .credit-kpi-value { font-size: 1.1rem  !important; }
    .credit-kpi-unit  { font-size: 0.62rem !important; }
  }

  /* ── Pulse animation ──────────────────────────────────────── */
  @keyframes kpi-pulse {
    0%, 100% { transform: scale(1);   opacity: 1;   }
    50%       { transform: scale(1.4); opacity: 0.6; }
  }
`

// ─────────────────────────────────────────────────────────────
// Component
// ─────────────────────────────────────────────────────────────
export default function CreditKPIBar() {
  const { data: kpis, isLoading } = useQuery({
    queryKey: ['credit-portfolio-kpis'],
    queryFn:  getCreditPortfolioKPIs,
    staleTime: 5 * 60_000,
  })

  if (isLoading) return <CreditKPIBarSkeleton />

  const totalUsedPct = kpis && kpis.totalLimit > 0
    ? Math.min(100, Math.round((kpis.totalUsed / kpis.totalLimit) * 100))
    : 0

  const cards = [
    {
      id:     'kpi-total-limit',
      label:  'إجمالي الحد',
      value:  formatNumber(kpis?.totalLimit ?? 0),
      unit:   'ج.م',
      accent: '#2563eb',
      bg:     'rgba(37,99,235,0.06)',
      border: 'rgba(37,99,235,0.15)',
      icon:   '🏦',
    },
    {
      id:     'kpi-total-used',
      label:  'إجمالي المستخدم',
      value:  formatNumber(kpis?.totalUsed ?? 0),
      unit:   'ج.م',
      accent: '#d97706',
      bg:     'rgba(217,119,6,0.06)',
      border: 'rgba(217,119,6,0.15)',
      icon:   '📊',
      sub:    `${totalUsedPct}% من الحد`,
    },
    {
      id:     'kpi-total-available',
      label:  'إجمالي المتاح',
      value:  formatNumber(kpis?.totalAvailable ?? 0),
      unit:   'ج.م',
      accent: '#16a34a',
      bg:     'rgba(22,163,74,0.06)',
      border: 'rgba(22,163,74,0.15)',
      icon:   '✅',
    },
    {
      id:     'kpi-exceeded',
      label:  'تجاوزوا الحد',
      value:  formatNumber(kpis?.countExceeded ?? 0),
      unit:   'عميل',
      accent: '#dc2626',
      bg:     'rgba(220,38,38,0.06)',
      border: 'rgba(220,38,38,0.15)',
      icon:   '⛔',
      urgent: (kpis?.countExceeded ?? 0) > 0,
    },
    {
      id:     'kpi-near-limit',
      label:  'قريبون من الحد',
      value:  formatNumber(kpis?.countNearLimit ?? 0),
      unit:   'عميل',
      accent: '#d97706',
      bg:     'rgba(217,119,6,0.06)',
      border: 'rgba(217,119,6,0.15)',
      icon:   '⚠️',
    },
    {
      id:     'kpi-total-credit',
      label:  'العملاء الائتمانيون',
      value:  formatNumber(kpis?.totalCreditCustomers ?? 0),
      unit:   'عميل',
      accent: '#0284c7',
      bg:     'rgba(2,132,199,0.06)',
      border: 'rgba(2,132,199,0.15)',
      icon:   '👥',
    },
  ]

  return (
    <>
      {/* ── Grid — gridTemplateColumns مُدارة بالكامل عبر CSS class ── */}
      <div id="credit-kpi-bar" className="credit-kpi-grid">
        {cards.map(card => (
          <div
            key={card.id}
            id={card.id}
            className="credit-kpi-card"
            style={{
              background: card.bg,
              border:     `1px solid ${card.border}`,
            }}
          >
            {/* Urgent pulse dot */}
            {card.urgent && (
              <span style={{
                position: 'absolute', top: 6, insetInlineStart: 6,
                width: 8, height: 8, borderRadius: '50%',
                background: card.accent,
                animation: 'kpi-pulse 1.5s ease-in-out infinite',
              }} />
            )}

            {/* Icon + Label */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <span style={{ fontSize: '1rem', flexShrink: 0 }}>{card.icon}</span>
              <span
                className="credit-kpi-label"
                style={{
                  fontSize:   'var(--text-xs)',
                  color:      'var(--text-secondary)',
                  fontWeight: 600,
                  lineHeight: 1.3,
                }}
              >
                {card.label}
              </span>
            </div>

            {/* Value + Unit */}
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 4, flexWrap: 'wrap' }}>
              <span
                className="credit-kpi-value"
                style={{
                  fontSize:           '1.35rem',
                  fontWeight:         800,
                  color:              card.accent,
                  fontVariantNumeric: 'tabular-nums',
                  letterSpacing:      '-0.5px',
                  lineHeight:         1.1,
                }}
              >
                {card.value}
              </span>
              <span
                className="credit-kpi-unit"
                style={{
                  fontSize:   '0.68rem',
                  color:      'var(--text-muted)',
                  fontWeight: 500,
                }}
              >
                {card.unit}
              </span>
            </div>

            {/* Sub text */}
            {card.sub && (
              <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                {card.sub}
              </span>
            )}
          </div>
        ))}
      </div>

      <style>{KPI_STYLES}</style>
    </>
  )
}

// ─────────────────────────────────────────────────────────────
// Skeleton — يشارك نفس CSS class لضمان تطابق التجاوب
// ─────────────────────────────────────────────────────────────
function CreditKPIBarSkeleton() {
  return (
    <>
      <div id="credit-kpi-bar" className="credit-kpi-grid">
        {Array.from({ length: 6 }).map((_, i) => (
          <div
            key={i}
            className="skeleton"
            style={{ height: 80, borderRadius: 12 }}
          />
        ))}
      </div>
      <style>{KPI_STYLES}</style>
    </>
  )
}
