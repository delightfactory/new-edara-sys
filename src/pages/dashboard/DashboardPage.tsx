import type { ReactNode } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useAuthStore } from '@/stores/auth-store'
import { supabase } from '@/lib/supabase/client'
import {
  Users, BoxesIcon, Warehouse, Package, TrendingUp,
  ShoppingCart, AlertTriangle, ClipboardList,
  DollarSign, Target, Truck,
} from 'lucide-react'
import { formatNumber, formatCurrency } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import GoalCommandCenter from '@/components/dashboard/GoalCommandCenter'
import Card from '@/components/patterns/Card'
import SectionHeader from '@/components/patterns/SectionHeader'
import StatCard from '@/components/patterns/StatCard'
import AlertPanel from '@/components/patterns/AlertPanel'
import StatePanel from '@/components/patterns/StatePanel'
import StatusBadge from '@/components/patterns/StatusBadge'
import './dashboard-v2.css'

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

async function fetchOverviewStats(): Promise<OverviewStats> {
  const [customers, products, warehouses, stock, salesPending, purchasePending] = await Promise.all([
    supabase.from('customers').select('id', { count: 'estimated', head: true }).eq('is_active', true),
    supabase.from('products').select('id', { count: 'estimated', head: true }).eq('is_active', true),
    supabase.from('warehouses').select('id', { count: 'estimated', head: true }).eq('is_active', true),
    supabase.from('stock').select('id', { count: 'estimated', head: true }),
    supabase.from('sales_orders').select('id', { count: 'estimated', head: true }).in('status', ['confirmed', 'partially_delivered']),
    supabase.from('purchase_invoices').select('id', { count: 'estimated', head: true }).eq('status', 'pending'),
  ])

  const { data: lowStockRows } = await supabase.rpc('get_low_stock', {
    p_warehouse_id: null, p_offset: 0, p_limit: 1,
  })
  const lowStockCount = (lowStockRows && lowStockRows.length > 0)
    ? Number((lowStockRows as any[])[0].total_count)
    : 0

  return {
    activeCustomers: customers.count ?? 0,
    activeProducts: products.count ?? 0,
    activeWarehouses: warehouses.count ?? 0,
    stockItems: stock.count ?? 0,
    pendingSalesOrders: salesPending.count ?? 0,
    pendingPurchaseInvoices: purchasePending.count ?? 0,
    lowStockItems: lowStockCount,
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

function MetricValue({ loading, children }: { loading?: boolean; children: ReactNode }) {
  if (loading) {
    return <span className="skeleton db-v2__value-skeleton" aria-label="جاري تحميل القيمة" />
  }
  return <>{children}</>
}

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

  const hour = new Date().getHours()
  const greeting = hour < 12 ? 'صباح الخير' : hour < 17 ? 'مساء الخير' : 'مساء النور'

  return (
    <div className="page-container animate-enter db-v2">
      <PageHeader
        title={`${greeting}، ${profile?.full_name?.split(' ')[0] || 'مستخدم'} 👋`}
        subtitle="لوحة القيادة — نظرة عامة على النظام"
      />

      <GoalCommandCenter />

      <div className="db-v2__kpi-grid" aria-label="مؤشرات النظام الرئيسية">
        <StatCard
          label="العملاء النشطون"
          value={<MetricValue loading={loadingOverview}>{formatNumber(overview?.activeCustomers ?? 0)}</MetricValue>}
          icon={<Users size={19} />}
          tone="info"
        />
        <StatCard
          label="المنتجات"
          value={<MetricValue loading={loadingOverview}>{formatNumber(overview?.activeProducts ?? 0)}</MetricValue>}
          icon={<BoxesIcon size={19} />}
          tone="success"
        />
        <StatCard
          label="المخازن النشطة"
          value={<MetricValue loading={loadingOverview}>{formatNumber(overview?.activeWarehouses ?? 0)}</MetricValue>}
          icon={<Warehouse size={19} />}
          tone="warning"
        />
        <StatCard
          label="أصناف المخزون"
          value={<MetricValue loading={loadingOverview}>{formatNumber(overview?.stockItems ?? 0)}</MetricValue>}
          icon={<Package size={19} />}
          tone="info"
        />
        {canViewSales && (
          <StatCard
            label="طلبات معلقة"
            value={<MetricValue loading={loadingOverview}>{formatNumber(overview?.pendingSalesOrders ?? 0)}</MetricValue>}
            icon={<ClipboardList size={19} />}
            tone="warning"
          />
        )}
        {canViewInventory && overview?.lowStockItems != null && overview.lowStockItems > 0 && (
          <StatCard
            label="أصناف منخفضة"
            value={<MetricValue loading={loadingOverview}>{formatNumber(overview.lowStockItems)}</MetricValue>}
            icon={<AlertTriangle size={19} />}
            tone="danger"
          />
        )}
      </div>

      {canViewSales && (
        <Card padding="lg">
          <div className="db-v2__section">
            <SectionHeader icon={<TrendingUp size={18} />} title="إيرادات المبيعات" />
            <div className="db-v2__sales-grid">
              <StatCard
                label="إيرادات اليوم"
                value={<MetricValue loading={loadingSales}>{formatCurrency(salesStats?.todayRevenue ?? 0)}</MetricValue>}
                icon={<DollarSign size={18} />}
                tone="success"
              />
              <StatCard
                label="إيرادات الشهر"
                value={<MetricValue loading={loadingSales}>{formatCurrency(salesStats?.monthRevenue ?? 0)}</MetricValue>}
                icon={<TrendingUp size={18} />}
                tone="info"
              />
              <StatCard
                label="طلبات محددة"
                value={<MetricValue loading={loadingSales}>{formatNumber(salesStats?.pendingOrders ?? 0)}</MetricValue>}
                icon={<ShoppingCart size={18} />}
                tone="warning"
              />
              <StatCard
                label="تسليمات اليوم"
                value={<MetricValue loading={loadingSales}>{formatNumber(salesStats?.deliveredToday ?? 0)}</MetricValue>}
                icon={<Truck size={18} />}
                tone="info"
              />
            </div>
          </div>
        </Card>
      )}

      {canViewInventory && overview?.lowStockItems != null && overview.lowStockItems > 0 && (
        <Card padding="lg">
          <div className="db-v2__section">
            <SectionHeader icon={<AlertTriangle size={18} />} title="تنبيهات المخزون" />
            <AlertPanel
              tone="danger"
              title={`${formatNumber(overview.lowStockItems)} صنف على وشك النفاد`}
              action={<StatusBadge label={formatNumber(overview.lowStockItems)} tone="danger" />}
            >
              يجب مراجعة المخزون وتوفير الكميات اللازمة
            </AlertPanel>
          </div>
        </Card>
      )}

      {!canViewFinance && !canViewSales && (
        <StatePanel
          kind="empty"
          icon={<Target size={34} />}
          title="مرحباً بك"
          description="استخدم القائمة الرئيسية للوصول إلى الأقسام المتاحة لك حسب صلاحياتك."
        />
      )}

      {(overview?.pendingSalesOrders ?? 0) > 0 || (overview?.pendingPurchaseInvoices ?? 0) > 0 ? (
        <Card padding="lg">
          <div className="db-v2__section">
            <SectionHeader icon={<ClipboardList size={18} />} title="يحتاج متابعة" />
            <div className="db-v2__follow-list">
              {(overview?.pendingSalesOrders ?? 0) > 0 && canViewSales && (
                <div className="db-v2__follow-row">
                  <span className="db-v2__follow-icon" aria-hidden="true"><ShoppingCart size={17} /></span>
                  <span className="db-v2__follow-label">طلبات بيع تحتاج تنفيذ</span>
                  <StatusBadge label={formatNumber(overview!.pendingSalesOrders)} tone="info" />
                </div>
              )}
              {(overview?.pendingPurchaseInvoices ?? 0) > 0 && canViewFinance && (
                <div className="db-v2__follow-row">
                  <span className="db-v2__follow-icon" aria-hidden="true"><Truck size={17} /></span>
                  <span className="db-v2__follow-label">فواتير مشتريات معلقة</span>
                  <StatusBadge label={formatNumber(overview!.pendingPurchaseInvoices)} tone="warning" />
                </div>
              )}
            </div>
          </div>
        </Card>
      ) : null}
    </div>
  )
}
