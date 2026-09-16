import type { ReactNode } from 'react'
import { ArrowRight } from 'lucide-react'
import type { SalesOrderStatus } from '@/lib/types/master-data'
import Button from '@/components/ui/Button'
import type { AppAction } from '@/components/patterns/ActionRegistry'
import TransactionHeader from '@/components/patterns/TransactionHeader'
import { SalesOrderStatusBadge } from './SalesOrdersListPresentation'

export interface SalesOrderDetailHeaderProps {
  orderNumber: ReactNode
  customer: ReactNode
  status: SalesOrderStatus
  onBack: () => void
  actions?: AppAction[]
  tools?: ReactNode
}

/**
 * Thin Sales-domain adapter over the shared TransactionHeader.
 *
 * The page decides which AppActions exist from its existing permissions/status/workflow truth.
 * This adapter only maps Sales identity/status into the shared V2 transaction grammar.
 */
export function SalesOrderDetailHeader({
  orderNumber,
  customer,
  status,
  onBack,
  actions,
  tools,
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
      actions={actions}
      tools={tools}
    />
  )
}
