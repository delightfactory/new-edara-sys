// src/lib/notifications/query-keys.ts
// ─────────────────────────────────────────────────────────────
// TanStack Query v5 key factory for the notification system.
// Following the same hierarchical key pattern used throughout
// the codebase (see useQueryHooks.ts).
// ─────────────────────────────────────────────────────────────

import type { NotificationFilters } from './types'

/**
 * Centralised query-key factory for all notification-related queries.
 * Using a factory pattern ensures cache invalidation is precise and
 * predictable — invalidate at the right level of specificity.
 *
 * @example
 *   notificationKeys.all                            → ['notifications']
 *   notificationKeys.unreadCount()                  → ['notifications', 'unread-count']
 *   notificationKeys.list({ isRead: false })         → ['notifications', 'list', { isRead: false }]
 */
export const notificationKeys = {
  /** Root key — invalidating this invalidates ALL notification queries */
  all: ['notifications'] as const,

  /** Group key for all list (paginated) queries */
  lists: () => [...notificationKeys.all, 'list'] as const,

  /**
   * Specific list query with its filter set.
   * Different filter combinations produce distinct cache entries.
   */
  list: (filters: NotificationFilters) =>
    [...notificationKeys.lists(), filters] as const,

  /** Unread badge count — updated optimistically and via Realtime */
  unreadCount: () => [...notificationKeys.all, 'unread-count'] as const,

  /**
   * Recent unread notifications for the notification panel header.
   * Limit is part of the key so different limits cache separately.
   */
  recent: (limit?: number) => [...notificationKeys.all, 'recent', limit] as const,

  /** User notification preferences */
  preferences: () => [...notificationKeys.all, 'preferences'] as const,

  /** Notification event-type catalogue (reference data) */
  events: () => [...notificationKeys.all, 'events'] as const,

  /** Push subscription records for the current user's devices */
  pushDevices: () => [...notificationKeys.all, 'push-devices'] as const,
} as const
