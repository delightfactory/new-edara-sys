/**
 * ReportsRedirect
 *
 * Replaces the static <Navigate to="overview" /> default at /reports.
 *
 * Redirect priority (first allowed tab wins):
 *   1. /reports/treasury   — reports.financial OR reports.sales OR reports.view_all
 *   2. /reports/overview   — reports.sales OR reports.view_all
 *   3. /reports/sales      — reports.sales OR reports.view_all
 *   4. /reports/receivables— reports.targets OR reports.sales OR reports.view_all
 *   5. /reports/customers  — reports.sales OR reports.view_all
 *
 * A finance-only user (reports.financial) lands on /reports/treasury.
 * A sales rep (reports.sales) lands on /reports/overview.
 */

import { Navigate } from 'react-router-dom'
import { useAuthStore } from '@/stores/auth-store'

export default function ReportsRedirect() {
  const can    = useAuthStore(s => s.can)
  const canAny = useAuthStore(s => s.canAny)

  const hasViewAll   = can('reports.view_all')
  const hasSales     = can('reports.sales')
  const hasFinancial = can('reports.financial')
  const hasTargets   = can('reports.targets')

  // Finance-only user: skip overview (requires reports.sales), go directly to treasury
  if (hasFinancial && !hasSales && !hasViewAll) {
    return <Navigate to="/reports/treasury" replace />
  }

  // Sales/View-all: land on overview
  if (hasSales || hasViewAll) {
    return <Navigate to="/reports/overview" replace />
  }

  // targets-only: land on receivables
  if (hasTargets) {
    return <Navigate to="/reports/receivables" replace />
  }

  // Fallback — shouldn't be reached if ProtectedRoute is correctly configured
  return <Navigate to="/unauthorized" replace />
}
