import { AlertCircle, CheckCircle, FileText, TrendingUp, Truck } from 'lucide-react'
import type { SalesOrderStatus } from '@/lib/types/master-data'
import { formatNumber } from '@/lib/utils/format'
import { useDeviceMode } from '@/hooks/useDeviceMode'
import StatCard from '@/components/patterns/StatCard'
import StatusBadge, { type SemanticTone } from '@/components/patterns/StatusBadge'

export const SALES_ORDER_STATUS_LABELS: Record<SalesOrderStatus, string> = {
  draft: 'مسودة',
  confirmed: 'مؤكد',
  partially_delivered: 'مسلّم جزئياً',
  delivered: 'مُسلّم',
  completed: 'مكتمل',
  cancelled: 'ملغي',
}

export const SALES_ORDER_STATUS_TONES: Record<SalesOrderStatus, SemanticTone> = {
  draft: 'neutral',
  confirmed: 'info',
  partially_delivered: 'info',
  delivered: 'success',
  completed: 'success',
  cancelled: 'danger',
}

export interface SalesOrdersKpiSnapshot {
  totalSales: number
  statusCounts: Partial<Record<SalesOrderStatus, number>>
}

export function SalesOrderStatusBadge({ status }: { status: SalesOrderStatus }) {
  return (
    <StatusBadge
      label={SALES_ORDER_STATUS_LABELS[status]}
      tone={SALES_ORDER_STATUS_TONES[status]}
    />
  )
}

export function SalesOrdersKpiGrid({ stats }: { stats: SalesOrdersKpiSnapshot }) {
  const device = useDeviceMode()
  const gridTemplateColumns = device === 'desktop'
    ? 'minmax(16rem, 2fr) repeat(4, minmax(0, 1fr))'
    : device === 'tablet'
      ? 'repeat(3, minmax(0, 1fr))'
      : 'repeat(2, minmax(0, 1fr))'
  const primaryGridColumn = device === 'desktop'
    ? 'auto'
    : device === 'tablet'
      ? '1 / -1'
      : '1 / -1'

  const count = (status: SalesOrderStatus) => (stats.statusCounts[status] ?? 0).toLocaleString('en-US')

  return (
    <section
      aria-label="ملخص أوامر البيع"
      data-device={device}
      style={{
        display: 'grid',
        gridTemplateColumns,
        gap: 'var(--space-3)',
        marginBlockEnd: 'var(--space-4)',
      }}
    >
      <div style={{ gridColumn: primaryGridColumn, minWidth: 0 }}>
        <StatCard
          label="إجمالي المبيعات"
          value={<span dir="ltr">{formatNumber(stats.totalSales)} <small>ج.م</small></span>}
          icon={<TrendingUp size={18} />}
          tone="info"
        />
      </div>

      <StatCard
        label="مسودة"
        value={count('draft')}
        icon={<FileText size={18} />}
        tone="neutral"
      />
      <StatCard
        label="مؤكد"
        value={count('confirmed')}
        icon={<CheckCircle size={18} />}
        tone="info"
      />
      <StatCard
        label="مُسلّم"
        value={count('delivered')}
        icon={<Truck size={18} />}
        tone="success"
      />
      <StatCard
        label="ملغي"
        value={count('cancelled')}
        icon={<AlertCircle size={18} />}
        tone="danger"
      />
    </section>
  )
}
