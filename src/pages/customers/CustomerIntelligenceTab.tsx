import React from 'react'
import { useNavigate } from 'react-router-dom'
import {
  useCustomer360Summary,
  useCustomer360SalesByMonth,
  useCustomer360TopProducts,
  useCustomer360CategoryMix,
  useCustomer360ArAging,
  useCustomer360PaymentBehavior,
  useCustomer360Timeline,
  useCustomer360Ledger,
  useCustomer360Profitability
} from '@/hooks/useCustomer360'
import { computeRecommendations, type Recommendation } from '@/lib/utils/customer360-recommendations'
import {
  TrendingUp, TrendingDown, DollarSign, Target, Package, Box, HelpCircle,
  AlertTriangle, Check, Info, AlertCircle, Clock, Calendar, Lock, List,
  BarChart as BarChartIcon
} from 'lucide-react'
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, ReferenceLine, PieChart, Pie, Cell, LineChart, Line, CartesianGrid } from 'recharts'
import type { Customer } from '@/lib/types/master-data'
import type { 
  Customer360Kpis, CustomerSalesByMonth, CustomerTopProduct, CustomerCategoryMix,
  CustomerArAgingBucket, CustomerPaymentBehavior, CustomerTimelineEvent,
  CustomerLedgerEntry
} from '@/lib/services/customer360'
import type { GrossProfitGrainResult } from '@/lib/types/profitability'

function FreshnessIndicator({ date, label }: { date?: string | null, label: string }) {
  if (!date) return <span className="text-muted text-xs mx-2">مباشر</span>
  return (
    <div className="flex items-center gap-1 text-xs text-muted" style={{ fontSize: 10 }}>
      <Clock size={10} />
      {label}: {new Date(date).toLocaleDateString('ar-EG')}
    </div>
  )
}

export function CustomerIntelligenceTab({ customer }: { customer: Customer }) {
  const navigate = useNavigate()
  
  // -- Phase 1 --
  const summary = useCustomer360Summary(customer.id)
  
  // Phase 3 hooks are deferred until Phase 1 has successfully loaded.
  // This reduces initial page load from 8 concurrent RPCs to 3 + 5 deferred,
  // without breaking Hook rules (all hooks are called unconditionally every render).
  const phase3Ready = !summary.isPending
  
  // -- Phase 2 --
  const { data: salesTrend } = useCustomer360SalesByMonth(customer.id, 18)
  const { data: topProducts } = useCustomer360TopProducts(customer.id)
  const { data: arAging } = useCustomer360ArAging(customer.id)
  
  // -- Phase 3 (deferred until Phase 1 is done) --
  const { data: categoryMix }    = useCustomer360CategoryMix(customer.id, phase3Ready)
  const { data: paymentBehavior } = useCustomer360PaymentBehavior(customer.id, phase3Ready)
  const { data: profitability }  = useCustomer360Profitability(customer.id, phase3Ready)
  
  const timeline = useCustomer360Timeline(customer.id, 30, phase3Ready)
  const ledger   = useCustomer360Ledger(customer.id, 15, phase3Ready)


  const isPending = summary.isPending
  if (isPending) return (
    <div style={{ padding: 20 }}>
      <div className="skeleton skeleton-row" style={{ height: 100, marginBottom: 15 }} />
      <div className="skeleton skeleton-row" style={{ height: 150, marginBottom: 15 }} />
      <div className="skeleton skeleton-row" style={{ height: 200 }} />
    </div>
  )

  // Compute inputs for recommendation engine.
  // monthly_trend_delta: avg last-3-months revenue vs avg prior-3-months revenue.
  // Falls back to 0 when fewer than 4 months of data are available for comparison.
  const computeMonthlyTrendDelta = (): number => {
    if (!salesTrend || salesTrend.length < 4) return 0
    const last3  = salesTrend.slice(-3).reduce((s, m) => s + m.net_revenue, 0) / 3
    const prior3 = salesTrend.slice(-6, -3).reduce((s, m) => s + m.net_revenue, 0) / 3
    if (prior3 === 0) return 0  // avoid division by zero when prior period has no sales
    return (last3 - prior3) / prior3
  }

  const recs = computeRecommendations({
    customer: { id: customer.id, name: customer.name, current_balance: customer.current_balance, is_active: customer.is_active },
    kpis: summary.kpis,
    health: summary.health,
    risk: summary.risk,
    arAging,
    paymentBehavior,
    profitability: profitability === undefined ? undefined : profitability, // handles null lock-state
    churned_products_count: topProducts?.filter(p => p.status === 'خامد')?.length || 0,
    category_concentration: categoryMix && categoryMix.length > 0 ? (categoryMix[0].all_time_pct / 100) : 0,
    monthly_trend_delta: computeMonthlyTrendDelta(),
    // avg_monetary_l90d not available from current service layer — dormant_high_value suppressed by engine
  })


  return (
    <div style={{ padding: '0 12px', display: 'flex', flexDirection: 'column', gap: 'var(--space-5)' }}>
      
      {/* 2. Recommendations */}
      <RecommendationsSection recommendations={recs} />

      {/* 3. Executive Summary */}
      <ExecutiveSummarySection kpis={summary.kpis || undefined} />

      {/* 4. Commercial History */}
      {salesTrend && salesTrend.length > 0 && (
        <CommercialHistorySection data={salesTrend} />
      )}

      {/* 5. Product & Category Intelligence */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))', gap: 'var(--space-4)' }}>
        {topProducts && topProducts.length > 0 && <TopProductsSection data={topProducts} />}
        {categoryMix && categoryMix.length > 0 && <CategoryMixSection data={categoryMix} />}
      </div>

      {/* 6. Collections & Financial Memory */}
      {arAging && paymentBehavior && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))', gap: 'var(--space-4)' }}>
          <ArAgingSection data={arAging} />
          <PaymentBehaviorSection data={paymentBehavior} />
        </div>
      )}

      {/* 7. Profitability */}
      <ProfitabilitySection data={profitability} />

      {/* 8. Unified Timeline */}
      <TimelineSection timeline={timeline} />

      {/* 9. Ledger Preview */}
      <LedgerPreviewSection ledger={ledger} customerId={customer.id} />
      
    </div>
  )
}

