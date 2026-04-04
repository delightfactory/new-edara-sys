// src/lib/notifications/api.ts
// ─────────────────────────────────────────────────────────────
// NotificationsAPI — static service class for all notification
// data operations against Supabase.
//
// Architecture decisions:
// - Static class (not standalone functions) to group the domain
//   clearly and mirror the project pattern in services/*.ts
// - All errors are wrapped in NotificationError with a typed code
// - No default exports — named exports only (project convention)
// - The browser's globalThis.PushSubscription type is referenced
//   explicitly to avoid clash with our PushSubscriptionRecord
// ─────────────────────────────────────────────────────────────

// External
import { supabase } from '@/lib/supabase/client'
import { getAuthUserId } from '@/lib/services/_get-user-id'

// Internal types
import type {
  Notification,
  NotificationRow,
  NotificationEvent,
  NotificationPreferences,
  NotificationFilters,
  PaginatedNotifications,
  PushSubscriptionRecord,
  NotificationCategory,
  DeviceInfo,
} from './types'
import { mapNotificationRow, DEFAULT_PREFERENCES } from './types'

// ============================================================
// ERROR CLASS
// ============================================================

/** Typed error thrown by all NotificationsAPI methods */
export class NotificationError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly details?: unknown,
  ) {
    super(message)
    this.name = 'NotificationError'
  }
}

// ============================================================
// INTERNAL HELPERS
// ============================================================

/**
 * Resolve the currently authenticated user's id.
 * Reads from AuthStore first (zero network), then session cache.
 * Throws NotificationError if no session is found.
 */
async function requireUserId(): Promise<string> {
  try {
    return await getAuthUserId()
  } catch {
    throw new NotificationError(
      'المستخدم غير مسجّل دخول',
      'UNAUTHENTICATED',
    )
  }
}

/**
 * Safe base64 encoding for ArrayBuffers.
 * Using Array.from + join avoids the call-stack overflow that
 * happens when spreading large Uint8Arrays into String.fromCharCode.
 */
function arrayBufferToBase64(buffer: ArrayBuffer): string {
  return btoa(
    Array.from(new Uint8Array(buffer), b => String.fromCharCode(b)).join('')
  )
}

/**
 * Map a Supabase Postgres error into a NotificationError.
 * Preserves the original error as `details` for debugging.
 */
function wrapSupabaseError(error: unknown, context: string): NotificationError {
  const pgError = error as { code?: string; message?: string } | null
  return new NotificationError(
    pgError?.message ?? `خطأ غير متوقع في ${context}`,
    pgError?.code ?? 'UNKNOWN',
    error,
  )
}

// ============================================================
// NotificationsAPI
// ============================================================

export class NotificationsAPI {
  // ──────────────────────────────────────────────────────────
  // LIST — paginated with filters
  // ──────────────────────────────────────────────────────────

  /**
   * Fetch a paginated, filtered list of notifications for the current user.
   * Results are always sorted newest-first.
   */
  static async getNotifications(options: {
    page?: number
    limit?: number
    filters?: NotificationFilters
  } = {}): Promise<PaginatedNotifications> {
    const page     = options.page  ?? 1
    const limit    = options.limit ?? 20
    const filters  = options.filters ?? {}
    const from     = (page - 1) * limit
    const to       = from + limit - 1

    try {
      let query = supabase
        .from('notifications')
        .select('*', { count: 'estimated' })
        .order('created_at', { ascending: false })
        .range(from, to)

      // Apply filters
      if (filters.category !== undefined) {
        query = query.eq('category', filters.category)
      }
      if (filters.priority !== undefined) {
        query = query.eq('priority', filters.priority)
      }
      if (filters.isRead !== undefined) {
        query = query.eq('is_read', filters.isRead)
      }
      if (filters.isArchived !== undefined) {
        query = query.eq('is_archived', filters.isArchived)
      } else {
        // Default: exclude archived unless caller explicitly wants them
        query = query.eq('is_archived', false)
      }
      if (filters.entityType !== undefined) {
        query = query.eq('entity_type', filters.entityType)
      }
      if (filters.entityId !== undefined) {
        query = query.eq('entity_id', filters.entityId)
      }
      if (filters.dateFrom !== undefined) {
        query = query.gte('created_at', filters.dateFrom)
      }
      if (filters.dateTo !== undefined) {
        query = query.lte('created_at', filters.dateTo + 'T23:59:59Z')
      }
      if (filters.search !== undefined && filters.search.trim() !== '') {
        // Sanitise special ilike pattern characters to prevent query breakage
        const safe = filters.search.replace(/[%()\\/]/g, '')
        query = query.or(
          `title.ilike.%${safe}%,body.ilike.%${safe}%`,
        )
      }

      const { data, error, count } = await query
      if (error) throw wrapSupabaseError(error, 'getNotifications')

      const rows    = (data ?? []) as NotificationRow[]
      const total   = count ?? 0

      return {
        data: rows.map(mapNotificationRow),
        count: total,
        page,
        pageSize: limit,
        totalPages: Math.ceil(total / limit),
      }
    } catch (err) {
      if (err instanceof NotificationError) throw err
      throw wrapSupabaseError(err, 'getNotifications')
    }
  }

