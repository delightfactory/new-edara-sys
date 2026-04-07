import type { TrustStateRow } from '@/hooks/useSystemTrustState'
import { AnalyticsUnauthorizedError, AnalyticsNotDeployedError } from '@/lib/services/analyticsClient'
import TrustStateBadge from './TrustStateBadge'
import FreshnessIndicator from './FreshnessIndicator'
import { RefreshCw, AlertTriangle, Lock, Database } from 'lucide-react'

interface Props {
  trustRows: TrustStateRow[] | undefined
  isLoading: boolean
  error?: Error | null
}

const COMPONENT_LABELS: Record<string, string> = {
  'fact_sales_daily_grain':                                'إيرادات المبيعات',
  'fact_sales_daily_grain.revenue':                        'الإيراد الصافي',
  'fact_sales_daily_grain.tax':                            'ضريبة القيمة المضافة',
  'fact_sales_daily_grain.ar_creation':                    'نشأة الذمم',
  'fact_treasury_cashflow_daily':                          'التدفق النقدي',
  'fact_treasury_cashflow_daily.net_collection':           'صافي التحصيل',
  'fact_ar_collections_attributed_to_origin_sale_date':   'تحصيلات AR',
  'snapshot_customer_health':                              'صحة العملاء',
  'fact_financial_ledgers_daily':                         'السجل المالي',
  'GLOBAL_SWEEP':                                          'المحرك الكلي',
}

/**
 * Classifies the trust query error into three honest categories:
 *   1. unauthorized  — permission mismatch (domain/role issue)
 *   2. not_deployed  — analytics schema or RPCs missing
 *   3. transient     — network/unknown error
 */
function classifyError(err: Error): { icon: typeof AlertTriangle; color: string; bg: string; message: string } {
  if (err instanceof AnalyticsUnauthorizedError) {
    return {
      icon: Lock,
      color: 'var(--color-danger)',
      bg: 'rgba(220,38,38,0.05)',
      message: `غير مصرح بجلب حالة المحرك لهذا القسم — تأكد من الصلاحية المطلوبة${err.domain ? ` (${err.domain})` : ''}`,
    }
  }
  if (err instanceof AnalyticsNotDeployedError) {
    return {
      icon: Database,
      color: 'var(--color-info)',
      bg: 'rgba(37,99,235,0.04)',
      message: 'محرك التقارير غير مُنشَّر بعد — طبّق migrations 75 / 76 / 77 أولاً',
    }
  }
  // Transient / unknown
  return {
    icon: AlertTriangle,
    color: 'var(--color-warning)',
    bg: 'rgba(217,119,6,0.05)',
    message: 'تعذّر الاتصال بمحرك الثقة — تحقق من الاتصال بالشبكة أو أعد تحميل الصفحة',
  }
}

export default function SystemHealthBar({ trustRows, isLoading, error }: Props) {
  const visibleRows = trustRows?.filter(r => r.component_name !== 'GLOBAL_SWEEP') ?? []
  const anyBlocked = visibleRows.some(r => r.status === 'BLOCKED' || r.status === 'FAILED')
  const anyStale   = visibleRows.some(r => r.is_stale)

  if (isLoading) {
    return (
      <div style={{
        background: 'var(--bg-surface)', border: '1px solid var(--border-primary)',
        borderRadius: 'var(--radius-md)', padding: 'var(--space-3) var(--space-4)',
        display: 'flex', alignItems: 'center', gap: 'var(--space-2)',
        fontSize: 'var(--text-xs)', color: 'var(--text-muted)',
      }}>
        <RefreshCw size={12} className="animate-spin" />
        جارٍ تحديث حالة المحرك…
      </div>
    )
  }

  if (error) {
    const { icon: Icon, color, bg, message } = classifyError(error)
    return (
      <div style={{
        background: bg, border: `1px solid ${color}33`,
        borderRadius: 'var(--radius-md)', padding: 'var(--space-3) var(--space-4)',
        display: 'flex', alignItems: 'center', gap: 'var(--space-2)',
        fontSize: 'var(--text-xs)', color,
      }}>
        <Icon size={12} />
        {message}
      </div>
    )
  }

  return (
    <div style={{
      background: anyBlocked ? 'rgba(220,38,38,0.04)' : anyStale ? 'rgba(217,119,6,0.04)' : 'var(--bg-surface)',
      border: `1px solid ${anyBlocked ? 'rgba(220,38,38,0.2)' : anyStale ? 'rgba(217,119,6,0.2)' : 'var(--border-primary)'}`,
      borderRadius: 'var(--radius-md)', padding: 'var(--space-3) var(--space-4)',
      display: 'flex', alignItems: 'center', gap: 'var(--space-3)', flexWrap: 'wrap',
      fontSize: 'var(--text-xs)',
    }}>
      <span style={{ color: 'var(--text-secondary)', fontWeight: 600 }}>حالة المحرك:</span>
      {visibleRows.map(row => (
        <div key={row.component_name} style={{ display: 'flex', alignItems: 'center', gap: '5px' }}>
          <span style={{ color: 'var(--text-muted)' }}>
            {COMPONENT_LABELS[row.component_name] ?? row.component_name}
          </span>
          <TrustStateBadge
            status={row.status}
            size="sm"
            domain={row.component_name.includes('treasury') ? 'treasury' : 'default'}
          />
          {row.is_stale && (
            <FreshnessIndicator lastCompletedAt={row.last_completed_at} isStale />
          )}
        </div>
      ))}
      {visibleRows.length === 0 && (
        <span style={{ color: 'var(--text-muted)' }}>لا توجد بيانات حتى الآن — شغّل sweep أولاً</span>
      )}
    </div>
  )
}
