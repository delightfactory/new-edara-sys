import type { ChangeEvent, ReactNode } from 'react'
import { Package } from 'lucide-react'
import Card from '@/components/patterns/Card'
import KeyValueList, { type KeyValueItem } from '@/components/patterns/KeyValueList'
import StatusBadge, { type SemanticTone } from '@/components/patterns/StatusBadge'

export interface StockBalanceCardSummary {
  productName: ReactNode
  productCode?: ReactNode
  warehouse: ReactNode
  quantity: ReactNode
  available: ReactNode
  reserved?: ReactNode
  weightedCost?: ReactNode
  statusLabel: ReactNode
  statusTone: SemanticTone
}

export interface StockBalanceReviewState {
  actualValue: string
  onActualValueChange: (value: string) => void
  diff?: ReactNode
  diffTone?: SemanticTone
}

export interface StockBalanceCardProps {
  summary: StockBalanceCardSummary
  mode: 'mobile' | 'tablet'
  review?: StockBalanceReviewState
}

function reviewToneColor(tone: SemanticTone | undefined) {
  if (tone === 'danger') return 'var(--ds-status-danger-fg)'
  if (tone === 'warning') return 'var(--ds-status-warning-fg)'
  if (tone === 'success') return 'var(--ds-status-success-fg)'
  if (tone === 'info') return 'var(--ds-status-info-fg)'
  return 'var(--ds-text-primary)'
}

/**
 * StockBalanceCard — Inventory-domain composition over shared V2 surfaces.
 *
 * Quantity/status/review calculations remain page-owned. This component only
 * owns the responsive card hierarchy, semantic status treatment and accessible
 * review-count input used by the existing local review mode.
 */
export function StockBalanceCard({ summary, mode, review }: StockBalanceCardProps) {
  const metadata: KeyValueItem[] = [
    { key: 'available', label: 'المتاح', value: summary.available, emphasis: 'strong' },
    { key: 'quantity', label: 'الإجمالي', value: summary.quantity },
    { key: 'warehouse', label: 'المخزن', value: summary.warehouse },
  ]

  if (summary.reserved != null) {
    metadata.push({ key: 'reserved', label: 'المحجوز', value: summary.reserved })
  }
  if (summary.weightedCost != null) {
    metadata.push({ key: 'weighted-cost', label: 'التكلفة المرجحة', value: summary.weightedCost })
  }

  const handleActualChange = (event: ChangeEvent<HTMLInputElement>) => {
    review?.onActualValueChange(event.target.value)
  }

  return (
    <Card
      surface="default"
      padding={mode === 'tablet' ? 'md' : 'sm'}
      data-stock-balance-card
      data-mode={mode}
    >
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 'var(--space-3)' }}>
        <div
          aria-hidden="true"
          style={{
            width: 40,
            height: 40,
            borderRadius: 'var(--radius-lg)',
            background: 'var(--bg-accent)',
            color: 'var(--color-primary)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            flexShrink: 0,
          }}
        >
          <Package size={18} />
        </div>

        <div style={{ minWidth: 0, flex: 1 }}>
          <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
            <div style={{ minWidth: 0 }}>
              <div style={{ fontWeight: 700, overflowWrap: 'anywhere' }}>{summary.productName}</div>
              {summary.productCode != null && (
                <div dir="ltr" style={{ marginBlockStart: 2, color: 'var(--ds-text-muted)', fontFamily: 'monospace', fontSize: 'var(--ds-type-caption-size)' }}>
                  {summary.productCode}
                </div>
              )}
            </div>

            <StatusBadge label={summary.statusLabel} tone={summary.statusTone} />
          </div>
        </div>
      </div>

      <div style={{ marginBlockStart: 'var(--space-3)' }}>
        <KeyValueList
          items={metadata}
          columns={mode === 'tablet' ? 3 : 2}
          compact
        />
      </div>

      {review && (
        <div
          data-stock-review
          style={{
            display: 'flex',
            alignItems: 'flex-end',
            gap: 'var(--space-4)',
            flexWrap: 'wrap',
            marginBlockStart: 'var(--space-3)',
            paddingBlockStart: 'var(--space-3)',
            borderBlockStart: '1px dashed var(--ds-border-default)',
          }}
        >
          <label style={{ display: 'grid', gap: 'var(--space-1)', color: 'var(--ds-text-secondary)', fontSize: 'var(--ds-type-caption-size)' }}>
            <span>العدد الفعلي</span>
            <input
              aria-label="العدد الفعلي"
              type="number"
              min={0}
              step="any"
              inputMode="decimal"
              value={review.actualValue}
              placeholder="أدخل العدد"
              onChange={handleActualChange}
              style={{
                width: 112,
                minHeight: 44,
                paddingInline: 'var(--space-3)',
                border: '1px solid var(--ds-border-default)',
                borderRadius: 'var(--radius-md)',
                background: 'var(--ds-surface-default)',
                color: 'var(--ds-text-primary)',
                fontVariantNumeric: 'tabular-nums',
              }}
            />
          </label>

          {review.diff != null && (
            <div>
              <div style={{ color: 'var(--ds-text-muted)', fontSize: 'var(--ds-type-caption-size)' }}>الفرق</div>
              <div
                data-review-diff
                style={{
                  marginBlockStart: 'var(--space-1)',
                  color: reviewToneColor(review.diffTone),
                  fontSize: 'var(--text-base)',
                  fontWeight: 800,
                  fontVariantNumeric: 'tabular-nums',
                }}
              >
                {review.diff}
              </div>
            </div>
          )}
        </div>
      )}
    </Card>
  )
}
