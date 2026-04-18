import type {
  Customer360Kpis,
  CustomerHealthSnapshot,
  CustomerRiskSnapshot,
  CustomerArAgingBucket,
  CustomerPaymentBehavior,
} from '../services/customer360'
import type { GrossProfitGrainResult } from '../types/profitability'

export const THRESHOLDS = {
  dormant_days:             60,
  overdue_critical_days:    90,
  credit_utilization_high:  0.85,
  high_payment_delay_days:  45,
  return_rate_high:         0.15,
  category_concentration:   0.80,
  sales_decline_pct:        0.30,
  churned_min_count:        2,
  low_gross_margin:         0.05,
} as const

export type RecommendationSeverity = 'critical' | 'warning' | 'opportunity' | 'positive' | 'info'
export type RecommendationCategory = 'collection' | 'sales' | 'credit' | 'risk' | 'opportunity' | 'system' | 'retention'

export interface Recommendation {
  id: string
  severity: RecommendationSeverity
  category: RecommendationCategory
  title: string
  reason: string
  action?: string
  action_url?: string
}

export interface ComputeRecommendationsInputs {
  customer: { id: string; name?: string; current_balance?: number; is_active?: boolean }
  kpis?: Customer360Kpis | null
  health?: CustomerHealthSnapshot | null
  risk?: CustomerRiskSnapshot | null
  arAging?: CustomerArAgingBucket[] | null
  paymentBehavior?: CustomerPaymentBehavior | null
  profitability?: GrossProfitGrainResult[] | null
  churned_products_count?: number
  category_concentration?: number
  monthly_trend_delta?: number
  avg_monetary_l90d?: number // To satisfy 'monetary_l90d > avg' rule
}