// ----------------------------------------------------------------------------
// Components
// ----------------------------------------------------------------------------

function RecommendationsSection({ recommendations }: { recommendations: Recommendation[] }) {
  if (recommendations.length === 0) {
    return (
      <div style={{ background: 'var(--color-success-light, #f0fdf4)', padding: 12, borderRadius: 8, display: 'flex', alignItems: 'center', gap: 10, border: '1px solid var(--color-success)' }}>
        <Check size={20} color="var(--color-success)" />
        <span style={{ fontWeight: 600, color: 'var(--color-success)' }}>العميل في وضع ممتاز وجيد جداً! 🌟</span>
      </div>
    )
  }

  const SEVERITY_ICONS: Record<string, React.ReactNode> = {
    critical: <AlertCircle size={20} color="var(--color-danger)" />,
    warning: <AlertTriangle size={20} color="var(--color-warning)" />,
    opportunity: <Target size={20} color="var(--color-primary)" />,
    positive: <Check size={20} color="var(--color-success)" />,
    info: <Info size={20} color="var(--color-info)" />
  }

  const SEVERITY_COLORS: Record<string, string> = {
    critical: 'var(--color-danger-light)',
    warning: 'var(--color-warning-light)',
    opportunity: 'var(--color-primary-light)',
    positive: 'var(--color-success-light)',
    info: 'var(--bg-surface-2)',
  }

  const SEVERITY_BORDERS: Record<string, string> = {
    critical: 'var(--color-danger)',
    warning: 'var(--color-warning)',
    opportunity: 'var(--color-primary)',
    positive: 'var(--color-success)',
    info: 'var(--border-primary)',
  }

  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: 'var(--space-3)' }}>
      {recommendations.map(r => (
        <div key={r.id} style={{ 
          background: SEVERITY_COLORS[r.severity], 
          border: `1px solid ${SEVERITY_BORDERS[r.severity]}`,
          padding: '12px 16px',
          borderRadius: 'var(--radius-lg)',
          display: 'flex',
          gap: 12
        }}>
          <div style={{ paddingTop: 2 }}>{SEVERITY_ICONS[r.severity]}</div>
          <div>
            <div style={{ fontWeight: 700, fontSize: 14, marginBottom: 4 }}>{r.title}</div>
            {r.reason && (
              <div style={{ fontSize: 13, color: 'var(--text-secondary)' }}>
                {r.reason}
              </div>
            )}
            {r.action && (
              <button style={{ marginTop: 8, fontSize: 11, fontWeight: 600, color: 'var(--color-on-primary, #fff)', background: SEVERITY_BORDERS[r.severity], border: 'none', borderRadius: 4, padding: '4px 8px', cursor: 'pointer' }}>
                {r.action}
              </button>
            )}
          </div>
        </div>
      ))}
    </div>
  )
}

