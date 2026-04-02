// src/lib/notifications/event-registry.ts
// ─────────────────────────────────────────────────────────────
// Frontend event-key registry — mirrors the seed data in
// migration 42_notification_system.sql (notification_event_types).
// Extended in migration 46_notification_full_coverage.sql.
//
// Purpose:
//   • Type-safe event_key references in business logic
//   • Prevents misspelling when calling dispatch-notification
//   • Single source of truth for frontend-facing event metadata
//
// Rule: when adding a new event to the DB seed, add it here too.
// ─────────────────────────────────────────────────────────────

import type { NotificationCategory, NotificationPriority } from './types'

// ── Registry entry shape ──────────────────────────────────────

export interface NotificationEventDef {
  /** Dot-separated key — must match notification_event_types.event_key */
  readonly key:             string
  readonly category:        NotificationCategory
  readonly defaultPriority: NotificationPriority
  readonly labelAr:         string
  readonly labelEn:         string
  /** Known template variable names for this event (documentation only) */
  readonly variables?:      readonly string[]
}

// ── Registry ─────────────────────────────────────────────────
// Keys use SCREAMING_SNAKE_CASE for easy import and IntelliSense.
// Values are const-asserted for full type narrowing.

export const NOTIFICATION_EVENTS = {
  // ── HR Attendance ────────────────────────────────────────────
  HR_ATTENDANCE_LATE: {
    key:             'hr.attendance.late',
    category:        'hr_attendance',
    defaultPriority: 'medium',
    labelAr:         'تأخر في الحضور',
    labelEn:         'Late Arrival',
    variables:       ['employee_name', 'minutes_late', 'date', 'employee_id'],
  },
  HR_ATTENDANCE_ABSENT: {
    key:             'hr.attendance.absent',
    category:        'hr_attendance',
    defaultPriority: 'high',
    labelAr:         'غياب بدون إذن',
    labelEn:         'Unexcused Absence',
    variables:       ['employee_name', 'date', 'employee_id'],
  },
  HR_ATTENDANCE_EARLY_LEAVE: {
    key:             'hr.attendance.early_leave',
    category:        'hr_attendance',
    defaultPriority: 'medium',
    labelAr:         'مغادرة مبكرة',
    labelEn:         'Early Departure',
    variables:       ['employee_name', 'minutes_early', 'date'],
  },

  // ── HR Leaves ────────────────────────────────────────────────
  HR_LEAVE_REQUESTED: {
    key:             'hr.leave.requested',
    category:        'hr_leaves',
    defaultPriority: 'high',
    labelAr:         'طلب إجازة جديد',
    labelEn:         'New Leave Request',
    variables:       ['employee_name', 'from_date', 'to_date', 'leave_id'],
  },
  HR_LEAVE_APPROVED: {
    key:             'hr.leave.approved',
    category:        'hr_leaves',
    defaultPriority: 'medium',
    labelAr:         'تمت الموافقة على الإجازة',
    labelEn:         'Leave Approved',
    variables:       ['from_date', 'to_date', 'leave_id'],
  },
  HR_LEAVE_REJECTED: {
    key:             'hr.leave.rejected',
    category:        'hr_leaves',
    defaultPriority: 'medium',
    labelAr:         'رُفض طلب الإجازة',
    labelEn:         'Leave Rejected',
    variables:       ['from_date', 'to_date', 'reason', 'leave_id'],
  },

  // ── HR Permission Requests ────────────────────────────────────
  HR_PERMISSION_REQUESTED: {
    key:             'hr.permission.requested',
    category:        'hr_attendance',
    defaultPriority: 'medium',
    labelAr:         'طلب إذن انصراف جديد',
    labelEn:         'Permission Request',
    variables:       ['employee_name', 'permission_date', 'reason', 'permission_id'],
  },
  HR_PERMISSION_APPROVED: {
    key:             'hr.permission.approved',
    category:        'hr_attendance',
    defaultPriority: 'low',
    labelAr:         'تمت الموافقة على إذن الانصراف',
    labelEn:         'Permission Approved',
    variables:       ['permission_date', 'permission_id'],
  },
  HR_PERMISSION_REJECTED: {
    key:             'hr.permission.rejected',
    category:        'hr_attendance',
    defaultPriority: 'medium',
    labelAr:         'رُفض إذن الانصراف',
    labelEn:         'Permission Rejected',
    variables:       ['permission_date', 'reason', 'permission_id'],
  },

  // ── HR Advances ───────────────────────────────────────────────
  HR_ADVANCE_REQUESTED: {
    key:             'hr.advance.requested',
    category:        'hr_payroll',
    defaultPriority: 'high',
    labelAr:         'طلب سلفة جديد',
    labelEn:         'Advance Request',
    variables:       ['employee_name', 'amount', 'currency', 'advance_id'],
  },
  HR_ADVANCE_APPROVED: {
    key:             'hr.advance.approved',
    category:        'hr_payroll',
    defaultPriority: 'medium',
    labelAr:         'تمت الموافقة على السلفة',
    labelEn:         'Advance Approved',
    variables:       ['amount', 'currency', 'advance_id'],
  },
  HR_ADVANCE_REJECTED: {
    key:             'hr.advance.rejected',
    category:        'hr_payroll',
    defaultPriority: 'medium',
    labelAr:         'رُفض طلب السلفة',
    labelEn:         'Advance Rejected',
    variables:       ['amount', 'currency', 'reason', 'advance_id'],
  },

  // ── HR Payroll ───────────────────────────────────────────────
  HR_PAYROLL_PROCESSED: {
    key:             'hr.payroll.processed',
    category:        'hr_payroll',
    defaultPriority: 'medium',
    labelAr:         'راتبك جاهز',
    labelEn:         'Payroll Ready',
    variables:       ['month', 'net_salary', 'total_amount', 'currency', 'payroll_run_id'],
  },

  // ── HR Contract Expiry ────────────────────────────────────────
  HR_CONTRACT_EXPIRING: {
    key:             'hr.contract.expiring',
    category:        'hr_attendance',
    defaultPriority: 'high',
    labelAr:         'عقد موظف ينتهي قريباً',
    labelEn:         'Contract Expiring Soon',
    variables:       ['employee_name', 'expiry_date', 'days_remaining', 'employee_id'],
  },

  // ── Finance Expenses ─────────────────────────────────────────
  FINANCE_EXPENSE_SUBMITTED: {
    key:             'finance.expense.submitted',
    category:        'finance_approvals',
    defaultPriority: 'high',
    labelAr:         'طلب صرف جديد',
    labelEn:         'Expense Submitted',
    variables:       ['requester_name', 'amount', 'currency', 'description', 'expense_id'],
  },
  FINANCE_EXPENSE_APPROVED: {
    key:             'finance.expense.approved',
    category:        'finance_expenses',
    defaultPriority: 'medium',
    labelAr:         'موافقة على طلب الصرف',
    labelEn:         'Expense Approved',
    variables:       ['amount', 'currency', 'approver_name', 'expense_id'],
  },
  FINANCE_EXPENSE_REJECTED: {
    key:             'finance.expense.rejected',
    category:        'finance_expenses',
    defaultPriority: 'medium',
    labelAr:         'رفض طلب الصرف',
    labelEn:         'Expense Rejected',
    variables:       ['amount', 'currency', 'reason', 'expense_id'],
  },
  FINANCE_BUDGET_ALERT: {
    key:             'finance.budget.alert',
    category:        'finance_approvals',
    defaultPriority: 'high',
    labelAr:         'تحذير ميزانية',
    labelEn:         'Budget Alert',
    variables:       ['budget_name', 'percentage', 'used', 'total', 'currency', 'budget_id'],
  },

  // ── Inventory ────────────────────────────────────────────────
  INVENTORY_STOCK_LOW: {
    key:             'inventory.stock.low',
    category:        'inventory',
    defaultPriority: 'high',
    labelAr:         'مخزون منخفض',
    labelEn:         'Low Stock Alert',
    variables:       ['product_name', 'current_quantity', 'min_quantity', 'unit', 'product_id'],
  },
  INVENTORY_STOCK_OUT: {
    key:             'inventory.stock.out',
    category:        'inventory',
    defaultPriority: 'critical',
    labelAr:         'نفاد المخزون',
    labelEn:         'Out of Stock',
    variables:       ['product_name', 'product_id'],
  },
  INVENTORY_TRANSFER_REQUESTED: {
    key:             'inventory.transfer.requested',
    category:        'inventory',
    defaultPriority: 'medium',
    labelAr:         'طلب تحويل مخزون',
    labelEn:         'Transfer Requested',
    variables:       ['requester_name', 'quantity', 'unit', 'product_name', 'transfer_id'],
  },
  INVENTORY_TRANSFER_COMPLETED: {
    key:             'inventory.transfer.completed',
    category:        'inventory',
    defaultPriority: 'low',
    labelAr:         'اكتمال تحويل المخزون',
    labelEn:         'Transfer Completed',
    variables:       ['quantity', 'unit', 'product_name', 'transfer_id'],
  },

  // ── Sales ────────────────────────────────────────────────────
  SALES_ORDER_CREATED: {
    key:             'sales.order.created',
    category:        'sales',
    defaultPriority: 'medium',
    labelAr:         'طلب بيع جديد',
    labelEn:         'New Sales Order',
    variables:       ['order_number', 'customer_name', 'amount', 'currency', 'order_id'],
  },
  SALES_ORDER_CONFIRMED: {
    key:             'sales.order.confirmed',
    category:        'sales',
    defaultPriority: 'medium',
    labelAr:         'طلب بيع مؤكد',
    labelEn:         'Sales Order Confirmed',
    variables:       ['order_number', 'customer_name', 'amount', 'currency', 'order_id'],
  },
  SALES_INVOICE_OVERDUE: {
    key:             'sales.invoice.overdue',
    category:        'sales',
    defaultPriority: 'critical',
    labelAr:         'فاتورة متأخرة السداد',
    labelEn:         'Invoice Overdue',
    variables:       ['invoice_number', 'amount', 'currency', 'customer_name', 'days_overdue', 'invoice_id'],
  },

  // ── Procurement ──────────────────────────────────────────────
  PURCHASE_INVOICE_RECEIVED: {
    key:             'purchase.invoice.received',
    category:        'procurement',
    defaultPriority: 'medium',
    labelAr:         'استلام بضاعة — فاتورة شراء',
    labelEn:         'Purchase Invoice Received',
    variables:       ['invoice_number', 'supplier_name', 'amount', 'currency', 'invoice_id'],
  },
  PURCHASE_INVOICE_BILLED: {
    key:             'purchase.invoice.billed',
    category:        'procurement',
    defaultPriority: 'medium',
    labelAr:         'اعتماد مالي — فاتورة شراء',
    labelEn:         'Purchase Invoice Billed',
    variables:       ['invoice_number', 'supplier_name', 'amount', 'currency', 'invoice_id'],
  },

  // ── System ───────────────────────────────────────────────────
  SYSTEM_APP_UPDATE: {
    key:             'system.app.update',
    category:        'system',
    defaultPriority: 'low',
    labelAr:         'تحديث متاح',
    labelEn:         'App Update Available',
    variables:       ['version'],
  },
  SYSTEM_LOGIN_NEW_DEVICE: {
    key:             'system.login.new_device',
    category:        'system',
    defaultPriority: 'high',
    labelAr:         'تسجيل دخول من جهاز جديد',
    labelEn:         'New Device Login',
    variables:       ['browser', 'os', 'location'],
  },
} as const satisfies Record<string, NotificationEventDef>

// ── Type helpers ──────────────────────────────────────────────

/** Union of all valid event keys — enforced by TypeScript */
export type NotificationEventKey =
  (typeof NOTIFICATION_EVENTS)[keyof typeof NOTIFICATION_EVENTS]['key']

/**
 * Look up an event definition by its dot-separated key.
 * Returns undefined if the key is not in the registry.
 *
 * @example
 *   const def = getEventDef('hr.leave.requested')
 *   def?.labelAr // 'طلب إجازة جديد'
 */
export function getEventDef(key: string): NotificationEventDef | undefined {
  return Object.values(NOTIFICATION_EVENTS).find(e => e.key === key)
}
