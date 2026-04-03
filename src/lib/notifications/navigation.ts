import type { Notification, NotificationRow } from './types'

type NotificationNavInput = {
  actionUrl?: string | null
  eventKey?: string | null
  entityId?: string | null
}

const PLACEHOLDER_RE = /\{\{.+?\}\}/

function fallbackUrl(eventKey?: string | null, entityId?: string | null): string | null {
  switch (eventKey) {
    case 'finance.custody.loaded':
      return '/finance/custody'

    case 'finance.payment.received':
    case 'finance.payment.confirmed':
    case 'finance.payment.rejected':
      return entityId ? `/finance/payments/${entityId}` : '/finance/payments'

    case 'sales.order.created':
    case 'sales.order.confirmed':
    case 'sales.order.delivered':
    case 'sales.order.cancelled':
    case 'sales.invoice.overdue':
      return entityId ? `/sales/orders/${entityId}` : '/sales/orders'

    case 'sales.return.created':
    case 'sales.return.confirmed':
      return entityId ? `/sales/returns/${entityId}` : '/sales/returns'

    case 'purchase.invoice.received':
    case 'purchase.invoice.billed':
    case 'purchase.invoice.paid':
      return entityId ? `/purchases/invoices/${entityId}` : '/purchases/invoices'

    case 'purchase.return.confirmed':
      return entityId ? `/purchases/returns/${entityId}` : '/purchases/returns'

    case 'inventory.transfer.requested':
    case 'inventory.transfer.approved':
    case 'inventory.transfer.completed':
      return entityId ? `/inventory/transfers/${entityId}` : '/inventory/transfers'

    case 'inventory.adjustment.pending':
    case 'inventory.adjustment.approved':
      return entityId ? `/inventory/adjustments/${entityId}` : '/inventory/adjustments'

    case 'inventory.stock.low':
    case 'inventory.stock.out':
      return '/inventory/stock'

    case 'hr.adjustment.created':
    case 'hr.adjustment.approved':
    case 'hr.adjustment.rejected':
      return '/hr/adjustments'

    case 'hr.payroll.ready_for_review':
    case 'hr.payroll.processed':
      return entityId ? `/hr/payroll/${entityId}` : '/hr/payroll'

    default:
      return null
  }
}

export function resolveNotificationActionUrl(
  actionUrl: string | null | undefined,
  eventKey?: string | null,
  entityId?: string | null,
): string | null {
  let url = actionUrl?.trim() || null

  if (!url) return fallbackUrl(eventKey, entityId)

  if (url.startsWith('/procurement/invoices/')) {
    url = url.replace('/procurement/invoices/', '/purchases/invoices/')
  } else if (url.startsWith('/procurement/returns/')) {
    url = url.replace('/procurement/returns/', '/purchases/returns/')
  } else if (url.startsWith('/finance/custody/')) {
    url = '/finance/custody'
  } else if (url.startsWith('/hr/payroll/adjustments/')) {
    url = '/hr/adjustments'
  } else if (url.startsWith('/sales/invoices/')) {
    url = entityId ? `/sales/orders/${entityId}` : '/sales/orders'
  } else if (url.startsWith('/inventory/products/')) {
    url = PLACEHOLDER_RE.test(url) ? '/inventory/stock' : url.replace('/inventory/products/', '/products/')
  }

  if (PLACEHOLDER_RE.test(url)) {
    return fallbackUrl(eventKey, entityId)
  }

  return url
}

export function resolveNotificationUrlFromModel(notification: Pick<Notification, 'actionUrl' | 'eventKey' | 'entityId'>): string | null {
  return resolveNotificationActionUrl(notification.actionUrl, notification.eventKey, notification.entityId)
}

export function resolveNotificationUrlFromRow(notification: Pick<NotificationRow, 'action_url' | 'event_key' | 'entity_id'>): string | null {
  return resolveNotificationActionUrl(notification.action_url, notification.event_key, notification.entity_id)
}