  // ──────────────────────────────────────────────────────────
  // UNREAD COUNT
  // ──────────────────────────────────────────────────────────

  /**
   * Returns the number of unread, non-archived, non-expired notifications
   * for the current user via the get_unread_notifications_count() RPC.
   */
  static async getUnreadCount(): Promise<number> {
    try {
      const { data, error } = await supabase.rpc('get_unread_notifications_count')
      if (error) throw wrapSupabaseError(error, 'getUnreadCount')
      return (data as number) ?? 0
    } catch (err) {
      if (err instanceof NotificationError) throw err
      throw wrapSupabaseError(err, 'getUnreadCount')
    }
  }

  // ──────────────────────────────────────────────────────────
  // RECENT UNREAD  (notification panel header)
  // ──────────────────────────────────────────────────────────

  /**
   * Returns the N most recent unread notifications.
   * Used to populate the notification panel dropdown.
   */
  static async getRecentUnread(limit = 10): Promise<Notification[]> {
    try {
      const { data, error } = await supabase
        .from('notifications')
        .select('*')
        .eq('is_read', false)
        .eq('is_archived', false)
        .or('expires_at.is.null,expires_at.gt.' + new Date().toISOString())
        .order('created_at', { ascending: false })
        .limit(limit)

      if (error) throw wrapSupabaseError(error, 'getRecentUnread')

      return ((data ?? []) as NotificationRow[]).map(mapNotificationRow)
    } catch (err) {
      if (err instanceof NotificationError) throw err
      throw wrapSupabaseError(err, 'getRecentUnread')
    }
  }

  // ──────────────────────────────────────────────────────────
  // MARK READ
  // ──────────────────────────────────────────────────────────

  /**
   * Marks a single notification as read.
   * Calls the mark_notification_read() RPC which enforces user ownership.
   */
  static async markAsRead(notificationId: string): Promise<void> {
    try {
      const { error } = await supabase.rpc('mark_notification_read', {
        p_notification_id: notificationId,
      })
      if (error) throw wrapSupabaseError(error, 'markAsRead')
    } catch (err) {
      if (err instanceof NotificationError) throw err
      throw wrapSupabaseError(err, 'markAsRead')
    }
  }

  /**
   * Marks all unread notifications as read, optionally filtered by category.
   * Returns the number of notifications updated.
   */
  static async markAllAsRead(category?: NotificationCategory): Promise<number> {
    try {
      const { data, error } = await supabase.rpc('mark_all_notifications_read', {
        p_category: category ?? null,
      })
      if (error) throw wrapSupabaseError(error, 'markAllAsRead')
      return (data as number) ?? 0
    } catch (err) {
      if (err instanceof NotificationError) throw err
      throw wrapSupabaseError(err, 'markAllAsRead')
    }
  }

  // ──────────────────────────────────────────────────────────
  // ARCHIVE / DELETE
  // ──────────────────────────────────────────────────────────

  /**
   * Archives a notification (soft-delete). Also marks it as read.
   * Calls the archive_notification() RPC which enforces user ownership.
   */
  static async archiveNotification(notificationId: string): Promise<void> {
    try {
      const { error } = await supabase.rpc('archive_notification', {
        p_notification_id: notificationId,
      })
      if (error) throw wrapSupabaseError(error, 'archiveNotification')
    } catch (err) {
      if (err instanceof NotificationError) throw err
      throw wrapSupabaseError(err, 'archiveNotification')
    }
  }

  /**
   * Hard-deletes an archived notification from the database.
   * Only allowed on already-archived rows (guards against accidental deletion).
   */
  static async deleteNotification(notificationId: string): Promise<void> {
    try {
      const { error } = await supabase
        .from('notifications')
        .delete()
        .eq('id', notificationId)
        .eq('is_archived', true)  // extra guard: only delete archived rows

      if (error) throw wrapSupabaseError(error, 'deleteNotification')
    } catch (err) {
      if (err instanceof NotificationError) throw err
      throw wrapSupabaseError(err, 'deleteNotification')
    }
  }

