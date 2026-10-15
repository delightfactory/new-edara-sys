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
import Button from '@/components/ui/Button'
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
  const { data, error } = await supabase.rpc('get_dashboard_overview_metrics')
  if (error) throw error
  if (!data) throw new Error('Dashboard overview response is missing')
  return data as OverviewStats
}

async function fetchSalesStats(): Promise<SalesStats> {
  const today = new Date().toISOString().split('T')[0]
  const monthStart = new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString()
  const { data, error } = await supabase.rpc('get_dashboard_sales_metrics', {
    p_today: today, p_month_start: monthStart,
  })
  if (error) throw error
  if (!data) throw new Error('Dashboard sales response is missing')
  return data as SalesStats
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
  const permissions = useAuthStore(s => s.permissions)
  const permissionKey = [...new Set(permissions)].sort()

  const { data: overview, isLoading: loadingOverview, isError: overviewError, isFetching: fetchingOverview, refetch: refetchOverview } = useQuery({
    queryKey: ['dashboard-overview', profile?.id, permissionKey],
    queryFn: fetchOverviewStats,
    enabled: !!profile?.id,
    staleTime: 60_000,
    retry: false,
  })

  const canViewSales = can('sales.read')
  const canViewFinance = can('finance.read') || can('finance.view_costs')
  const canViewInventory = can('inventory.read')

  const { data: salesStats, isLoading: loadingSales, isError: salesError, isFetching: fetchingSales, refetch: refetchSales } = useQuery({
    queryKey: ['dashboard-sales', profile?.id, permissionKey],
    queryFn: fetchSalesStats,
    enabled: !!profile?.id && canViewSales,
    staleTime: 60_000,
    retry: false,
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

      {overviewError && (
        <StatePanel
          kind="error"
          title="تعذّر تحميل مؤشرات النظام"
          description={overview ? 'القيم المعروضة من آخر تحميل ناجح ولم تُحدّث.' : 'لم نتمكن من تحميل المؤشرات. أعد المحاولة.'}
          action={<Button variant="secondary" touchTarget loading={fetchingOverview} onClick={() => { if (!fetchingOverview) void refetchOverview() }}>إعادة تحميل المؤشرات</Button>}
        />
      )}
      {(!overviewError || overview) && (
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
      )}

      {canViewSales && (
        <Card padding="lg">
          <div className="db-v2__section">
            <SectionHeader icon={<TrendingUp size={18} />} title="إيرادات المبيعات" />
            {salesError && (
              <StatePanel
                kind="error"
                title="تعذّر تحميل مؤشرات المبيعات"
                description={salesStats ? 'القيم المعروضة من آخر تحميل ناجح ولم تُحدّث.' : 'لم نتمكن من تحميل مؤشرات المبيعات. أعد المحاولة.'}
                action={<Button variant="secondary" touchTarget loading={fetchingSales} onClick={() => { if (!fetchingSales) void refetchSales() }}>إعادة تحميل المبيعات</Button>}
              />
            )}
            {(!salesError || salesStats) && (
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
            )}
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
