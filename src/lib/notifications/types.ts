// src/lib/notifications/types.ts
// ─────────────────────────────────────────────────────────────
// Core TypeScript types for the EDARA Notification System.
// All types use camelCase to match TypeScript conventions;
// snake_case equivalents are used only in DB row shapes.
// ─────────────────────────────────────────────────────────────

// ============================================================
// PRIMITIVE UNIONS
// ============================================================

/** Maps to the notification_category DB enum */
export type NotificationCategory =
  | 'system'
  | 'hr_attendance'
  | 'hr_payroll'
  | 'hr_leaves'
  | 'finance_expenses'
  | 'finance_approvals'
  | 'inventory'
  | 'sales'
  | 'procurement'
  | 'tasks'
  | 'alerts'

/** Maps to the notification_priority DB enum */
export type NotificationPriority = 'low' | 'medium' | 'high' | 'critical'

/** Delivery channels supported by the system */
export type NotificationDeliveryChannel = 'in_app' | 'push' | 'email'

/** Lifecycle status of a single delivery attempt */
export type NotificationDeliveryStatus =
  | 'sent'
  | 'delivered'
  | 'clicked'
  | 'dismissed'
  | 'failed'
  | 'skipped'

/** Physical device category for push subscriptions */
export type DeviceType = 'desktop' | 'mobile' | 'tablet'

/** Digest batching frequency */
export type DigestFrequency = 'realtime' | 'hourly' | 'daily'

// ============================================================
// NOTIFICATION
// ============================================================

/**
 * Application-level notification object (camelCase, used throughout the UI).
 * Each instance belongs to exactly one user.
 */
export interface Notification {
  id: string
  userId: string
  /** References notification_event_types.event_key — null if event type was deleted */
  eventKey: string | null
  title: string
  body: string
  category: NotificationCategory
  priority: NotificationPriority
  /** Lucide icon name, e.g. 'clock-alert' */
  icon: string | null
  /** Deep-link URL within the app */
  actionUrl: string | null
  /** Type of the originating entity, e.g. 'expense' | 'leave_request' */
  entityType: string | null
  entityId: string | null
  /** Arbitrary extra data for UI rendering */
  metadata: Record<string, unknown>
  isRead: boolean
  readAt: string | null
  isArchived: boolean
  archivedAt: string | null
  /** Per-channel delivery status snapshot */
  deliveryChannels: Partial<Record<NotificationDeliveryChannel, NotificationDeliveryStatus>>
  /** ISO 8601 expiry timestamp — null means no TTL */
  expiresAt: string | null
  createdAt: string
  updatedAt: string
}

/**
 * Raw database row shape returned by Supabase (snake_case).
 * Use mapNotificationRow() to convert to Notification.
 */
export interface NotificationRow {
  id: string
  user_id: string
  event_key: string | null
  title: string
  body: string
  category: NotificationCategory
  priority: NotificationPriority
  icon: string | null
  action_url: string | null
  entity_type: string | null
  entity_id: string | null
  metadata: Record<string, unknown>
  is_read: boolean
  read_at: string | null
  is_archived: boolean
  archived_at: string | null
  delivery_channels: Partial<Record<NotificationDeliveryChannel, NotificationDeliveryStatus>>
  expires_at: string | null
  created_at: string
  updated_at: string
}

/** Maps a Supabase DB row to the application-level Notification interface */
export function mapNotificationRow(row: NotificationRow): Notification {
  return {
    id: row.id,
    userId: row.user_id,
    eventKey: row.event_key,
    title: row.title,
    body: row.body,
    category: row.category,
    priority: row.priority,
    icon: row.icon,
    actionUrl: row.action_url,
    entityType: row.entity_type,
    entityId: row.entity_id,
    metadata: row.metadata,
    isRead: row.is_read,
    readAt: row.read_at,
    isArchived: row.is_archived,
    archivedAt: row.archived_at,
    deliveryChannels: row.delivery_channels,
    expiresAt: row.expires_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }
}

// ============================================================
// NOTIFICATION EVENT TYPE  (catalogue)
// ============================================================

/**
 * A registered event type from the notification_event_types catalogue.
 * Used in the settings UI to let users configure per-event preferences.
 */
