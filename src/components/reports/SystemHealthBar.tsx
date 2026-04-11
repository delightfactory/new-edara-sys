import type { TrustStateRow } from '@/hooks/useSystemTrustState'
import { AnalyticsUnauthorizedError, AnalyticsNotDeployedError, analyticsRefreshNow } from '@/lib/services/analyticsClient'
import TrustStateBadge from './TrustStateBadge'
import FreshnessIndicator from './FreshnessIndicator'
import { RefreshCw, AlertTriangle, Lock, Database } from 'lucide-react'
import { useState } from 'react'
import { toast } from 'sonner'
import { useQueryClient } from '@tanstack/react-query'
import { useAuthStore } from '@/stores/auth-store'

interface Props {
  trustRows: TrustStateRow[] | undefined
  isLoading: boolean
  error?: Error | null
}

const COMPONENT_LABELS: Record<string, string> = {
  fact_sales_daily_grain: 'إيرادات المبيعات',
  'fact_sales_daily_grain.revenue': 'الإيراد الصافي',
  'fact_sales_daily_grain.tax': 'ضريبة القيمة المضافة',
  'fact_sales_daily_grain.ar_creation': 'نشأة الذمم',
  fact_treasury_cashflow_daily: 'التدفق النقدي',
  'fact_treasury_cashflow_daily.net_collection': 'صافي التحصيل',
  fact_ar_collections_attributed_to_origin_sale_date: 'تحصيلات AR',
  snapshot_customer_health: 'صحة العملاء',
  fact_financial_ledgers_daily: 'السجل المالي',
  fact_geography_daily: 'التحليل الجغرافي',
  snapshot_customer_risk: 'خطر الخمود',
  snapshot_target_attainment: 'إنجاز الأهداف',
  GLOBAL_SWEEP: 'المحرك الكلي',
}

function classifyError(err: Error): { icon: typeof AlertTriangle; color: string; bg: string; message: string } {
  if (err instanceof AnalyticsUnauthorizedError) {
    return {
      icon: Lock,
      color: 'var(--color-danger)',
      bg: 'rgba(220,38,38,0.05)',
      message: `غير مصرح بجلب حالة المحرك لهذا القسم${err.domain ? ` (${err.domain})` : ''}`,
    }
  }

  if (err instanceof AnalyticsNotDeployedError) {
    return {
      icon: Database,
      color: 'var(--color-info)',
      bg: 'rgba(37,99,235,0.04)',
      message: 'محرك التقارير غير مطبق بعد. طبّق الـ migrations المطلوبة أولًا.',
    }
  }

  return {
    icon: AlertTriangle,
    color: 'var(--color-warning)',
    bg: 'rgba(217,119,6,0.05)',
    message: 'تعذر الاتصال بمحرك الثقة. تحقق من الشبكة أو أعد تحميل الصفحة.',
  }
}

export default function SystemHealthBar({ trustRows, isLoading, error }: Props) {
  const queryClient = useQueryClient()
  const hasAdminRefresh = useAuthStore(s => s.can('reports.view_all'))
  const [isRefreshing, setIsRefreshing] = useState(false)

  const handleRefresh = async () => {
    setIsRefreshing(true)
    const toastId = toast.loading('جارٍ تشغيل محرك التحديث...')

    try {
      const started = await analyticsRefreshNow()
      if (started) {
        toast.success('تم تشغيل التحديث. راقب حالة المحرك أدناه.', { id: toastId })
        void queryClient.invalidateQueries({ queryKey: ['analytics', 'system-trust-state'] })
        void queryClient.invalidateQueries({ queryKey: ['profitability'] })
      } else {
        toast.success('المحرك يعمل بالفعل. حدّث بعد اكتمال المعالجة.', { id: toastId })
      }
    } catch (err: any) {
      toast.error(err.message || 'فشل تشغيل التحديث والتزامن', { id: toastId })
    } finally {
      setIsRefreshing(false)
    }
  }

  const visibleRows = trustRows?.filter(r => r.component_name !== 'GLOBAL_SWEEP') ?? []
  const anyBlocked = visibleRows.some(r => r.status === 'BLOCKED' || r.status === 'FAILED')
  const anyStale = visibleRows.some(r => r.is_stale)

  if (isLoading) {
    return (
      <div style={{
        background: 'var(--bg-surface)',
        border: '1px solid var(--border-primary)',
        borderRadius: 'var(--radius-md)',
        padding: 'var(--space-3) var(--space-4)',
        display: 'flex',
        alignItems: 'center',
        gap: 'var(--space-2)',
        fontSize: 'var(--text-xs)',
        color: 'var(--text-muted)',
      }}>
        <RefreshCw size={12} className="animate-spin" />
        جارٍ تحميل حالة المحرك...
      </div>
    )
  }

  if (error) {
    const { icon: Icon, color, bg, message } = classifyError(error)
    return (
      <div style={{
        background: bg,
        border: `1px solid ${color}33`,
        borderRadius: 'var(--radius-md)',
        padding: 'var(--space-3) var(--space-4)',
        display: 'flex',
        alignItems: 'center',
        gap: 'var(--space-2)',
        fontSize: 'var(--text-xs)',
        color,
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
      borderRadius: 'var(--radius-md)',
      padding: 'var(--space-3) var(--space-4)',
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-3)',
      flexWrap: 'wrap',
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
        <span style={{ color: 'var(--text-muted)' }}>لا توجد بيانات حتى الآن. شغّل التحديث أولًا.</span>
      )}

      {hasAdminRefresh && (
        <button
          onClick={handleRefresh}
          disabled={isRefreshing || isLoading}
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '4px',
            background: 'var(--color-primary)',
            color: 'white',
            border: 'none',
            borderRadius: 'var(--radius-sm)',
            padding: 'var(--space-1) var(--space-3)',
            fontSize: 'var(--text-xs)',
            cursor: (isRefreshing || isLoading) ? 'not-allowed' : 'pointer',
            opacity: (isRefreshing || isLoading) ? 0.6 : 1,
            marginRight: 'auto',
            fontWeight: 500,
            transition: 'all 0.2s',
          }}
        >
          <RefreshCw size={12} className={isRefreshing ? 'animate-spin' : ''} />
          تحديث الآن
        </button>
      )}
    </div>
  )
}
