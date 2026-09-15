import { NAVIGATION_DESTINATIONS, type NavigationDestination } from './registry'
import { canShowNavigation, type PermissionEvaluator } from './resolvers'

export interface SidebarLeafDescriptor {
  kind: 'leaf'
  id: string
  destinationId: string
}

export interface SidebarGroupDescriptor {
  kind: 'group'
  id: string
  label: string
  destinationIds: string[]
}

export type SidebarEntryDescriptor = SidebarLeafDescriptor | SidebarGroupDescriptor

export interface SidebarSectionDescriptor {
  id: string
  label?: string
  entries: SidebarEntryDescriptor[]
}

export interface VisibleSidebarLeaf {
  kind: 'leaf'
  id: string
  destination: NavigationDestination
}

export interface VisibleSidebarGroup {
  kind: 'group'
  id: string
  label: string
  destinations: NavigationDestination[]
}

export interface VisibleSidebarSection {
  id: string
  label?: string
  entries: Array<VisibleSidebarLeaf | VisibleSidebarGroup>
}

/**
 * App Shell V2 information architecture.
 *
 * This keeps the current product destinations, but separates the structure from
 * rendering, theme, expansion state and permission evaluation.
 */
export const SIDEBAR_SECTIONS: SidebarSectionDescriptor[] = [
  {
    id: 'home',
    entries: [
      { kind: 'leaf', id: 'dashboard', destinationId: 'dashboard' },
      { kind: 'leaf', id: 'notifications', destinationId: 'notifications' },
    ],
  },
  {
    id: 'operations',
    label: 'التشغيل',
    entries: [
      { kind: 'group', id: 'work', label: 'إدارة العمل', destinationIds: ['work', 'work-team', 'work-manage'] },
      { kind: 'group', id: 'sales', label: 'المبيعات', destinationIds: ['sales-orders', 'sales-returns', 'sales-shipping'] },
      { kind: 'group', id: 'purchases', label: 'المشتريات', destinationIds: ['purchase-invoices', 'purchase-returns'] },
      { kind: 'group', id: 'customers', label: 'العملاء', destinationIds: ['customers', 'credit', 'credit-overdue'] },
      { kind: 'leaf', id: 'suppliers', destinationId: 'suppliers' },
    ],
  },
  {
    id: 'inventory',
    label: 'المخزون',
    entries: [
      { kind: 'group', id: 'inventory', label: 'المخزون', destinationIds: ['warehouses', 'stock', 'transfers', 'adjustments', 'stock-movements', 'inventory-valuation'] },
      { kind: 'group', id: 'products', label: 'المنتجات', destinationIds: ['products', 'categories', 'price-lists', 'bundles', 'brands'] },
      { kind: 'leaf', id: 'branches', destinationId: 'branches' },
    ],
  },
  {
    id: 'finance',
    label: 'المالية',
    entries: [
      { kind: 'group', id: 'finance', label: 'المالية', destinationIds: ['vaults', 'custody', 'payments', 'expenses', 'accounts', 'journals', 'ledger', 'balance-sheet', 'approval-rules'] },
    ],
  },
  {
    id: 'field',
    label: 'الأنشطة الميدانية',
    entries: [
      { kind: 'group', id: 'activities', label: 'الأنشطة', destinationIds: ['activities', 'activities-list', 'visit-plans', 'call-plans', 'targets', 'checklists', 'activity-types', 'target-types'] },
    ],
  },
  {
    id: 'tools',
    label: 'أدوات',
    entries: [
      { kind: 'group', id: 'reports', label: 'التقارير', destinationIds: ['reports-overview', 'reports-sales', 'reports-receivables', 'reports-treasury', 'reports-customers', 'reports-reps', 'reports-visits', 'reports-products', 'reports-churn', 'reports-geography', 'reports-targets', 'reports-credit', 'reports-reengagement', 'reports-profitability'] },
      { kind: 'group', id: 'hr-self', label: 'الخدمات الذاتية', destinationIds: ['my-profile', 'attendance-checkin', 'hr-permissions', 'leaves', 'advances'] },
      { kind: 'group', id: 'hr', label: 'الشئون الإدارية', destinationIds: ['hr-dashboard', 'employees', 'attendance', 'commissions', 'payroll', 'target-payouts', 'hr-adjustments', 'delegations', 'hr-settings'] },
      { kind: 'group', id: 'settings', label: 'الإعدادات', destinationIds: ['settings-users', 'settings-roles', 'settings-company', 'settings-audit'] },
    ],
  },
]

export function getVisibleSidebarSections(evaluator: PermissionEvaluator): VisibleSidebarSection[] {
  const destinations = new Map(NAVIGATION_DESTINATIONS.map(item => [item.id, item]))

  return SIDEBAR_SECTIONS
    .map(section => {
      const entries = section.entries.reduce<Array<VisibleSidebarLeaf | VisibleSidebarGroup>>((result, entry) => {
        if (entry.kind === 'leaf') {
          const destination = destinations.get(entry.destinationId)
          if (destination && canShowNavigation(destination.permission, evaluator)) {
            result.push({ kind: 'leaf', id: entry.id, destination })
          }
          return result
        }

        const visibleDestinations = entry.destinationIds
          .map(id => destinations.get(id))
          .filter((destination): destination is NavigationDestination => Boolean(destination))
          .filter(destination => canShowNavigation(destination.permission, evaluator))

        if (visibleDestinations.length > 0) {
          result.push({
            kind: 'group',
            id: entry.id,
            label: entry.label,
            destinations: visibleDestinations,
          })
        }

        return result
      }, [])

      return {
        id: section.id,
        label: section.label,
        entries,
      }
    })
    .filter(section => section.entries.length > 0)
}
