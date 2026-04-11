import { NavLink, Outlet } from 'react-router-dom'
import { LayoutDashboard, Users, User, Package, Building2, Building, ShieldCheck } from 'lucide-react'

const PROFIT_TABS = [
  { to: '/reports/profitability', end: true, label: 'لوحة القيادة', icon: LayoutDashboard },
  { to: '/reports/profitability/products', label: 'المنتجات', icon: Package },
  { to: '/reports/profitability/customers', label: 'العملاء', icon: Users },
  { to: '/reports/profitability/reps', label: 'المندوبين', icon: User },
  { to: '/reports/profitability/branch-direct', label: 'مباشر الفروع', icon: Building },
  { to: '/reports/profitability/branch-final', label: 'نهائي الفروع', icon: Building2 },
  { to: '/reports/profitability/quality', label: 'جودة التوزيع', icon: ShieldCheck },
]

export default function ProfitabilityLayout() {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
      {/* Sub-sub-nav tabs for profitability */}
      <div style={{
        background: 'var(--bg-surface)',
        borderRadius: 'var(--radius-lg)',
        border: '1px solid var(--border-primary)',
        padding: '4px',
        display: 'flex',
        gap: '4px',
        overflowX: 'auto',
        scrollbarWidth: 'none',
      }}>
        {PROFIT_TABS.map(t => {
          const Icon = t.icon
          return (
            <NavLink
              key={t.to}
              to={t.to}
              end={t.end}
              style={({ isActive }) => ({
                display: 'flex',
                alignItems: 'center',
                gap: '6px',
                padding: '8px 16px',
                fontSize: 'var(--text-sm)',
                fontWeight: isActive ? 600 : 500,
                color: isActive ? 'var(--color-primary-dark)' : 'var(--text-secondary)',
                background: isActive ? 'var(--color-primary-light)' : 'transparent',
                borderRadius: 'var(--radius-md)',
                textDecoration: 'none',
                whiteSpace: 'nowrap',
                transition: 'all 0.15s',
              })}
            >
              <Icon size={14} />
              {t.label}
            </NavLink>
          )
        })}
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-6)' }}>
        <Outlet />
      </div>
    </div>
  )
}
