import type { ReactNode } from 'react'
import { Building, History, User, Users } from 'lucide-react'
import Tabs from '@/components/patterns/Tabs'
import StatusBadge from '@/components/patterns/StatusBadge'

export type CustomerDetailTab = 'info' | 'branches' | 'contacts' | 'credit'

export interface CustomerDetailTabsProps {
  value: CustomerDetailTab
  onValueChange: (value: CustomerDetailTab) => void
  counts: {
    branches: number
    contacts: number
    credit: number
  }
  canViewCredit: boolean
  infoPanel: ReactNode
  branchesPanel: ReactNode
  contactsPanel: ReactNode
  creditPanel: ReactNode
}

function countBadge(count: number, label: string) {
  if (count <= 0) return undefined
  return <StatusBadge label={<span aria-label={`${label}: ${count}`}>{count}</span>} tone="neutral" />
}

/**
 * CustomerDetailTabs — Customer-domain composition over the shared V2 Tabs contract.
 *
 * It owns only Customer section labels/counts/visibility. Keyboard, focus,
 * tab/tabpanel relationships and RTL arrow behavior remain owned by shared Tabs.
 */
export default function CustomerDetailTabs({
  value,
  onValueChange,
  counts,
  canViewCredit,
  infoPanel,
  branchesPanel,
  contactsPanel,
  creditPanel,
}: CustomerDetailTabsProps) {
  const items = [
    {
      value: 'info',
      label: 'البيانات الأساسية',
      icon: <User size={16} />,
      panel: infoPanel,
    },
    {
      value: 'branches',
      label: 'الفروع',
      icon: <Building size={16} />,
      badge: countBadge(counts.branches, 'عدد الفروع'),
      panel: branchesPanel,
    },
    {
      value: 'contacts',
      label: 'جهات الاتصال',
      icon: <Users size={16} />,
      badge: countBadge(counts.contacts, 'عدد جهات الاتصال'),
      panel: contactsPanel,
    },
    ...(canViewCredit ? [{
      value: 'credit',
      label: 'سجل الائتمان',
      icon: <History size={16} />,
      badge: countBadge(counts.credit, 'عدد تغييرات الائتمان'),
      panel: creditPanel,
    }] : []),
  ] satisfies Array<{
    value: CustomerDetailTab
    label: ReactNode
    icon: ReactNode
    badge?: ReactNode
    panel: ReactNode
  }>

  return (
    <Tabs
      value={value}
      onValueChange={next => onValueChange(next as CustomerDetailTab)}
      ariaLabel="أقسام تفاصيل العميل"
      items={items}
    />
  )
}
