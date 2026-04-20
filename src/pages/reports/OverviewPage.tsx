import { useState } from 'react'
import { useSystemTrustState, useTrustForComponent } from '@/hooks/useSystemTrustState'
import { useSalesSummary } from '@/hooks/useSalesGrain'
import { useTreasurySummary } from '@/hooks/useTreasuryCashflow'
import { useARSummary } from '@/hooks/useARCollections'
import { useCustomerHealthSummary } from '@/hooks/useCustomerHealth'
import MetricCard from '@/components/reports/MetricCard'
import SkeletonCard from '@/components/reports/SkeletonCard'
import SystemHealthBar from '@/components/reports/SystemHealthBar'
import ReportFilterBar, { type DateRange } from '@/components/reports/ReportFilterBar'
import { TrendingUp, Wallet, BarChart3, Users2, Package, AlertTriangle, MapPin, Target, UserCheck, ShieldCheck } from 'lucide-react'
import { Link } from 'react-router-dom'
import { toLocalISODate } from '@/lib/utils/date'

const today = new Date()
const monthStart = new Date(today.getFullYear(), today.getMonth(), 1)
const monthEnd = new Date(today.getFullYear(), today.getMonth() + 1, 0)

const FMT = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 })
const fmt = (n: number | undefined | null) => n != null ? FMT.format(n) + ' ج.م' : '—'