export interface NotificationEvent {
  id: string
  eventKey: string
  labelAr: string
  labelEn: string
  category: NotificationCategory
  defaultPriority: NotificationPriority
  titleTemplate: string
  bodyTemplate: string
  icon: string | null
  actionUrlTemplate: string | null
  isActive: boolean
  createdAt: string
  updatedAt: string
}

// ============================================================
// PREFERENCES
// ============================================================

/** Per-category delivery preferences */
export interface NotificationCategoryPreference {
  inApp: boolean
  push: boolean
}

/**
 * Per-user notification preferences stored in notification_preferences.
 * A row is created with DEFAULT_PREFERENCES on first access.
 */
export interface NotificationPreferences {
  userId: string

  // Global channel toggles
  inAppEnabled: boolean
  pushEnabled: boolean
  emailEnabled: boolean

  // Quiet hours
  quietHoursEnabled: boolean
  /** 24-hour "HH:MM" format */
  quietStart: string
  /** 24-hour "HH:MM" format */
  quietEnd: string
  timezone: string

  // Minimum priority per channel
  minPriorityInApp: NotificationPriority
  minPriorityPush: NotificationPriority

  // Per-category overrides
  categoryPreferences: Partial<Record<NotificationCategory, NotificationCategoryPreference>>

  // Digest settings
  digestModeEnabled: boolean
  digestFrequency: DigestFrequency

  createdAt: string
  updatedAt: string
}

/**
 * Default preferences applied when no row exists for a user.
 * Excludes server-generated timestamps and the user_id FK.
 */
export const DEFAULT_PREFERENCES: Omit<
  NotificationPreferences,
  'userId' | 'createdAt' | 'updatedAt'
> = {
  inAppEnabled: true,
  pushEnabled: false,
  emailEnabled: false,
  quietHoursEnabled: false,
  quietStart: '22:00',
  quietEnd: '08:00',
  timezone: 'Africa/Cairo',
  minPriorityInApp: 'low',
  minPriorityPush: 'medium',
  categoryPreferences: {},
  digestModeEnabled: false,
  digestFrequency: 'realtime',
}

// ============================================================
// PUSH SUBSCRIPTIONS
// ============================================================

/**
 * A registered Web Push subscription for a specific device.
 * The sensitive key material (p256dh_key, auth_key) is intentionally
 * omitted from this read-model; it lives only in the DB.
 */
export interface PushSubscriptionRecord {
  id: string
  userId: string
  endpoint: string
  deviceName: string | null
  deviceType: DeviceType
  browser: string | null
  isActive: boolean
  failedCount: number
  lastPushAt: string | null
  lastSeenAt: string | null
  createdAt: string
}

/** Metadata captured at subscription time for the device label */
export interface DeviceInfo {
  deviceName: string
  deviceType: DeviceType
  browser: string
  userAgent: string
}

// ============================================================
// DELIVERY LOG
// ============================================================

/** Immutable delivery audit log entry */
export interface DeliveryLog {
  id: string
  notificationId: string
  channel: NotificationDeliveryChannel
  status: NotificationDeliveryStatus
  subscriptionId: string | null
  errorCode: string | null
  errorMessage: string | null
  processedAt: string
}

// ============================================================
// QUERY & FILTER TYPES
// ============================================================

/** Filters accepted by getNotifications() */
export interface NotificationFilters {
  category?: NotificationCategory
  priority?: NotificationPriority
  isRead?: boolean
  isArchived?: boolean
  /** Full-text search across title and body */
  search?: string
  dateFrom?: string
  dateTo?: string
  entityType?: string
  entityId?: string
}

/** Paginated response wrapper for notification list queries */
export interface PaginatedNotifications {
  data: Notification[]
  count: number
  page: number
  pageSize: number
  totalPages: number
}

// ============================================================
// DISPATCH TYPES  (used by server-side dispatch layer — Sprint 2+)
// ============================================================

/**
 * Variables used to interpolate {{variable}} placeholders in templates.
 * Values must be scalar so they serialise cleanly to the DB.
 */
export type TemplateVariables = Record<string, string | number>

/**
 * Payload required to dispatch a notification for a registered event type.
 * The server looks up the event_key to resolve templates and defaults.
 */
export interface DispatchPayload {
  eventKey: string
  userId: string
  variables?: TemplateVariables
  entityType?: string
  entityId?: string
  metadata?: Record<string, unknown>
  /** Override the event-type default priority */
  priority?: NotificationPriority
  /** Optional TTL in seconds from now */
  ttlSeconds?: number
}
