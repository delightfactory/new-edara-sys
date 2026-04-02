// src/stores/notification-store.ts
// ─────────────────────────────────────────────────────────────
// Zustand store for ephemeral notification UI state.
//
// Design decisions:
// - NO persist middleware — all state is re-derived on mount:
//   • unreadCount  → fetched via TanStack Query + updated by Realtime
//   • pushPermission → read from browser Notification API on boot
// - Follows the same pattern as auth-store.ts (create + named export)
// - Named exports only — no default export (project convention)
// ─────────────────────────────────────────────────────────────

import { create } from 'zustand'

// ============================================================
// STATE SHAPE
// ============================================================

interface NotificationState {
  /**
   * Live count of unread, non-archived, non-expired notifications.
   * Initialised to 0; populated by the initial TanStack Query fetch
   * and incremented/decremented by Realtime events.
   */
  unreadCount: number

  /** Controls whether the notification panel/drawer is open */
  isPanelOpen: boolean

  /**
   * Status of the Supabase Realtime channel that listens for
   * new notification INSERTs for the current user.
   */
  realtimeChannelStatus: 'connecting' | 'connected' | 'disconnected' | 'error'

  /**
   * Current browser push notification permission.
   * - 'loading'     : permission state not yet read from browser API
   * - 'unsupported' : Notification API not available (e.g. iOS Safari <16.4)
   * - PermissionState values: 'granted' | 'denied' | 'default'
   */
  pushPermission: NotificationPermission | 'unsupported' | 'loading'
}

// ============================================================
// ACTION SHAPE
// ============================================================

interface NotificationActions {
  /** Directly set the unread count (e.g. on initial fetch) */
  setUnreadCount: (count: number) => void

  /** Increment the count by 1 when a new notification arrives via Realtime */
  incrementUnread: () => void

  /**
   * Decrement the count, e.g. after the user reads one or more notifications.
   * @param by Number to subtract — defaults to 1
   */
  decrementUnread: (by?: number) => void

  /** Reset count to 0 (e.g. after markAllAsRead) */
  resetUnread: () => void

  /** Explicitly open or close the notification panel */
  setPanelOpen: (open: boolean) => void

  /** Toggle the panel open/closed state */
  togglePanel: () => void

  /** Update the Realtime channel connection status */
  setRealtimeStatus: (status: NotificationState['realtimeChannelStatus']) => void

  /** Update the browser push permission state */
  setPushPermission: (permission: NotificationState['pushPermission']) => void
}

// ============================================================
// STORE
// ============================================================

/**
 * ⚠️ NO persist middleware — state is fully ephemeral.
 * unreadCount is restored on mount by TanStack Query.
 * pushPermission is restored by reading the browser API on mount.
 */
export const useNotificationStore = create<NotificationState & NotificationActions>()(
  (set, get) => ({
    // ── Initial state ───────────────────────────────────────
    unreadCount:           0,
    isPanelOpen:           false,
    realtimeChannelStatus: 'disconnected',
    pushPermission:        'loading',

    // ── Actions ─────────────────────────────────────────────
    setUnreadCount: (count) =>
      set({ unreadCount: Math.max(0, count) }),

    incrementUnread: () =>
      set(s => ({ unreadCount: s.unreadCount + 1 })),

    decrementUnread: (by = 1) =>
      set(s => ({ unreadCount: Math.max(0, s.unreadCount - by) })),

    resetUnread: () =>
      set({ unreadCount: 0 }),

    setPanelOpen: (open) =>
      set({ isPanelOpen: open }),

    togglePanel: () =>
      set(s => ({ isPanelOpen: !s.isPanelOpen })),

    setRealtimeStatus: (realtimeChannelStatus) =>
      set({ realtimeChannelStatus }),

    setPushPermission: (pushPermission) =>
      set({ pushPermission }),
  }),
)
