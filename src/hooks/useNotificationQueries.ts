// src/hooks/useNotificationQueries.ts
// ─────────────────────────────────────────────────────────────
// TanStack Query v5 hooks + mutations for the notification system.
// All hooks are named exports (no default). No `any` types.
// ─────────────────────────────────────────────────────────────

// External
import {
  useQuery,
  useMutation,
  useQueryClient,
  keepPreviousData,
} from '@tanstack/react-query'

// Internal — Sprint 1 foundation
import { NotificationsAPI } from '@/lib/notifications/api'
import { notificationKeys } from '@/lib/notifications/query-keys'
import { useNotificationStore } from '@/stores/notification-store'
import type {
  Notification,
  NotificationCategory,
  NotificationEvent,
  NotificationFilters,
  NotificationPreferences,
} from '@/lib/notifications/types'

// ============================================================
// QUERIES
// ============================================================

/**
 * Live unread count badge — hydrated from DB and kept in sync via
 * Realtime (GlobalRealtimeManager increments store on INSERT).
 * 60s refetchInterval provides a fallback for browsers where
 * Realtime is unavailable (SSR, network issues, etc.).
 */
export function useUnreadCountQuery() {
  return useQuery({
    queryKey: notificationKeys.unreadCount(),
    queryFn: async () => {
      const count = await NotificationsAPI.getUnreadCount()
      // Sync store so NotificationBell and Sidebar badge always match
      useNotificationStore.getState().setUnreadCount(count)
      return count
    },
    staleTime: 30_000,
    refetchInterval: 60_000,
  })
}

/**
 * Most recent N unread notifications for the NotificationPanel header.
 */
export function useRecentNotificationsQuery(limit = 10) {
  return useQuery({
    queryKey: notificationKeys.recent(limit),
    queryFn: () => NotificationsAPI.getRecentUnread(limit),
    staleTime: 10_000,
  })
}

/**
 * Full paginated list for the NotificationCenter page.
 * Uses keepPreviousData so the old page shows while the new one loads.
 */
export function useNotificationsQuery(options: {
  page?: number
  filters?: NotificationFilters
} = {}) {
  const { page = 1, filters = {} } = options
  return useQuery({
    // page must be part of the key — same filters + different page → different cache entry
    queryKey: [...notificationKeys.list(filters), page] as const,
    queryFn: () => NotificationsAPI.getNotifications({ page, limit: 20, filters }),
    staleTime: 30_000,
    placeholderData: keepPreviousData,
  })
}

/**
 * Per-user notification preferences for the settings UI.
 */
export function usePreferencesQuery() {
  return useQuery({
    queryKey: notificationKeys.preferences(),
    queryFn: NotificationsAPI.getPreferences,
    staleTime: 5 * 60_000,
  })
}

/**
 * Registered push-subscription devices for the current user.
 */
export function usePushDevicesQuery() {
  return useQuery({
    queryKey: notificationKeys.pushDevices(),
    queryFn: NotificationsAPI.getPushSubscriptions,
    staleTime: 5 * 60_000,
  })
}

// ============================================================
// MUTATIONS
// ============================================================

/**
 * Mark a single notification as read with optimistic update.
 * Immediately marks it in all list and recent caches before the
 * network call completes, then rolls back on error.
 */
export function useMarkAsReadMutation() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (id: string) => NotificationsAPI.markAsRead(id),

    onMutate: async (id: string) => {
      // Cancel in-flight refetches so they don't overwrite our optimistic update
      await queryClient.cancelQueries({ queryKey: notificationKeys.all })

      // Snapshot previous cache states for rollback
      const previousLists = queryClient.getQueriesData<{ data: Notification[] }>({
        queryKey: notificationKeys.lists(),
      })
      // Capture ALL recent caches regardless of limit (e.g. recent(10), recent(15))
      const previousRecentEntries = queryClient.getQueriesData<Notification[]>({
        queryKey: [...notificationKeys.all, 'recent'],
      })

      // Apply optimistic update to all list caches
      queryClient.setQueriesData<{ data: Notification[]; count: number; page: number; pageSize: number; totalPages: number }>(
        { queryKey: notificationKeys.lists() },
        old => {
          if (!old) return old
          return {
            ...old,
            data: old.data.map(n => n.id === id ? { ...n, isRead: true } : n),
          }
        },
      )

      // Apply optimistic update to all recent caches (any limit variant)
      queryClient.setQueriesData<Notification[]>(
        { queryKey: [...notificationKeys.all, 'recent'] },
        old => old?.map(n => n.id === id ? { ...n, isRead: true } : n),
      )

      // Decrement badge optimistically
      useNotificationStore.getState().decrementUnread()

      return { previousLists, previousRecentEntries }
    },

    onError: (_err, _id, context) => {
      // Roll back all mutated caches
      if (context?.previousLists) {
        for (const [key, value] of context.previousLists) {
          queryClient.setQueryData(key, value)
        }
      }
      if (context?.previousRecentEntries) {
        for (const [key, value] of context.previousRecentEntries) {
          queryClient.setQueryData(key, value)
        }
      }
      // Restore count from server
      queryClient.invalidateQueries({ queryKey: notificationKeys.unreadCount() })
    },

    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: notificationKeys.unreadCount() })
    },
  })
}