function ExecutiveSummarySection({ kpis }: { kpis: Customer360Kpis | undefined }) {
  if (!kpis) return null
  return (
    <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
      <h3 style={{ fontSize: 16, fontWeight: 700, marginBottom: 16, display: 'flex', alignItems: 'center', gap: 6 }}>
        <BarChartIcon size={16} /> الملخص التنفيذي
        <FreshnessIndicator label="مباشر" />
      </h3>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: 'var(--space-3)' }}>
        <StatCard title="صافي الإيراد" value={(kpis.net_revenue ?? 0).toLocaleString('ar-EG-u-nu-latn')} suffix="ج.م" />
        <StatCard title="إجمالي المحصل" value={(kpis.total_collected ?? 0).toLocaleString('ar-EG-u-nu-latn')} suffix="ج.م" />
        <StatCard title="الرصيد المعلق" value={Math.abs(kpis.outstanding_balance || 0).toLocaleString()} suffix="ج.م" color={(kpis.outstanding_balance || 0) > 0 ? 'var(--color-danger)' : 'var(--color-success)'} />
        <StatCard title="إجمالي الطلبات" value={(kpis.order_count ?? 0).toLocaleString()} />
        
        <StatCard title="متوسط طلبات/شهر" value={(kpis.monthly_avg_orders ?? 0).toLocaleString()} />
        <StatCard title="نسبة المرتجعات" value={`${(kpis.return_rate_pct || 0).toFixed(1)}%`} color={(kpis.return_rate_pct || 0) > 15 ? 'var(--color-warning)' : 'var(--text-primary)'} />
        <StatCard title="مدة العميل" value={`${kpis.customer_since_days || 0} يوم`} />
        <StatCard title="استخدام الائتمان" value={`${(kpis.credit_utilization_pct || 0).toFixed(1)}%`} color={(kpis.credit_utilization_pct || 0) > 85 ? 'var(--color-danger)' : 'var(--text-primary)'} />
      </div>
    </div>
  )
}

function StatCard({ title, value, suffix, color, style }: { title: string, value: string, suffix?: string, color?: string, style?: React.CSSProperties }) {
  return (
    <div style={{ background: 'var(--bg-surface-2)', padding: 12, borderRadius: 8, border: '1px solid var(--border-secondary)', ...style }}>
      <div style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 6 }}>{title}</div>
      <div style={{ fontSize: 18, fontWeight: 700, color: color || 'var(--text-primary)' }}>
        {value} {suffix && <span style={{ fontSize: 12, fontWeight: 400, color: 'var(--text-secondary)' }}>{suffix}</span>}
      </div>
    </div>
  )
}

function CommercialHistorySection({ data }: { data: CustomerSalesByMonth[] }) {
  const avg = data.reduce((sum, d) => sum + d.net_revenue, 0) / data.length
  return (
    <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
      <h3 style={{ fontSize: 16, fontWeight: 700, marginBottom: 20 }}>الاتجاه الشهري للمبيعات</h3>
      <div style={{ height: 250, width: '100%' }}>
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={data} margin={{ top: 0, right: 0, left: 0, bottom: 0 }}>
            <XAxis dataKey="month" tick={{ fontSize: 10, fill: 'var(--text-muted)' }} tickLine={false} axisLine={false} />
            <Tooltip 
              cursor={{ fill: 'var(--bg-surface-2)' }}
              contentStyle={{ borderRadius: 8, border: '1px solid var(--border-primary)', fontSize: 12, textAlign: 'right' }}
              formatter={(value: number) => [`${value.toLocaleString()} ج.م`, '']}
            />
            <ReferenceLine y={avg} stroke="var(--color-warning)" strokeDasharray="3 3" />
            <Bar dataKey="net_revenue" name="صافي الإيراد" stackId="a" fill="var(--color-primary)" radius={[4, 4, 0, 0]} maxBarSize={18} />
            <Bar dataKey="returns_value" name="المرتجعات" stackId="b" fill="var(--color-danger)" radius={[4, 4, 0, 0]} maxBarSize={18} />
          </BarChart>
        </ResponsiveContainer>
      </div>
    </div>
  )
}