export function computeRecommendations(inputs: ComputeRecommendationsInputs): Recommendation[] {
  const recs: Recommendation[] = []

  // 1. Overdue Critical
  if (inputs.arAging && inputs.arAging.length > 0) {
    const overdue90Plus = inputs.arAging.find(b => b.bucket === '90+')
    if (overdue90Plus && overdue90Plus.amount > 0) {
      recs.push({
        id: 'overdue_critical',
        category: 'collection',
        severity: 'critical',
        title: 'مديونية متأخرة تجاوزت 90 يومًا',
        reason: `لديه ${overdue90Plus.invoice_count} فواتير بإجمالي ${overdue90Plus.amount.toLocaleString()} ج.م متأخرة 90+ يومًا`,
        action: 'تحصيل فوري'
      })
    }
  }

  // 2. Dormant High Value
  // Requires avg_monetary_l90d to be provided for a fair comparison.
  // If avg_monetary_l90d is absent, the rule is suppressed to avoid a false critical
  // alert based solely on monetary_l90d > 0 (any customer with any past revenue would qualify).
  if (inputs.health?.recency_days && inputs.health.recency_days > THRESHOLDS.dormant_days) {
    if (inputs.avg_monetary_l90d !== undefined && inputs.avg_monetary_l90d !== null) {
      const isHighValue = (inputs.health.monetary_l90d ?? 0) > inputs.avg_monetary_l90d
      if (isHighValue) {
        recs.push({
          id: 'dormant_high_value',
          category: 'risk',
          severity: 'critical',
          title: 'انقطاع عميل عالي القيمة',
          reason: `انقطع العميل منذ ${inputs.health.recency_days} يوماً برغم أن مسحوباته الأخيرة كانت بقيمة ${inputs.health.monetary_l90d?.toLocaleString()} ج.م`,
          action: 'تواصل لمعرفة سبب الانقطاع'
        })
      }
    }
    // When avg_monetary_l90d is not available, dormant_high_value is deferred.
    // The customer_inactive rule (below) will still fire for dormant customers.
  }

  // 3. Credit Near Limit
  if (inputs.kpis?.credit_limit && inputs.kpis.credit_limit > 0 && inputs.customer.current_balance !== undefined) {
    const util = inputs.customer.current_balance / inputs.kpis.credit_limit
    if (util > THRESHOLDS.credit_utilization_high) {
      recs.push({
        id: 'credit_near_limit',
        category: 'credit',
        severity: 'warning',
        title: 'استخدام ائتماني مرتفع',
        reason: `معدل الاستخدام ${(util * 100).toFixed(1)}% من الحد الائتماني البالغ ${inputs.kpis.credit_limit.toLocaleString()} ج.م`,
        action: 'مراجعة الحد الائتماني'
      })
    }
  }

  // 4. Slow Payer
  if (inputs.paymentBehavior?.avg_payment_delay_days && inputs.paymentBehavior.avg_payment_delay_days > THRESHOLDS.high_payment_delay_days) {
    recs.push({
      id: 'slow_payer',
      category: 'collection',
      severity: 'warning',
      title: 'تباطؤ في السداد',
      reason: `متوسط أيام تأخير السداد بلغ ${inputs.paymentBehavior.avg_payment_delay_days.toFixed(0)} يوماً`,
    })
  }

  // 5. High Return Rate
  if (inputs.kpis?.return_rate_pct !== undefined && inputs.kpis.return_rate_pct !== null) {
    // Return rate is traditionally given as a percentage like 15 for 15%. Threshold is 0.15. Thus 15 > 0.15 * 100
    if (inputs.kpis.return_rate_pct > THRESHOLDS.return_rate_high * 100) {
      recs.push({
        id: 'high_return_rate',
        category: 'risk',
        severity: 'warning',
        title: 'معدل مرتجعات غير طبيعي',
        reason: `نسبة المرتجعات تبلغ ${inputs.kpis.return_rate_pct.toFixed(1)}% من إجمالي المبيعات`
      })
    }
  }

  // 6. Churned Products
  if (inputs.churned_products_count !== undefined && inputs.churned_products_count >= THRESHOLDS.churned_min_count) {
    recs.push({
      id: 'churned_products',
      category: 'opportunity',
      severity: 'opportunity',
      title: 'فرصة بيع تصالبية (Cross-sell)',
      reason: `العميل توقف عن شراء ${inputs.churned_products_count} منتجات كانت ضمن تفضيلاته`,
    })
  }

  // 7. Category Concentration
  if (inputs.category_concentration !== undefined && inputs.category_concentration > THRESHOLDS.category_concentration) {
    recs.push({
      id: 'category_concentration',
      category: 'opportunity',
      severity: 'opportunity',
      title: 'تركز شرائي مرتفع',
      reason: `حوالي ${(inputs.category_concentration * 100).toFixed(0)}% من مسحوبات العميل تتركز في تصنيف رئيسي واحد`,
    })
  }

  // 8. Sales Decline
  if (inputs.monthly_trend_delta !== undefined && inputs.monthly_trend_delta < -THRESHOLDS.sales_decline_pct) {
    recs.push({
      id: 'sales_decline',
      category: 'sales',
      severity: 'warning',
      title: 'تراجع مستمر في المبيعات',
      reason: `هناك تراجع بنسبة ${(Math.abs(inputs.monthly_trend_delta) * 100).toFixed(1)}% مقارنة بفترات النشاط المعتادة`,
    })
  }

  // 9. Credit Balance (Positive state)
  if (inputs.customer.current_balance !== undefined && inputs.customer.current_balance < 0) {
    recs.push({
      id: 'credit_balance',
      category: 'credit',
      severity: 'positive',
      title: 'رصيد دائن للعميل',
      reason: `يوجد دفعة مسددة مقدماً للعميل بقيمة ${Math.abs(inputs.customer.current_balance).toLocaleString()} ج.م جاهزة لتغطية الطلبات الجديدة`,
    })
  }

  // 10. Low Margin
  if (inputs.profitability !== null && inputs.profitability !== undefined && inputs.profitability.length > 0) {
    const totalRev = inputs.profitability.reduce((sum, r) => sum + Number(r.gross_revenue), 0)
    const totalProfit = inputs.profitability.reduce((sum, r) => sum + Number(r.gross_profit), 0)
    
    if (totalRev > 0) {
      const margin = totalProfit / totalRev
      if (margin < THRESHOLDS.low_gross_margin) {
        recs.push({
          id: 'low_margin',
          category: 'risk',
          severity: 'warning',
          title: 'هامش ربح تشغيلي منخفض',
          reason: `هوامش الربحية للعميل انخفضت لتصل إلى ${(margin * 100).toFixed(1)}% وهو دون الحد الأدنى الآمن`
        })
      }
    }
  }

  // 11. Customer Inactive
  if (inputs.customer.is_active === false || inputs.health?.health_status === 'خامد') {
    // Avoid duplicating inactive vs dormant if already pushed
    if (!recs.find(r => r.id === 'dormant_high_value')) {
      recs.push({
        id: 'customer_inactive',
        category: 'retention',
        severity: 'warning',
        title: 'عميل منقطع متوقف',
        reason: 'توقف العميل عن السحب ولا توجد له تفاعلات حديثة في الفترات السابقة الذكر.',
      })
    }
  }

  // 12. Profitability Lock State
  if (inputs.profitability === null) {
    recs.push({
      id: 'profitability_locked',
      category: 'system',
      severity: 'info',
      title: 'بيانات الربحية محجوبة',
      reason: 'مستوى الوصول الخاص بك قياسي لا يسمح برؤية هوامش وحسابات تكلفة المبيعات للعميل.'
    })
  }

  return recs
}
