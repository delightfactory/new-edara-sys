import type { ReactNode } from 'react'
import { ArrowRight } from 'lucide-react'
import Button from '@/components/ui/Button'
import type { AppAction } from '@/components/patterns/ActionRegistry'
import StatusBadge, { type SemanticTone } from '@/components/patterns/StatusBadge'
import TransactionHeader from '@/components/patterns/TransactionHeader'

interface PaymentReceiptStatusPresentation {
  label: string
  tone: SemanticTone
}

export const PAYMENT_RECEIPT_STATUS_PRESENTATION: Record<string, PaymentReceiptStatusPresentation> = {
  pending: { label: 'معلق — بانتظار المراجعة', tone: 'warning' },
  confirmed: { label: 'مؤكد', tone: 'success' },
  rejected: { label: 'مرفوض', tone: 'danger' },
}

export interface PaymentReceiptDetailHeaderProps {
  receiptNumber: ReactNode
  context: ReactNode
  status: string
  onBack: () => void
  actions?: AppAction[]
  tools?: ReactNode
}

/**
 * Thin Finance-domain adapter over the shared V2 transaction-detail grammar.
 *
 * Payment eligibility, permissions, workflow predicates and callbacks stay in the
 * Finance page. This adapter only maps receipt identity/status and shared placement.
 */
export function PaymentReceiptDetailHeader({
  receiptNumber,
  context,
  status,
  onBack,
  actions,
  tools,
}: PaymentReceiptDetailHeaderProps) {
  const statusPresentation = PAYMENT_RECEIPT_STATUS_PRESENTATION[status] ?? {
    label: status,
    tone: 'neutral' as const,
  }

  return (
    <TransactionHeader
      aria-label="تفاصيل إيصال التحصيل"
      sticky
      title={<span dir="ltr">{receiptNumber}</span>}
      subtitle={context}
      status={(
        <StatusBadge
          label={statusPresentation.label}
          tone={statusPresentation.tone}
        />
      )}
      backAction={(
        <Button
          type="button"
          variant="secondary"
          size="sm"
          touchTarget
          icon={<ArrowRight size={14} aria-hidden="true" />}
          onClick={onBack}
        >
          رجوع
        </Button>
      )}
      actions={actions}
      tools={tools}
    />
  )
}