/**
 * Mark all notifications (or all in a category) as read.
 * Resets store + nukes all notification cache entries.
 */
export function useMarkAllAsReadMutation() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (category?: NotificationCategory) =>
      NotificationsAPI.markAllAsRead(category),

    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: notificationKeys.all })
      useNotificationStore.getState().resetUnread()
    },
  })
}

/**
 * Archive a notification with optimistic removal from all list caches.
 */
export function useArchiveMutation() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (id: string) => NotificationsAPI.archiveNotification(id),

    onMutate: async (id: string) => {
      // Cancel all notification queries (lists AND recent) to prevent stale overwrites
      await queryClient.cancelQueries({ queryKey: notificationKeys.all })

      const previousLists = queryClient.getQueriesData<{ data: Notification[] }>({
        queryKey: notificationKeys.lists(),
      })
      const previousRecentEntries = queryClient.getQueriesData<Notification[]>({
        queryKey: [...notificationKeys.all, 'recent'],
      })

      // Optimistically remove from all list caches
      queryClient.setQueriesData<{ data: Notification[]; count: number; page: number; pageSize: number; totalPages: number }>(
        { queryKey: notificationKeys.lists() },
        old => {
          if (!old) return old
          const removed = old.data.find(n => n.id === id)
          // Decrement unread count if the archived item was unread (side-effect only, not in cache)
          if (removed && !removed.isRead) {
            useNotificationStore.getState().decrementUnread()
          }
          return {
            ...old,
            data: old.data.filter(n => n.id !== id),
            count: Math.max(0, old.count - 1),
          }
        },
      )

      // Optimistically remove from all recent caches (any limit variant)
      queryClient.setQueriesData<Notification[]>(
        { queryKey: [...notificationKeys.all, 'recent'] },
        old => old?.filter(n => n.id !== id),
      )

      return { previousLists, previousRecentEntries }
    },

    onError: (_err, _id, context) => {
      if (context?.previousLists) {
        for (const [key, value] of context.previousLists) {
          queryClient.setQueryData(key, value)
        }
      }
      if (context?.previousRecentEntries) {
        for (const [key, value] of context.previousRecentEntries) {
          queryClient.setQueryData(key, value)
        }
      }
    },

    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: notificationKeys.lists() })
      queryClient.invalidateQueries({ queryKey: notificationKeys.unreadCount() })
    },
  })
}

/**
 * Save notification preferences with optimistic update.
 */
export function useUpdatePreferencesMutation() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (
      partial: Partial<Omit<NotificationPreferences, 'userId' | 'createdAt' | 'updatedAt'>>,
    ) => NotificationsAPI.updatePreferences(partial),

    onMutate: async partial => {
      await queryClient.cancelQueries({ queryKey: notificationKeys.preferences() })
      const previous = queryClient.getQueryData<NotificationPreferences>(
        notificationKeys.preferences(),
      )

      queryClient.setQueryData<NotificationPreferences>(
        notificationKeys.preferences(),
        old => old ? { ...old, ...partial, updatedAt: new Date().toISOString() } : old,
      )

      return { previous }
    },

    onError: (_err, _partial, context) => {
      if (context?.previous) {
        queryClient.setQueryData(notificationKeys.preferences(), context.previous)
      }
    },

    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: notificationKeys.preferences() })
    },
  })
}

/**
 * Hard-delete an archived notification.
 * Only works on is_archived=true rows (API enforces this guard).
 * Optimistically removes from all list caches to avoid flash of deleted item.
 * BUG-10: exposes deleteNotification() API method which had no hook.
 */
export function useDeleteMutation() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (id: string) => NotificationsAPI.deleteNotification(id),

    onMutate: async (id: string) => {
      await queryClient.cancelQueries({ queryKey: notificationKeys.all })

      // Snapshot for rollback
      const previousLists = queryClient.getQueriesData<{ data: Notification[] }>({
        queryKey: notificationKeys.lists(),
      })

      // Optimistically remove from all list caches
      queryClient.setQueriesData<{ data: Notification[]; count: number; page: number; pageSize: number; totalPages: number }>(
        { queryKey: notificationKeys.lists() },
        old => {
          if (!old) return old
          return {
            ...old,
            data: old.data.filter(n => n.id !== id),
            count: Math.max(0, old.count - 1),
          }
        },
      )

      return { previousLists }
    },

    onError: (_err, _id, context) => {
      if (context?.previousLists) {
        for (const [key, value] of context.previousLists) {
          queryClient.setQueryData(key, value)
        }
      }
    },

    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: notificationKeys.lists() })
    },
  })
}

/**
 * Fetch the notification event-type catalogue.
 * Reference data — changes rarely, so staleTime is 24 hours.
 * C-04: activates the previously dead notificationKeys.events() key.
 */
export function useNotificationEventsQuery(category?: NotificationCategory) {
  return useQuery({
    queryKey: [...notificationKeys.events(), category] as const,
    queryFn: () => NotificationsAPI.getNotificationEvents(category),
    staleTime: 24 * 60 * 60_000, // 24 hours — reference data
    gcTime:    48 * 60 * 60_000, // keep in cache 48 hours
  })
}
