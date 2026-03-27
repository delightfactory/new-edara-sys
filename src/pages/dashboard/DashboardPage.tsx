import { useQuery } from '@tanstack/react-query'
import { useAuthStore } from '@/stores/auth-store'
import { supabase } from '@/lib/supabase/client'
import {
  Users, BoxesIcon, Warehouse, Package, TrendingUp,
  ShoppingCart, AlertTriangle, ClipboardList, ArrowUpRight, ArrowDownRight,
  DollarSign, Target, Truck,
} from 'lucide-react'
import { formatNumber, formatCurrency } from '@/lib/utils/format'
import Badge from '@/components/ui/Badge'

// ── Data types ───────────────────────────────────────────────
interface OverviewStats {
  activeCustomers: number
  activeProducts: number
  activeWarehouses: number
  stockItems: number
  pendingSalesOrders: number
  pendingPurchaseInvoices: number
  lowStockItems: number
}

interface SalesStats {
  todayRevenue: number
  monthRevenue: number
  pendingOrders: number
  deliveredToday: number
}

// ── Fetchers ─────────────────────────────────────────────────
async function fetchOverviewStats(): Promise<OverviewStats> {
  const [customers, products, warehouses, stock, salesPending, purchasePending, lowStock] = await Promise.all([
    supabase.from('customers').select('id', { count: 'estimated', head: true }).eq('is_active', true),
    supabase.from('products').select('id', { count: 'estimated', head: true }).eq('is_active', true),
    supabase.from('warehouses').select('id', { count: 'estimated', head: true }).eq('is_active', true),
    supabase.from('stock').select('id', { count: 'estimated', head: true }),
    supabase.from('sales_orders').select('id', { count: 'estimated', head: true }).in('status', ['confirmed', 'partially_delivered']),
    supabase.from('purchase_invoices').select('id', { count: 'estimated', head: true }).eq('status', 'pending'),
    supabase.from('stock').select('id', { count: 'estimated', head: true }).lt('quantity', 10).gt('quantity', 0),
  ])
  return {
    activeCustomers: customers.count ?? 0,
    activeProducts: products.count ?? 0,
    activeWarehouses: warehouses.count ?? 0,
    stockItems: stock.count ?? 0,
    pendingSalesOrders: salesPending.count ?? 0,
    pendingPurchaseInvoices: purchasePending.count ?? 0,
    lowStockItems: lowStock.count ?? 0,
  }
}

async function fetchSalesStats(): Promise<SalesStats> {
  const today = new Date().toISOString().split('T')[0]
  const monthStart = new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString()

  const [todayOrders, monthOrders, pendingOrders, deliveredToday] = await Promise.all([
    supabase.from('sales_orders').select('total_amount').gte('created_at', today).eq('status', 'delivered'),
    supabase.from('sales_orders').select('total_amount').gte('created_at', monthStart).eq('status', 'delivered'),
    supabase.from('sales_orders').select('id', { count: 'estimated', head: true }).in('status', ['confirmed', 'partially_delivered']),
    supabase.from('sales_orders').select('id', { count: 'estimated', head: true }).gte('created_at', today).eq('status', 'delivered'),
  ])

  const todayRevenue = (todayOrders.data || []).reduce((s, o) => s + (o.total_amount || 0), 0)
  const monthRevenue = (monthOrders.data || []).reduce((s, o) => s + (o.total_amount || 0), 0)

  return {
    todayRevenue,
    monthRevenue,
    pendingOrders: pendingOrders.count ?? 0,
    deliveredToday: deliveredToday.count ?? 0,
  }
}

// ── KPI Card ─────────────────────────────────────────────────
function KpiCard({
  label, value, icon: Icon, color, loading,
  trend, trendLabel,
}: {
  label: string; value: string; icon: React.ElementType;
  color: string; loading?: boolean; trend?: 'up' | 'down' | 'neutral'; trendLabel?: string;
}) {
  return (
    <div className="db-kpi-card edara-card">
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: 12 }}>
        <div className="db-kpi-icon" style={{ background: `color-mix(in srgb, ${color} 12%, transparent)` }}>
          <Icon size={20} style={{ color }} />
        </div>
        {trend && trend !== 'neutral' && (
          <div style={{
            display: 'flex', alignItems: 'center', gap: 3, fontSize: 11, fontWeight: 600,
            color: trend === 'up' ? 'var(--color-success)' : 'var(--color-danger)',
          }}>
            {trend === 'up' ? <ArrowUpRight size={13} /> : <ArrowDownRight size={13} />}
            {trendLabel}
          </div>
        )}
      </div>
      <div className="db-kpi-label">{label}</div>
      {loading ? (
        <div className="skeleton" style={{ height: 28, width: '55%', marginTop: 6, borderRadius: 6 }} />
      ) : (
        <div className="db-kpi-value" style={{ color }}>{value}</div>
      )}
    </div>
  )
}

