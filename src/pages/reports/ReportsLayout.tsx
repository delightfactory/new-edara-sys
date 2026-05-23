import { NavLink, Outlet, useMatch } from 'react-router-dom'
import { usePageTitle } from '@/components/layout/PageTitleContext'
import { useEffect } from 'react'
import { BarChart3, TrendingUp, Wallet, Users2, LayoutDashboard, Package, AlertTriangle, MapPin, Target, UserCheck, LineChart, ShieldCheck, RefreshCcw } from 'lucide-react'
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
  { to: '/reports/credit-commitment', label: 'التزام المندوبين', icon: ShieldCheck    },
  { to: '/reports/reengagement',      label: 'إعادة الاستهداف', icon: RefreshCcw    },
  { to: '/reports/profitability',     label: 'الربحية',         icon: LineChart     },
]

export default function ReportsLayout() {
  const { setTitle } = usePageTitle()
  useEffect(() => setTitle('التقارير'), [])

  // الصفحات التشغيلية المستقلة عن analytics engine
  // تعمل دائماً بغض النظر عن حالة analytics — لا تمر بـ AnalyticsGate
  const isOperationalPage = !!useMatch('/reports/reengagement')

  return (
    <div className="reports-shell" style={{ display: 'flex', flexDirection: 'column', minHeight: '100%', gap: 0 }}>
      {/* Sub-nav tabs */}
      <div className="reports-tabs" style={{
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

      {/* Page content
          - الصفحات التشغيلية المستقلة: تعرض Outlet مباشرة
          - الصفحات Analytics: تمر بـ AnalyticsGate */}
      <div className="reports-content" style={{ flex: 1, padding: 'var(--space-6)', display: 'flex', flexDirection: 'column', gap: 'var(--space-6)' }}>
        {isOperationalPage ? (
          <Outlet />
        ) : (
          <AnalyticsGate>
            <Outlet />
          </AnalyticsGate>
        )}
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
        .reports-shell {
          width: 100%;
          max-width: 100%;
          min-width: 0;
          overflow-x: hidden;
        }
        .reports-shell *,
        .reports-shell *::before,
        .reports-shell *::after {
          box-sizing: border-box;
        }
        .reports-tabs {
          max-width: 100%;
          -webkit-overflow-scrolling: touch;
        }
        .reports-tabs::-webkit-scrollbar {
          display: none;
        }
        .reports-tabs a {
          min-height: 44px;
        }
        .reports-content,
        .reports-content > *,
        .reports-content > * > * {
          min-width: 0;
          max-width: 100%;
        }
        .reports-content h1,
        .reports-content h2,
        .reports-content p {
          overflow-wrap: anywhere;
        }
        .edara-card:hover {
          box-shadow: var(--shadow-md);
          transform: translateY(-1px);
        }
        .report-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(min(250px, 100%), 1fr));
          gap: var(--space-4);
          min-width: 0;
        }
        .report-grid-2 {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
          gap: var(--space-4);
          min-width: 0;
        }
        .reports-content .edara-card,
        .reports-content [style*="box-shadow"] {
          min-width: 0;
          max-width: 100%;
        }
        .reports-content table {
          min-width: max-content;
        }
        .reports-content td,
        .reports-content th {
          overflow-wrap: anywhere;
        }
        .reports-content .recharts-responsive-container {
          min-width: 0 !important;
          max-width: 100% !important;
        }
        .reports-content input,
        .reports-content select,
        .reports-content button {
          max-width: 100%;
        }
        .report-filter-bar {
          justify-content: flex-end;
        }
        .report-filter-presets {
          flex: 1 1 280px;
          justify-content: flex-end;
        }
        .report-filter-presets button {
          min-height: 32px;
        }
        .report-filter-dates {
          flex: 0 1 auto;
          flex-wrap: nowrap;
        }
        .report-filter-dates input {
          min-width: 0;
          width: 132px;
          direction: ltr;
        }
        .report-health-bar {
          min-width: 0;
          max-width: 100%;
          overflow: hidden;
        }
        .report-health-bar > * {
          min-width: 0;
        }
        .report-metric-card {
          overflow-wrap: anywhere;
        }
        .report-metric-head {
          flex-wrap: wrap;
        }
        @media (min-width: 1200px) {
          .reports-content {
            padding: var(--space-5) var(--space-6) !important;
          }
        }
        @media (max-width: 1024px) {
          .reports-content {
            padding: var(--space-4) !important;
            gap: var(--space-4) !important;
          }
          .report-filter-bar {
            width: 100%;
            justify-content: flex-start;
          }
          .report-grid {
            grid-template-columns: repeat(auto-fit, minmax(min(220px, 100%), 1fr));
          }
        }
        @media (max-width: 768px) {
          .reports-tabs {
            padding: 0 var(--space-2) !important;
          }
          .reports-tabs a {
            padding: 10px 12px !important;
            font-size: var(--text-xs) !important;
          }
          .reports-content {
            padding: var(--space-3) !important;
            gap: var(--space-4) !important;
          }
          .report-grid-2 { grid-template-columns: 1fr; }
          .report-grid { grid-template-columns: 1fr; }
          .reports-content h1 {
            font-size: var(--text-xl) !important;
            font-weight: 700 !important;
          }
          .report-filter-bar,
          .report-filter-presets,
          .report-filter-dates {
            width: 100%;
          }
          .report-filter-presets {
            flex: 1 1 100%;
            justify-content: flex-start;
          }
          .report-filter-dates {
            display: grid !important;
            grid-template-columns: auto minmax(0, 1fr) auto minmax(0, 1fr);
            align-items: center;
          }
          .report-filter-dates input {
            width: 100%;
          }
          .report-health-bar {
            padding: var(--space-3) !important;
          }
        }
        @media (max-width: 480px) {
          .reports-tabs a {
            padding: 9px 10px !important;
          }
          .reports-tabs svg {
            width: 13px;
            height: 13px;
          }
          .reports-content {
            padding: var(--space-2) !important;
          }
        }
      `}</style>
    </div>
  )
}
