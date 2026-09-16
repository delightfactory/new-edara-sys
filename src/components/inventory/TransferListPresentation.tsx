import type { ReactNode } from 'react'
import { ArrowLeftRight } from 'lucide-react'
import Card from '@/components/patterns/Card'
import KeyValueList, { type KeyValueItem } from '@/components/patterns/KeyValueList'
import StatusBadge, { type SemanticTone } from '@/components/patterns/StatusBadge'
import Button from '@/components/ui/Button'

export interface TransferCardSummary {
  number: ReactNode
  directionLabel: ReactNode
  directionTone: SemanticTone
  statusLabel: ReactNode
  statusTone: SemanticTone
  createdAt: ReactNode
  fromWarehouse: ReactNode
  toWarehouse: ReactNode
}

export interface TransferCardProps {
  summary: TransferCardSummary
  mode: 'mobile' | 'tablet'
  actions?: ReactNode
  onOpen?: () => void
  openLabel?: string
}

/**
 * TransferCard — Inventory-domain composition over the shared V2 card/status/detail grammar.
 *
 * Workflow predicates, permissions, status mapping and action callbacks remain page-owned.
 * This component only owns the responsive identity/detail hierarchy and touch-safe detail entry.
 */
export function TransferCard({
  summary,
  mode,
  actions,
  onOpen,
  openLabel = 'عرض تفاصيل التحويل',
}: TransferCardProps) {
  const metadata: KeyValueItem[] = [
    { key: 'from', label: 'من مخزن', value: summary.fromWarehouse },
    { key: 'to', label: 'إلى مخزن', value: summary.toWarehouse },
    { key: 'date', label: 'التاريخ', value: summary.createdAt },
  ]

  return (
    <Card
      surface="default"
      padding={mode === 'tablet' ? 'md' : 'sm'}
      data-transfer-card
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
          <ArrowLeftRight size={18} />
        </div>

        <div style={{ minWidth: 0, flex: 1 }}>
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'flex-start',
              gap: 'var(--space-2)',
              flexWrap: 'wrap',
            }}
          >
            <div
              dir="ltr"
              style={{
                fontFamily: 'monospace',
                fontWeight: 800,
                color: 'var(--color-primary)',
                overflowWrap: 'anywhere',
              }}
            >
              {summary.number}
            </div>

            <div style={{ display: 'flex', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
              <StatusBadge label={summary.directionLabel} tone={summary.directionTone} />
              <StatusBadge label={summary.statusLabel} tone={summary.statusTone} />
            </div>
          </div>
        </div>
      </div>

      <div style={{ marginBlockStart: 'var(--space-3)' }}>
        <KeyValueList
          items={metadata}
          columns={mode === 'tablet' ? 3 : 1}
          compact
        />
      </div>

      {(actions || onOpen) && (
        <div
          role="group"
          aria-label="إجراءات التحويل"
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 'var(--space-2)',
            flexWrap: 'wrap',
            marginBlockStart: 'var(--space-3)',
            paddingBlockStart: 'var(--space-3)',
            borderBlockStart: '1px solid var(--ds-border-default)',
          }}
        >
          {actions}
          {onOpen && (
            <Button
              type="button"
              variant="ghost"
              size="sm"
              touchTarget
              aria-label={openLabel}
              onClick={onOpen}
            >
              عرض التفاصيل
            </Button>
          )}
        </div>
      )}
    </Card>
  )
}
