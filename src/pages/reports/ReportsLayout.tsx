import { NavLink, Outlet } from 'react-router-dom'
import { usePageTitle } from '@/components/layout/PageTitleContext'
import { useEffect } from 'react'
import { BarChart3, TrendingUp, Wallet, Users2, LayoutDashboard, Package, AlertTriangle, MapPin, Target, UserCheck, LineChart } from 'lucide-react'
import AnalyticsGate from '@/components/reports/AnalyticsGate'

const TABS = [
  { to: '/reports/overview', label: 'نظرة عامة', icon: LayoutDashboard },
  { to: '/reports/sales', label: 'المبيعات', icon: TrendingUp },
  { to: '/reports/receivables', label: 'المستحقات', icon: BarChart3 },
  { to: '/reports/treasury', label: 'الخزينة', icon: Wallet },
  { to: '/reports/customers',         label: 'العملاء',        icon: Users2        },
  { to: '/reports/reps',              label: 'أداء المندوبين', icon: UserCheck     },
  { to: '/reports/products',          label: 'أداء المنتجات',  icon: Package       },
  { to: '/reports/churn-risk',        label: 'خطر الخمود',      icon: AlertTriangle },
  { to: '/reports/geography',         label: 'جغرافى',          icon: MapPin        },
  { to: '/reports/target-attainment', label: 'إنجاز الأهداف',   icon: Target        },
  { to: '/reports/profitability',     label: 'الربحية',         icon: LineChart     },
]

export default function ReportsLayout() {
  const { setTitle } = usePageTitle()
  useEffect(() => setTitle('التقارير'), [])

  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%', gap: 0 }}>
      {/* Sub-nav tabs */}
      <div style={{
        background: 'var(--bg-surface)',
        borderBottom: '1px solid var(--border-primary)',
        padding: '0 var(--space-4)',
        display: 'flex',
        gap: '2px',
        overflowX: 'auto',
        scrollbarWidth: 'none',
        flexShrink: 0,
        position: 'sticky',
        top: 0,
        zIndex: 'var(--z-sticky)',
      }}>
        {TABS.map(t => {
          const Icon = t.icon
          return (
            <NavLink
              key={t.to}
              to={t.to}
              style={({ isActive }) => ({
                display: 'flex',
                alignItems: 'center',
                gap: '6px',
                padding: '12px 16px',
                fontSize: 'var(--text-sm)',
                fontWeight: 500,
                color: isActive ? 'var(--color-primary)' : 'var(--text-secondary)',
                borderBottom: `2px solid ${isActive ? 'var(--color-primary)' : 'transparent'}`,
                textDecoration: 'none',
                whiteSpace: 'nowrap',
                transition: 'color 0.15s',
                flexShrink: 0,
              })}
            >
              <Icon size={14} />
              {t.label}
            </NavLink>
          )
        })}
      </div>

      {/* Page content — gated behind analytics availability probe */}
      <div style={{ flex: 1, padding: 'var(--space-6)', display: 'flex', flexDirection: 'column', gap: 'var(--space-6)' }}>
        <AnalyticsGate>
          <Outlet />
        </AnalyticsGate>
      </div>

      <style>{`
        @keyframes shimmer {
          0% { background-position: 200% 0; }
          100% { background-position: -200% 0; }
        }
        @keyframes spin {
          to { transform: rotate(360deg); }
        }
        .animate-spin { animation: spin 1s linear infinite; }
        .edara-card:hover {
          box-shadow: var(--shadow-md);
          transform: translateY(-1px);
        }
        .report-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
          gap: var(--space-4);
        }
        .report-grid-2 {
          display: grid;
          grid-template-columns: repeat(2, 1fr);
          gap: var(--space-4);
        }
        @media (max-width: 768px) {
          .report-grid-2 { grid-template-columns: 1fr; }
          .report-grid { grid-template-columns: 1fr; }
        }
      `}</style>
    </div>
  )
}
