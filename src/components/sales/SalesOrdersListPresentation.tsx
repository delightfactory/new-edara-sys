import {
  AlertCircle,
  CheckCircle,
  Eye,
  FileText,
  MapPin,
  PhoneCall,
  ShoppingCart,
  TrendingUp,
  Truck,
} from 'lucide-react'
import type { ReactNode } from 'react'
import type { SalesOrderStatus } from '@/lib/types/master-data'
import { formatNumber } from '@/lib/utils/format'
import { useDeviceMode } from '@/hooks/useDeviceMode'
import Button from '@/components/ui/Button'
import Card from '@/components/patterns/Card'
import KeyValueList, { type KeyValueItem } from '@/components/patterns/KeyValueList'
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

export interface SalesOrderCardSummary {
  customerName: ReactNode
  customerCode?: ReactNode
  orderNumber: ReactNode
  orderDate: ReactNode
  status: SalesOrderStatus
  total: ReactNode
  paid: ReactNode
  outstanding?: ReactNode
  paymentTerms?: ReactNode
  representative?: ReactNode
  paidPercent?: number
}

export interface SalesOrderCardProps {
  summary: SalesOrderCardSummary
  mode: 'mobile' | 'tablet'
  onOpen: () => void
  onMap?: () => void
  onCall?: () => void
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
  const primaryGridColumn = device === 'desktop' ? 'auto' : '1 / -1'

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

      <StatCard label="مسودة" value={count('draft')} icon={<FileText size={18} />} tone="neutral" />
      <StatCard label="مؤكد" value={count('confirmed')} icon={<CheckCircle size={18} />} tone="info" />
      <StatCard label="مُسلّم" value={count('delivered')} icon={<Truck size={18} />} tone="success" />
      <StatCard label="ملغي" value={count('cancelled')} icon={<AlertCircle size={18} />} tone="danger" />
    </section>
  )
}

/**
 * SalesOrderCard — Sales-domain composition over shared V2 primitives.
 *
 * Business/query/calculation truth stays with the page. This component receives
 * already-projected values and only owns responsive information hierarchy,
 * semantic status, touch-safe actions and payment-progress presentation.
 */
export function SalesOrderCard({ summary, mode, onOpen, onMap, onCall }: SalesOrderCardProps) {
  const paidPercent = summary.paidPercent == null
    ? undefined
    : Math.max(0, Math.min(100, Math.round(summary.paidPercent)))

  const metadata: KeyValueItem[] = [
    { key: 'date', label: 'التاريخ', value: summary.orderDate },
    { key: 'total', label: 'الإجمالي', value: summary.total, emphasis: 'strong' },
    { key: 'paid', label: 'المدفوع', value: summary.paid },
  ]

  if (summary.outstanding != null) {
    metadata.push({ key: 'outstanding', label: 'المتبقي', value: summary.outstanding, emphasis: 'strong' })
  }
  if (summary.paymentTerms != null) {
    metadata.push({ key: 'payment', label: 'الدفع', value: summary.paymentTerms })
  }
  if (summary.representative != null) {
    metadata.push({ key: 'rep', label: 'المندوب', value: summary.representative })
  }

  return (
    <Card surface="default" padding={mode === 'tablet' ? 'md' : 'sm'} data-sales-order-card data-mode={mode}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 'var(--space-3)' }}>
        <div
          aria-hidden="true"
          style={{
            width: 42,
            height: 42,
            borderRadius: 'var(--radius-lg)',
            background: 'var(--bg-accent)',
            color: 'var(--color-primary)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            flexShrink: 0,
          }}
        >
          <ShoppingCart size={18} />
        </div>

        <div style={{ minWidth: 0, flex: 1 }}>
          <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-start', justifyContent: 'space-between', flexWrap: 'wrap' }}>
            <div style={{ minWidth: 0 }}>
              <div style={{ fontWeight: 700, color: 'var(--text-primary)', overflowWrap: 'anywhere' }}>
                {summary.customerName}
              </div>
              <div style={{ display: 'flex', gap: 'var(--space-2)', flexWrap: 'wrap', marginBlockStart: 2 }}>
                <span dir="ltr" style={{ fontFamily: 'monospace', fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }}>
                  {summary.orderNumber}
                </span>
                {summary.customerCode != null && (
                  <span dir="ltr" style={{ fontFamily: 'monospace', fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                    {summary.customerCode}
                  </span>
                )}
              </div>
            </div>
            <SalesOrderStatusBadge status={summary.status} />
          </div>
        </div>
      </div>

      <div style={{ marginBlockStart: 'var(--space-3)' }}>
        <KeyValueList items={metadata} columns={mode === 'tablet' ? 3 : 2} compact />
      </div>

      {paidPercent != null && (
        <div style={{ marginBlockStart: 'var(--space-3)' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', gap: 'var(--space-2)', color: 'var(--text-muted)', fontSize: 'var(--text-xs)' }}>
            <span>نسبة السداد</span>
            <span dir="ltr">{paidPercent}%</span>
          </div>
          <div
            role="progressbar"
            aria-label="نسبة سداد أمر البيع"
            aria-valuemin={0}
            aria-valuemax={100}
            aria-valuenow={paidPercent}
            style={{
              height: 4,
              borderRadius: 9999,
              background: 'var(--border-subtle)',
              overflow: 'hidden',
              marginBlockStart: 'var(--space-1)',
            }}
          >
            <div
              aria-hidden="true"
              style={{
                width: `${paidPercent}%`,
                height: '100%',
                borderRadius: 9999,
                background: paidPercent >= 100
                  ? 'var(--color-success)'
                  : paidPercent > 0
                    ? 'var(--color-warning)'
                    : 'var(--border-subtle)',
              }}
            />
          </div>
        </div>
      )}

      <div
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          gap: 'var(--space-2)',
          marginBlockStart: 'var(--space-3)',
          paddingBlockStart: 'var(--space-3)',
          borderBlockStart: '1px solid var(--divider)',
        }}
      >
        <Button
          variant="primary"
          size="sm"
          touchTarget
          icon={<Eye size={15} />}
          onClick={onOpen}
          style={{ flex: mode === 'mobile' ? '1 1 100%' : '1 1 auto', justifyContent: 'center' }}
        >
          عرض الطلب
        </Button>
        {onMap && (
          <Button
            variant="secondary"
            size="sm"
            touchTarget
            icon={<MapPin size={15} />}
            onClick={onMap}
            style={{ flex: '1 1 auto', justifyContent: 'center' }}
          >
            الخريطة
          </Button>
        )}
        {onCall && (
          <Button
            variant="secondary"
            size="sm"
            touchTarget
            icon={<PhoneCall size={15} />}
            onClick={onCall}
            style={{ flex: '1 1 auto', justifyContent: 'center' }}
          >
            اتصال
          </Button>
        )}
      </div>
    </Card>
  )
}