function TopProductsSection({ data }: { data: CustomerTopProduct[] }) {
  const STATUS_CFG = {
    'خامد':  { badge: 'badge-danger',  color: 'var(--color-danger)' },
    'جديد':  { badge: 'badge-info',    color: 'var(--color-info, #0284c7)' },
    'مستمر': { badge: 'badge-success', color: 'var(--color-success)' },
  } as const

  const RANK_COLORS = ['#f59e0b', '#64748b', '#b45309']  // gold, silver, bronze

  const fmt = (n: number) => n.toLocaleString('ar-EG-u-nu-latn')
  const fmtDate = (d: string | null) =>
    d ? new Date(d).toLocaleDateString('ar-EG', { month: 'short', day: 'numeric', year: 'numeric' }) : '—'

  const maxVal = Math.max(...data.map(p => Number(p.total_value)), 1)

  return (
    <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
        <h3 style={{ fontSize: 16, fontWeight: 700, margin: 0, display: 'flex', alignItems: 'center', gap: 8 }}>
          <Package size={16} style={{ color: 'var(--color-primary)' }} />
          المنتجات المفضلة
        </h3>
        <span style={{ fontSize: 11, color: 'var(--text-muted)', background: 'var(--bg-surface-2)', padding: '3px 8px', borderRadius: 20, border: '1px solid var(--border-secondary)' }}>
          أعلى {data.length} منتج
        </span>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {data.map((p, idx) => {
          const cfg = STATUS_CFG[p.status as keyof typeof STATUS_CFG] ?? STATUS_CFG['مستمر']
          const barPct = Math.round((Number(p.total_value) / maxVal) * 100)
          const isTopThree = idx < 3

          return (
            <div key={p.product_id} style={{
              background: 'var(--bg-surface-2)',
              border: '1px solid var(--border-secondary)',
              borderInlineStart: `3px solid ${isTopThree ? RANK_COLORS[idx] : 'var(--border-secondary)'}`,
              borderRadius: 8,
              padding: '12px 14px',
              transition: 'box-shadow 0.15s',
            }}>

              {/* ── الرسالة الرئيسية: اسم + تصنيف + حالة */}
              <div style={{ display: 'flex', alignItems: 'flex-start', gap: 10, marginBottom: 12 }}>
                {/* رقم الترتيب */}
                <div style={{
                  width: 22, height: 22, borderRadius: 4, flexShrink: 0, marginTop: 1,
                  background: isTopThree ? RANK_COLORS[idx] : 'var(--bg-surface)',
                  color: isTopThree ? '#fff' : 'var(--text-muted)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  fontSize: 10, fontWeight: 800,
                }}>
                  {idx + 1}
                </div>

                {/* الاسم والتصنيف */}
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontWeight: 700, fontSize: 13, color: 'var(--text-primary)', lineHeight: 1.4, marginBottom: 1 }}>
                    {p.product_name}
                  </div>
                  {p.category_name && p.category_name !== 'بدون تصنيف' && (
                    <div style={{ fontSize: 11, color: 'var(--text-muted)', lineHeight: 1 }}>{p.category_name}</div>
                  )}
                </div>

                {/* الحالة */}
                <span className={`badge ${cfg.badge}`} style={{ flexShrink: 0, fontSize: 10, padding: '2px 7px' }}>
                  {p.status}
                </span>
              </div>

              {/* ── شريط التقدم المرئي */}
              <div style={{ height: 3, background: 'var(--border-secondary)', borderRadius: 2, marginBottom: 10, overflow: 'hidden' }}>
                <div style={{ height: '100%', width: `${barPct}%`, background: cfg.color, borderRadius: 2, transition: 'width 0.4s ease' }} />
              </div>

              {/* ── المؤشرات المالية: صفان 2+2 */}
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 6, marginBottom: 10 }}>
                {/* إجمالي السحب */}
                <div style={{ background: 'var(--bg-surface)', borderRadius: 6, padding: '7px 10px' }}>
                  <div style={{ fontSize: 10, color: 'var(--text-muted)', marginBottom: 3 }}>إجمالي السحب</div>
                  <div style={{ fontSize: 14, fontWeight: 800, color: 'var(--text-primary)', lineHeight: 1 }}>
                    {fmt(Number(p.total_value))}
                    <span style={{ fontSize: 9, fontWeight: 400, color: 'var(--text-muted)', marginRight: 2 }}>ج.م</span>
                  </div>
                </div>

                {/* عدد الطلبات */}
                <div style={{ background: 'var(--bg-surface)', borderRadius: 6, padding: '7px 10px' }}>
                  <div style={{ fontSize: 10, color: 'var(--text-muted)', marginBottom: 3 }}>عدد الطلبات</div>
                  <div style={{ fontSize: 14, fontWeight: 800, color: 'var(--color-primary)', lineHeight: 1 }}>
                    {fmt(Number(p.order_count ?? 0))}
                    <span style={{ fontSize: 9, fontWeight: 400, color: 'var(--text-muted)', marginRight: 2 }}>طلب</span>
                  </div>
                </div>

                {/* الكمية المسحوبة */}
                <div style={{ background: 'var(--bg-surface)', borderRadius: 6, padding: '7px 10px' }}>
                  <div style={{ fontSize: 10, color: 'var(--text-muted)', marginBottom: 3 }}>الكمية</div>
                  <div style={{ fontSize: 14, fontWeight: 800, color: 'var(--text-primary)', lineHeight: 1 }}>
                    {fmt(Number(p.total_qty || 0))}
                    <span style={{ fontSize: 9, fontWeight: 400, color: 'var(--text-muted)', marginRight: 2 }}>وحدة</span>
                  </div>
                </div>

                {/* متوسط السعر */}
                <div style={{ background: 'var(--bg-surface)', borderRadius: 6, padding: '7px 10px' }}>
                  <div style={{ fontSize: 10, color: 'var(--text-muted)', marginBottom: 3 }}>متوسط السعر</div>
                  <div style={{ fontSize: 14, fontWeight: 800, color: 'var(--text-primary)', lineHeight: 1 }}>
                    {fmt(Number(p.avg_price || 0))}
                    <span style={{ fontSize: 9, fontWeight: 400, color: 'var(--text-muted)', marginRight: 2 }}>ج.م</span>
                  </div>
                </div>
              </div>

              {/* ── صف الميتاداتا السفلي: شيبس */}
              <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', alignItems: 'center' }}>
                {/* آخر شراء */}
                <div style={{
                  display: 'flex', alignItems: 'center', gap: 4, fontSize: 11,
                  background: 'var(--bg-surface)', border: '1px solid var(--border-secondary)',
                  borderRadius: 20, padding: '3px 8px', color: 'var(--text-secondary)',
                }}>
                  <Calendar size={9} style={{ color: 'var(--text-muted)' }} />
                  <span style={{ color: 'var(--text-muted)' }}>آخر شراء</span>
                  <span style={{ fontWeight: 600, color: 'var(--text-primary)' }}>{fmtDate(p.last_purchase_date)}</span>
                </div>

                {/* آخر 90 يوم — يظهر فقط إذا كان نشطًا */}
                {Number(p.value_l90d) > 0 && (
                  <div style={{
                    display: 'flex', alignItems: 'center', gap: 4, fontSize: 11,
                    background: 'rgba(22,163,74,0.08)', border: '1px solid var(--color-success)',
                    borderRadius: 20, padding: '3px 8px',
                  }}>
                    <TrendingUp size={9} color="var(--color-success)" />
                    <span style={{ color: 'var(--text-muted)' }}>90 يوم</span>
                    <span style={{ fontWeight: 600, color: 'var(--color-success)' }}>
                      {fmt(Number(p.value_l90d))} ج.م
                    </span>
                  </div>
                )}

                {/* المرتجعات — يظهر فقط إذا > 0 */}
                {(p.return_rate_pct || 0) > 0 && (
                  <div style={{
                    display: 'flex', alignItems: 'center', gap: 4, fontSize: 11,
                    background: (p.return_rate_pct || 0) > 10
                      ? 'rgba(220,38,38,0.08)' : 'var(--bg-surface)',
                    border: `1px solid ${(p.return_rate_pct || 0) > 10 ? 'var(--color-danger)' : 'var(--border-secondary)'}`,
                    borderRadius: 20, padding: '3px 8px',
                  }}>
                    <TrendingDown size={9} color={(p.return_rate_pct || 0) > 10 ? 'var(--color-danger)' : 'var(--text-muted)'} />
                    <span style={{ color: 'var(--text-muted)' }}>مرتجع</span>
                    <span style={{ fontWeight: 600, color: (p.return_rate_pct || 0) > 10 ? 'var(--color-danger)' : 'var(--text-secondary)' }}>
                      {(p.return_rate_pct || 0).toFixed(1)}%
                    </span>
                  </div>
                )}
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}



function CategoryMixSection({ data }: { data: CustomerCategoryMix[] }) {
  // Chart palette — CSS vars first, hex fallbacks only where no semantic token exists.
  // Matches the design system's distinction between primary/success/warning/info/accent.
  const COLORS = [
    'var(--color-primary)',
    'var(--color-info,    #3b82f6)',
    'var(--color-success, #10b981)',
    'var(--color-warning, #f59e0b)',
    'var(--color-accent,  #8b5cf6)',
  ]
  return (
    <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
      <h3 style={{ fontSize: 16, fontWeight: 700, marginBottom: 12 }}>توزيع التصنيفات</h3>
      <div style={{ display: 'flex', alignItems: 'flex-start', flexWrap: 'wrap', gap: 'var(--space-4)' }}>
        <div style={{ height: 200, flex: 1, minWidth: 160 }}>
          <ResponsiveContainer width="100%" height="100%">
            <PieChart>
              <Pie data={data} innerRadius={50} outerRadius={80} paddingAngle={2} dataKey="all_time_value">
                {data.map((entry, index) => <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />)}
              </Pie>
              <Tooltip formatter={(value: number) => [`${value.toLocaleString()} ج.م`, 'القيمة']} />
            </PieChart>
          </ResponsiveContainer>
        </div>
        <div style={{ flex: 1.5, minWidth: 0, overflow: 'hidden' }}>
          <table className="data-table" style={{ background: 'transparent' }}>
             <thead>
               <tr>
                 <th style={{ fontSize: 10, padding: '4px 8px' }}>التصنيف</th>
                 <th style={{ fontSize: 10, padding: '4px 8px', textAlign: 'center' }}>إجمالي</th>
                 <th style={{ fontSize: 10, padding: '4px 8px', textAlign: 'center' }}>90 يوم</th>
               </tr>
             </thead>
             <tbody>
               {data.map((d, i) => (
                 <tr key={d.category_id}>
                   <td style={{ fontSize: 11, padding: '4px 8px' }}>
                     <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                        <div style={{ width: 8, height: 8, borderRadius: '50%', background: COLORS[i % COLORS.length], flexShrink: 0 }} />
                        <span style={{ whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: 100 }} title={d.category_name}>{d.category_name}</span>
                     </div>
                   </td>
                   <td style={{ fontSize: 11, fontWeight: 600, textAlign: 'center', padding: '4px 8px' }}>{d.all_time_pct}%</td>
                   <td style={{ fontSize: 11, fontWeight: 600, textAlign: 'center', padding: '4px 8px', color: 'var(--color-primary)' }}>{d.recent_90d_pct}%</td>
                 </tr>
               ))}
             </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}

function ArAgingSection({ data }: { data: CustomerArAgingBucket[] }) {
  // Colors defined once outside the map — CSS vars with semantic fallbacks for dark mode
  const agingColors: Record<string, string> = {
    '0-30':  'var(--color-text-muted, #9ca3af)',
    '31-60': 'var(--color-warning)',
    '61-90': 'var(--color-danger)',
    '90+':   'var(--color-danger-dark, #7f1d1d)',
  }

  return (
    <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
      <h3 style={{ fontSize: 16, fontWeight: 700, marginBottom: 16 }}>أعمار الديون (AR Aging)</h3>
      <div style={{ display: 'flex', gap: 2, height: 40, overflow: 'hidden', borderRadius: 8, marginBottom: 10 }}>
        {data.map((d) => {
          if (d.amount === 0) return null
          const bgColor = agingColors[d.bucket] || 'var(--color-text-muted)'
          return (
            <div key={d.bucket} style={{ flex: d.amount, background: bgColor, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--color-on-danger, #fff)', fontSize: 10, fontWeight: 600, minWidth: 20 }}>
              {d.bucket}
            </div>
          )
        })}
      </div>
      <div style={{ display: 'flex', justifyContent: 'space-between', gap: 6, flexWrap: 'wrap' }}>
        {data.map(d => (
          <div key={d.bucket} style={{ fontSize: 11, textAlign: 'center' }}>
            <div style={{ fontWeight: 600, color: 'var(--text-primary)' }}>{Number(d.amount).toLocaleString()}</div>
            <div style={{ color: 'var(--text-muted)' }}>{d.bucket} ({d.invoice_count})</div>
          </div>
        ))}
      </div>
    </div>
  )
}

function PaymentBehaviorSection({ data }: { data: CustomerPaymentBehavior }) {
  const recent = data.recent_receipts || []
  // SQL returns SUM(amount) per payment_method — keys match schema CHECK constraint:
  // 'cash' | 'bank_transfer' | 'instapay' | 'cheque' | 'mobile_wallet'
  const breakdown = data.payment_methods_breakdown || {}
  const cash_abs       = breakdown['cash']           ?? 0
  const cheque_abs     = breakdown['cheque']         ?? 0
  const transfer_abs   = breakdown['bank_transfer']  ?? 0
  const instapay_abs   = breakdown['instapay']       ?? 0
  const wallet_abs     = breakdown['mobile_wallet']  ?? 0
  const total_abs = cash_abs + cheque_abs + transfer_abs + instapay_abs + wallet_abs
  // Convert to percentages safely
  const pct = (v: number) => total_abs > 0 ? (v / total_abs) * 100 : 0
  const cash_pct     = pct(cash_abs)
  const cheque_pct   = pct(cheque_abs)
  const transfer_pct = pct(transfer_abs)

  // Human-readable label for payment_method values
  const PM_LABEL: Record<string, string> = {
    cash: 'نقدي', cheque: 'شيك', bank_transfer: 'تحويل بنكي',
    instapay: 'إنستاباي', mobile_wallet: 'محفظة إلكترونية',
  }

  return (
    <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
      <h3 style={{ fontSize: 16, fontWeight: 700, marginBottom: 16 }}>سلوك السداد</h3>
      
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 16 }}>
        <div style={{ background: 'var(--bg-surface-2)', padding: 10, borderRadius: 8, textAlign: 'center' }}>
          <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>متوسط التأخير</div>
          <div style={{ fontSize: 16, fontWeight: 700 }}>{data.avg_payment_delay_days || 0} <span style={{fontSize: 10, fontWeight: 400}}>يوم</span></div>
        </div>
        <div style={{ background: 'var(--bg-surface-2)', padding: 10, borderRadius: 8, textAlign: 'center' }}>
          <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>طبيعة التحصيل</div>
          <div style={{ fontSize: 14, fontWeight: 700, color: cash_pct > 80 ? 'var(--color-success)' : 'var(--text-primary)' }}>
            {cash_pct.toFixed(0)}% نقدي
          </div>
        </div>
      </div>

      {/* Payment method breakdown — percentages computed from raw amounts */}
      {total_abs > 0 && (
        <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 16, borderBottom: '1px solid var(--border-secondary)', paddingBottom: 12, flexWrap: 'wrap' }}>
          {cheque_pct > 0 && (
            <div style={{ fontSize: 11 }}><span style={{ color: 'var(--text-muted)' }}>شيكات:</span> <span style={{ fontWeight: 600 }}>{cheque_pct.toFixed(0)}%</span></div>
          )}
          {transfer_pct > 0 && (
            <div style={{ fontSize: 11 }}><span style={{ color: 'var(--text-muted)' }}>تحويل بنكي:</span> <span style={{ fontWeight: 600 }}>{transfer_pct.toFixed(0)}%</span></div>
          )}
          {(instapay_abs > 0 || wallet_abs > 0) && (
            <div style={{ fontSize: 11 }}><span style={{ color: 'var(--text-muted)' }}>إلكتروني:</span> <span style={{ fontWeight: 600 }}>{pct(instapay_abs + wallet_abs).toFixed(0)}%</span></div>
          )}
        </div>
      )}

      {recent.length > 0 && (
        <div>
          <div style={{ fontSize: 12, fontWeight: 600, marginBottom: 8 }}>أحدث الدفعات</div>
          {recent.slice(0,5).map((r) => (
            <div key={r.number} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, padding: '8px 0', borderBottom: '1px solid var(--border-secondary)' }}>
              <div style={{ color: 'var(--text-muted)', width: 60 }}>{new Date(r.date).toLocaleDateString('ar-EG', {month: 'short', day: 'numeric'})}</div>
              <div style={{ flex: 1, textAlign: 'center', color: 'var(--color-primary)' }}>{PM_LABEL[r.payment_method] ?? r.payment_method}</div>
              <div style={{ fontWeight: 700, textAlign: 'start', fontVariantNumeric: 'tabular-nums' }}>{Number(r.amount).toLocaleString()} ج.م</div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

function ProfitabilitySection({ data }: { data: GrossProfitGrainResult[] | null | undefined }) {
  if (data === undefined) return <div className="skeleton" style={{ height: 150 }} />
  if (data === null) return (
    <div className="edara-card" style={{ padding: 'var(--space-6)', textAlign: 'center', background: 'var(--bg-surface-2)', border: '1px dashed var(--border-primary)' }}>
      <Lock size={32} style={{ color: 'var(--text-muted)', margin: '0 auto 12px' }} />
      <h3 style={{ fontSize: 16, fontWeight: 700, marginBottom: 4 }}>بيانات الربحية محجوبة</h3>
      <p style={{ fontSize: 13, color: 'var(--text-secondary)' }}>لا تملك الصلاحية الكافية (finance.view_costs) للإطلاع على الهوامش الربحية للعملاء.</p>
    </div>
  )

  if (data.length === 0) return null

  const sumRevenue = data.reduce((s, r) => s + Number(r.gross_revenue), 0)
  const sumProfit = data.reduce((s, r) => s + Number(r.gross_profit), 0)
  const margin = sumRevenue ? ((sumProfit / sumRevenue) * 100).toFixed(1) : '0'

  return (
    <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
      <h3 style={{ fontSize: 16, fontWeight: 700, marginBottom: 16, display: 'flex', alignItems: 'center', gap: 6 }}>
        <DollarSign size={16} color="var(--color-success)" /> تحليل الربحية 
        <FreshnessIndicator date={data[data.length - 1]?.period} label="T-1" />
      </h3>
      <div style={{ display: 'flex', gap: 12, marginBottom: 20, flexWrap: 'wrap' }}>
        <StatCard title="إجمالي الإيراد" value={sumRevenue.toLocaleString()} suffix="ج.م" style={{ flex: 1, minWidth: 110 }} />
        <StatCard title="مجمل الربح" value={sumProfit.toLocaleString()} suffix="ج.م" style={{ flex: 1, minWidth: 110 }} />
        <StatCard title="هامش الربح" value={`${margin}%`} color={Number(margin) < 10 ? 'var(--color-danger)' : 'var(--color-success)'} style={{ flex: 1, minWidth: 110 }} />
      </div>
      <div style={{ height: 200, width: '100%' }}>
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={data} margin={{ top: 0, right: 0, left: 0, bottom: 0 }}>
            <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--border-secondary)" />
            <XAxis dataKey="period" tick={{ fontSize: 10, fill: 'var(--text-muted)' }} tickFormatter={(val) => val.substring(0, 7)} />
            <Tooltip contentStyle={{ borderRadius: 8, fontSize: 12, textAlign: 'right' }} formatter={(v: number) => [`${v.toLocaleString()} ج.م`, '']} />
            <Line type="monotone" dataKey="gross_profit" name="مجمل الربح" stroke="var(--color-success)" strokeWidth={3} dot={{ r: 4 }} />
            <Line type="monotone" dataKey="net_cogs" name="التكلفة" stroke="var(--color-danger)" strokeWidth={2} dot={false} strokeDasharray="4 4" />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  )
}

function TimelineSection({ timeline }: { timeline: { data: { pages: CustomerTimelineEvent[][] } | undefined, isPending: boolean, hasNextPage: boolean, fetchNextPage: () => void, isFetchingNextPage: boolean } }) {
  if (timeline.isPending) return <div className="skeleton" style={{ height: 200 }} />
  
  const pages = timeline.data?.pages || []
  const allEvents = pages.flatMap(p => p)
  
  return (
    <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
      <h3 style={{ fontSize: 16, fontWeight: 700, marginBottom: 16 }}>التسلسل الزمني</h3>
      <div style={{ position: 'relative', paddingRight: 10, borderRight: '2px solid var(--border-secondary)' }}>
        {allEvents.map((evt) => {
          const isRed = ['return', 'credit_change'].includes(evt.event_type) && evt.amount < 0
          return (
            <div key={evt.event_id} style={{ position: 'relative', marginBottom: 16, paddingRight: 16 }}>
              <div style={{ position: 'absolute', right: -15, top: 4, width: 10, height: 10, borderRadius: '50%', background: 'var(--color-primary)', border: '2px solid var(--bg-surface)' }} />
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginBottom: 2 }}>
                {new Date(evt.event_ts).toLocaleString('ar-EG')}
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontSize: 13, fontWeight: 600 }}>{evt.title}</span>
                {evt.amount !== 0 && (
                  <span style={{ fontSize: 13, fontWeight: 700, color: isRed ? 'var(--color-danger)' : 'var(--text-primary)' }}>
                    {Math.abs(evt.amount).toLocaleString()} ج.م
                  </span>
                )}
              </div>
              <div style={{ display: 'flex', gap: 8, marginTop: 4, fontSize: 11, color: 'var(--text-secondary)' }}>
                {evt.actor && <span>👤 {evt.actor}</span>}
                <span className="badge badge-neutral" style={{ fontSize: 10, padding: '2px 4px' }}>{evt.status}</span>
              </div>
            </div>
          )
        })}
      </div>
      {timeline.hasNextPage && (
        <button onClick={() => timeline.fetchNextPage()} disabled={timeline.isFetchingNextPage} className="btn" style={{ width: '100%', marginTop: 12, background: 'var(--bg-surface-2)', border: '1px solid var(--border-primary)', fontSize: 12 }}>
          {timeline.isFetchingNextPage ? 'جاري التحميل...' : 'تحميل المزيد'}
        </button>
      )}
    </div>
  )
}

