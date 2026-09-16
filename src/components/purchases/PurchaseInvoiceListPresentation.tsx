import type { ReactNode } from 'react'
import { Eye, FileText } from 'lucide-react'
import Card from '@/components/patterns/Card'
import KeyValueList, { type KeyValueItem } from '@/components/patterns/KeyValueList'
import StatusBadge, { type SemanticTone } from '@/components/patterns/StatusBadge'
import Button from '@/components/ui/Button'

export interface PurchaseInvoiceCardSummary {
  number: ReactNode
  supplier: ReactNode
  date: ReactNode
  warehouse?: ReactNode
  total: ReactNode
  paid: ReactNode
  statusLabel: ReactNode
  statusTone: SemanticTone
}

export interface PurchaseInvoiceCardProps {
  summary: PurchaseInvoiceCardSummary
  mode: 'mobile' | 'tablet'
  onOpen: () => void
  openLabel: string
}

/**
 * PurchaseInvoiceCard — Procurement-domain composition over shared V2 surfaces.
 *
 * Financial values, workflow status mapping, supplier/warehouse identity and
 * navigation remain page-owned. The card owns presentation hierarchy only.
 */
export function PurchaseInvoiceCard({
  summary,
  mode,
  onOpen,
  openLabel,
}: PurchaseInvoiceCardProps) {
  const metadata: KeyValueItem[] = [
    { key: 'date', label: 'التاريخ', value: summary.date },
    { key: 'total', label: 'الإجمالي', value: summary.total, emphasis: 'strong' },
    { key: 'paid', label: 'المدفوع', value: summary.paid },
  ]

  if (summary.warehouse != null) {
    metadata.push({ key: 'warehouse', label: 'المخزن', value: summary.warehouse })
  }

  return (
    <Card
      surface="default"
      padding={mode === 'tablet' ? 'md' : 'sm'}
      data-purchase-invoice-card
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
          <FileText size={18} />
        </div>

        <div style={{ minWidth: 0, flex: 1 }}>
          <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
            <div style={{ minWidth: 0, flex: 1 }}>
              <div style={{ fontWeight: 700, overflowWrap: 'anywhere' }}>{summary.supplier}</div>
              <div
                dir="ltr"
                style={{
                  marginBlockStart: 2,
                  color: 'var(--ds-text-muted)',
                  fontFamily: 'monospace',
                  fontSize: 'var(--ds-type-caption-size)',
                  overflowWrap: 'anywhere',
                }}
              >
                {summary.number}
              </div>
            </div>

            <StatusBadge label={summary.statusLabel} tone={summary.statusTone} />
          </div>
        </div>
      </div>

      <div style={{ marginBlockStart: 'var(--space-3)' }}>
        <KeyValueList items={metadata} columns={2} compact />
      </div>

      <div style={{ marginBlockStart: 'var(--space-3)' }}>
        <Button
          variant="secondary"
          size="sm"
          touchTarget
          block
          icon={<Eye size={14} />}
          aria-label={openLabel}
          onClick={onOpen}
        >
          عرض التفاصيل
        </Button>
      </div>
    </Card>
  )
}
