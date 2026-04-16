/**
 * CreditKPIBar — شريط مؤشرات المحفظة الائتمانية (6 مؤشرات)
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
      id:      'kpi-total-limit',
      label:   'إجمالي الحد',
      value:   formatNumber(kpis?.totalLimit ?? 0),
      unit:    'ج.م',
      accent:  '#2563eb',
      bg:      'rgba(37,99,235,0.06)',
      border:  'rgba(37,99,235,0.15)',
      icon:    '🏦',
    },
    {
      id:      'kpi-total-used',
      label:   'إجمالي المستخدم',
      value:   formatNumber(kpis?.totalUsed ?? 0),
      unit:    'ج.م',
      accent:  '#d97706',
      bg:      'rgba(217,119,6,0.06)',
      border:  'rgba(217,119,6,0.15)',
      icon:    '📊',
      sub:     `${totalUsedPct}% من الحد`,
    },
    {
      id:      'kpi-total-available',
      label:   'إجمالي المتاح',
      value:   formatNumber(kpis?.totalAvailable ?? 0),
      unit:    'ج.م',
      accent:  '#16a34a',
      bg:      'rgba(22,163,74,0.06)',
      border:  'rgba(22,163,74,0.15)',
      icon:    '✅',
    },
    {
      id:      'kpi-exceeded',
      label:   'تجاوزوا الحد',
      value:   formatNumber(kpis?.countExceeded ?? 0),
      unit:    'عميل',
      accent:  '#dc2626',
      bg:      'rgba(220,38,38,0.06)',
      border:  'rgba(220,38,38,0.15)',
      icon:    '⛔',
      urgent:  (kpis?.countExceeded ?? 0) > 0,
    },
    {
      id:      'kpi-near-limit',
      label:   'قريبون من الحد',
      value:   formatNumber(kpis?.countNearLimit ?? 0),
      unit:    'عميل',
      accent:  '#d97706',
      bg:      'rgba(217,119,6,0.06)',
      border:  'rgba(217,119,6,0.15)',
      icon:    '⚠️',
    },
    {
      id:      'kpi-total-credit',
      label:   'العملاء الائتمانيون',
      value:   formatNumber(kpis?.totalCreditCustomers ?? 0),
      unit:    'عميل',
      accent:  '#0284c7',
      bg:      'rgba(2,132,199,0.06)',
      border:  'rgba(2,132,199,0.15)',
      icon:    '👥',
    },
  ]

  return (
    <div
      id="credit-kpi-bar"
      style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(6, 1fr)',
        gap: 'var(--space-3)',
        marginBottom: 'var(--space-4)',
      }}
    >
      {cards.map(card => (
        <div
          key={card.id}
          id={card.id}
          style={{
            background:   card.bg,
            border:       `1px solid ${card.border}`,
            borderRadius: 12,
            padding:      '12px 14px',
            display:      'flex',
            flexDirection: 'column',
            gap:          4,
            position:     'relative',
            overflow:     'hidden',
            transition:   'transform 0.15s, box-shadow 0.15s',
          }}
          className="credit-kpi-card"
        >
          {/* Urgent pulse */}
          {card.urgent && (
            <span style={{
              position: 'absolute', top: 6, insetInlineStart: 6,
              width: 8, height: 8, borderRadius: '50%',
              background: card.accent,
              animation: 'kpi-pulse 1.5s ease-in-out infinite',
            }} />
          )}

          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span style={{ fontSize: '1rem' }}>{card.icon}</span>
            <span style={{
              fontSize:   'var(--text-xs)',
              color:      'var(--text-secondary)',
              fontWeight: 600,
            }}>
              {card.label}
            </span>
          </div>

          <div style={{ display: 'flex', alignItems: 'baseline', gap: 4 }}>
            <span style={{
              fontSize:            '1.35rem',
              fontWeight:          800,
              color:               card.accent,
              fontVariantNumeric:  'tabular-nums',
              letterSpacing:       '-0.5px',
              lineHeight:          1.1,
            }}>
              {card.value}
            </span>
            <span style={{
              fontSize:   '0.68rem',
              color:      'var(--text-muted)',
              fontWeight: 500,
            }}>
              {card.unit}
            </span>
          </div>

          {card.sub && (
            <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
              {card.sub}
            </span>
          )}
        </div>
      ))}

      <style>{`
        .credit-kpi-card:hover {
          transform: translateY(-1px);
          box-shadow: var(--shadow-md);
        }
        @keyframes kpi-pulse {
          0%, 100% { transform: scale(1); opacity: 1; }
          50%       { transform: scale(1.4); opacity: 0.6; }
        }
        @media (max-width: 900px) {
          #credit-kpi-bar {
            grid-template-columns: repeat(3, 1fr);
          }
        }
        @media (max-width: 600px) {
          #credit-kpi-bar {
            grid-template-columns: repeat(2, 1fr);
          }
        }
      `}</style>
    </div>
  )
}

function CreditKPIBarSkeleton() {
  return (
    <div style={{
      display: 'grid',
      gridTemplateColumns: 'repeat(6, 1fr)',
      gap: 'var(--space-3)',
      marginBottom: 'var(--space-4)',
    }}>
      {Array.from({ length: 6 }).map((_, i) => (
        <div key={i} className="skeleton" style={{ height: 80, borderRadius: 12 }} />
      ))}
    </div>
  )
}