  // ──────────────────────────────────────────────────────────
  // PREFERENCES
  // ──────────────────────────────────────────────────────────

  /**
   * Fetches the current user's notification preferences.
   * If no row exists, returns DEFAULT_PREFERENCES (no throw — first-time users).
   */
  static async getPreferences(): Promise<NotificationPreferences> {
    try {
      const userId = await requireUserId()

      const { data, error } = await supabase
        .from('notification_preferences')
        .select('*')
        .eq('user_id', userId)
        .maybeSingle()

      if (error) throw wrapSupabaseError(error, 'getPreferences')

      if (!data) {
        // No row yet — return defaults with synthetic timestamps
        const now = new Date().toISOString()
        return {
          ...DEFAULT_PREFERENCES,
          userId,
          createdAt: now,
          updatedAt: now,
        }
      }

      return {
        userId: data.user_id,
        inAppEnabled: data.in_app_enabled,
        pushEnabled: data.push_enabled,
        emailEnabled: data.email_enabled,
        quietHoursEnabled: data.quiet_hours_enabled,
        quietStart: data.quiet_start?.substring(0, 5) ?? '22:00', // Postgres 'time' returns "HH:MM:SS" — trim to "HH:MM"
        quietEnd: data.quiet_end?.substring(0, 5)     ?? '08:00', // same trimming for cross-browser input[type=time] compat
        timezone: data.timezone,
        minPriorityInApp: data.min_priority_in_app,
        minPriorityPush: data.min_priority_push,
        categoryPreferences: data.category_preferences ?? {},
        digestModeEnabled: data.digest_mode_enabled,
        digestFrequency: data.digest_frequency,
        createdAt: data.created_at,
        updatedAt: data.updated_at,
      }
    } catch (err) {
      if (err instanceof NotificationError) throw err
      throw wrapSupabaseError(err, 'getPreferences')
    }
  }

  /**
   * Upserts (creates or updates) the current user's notification preferences.
   * Accepts a partial object — only provided fields are written.
   */
  static async updatePreferences(
    partial: Partial<Omit<NotificationPreferences, 'userId' | 'createdAt' | 'updatedAt'>>,
  ): Promise<void> {
    try {
      const userId = await requireUserId()

      // Build the snake_case upsert object
      const upsertData: Record<string, unknown> = { user_id: userId }
      if (partial.inAppEnabled !== undefined)      upsertData.in_app_enabled       = partial.inAppEnabled
      if (partial.pushEnabled !== undefined)       upsertData.push_enabled         = partial.pushEnabled
      if (partial.emailEnabled !== undefined)      upsertData.email_enabled        = partial.emailEnabled
      if (partial.quietHoursEnabled !== undefined) upsertData.quiet_hours_enabled  = partial.quietHoursEnabled
      if (partial.quietStart !== undefined)        upsertData.quiet_start          = partial.quietStart
      if (partial.quietEnd !== undefined)          upsertData.quiet_end            = partial.quietEnd
      if (partial.timezone !== undefined)          upsertData.timezone             = partial.timezone
      if (partial.minPriorityInApp !== undefined)  upsertData.min_priority_in_app  = partial.minPriorityInApp
      if (partial.minPriorityPush !== undefined)   upsertData.min_priority_push    = partial.minPriorityPush
      if (partial.categoryPreferences !== undefined) upsertData.category_preferences = partial.categoryPreferences
      if (partial.digestModeEnabled !== undefined) upsertData.digest_mode_enabled  = partial.digestModeEnabled
      if (partial.digestFrequency !== undefined)   upsertData.digest_frequency     = partial.digestFrequency

      const { error } = await supabase
        .from('notification_preferences')
        .upsert(upsertData, { onConflict: 'user_id' })

      if (error) throw wrapSupabaseError(error, 'updatePreferences')
    } catch (err) {
      if (err instanceof NotificationError) throw err
      throw wrapSupabaseError(err, 'updatePreferences')
    }
  }

  // ──────────────────────────────────────────────────────────
  // PUSH SUBSCRIPTIONS
  // ──────────────────────────────────────────────────────────