export default function OverviewPage() {
  const [range, setRange] = useState<DateRange>({ from: toLocalISODate(monthStart), to: toLocalISODate(monthEnd) })
  const filters = { dateFrom: range.from, dateTo: range.to }

  const { data: trustRows, isLoading: trustLoading, error: trustError } = useSystemTrustState('all')
  const { data: sales, isLoading: salesLoading } = useSalesSummary(filters)
  const { data: treasury, isLoading: trsLoading } = useTreasurySummary(filters)
  const { data: ar, isLoading: arLoading } = useARSummary(filters)
  const { data: customers, isLoading: custLoading } = useCustomerHealthSummary({ asOfDate: range.to })

  const salesTrust = useTrustForComponent(trustRows, 'fact_sales_daily_grain')
  const revTrust   = useTrustForComponent(trustRows, 'fact_sales_daily_grain.revenue')
  const trsTrust   = useTrustForComponent(trustRows, 'fact_treasury_cashflow_daily.net_collection')
    ?? useTrustForComponent(trustRows, 'fact_treasury_cashflow_daily')
  const arTrust    = useTrustForComponent(trustRows, 'fact_ar_collections_attributed_to_origin_sale_date')
  const custTrust  = useTrustForComponent(trustRows, 'snapshot_customer_health')

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-6)' }}>

      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', flexWrap: 'wrap', gap: 'var(--space-3)' }}>
        <div>
          <h1 style={{ fontSize: 'var(--text-2xl)', fontWeight: 800, color: 'var(--text-primary)', margin: 0 }}>نظرة إدارية شاملة</h1>
          <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', margin: '4px 0 0' }}>
            مؤشرات المبيعات والتحصيل والخزينة وصحة العملاء — بناءً على البيانات المعتمدة فقط
          </p>
        </div>
        <ReportFilterBar value={range} onChange={setRange} />
      </div>

      <SystemHealthBar trustRows={trustRows} isLoading={trustLoading} error={trustError} />

      {/* KPI grid */}
      <div>
        <h2 style={{ fontSize: 'var(--text-base)', fontWeight: 700, color: 'var(--text-primary)', margin: '0 0 var(--space-3)' }}>
          المؤشرات الرئيسية
        </h2>
        <div className="report-grid">
          {salesLoading || trsLoading || arLoading ? (
            [1, 2, 3, 4].map(i => <SkeletonCard key={i} height={160} />)
          ) : (
            <>
              <MetricCard
                label="صافي الإيراد"
                subtitle="ضريبة مستبعدة"
                value={fmt(sales?.total_revenue)}
                status={revTrust?.status ?? salesTrust?.status ?? null}
                lastCompletedAt={salesTrust?.last_completed_at}
                isStale={salesTrust?.is_stale}
                domain="sales"
                icon={<TrendingUp size={16} />}
                secondary={{ label: 'إجمالي الضريبة', value: fmt(sales?.total_tax) }}
              />
              <MetricCard
                label="إجمالي المبيعات"
                subtitle="شامل الضريبة"
                value={fmt(sales?.total_gross_revenue)}
                status={salesTrust?.status ?? null}
                lastCompletedAt={salesTrust?.last_completed_at}
                isStale={salesTrust?.is_stale}
                domain="sales"
                icon={<TrendingUp size={16} />}
                secondary={{ label: 'قيمة المرتجعات', value: fmt(sales?.total_returns_value) }}
              />
              <MetricCard
                label="صافي التحصيل الخزيني"
                subtitle="مطابق لسجلات الخزينة فعلياً"
                value={fmt(treasury?.net_cashflow)}
                status={trsTrust?.status ?? null}
                lastCompletedAt={trsTrust?.last_completed_at}
                isStale={trsTrust?.is_stale}
                domain="treasury"
                icon={<Wallet size={16} />}
                secondary={{ label: 'إجمالي التحصيل', value: fmt(treasury?.total_inflow) }}
              />
              <MetricCard
                label="تحصيل AR المنسوب"
                subtitle="مُسنَد لتاريخ البيع الأصلي"
                value={fmt(ar?.total_net_cohort)}
                status={arTrust?.status ?? null}
                lastCompletedAt={arTrust?.last_completed_at}
                isStale={arTrust?.is_stale}
                domain="ar"
                icon={<BarChart3 size={16} />}
                secondary={{ label: 'إجمالي الإيصالات', value: fmt(ar?.total_receipt_amount) }}
              />
            </>
          )}
        </div>
      </div>

      {/* Customer health strip */}
      <div>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--space-3)' }}>
          <h2 style={{ fontSize: 'var(--text-base)', fontWeight: 700, color: 'var(--text-primary)', margin: 0 }}>صحة قاعدة العملاء</h2>
          <Link to="/reports/customers" style={{ fontSize: 'var(--text-xs)', color: 'var(--color-primary)', textDecoration: 'none', fontWeight: 600 }}>
            عرض التفاصيل ←
          </Link>
        </div>
        {custLoading ? <SkeletonCard height={120} /> : (
          <div className="report-grid">
            <MetricCard
              label="إجمالي العملاء النشطين"
              value={customers?.stats.active ?? null}
              status={custTrust?.status ?? null}
              lastCompletedAt={custTrust?.last_completed_at}
              isStale={custTrust?.is_stale}
              domain="customers"
              icon={<Users2 size={16} />}
              secondary={{ label: 'خامدون', value: String(customers?.stats.dormant ?? 0) }}
            />
            <MetricCard
              label="متوسط قيمة العميل"
              subtitle="آخر 90 يوماً"
              value={customers?.stats.avg_monetary != null ? fmt(customers.stats.avg_monetary) : null}
              status={custTrust?.status ?? null}
              lastCompletedAt={custTrust?.last_completed_at}
              isStale={custTrust?.is_stale}
              domain="customers"
              icon={<Users2 size={16} />}
              secondary={{ label: 'متوسط أيام الخمود', value: customers?.stats.avg_recency != null ? `${Math.round(customers.stats.avg_recency)} يوم` : 'لا يوجد' }}
            />
          </div>
        )}
      </div>

      {/* Navigation grid */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))', gap: 'var(--space-3)' }}>
        {[
          { to: '/reports/sales',       label: 'تقرير المبيعات',   desc: 'الإيرادات — المرتجعات — الكميات', icon: TrendingUp, color: 'var(--color-success)' },
          { to: '/reports/receivables', label: 'المستحقات (AR)',    desc: 'تحصيلات منسوبة لتاريخ البيع',     icon: BarChart3,  color: 'var(--color-info)' },
          { to: '/reports/treasury',    label: 'الخزينة',           desc: 'تدفق نقدي موثق خزينياً',          icon: Wallet,    color: 'var(--color-primary)' },
          { to: '/reports/customers',         label: 'صحة العملاء',       desc: 'الخمول — التكرار — القيمة',        icon: Users2,        color: 'var(--color-warning)'  },
          { to: '/reports/reps',              label: 'أداء المندوبين',   desc: 'إيراد — مرتجعات — عملاء بالمندوب', icon: UserCheck,     color: 'var(--color-primary)'  },
          { to: '/reports/products',          label: 'أداء المنتجات',    desc: 'إيراد — كميات — حصة السوق',        icon: Package,       color: 'var(--color-info)'     },
          { to: '/reports/churn-risk',        label: 'خطر الخمود',       desc: 'VIP — مخلص — معرض للخطر — خامد',   icon: AlertTriangle, color: 'var(--color-warning)'  },
          { to: '/reports/reengagement',      label: 'إعادة الاستهداف', desc: 'أولويات تشغيلية — Champion Lost',    icon: Target,        color: '#e11d48'                },
          { to: '/reports/geography',         label: 'التحليل الجغرافى', desc: 'محافظة — مدينة — منطقة',           icon: MapPin,        color: 'var(--color-success)'  },
          { to: '/reports/target-attainment', label: 'إنجاز الأهداف',    desc: 'فعلى مقابل مستهدف — الاتجاه',      icon: Target,        color: '#f59e0b'                },
          { to: '/reports/credit-commitment', label: 'التزام ائتمان المندوبين', desc: 'محفظة — مديونية منشأة — تحصيلات', icon: ShieldCheck,   color: '#7c3aed'                },
        ].map(item => {
          const Icon = item.icon
          return (
            <Link key={item.to} to={item.to} className="edara-card" style={{
              background: 'var(--bg-surface)', border: '1px solid var(--border-primary)',
              borderRadius: 'var(--radius-lg)', padding: 'var(--space-4)',
              textDecoration: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)',
              transition: 'all 0.15s', boxShadow: 'var(--shadow-sm)',
            }}>
              <span style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', width: '36px', height: '36px', borderRadius: '10px', background: `${item.color}18`, color: item.color }}>
                <Icon size={18} />
              </span>
              <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', color: 'var(--text-primary)' }}>{item.label}</div>
              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{item.desc}</div>
            </Link>
          )
        })}
      </div>
    </div>
  )
}
