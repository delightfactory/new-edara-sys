import type { ReactNode } from 'react'
import { ArrowRight } from 'lucide-react'
import type { SalesOrderStatus } from '@/lib/types/master-data'
import Button from '@/components/ui/Button'
import TransactionHeader, {
  type TransactionHeaderAction,
} from '@/components/patterns/TransactionHeader'
import { SalesOrderStatusBadge } from './SalesOrdersListPresentation'

export interface SalesOrderDetailHeaderProps {
  orderNumber: ReactNode
  customer: ReactNode
  status: SalesOrderStatus
  onBack: () => void
  primaryAction?: TransactionHeaderAction
  secondaryActions?: TransactionHeaderAction[]
  destructiveActions?: TransactionHeaderAction[]
  utilityActions?: ReactNode
}

/**
 * Thin Sales-domain adapter over the shared TransactionHeader.
 *
 * The page decides which actions exist from its existing permissions/status/workflow truth.
 * This adapter only maps Sales identity/status into the shared V2 transaction grammar.
 */
export function SalesOrderDetailHeader({
  orderNumber,
  customer,
  status,
  onBack,
  primaryAction,
  secondaryActions,
  destructiveActions,
  utilityActions,
}: SalesOrderDetailHeaderProps) {
  return (
    <TransactionHeader
      aria-label="تفاصيل أمر البيع"
      sticky
      title={(
        <>
          طلب <span dir="ltr">#{orderNumber}</span>
        </>
      )}
      subtitle={customer}
      status={<SalesOrderStatusBadge status={status} />}
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
      primaryAction={primaryAction}
      secondaryActions={secondaryActions}
      destructiveActions={destructiveActions}
      utilityActions={utilityActions}
    />
  )
}