function LedgerPreviewSection({ ledger, customerId }: { ledger: { data: { pages: CustomerLedgerEntry[][] } | undefined, isPending: boolean, hasNextPage: boolean, fetchNextPage: () => void, isFetchingNextPage: boolean }, customerId: string }) {
  const navigate = useNavigate()
  if (ledger.isPending) return <div className="skeleton" style={{ height: 150 }} />

  const pages = ledger.data?.pages || []
  const allEntries = pages.flatMap(p => p)

  if (allEntries.length === 0) return null

  return (
    <div className="edara-card" style={{ padding: '0', overflow: 'hidden' }}>
      <div style={{ padding: 'var(--space-4)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h3 style={{ fontSize: 16, fontWeight: 700, margin: 0, display: 'flex', gap: 6, alignItems: 'center' }}>
          <List size={16} /> كشف الحساب المختصر
        </h3>
      </div>
      <table className="data-table" style={{ borderTop: '1px solid var(--border-secondary)' }}>
        <thead style={{ background: 'var(--bg-surface-2)' }}>
          <tr>
            <th style={{ fontSize: 11 }}>التاريخ</th>
            <th style={{ fontSize: 11 }}>مدين</th>
            <th style={{ fontSize: 11 }}>دائن</th>
            <th style={{ fontSize: 11 }}>الرصيد</th>
          </tr>
        </thead>
        <tbody>
          {allEntries.map((e) => (
            <tr key={e.id}>
              <td style={{ fontSize: 11, color: 'var(--text-muted)' }}>{new Date(e.created_at).toLocaleDateString('ar-EG', { month: 'short', day: 'numeric' })}</td>
              <td style={{ fontSize: 12, fontWeight: 600, color: 'var(--text-primary)' }}>{e.type === 'debit' ? Number(e.amount).toLocaleString() : ''}</td>
              <td style={{ fontSize: 12, fontWeight: 600, color: 'var(--color-success)' }}>{e.type === 'credit' ? Number(e.amount).toLocaleString() : ''}</td>
              <td style={{ fontSize: 12, fontWeight: 700 }}>{Number(e.running_balance).toLocaleString()}</td>
            </tr>
          ))}
        </tbody>
      </table>
      {ledger.hasNextPage && (
        <div style={{ padding: '8px 12px', borderTop: '1px solid var(--border-secondary)', textAlign: 'center' }}>
          <button onClick={() => ledger.fetchNextPage()} disabled={ledger.isFetchingNextPage} className="btn" style={{ fontSize: 11, background: 'transparent', border: 'none', color: 'var(--color-primary)', fontWeight: 600, cursor: 'pointer' }}>
            تحميل المزيد...
          </button>
        </div>
      )}
    </div>
  )
}