  /**
   * Saves (or updates) a Web Push API subscription for the current user.
   * Uses upsert on the unique endpoint constraint so re-subscribing the
   * same device updates keys without creating a duplicate row.
   */
  static async savePushSubscription(
    subscription: globalThis.PushSubscription,
    deviceInfo: DeviceInfo,
  ): Promise<void> {
    try {
      const userId = await requireUserId()

      // Extract key material from the browser subscription object
      const rawKey  = subscription.getKey('p256dh')
      const rawAuth = subscription.getKey('auth')

      if (!rawKey || !rawAuth) {
        throw new NotificationError(
          'بيانات اشتراك Push غير كاملة — لا يمكن استخراج المفاتيح',
          'PUSH_KEYS_MISSING',
        )
      }

      const p256dh = arrayBufferToBase64(rawKey)
      const auth   = arrayBufferToBase64(rawAuth)

      const { error } = await supabase
        .from('push_subscriptions')
        .upsert(
          {
            user_id:     userId,
            endpoint:    subscription.endpoint,
            p256dh_key:  p256dh,
            auth_key:    auth,
            device_name: deviceInfo.deviceName,
            device_type: deviceInfo.deviceType,
            browser:     deviceInfo.browser,
            user_agent:  deviceInfo.userAgent,
            is_active:   true,
            failed_count: 0,
            last_seen_at: new Date().toISOString(),
          },
          { onConflict: 'endpoint' },
        )

      if (error) throw wrapSupabaseError(error, 'savePushSubscription')
    } catch (err) {
      if (err instanceof NotificationError) throw err
      throw wrapSupabaseError(err, 'savePushSubscription')
    }
  }

  /**
   * Removes a push subscription by endpoint for the current user.
   * Called when the user explicitly unsubscribes a device.
   */
  static async removePushSubscription(endpoint: string): Promise<void> {
    try {
      const userId = await requireUserId()

      const { error } = await supabase
        .from('push_subscriptions')
        .delete()
        .eq('endpoint', endpoint)
        .eq('user_id', userId)

      if (error) throw wrapSupabaseError(error, 'removePushSubscription')
    } catch (err) {
      if (err instanceof NotificationError) throw err
      throw wrapSupabaseError(err, 'removePushSubscription')
    }
  }

  /**
   * Returns all push subscription records for the current user.
   * Used in the notification settings page to list registered devices.
   */
  static async getPushSubscriptions(): Promise<PushSubscriptionRecord[]> {
    try {
      const userId = await requireUserId()

      const { data, error } = await supabase
        .from('push_subscriptions')
        .select('id, user_id, endpoint, device_name, device_type, browser, is_active, failed_count, last_push_at, last_seen_at, created_at')
        .eq('user_id', userId)
        .order('created_at', { ascending: false })

      if (error) throw wrapSupabaseError(error, 'getPushSubscriptions')

      return (data ?? []).map(row => ({
        id:          row.id,
        userId:      row.user_id,
        endpoint:    row.endpoint,
        deviceName:  row.device_name,
        deviceType:  row.device_type,
        browser:     row.browser,
        isActive:    row.is_active,
        failedCount: row.failed_count,
        lastPushAt:  row.last_push_at,
        lastSeenAt:  row.last_seen_at,
        createdAt:   row.created_at,
      }))
    } catch (err) {
      if (err instanceof NotificationError) throw err
      throw wrapSupabaseError(err, 'getPushSubscriptions')
    }
  }

  // ──────────────────────────────────────────────────────────
  // EVENT TYPE CATALOGUE
  // ──────────────────────────────────────────────────────────

  /**
   * Fetches the notification event-type catalogue.
   * Optionally filtered by category for settings pages.
   * Results are cached by TanStack Query with a long staleTime.
   */
  static async getNotificationEvents(
    category?: NotificationCategory,
  ): Promise<NotificationEvent[]> {
    try {
      let query = supabase
        .from('notification_event_types')
        .select('*')
        .eq('is_active', true)
        .order('category')
        .order('event_key')

      if (category !== undefined) {
        query = query.eq('category', category)
      }

      const { data, error } = await query
      if (error) throw wrapSupabaseError(error, 'getNotificationEvents')

      return (data ?? []).map(row => ({
        id:                row.id,
        eventKey:          row.event_key,
        labelAr:           row.label_ar,
        labelEn:           row.label_en,
        category:          row.category,
        defaultPriority:   row.default_priority,
        titleTemplate:     row.title_template,
        bodyTemplate:      row.body_template,
        icon:              row.icon,
        actionUrlTemplate: row.action_url_template,
        isActive:          row.is_active,
        createdAt:         row.created_at,
        updatedAt:         row.updated_at,
      }))
    } catch (err) {
      if (err instanceof NotificationError) throw err
      throw wrapSupabaseError(err, 'getNotificationEvents')
    }
  }
}