// ── Section heading ───────────────────────────────────────────
function SectionHead({ icon: Icon, title }: { icon: React.ElementType; title: string }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 16 }}>
      <div style={{ width: 32, height: 32, borderRadius: 8, background: 'var(--color-primary-light)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <Icon size={16} style={{ color: 'var(--color-primary)' }} />
      </div>
      <h2 style={{ fontSize: 'var(--text-md)', fontWeight: 700, color: 'var(--text-primary)', margin: 0 }}>{title}</h2>
    </div>
  )
}

// ── Main Component ────────────────────────────────────────────
export default function DashboardPage() {
  const profile = useAuthStore(s => s.profile)
  const can = useAuthStore(s => s.can)

  const { data: overview, isLoading: loadingOverview } = useQuery({
    queryKey: ['dashboard-overview'],
    queryFn: fetchOverviewStats,
    staleTime: 60_000,
  })

  const canViewSales = can('sales.read')
  const canViewFinance = can('finance.read') || can('finance.view_costs')
  const canViewInventory = can('inventory.read')

  const { data: salesStats, isLoading: loadingSales } = useQuery({
    queryKey: ['dashboard-sales'],
    queryFn: fetchSalesStats,
    enabled: canViewSales,
    staleTime: 60_000,
  })

  // ── Greeting ──
  const hour = new Date().getHours()
  const greeting = hour < 12 ? 'صباح الخير' : hour < 17 ? 'مساء الخير' : 'مساء النور'

  return (
    <div className="page-container animate-enter">
      {/* Header */}
      <div className="page-header">
        <div className="page-header-info">
          <h1 className="page-title">{greeting}، {profile?.full_name?.split(' ')[0] || 'مستخدم'} 👋</h1>
          <p className="page-subtitle">لوحة القيادة — نظرة عامة على النظام</p>
        </div>
      </div>

      {/* ── KPI Grid (2-col on mobile, auto on desktop) ── */}
      <div className="db-kpi-grid" style={{ marginBottom: 'var(--space-4)' }}>
        <KpiCard
          label="العملاء النشطون"
          value={formatNumber(overview?.activeCustomers ?? 0)}
          icon={Users}
          color="var(--color-primary)"
          loading={loadingOverview}
        />
        <KpiCard
          label="المنتجات"
          value={formatNumber(overview?.activeProducts ?? 0)}
          icon={BoxesIcon}
          color="var(--color-success)"
          loading={loadingOverview}
        />
        <KpiCard
          label="المخازن النشطة"
          value={formatNumber(overview?.activeWarehouses ?? 0)}
          icon={Warehouse}
          color="var(--color-warning)"
          loading={loadingOverview}
        />
        <KpiCard
          label="أصناف المخزون"
          value={formatNumber(overview?.stockItems ?? 0)}
          icon={Package}
          color="var(--color-info)"
          loading={loadingOverview}
        />
        {canViewSales && (
          <KpiCard
            label="طلبات معلقة"
            value={formatNumber(overview?.pendingSalesOrders ?? 0)}
            icon={ClipboardList}
            color="var(--color-warning)"
            loading={loadingOverview}
          />
        )}
        {canViewInventory && overview?.lowStockItems != null && overview.lowStockItems > 0 && (
          <KpiCard
            label="أصناف منخفضة"
            value={formatNumber(overview.lowStockItems)}
            icon={AlertTriangle}
            color="var(--color-danger)"
            loading={loadingOverview}
          />
        )}
      </div>

      {/* ── Sales section (if user can view sales) ── */}
      {canViewSales && (
        <div className="edara-card" style={{ marginBottom: 'var(--space-4)', padding: 'var(--space-5)' }}>
          <SectionHead icon={TrendingUp} title="إيرادات المبيعات" />
          <div className="db-sales-grid">
            <KpiCard
              label="إيرادات اليوم"
              value={formatCurrency(salesStats?.todayRevenue ?? 0)}
              icon={DollarSign}
              color="var(--color-success)"
              loading={loadingSales}
            />
            <KpiCard
              label="إيرادات الشهر"
              value={formatCurrency(salesStats?.monthRevenue ?? 0)}
              icon={TrendingUp}
              color="var(--color-primary)"
              loading={loadingSales}
            />
            <KpiCard
              label="طلبات محددة"
              value={formatNumber(salesStats?.pendingOrders ?? 0)}
              icon={ShoppingCart}
              color="var(--color-warning)"
              loading={loadingSales}
            />
            <KpiCard
              label="تسليمات اليوم"
              value={formatNumber(salesStats?.deliveredToday ?? 0)}
              icon={Truck}
              color="var(--color-info)"
              loading={loadingSales}
            />
          </div>
        </div>
      )}

      {/* ── Inventory Alerts section ── */}
      {canViewInventory && overview?.lowStockItems != null && overview.lowStockItems > 0 && (
        <div className="edara-card" style={{ marginBottom: 'var(--space-4)', padding: 'var(--space-5)' }}>
          <SectionHead icon={AlertTriangle} title="تنبيهات المخزون" />
          <div style={{
            display: 'flex', alignItems: 'center', gap: 16,
            padding: 'var(--space-4)', borderRadius: 12,
            background: 'color-mix(in srgb, var(--color-danger) 6%, transparent)',
            border: '1px solid color-mix(in srgb, var(--color-danger) 18%, transparent)',
          }}>
            <div style={{
              width: 44, height: 44, borderRadius: '50%', flexShrink: 0,
              background: 'color-mix(in srgb, var(--color-danger) 12%, transparent)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              <AlertTriangle size={20} style={{ color: 'var(--color-danger)' }} />
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontWeight: 700, fontSize: 15, color: 'var(--color-danger)', marginBottom: 3 }}>
                {formatNumber(overview.lowStockItems)} صنف على وشك النفاد
              </div>
              <div style={{ fontSize: 13, color: 'var(--text-muted)' }}>
                يجب مراجعة المخزون وتوفير الكميات اللازمة
              </div>
            </div>
            <Badge variant="danger">{overview.lowStockItems}</Badge>
          </div>
        </div>
      )}

      {/* ── Finance prompt for non-finance users ── */}
      {!canViewFinance && !canViewSales && (
        <div className="edara-card" style={{ padding: 'var(--space-8)', textAlign: 'center' }}>
          <Target size={40} style={{ margin: '0 auto 12px', display: 'block', color: 'var(--color-primary)', opacity: 0.6 }} />
          <p style={{ color: 'var(--text-secondary)', fontSize: 'var(--text-sm)' }}>
            مرحباً بك! استخدم القائمة الجانبية للوصول إلى صلاحياتك.
          </p>
        </div>
      )}

      {/* ── Pending operations summary ── */}
      {(overview?.pendingSalesOrders ?? 0) > 0 || (overview?.pendingPurchaseInvoices ?? 0) > 0 ? (
        <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
          <SectionHead icon={ClipboardList} title="يحتاج متابعة" />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {(overview?.pendingSalesOrders ?? 0) > 0 && canViewSales && (
              <div className="db-action-row">
                <ShoppingCart size={16} style={{ color: 'var(--color-primary)', flexShrink: 0 }} />
                <span style={{ flex: 1, fontSize: 14 }}>طلبات بيع تحتاج تنفيذ</span>
                <Badge variant="primary">{overview!.pendingSalesOrders}</Badge>
              </div>
            )}
            {(overview?.pendingPurchaseInvoices ?? 0) > 0 && canViewFinance && (
              <div className="db-action-row">
                <Truck size={16} style={{ color: 'var(--color-warning)', flexShrink: 0 }} />
                <span style={{ flex: 1, fontSize: 14 }}>فواتير مشتريات معلقة</span>
                <Badge variant="warning">{overview!.pendingPurchaseInvoices}</Badge>
              </div>
            )}
          </div>
        </div>
      ) : null}

      <style>{`
        /* ── KPI Grid ── */
        .db-kpi-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
          gap: var(--space-3);
        }
        .db-sales-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
          gap: var(--space-3);
        }
        .db-kpi-card {
          padding: var(--space-4);
          min-width: 0;
          transition: transform 0.15s, box-shadow 0.15s;
        }
        .db-kpi-card:hover {
          transform: translateY(-2px);
          box-shadow: 0 8px 24px rgba(0,0,0,0.1);
        }
        .db-kpi-icon {
          width: 40px; height: 40px; border-radius: 10px;
          display: flex; align-items: center; justify-content: center;
          flex-shrink: 0;
        }
        .db-kpi-label {
          font-size: 12px; font-weight: 500; color: var(--text-muted);
          margin-bottom: 4px; white-space: nowrap;
          overflow: hidden; text-overflow: ellipsis;
        }
        .db-kpi-value {
          font-size: 22px; font-weight: 800;
          font-variant-numeric: tabular-nums;
          letter-spacing: -0.5px; margin-top: 2px;
        }
        .db-action-row {
          display: flex; align-items: center; gap: 12px;
          padding: var(--space-3) var(--space-4);
          border-radius: 10px;
          background: var(--bg-surface-2);
          border: 1px solid var(--border-primary);
        }

        /* ── Mobile: 2-column grid ── */
        @media (max-width: 640px) {
          .db-kpi-grid,
          .db-sales-grid {
            grid-template-columns: repeat(2, 1fr);
            gap: var(--space-2);
          }
          .db-kpi-card { padding: var(--space-3); }
          .db-kpi-value { font-size: 17px; }
          .db-kpi-icon { width: 34px; height: 34px; }
        }
      `}</style>
    </div>
  )
}
