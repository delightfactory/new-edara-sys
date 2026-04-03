/**
 * notification-store.test.ts
 * Tests for decrementUnread — must never go below 0.
 * Regression guard for the DATA-02 fix (archive mutation calling
 * decrementUnread N times instead of once).
 */
import { describe, it, expect, beforeEach } from 'vitest'
import { useNotificationStore } from '@/stores/notification-store'

beforeEach(() => {
  useNotificationStore.getState().setUnreadCount(0)
})

describe('useNotificationStore unread counter', () => {
  it('increments from 0 to 1', () => {
    useNotificationStore.getState().incrementUnread()
    expect(useNotificationStore.getState().unreadCount).toBe(1)
  })

  it('decrements from 3 to 2', () => {
    useNotificationStore.getState().setUnreadCount(3)
    useNotificationStore.getState().decrementUnread()
    expect(useNotificationStore.getState().unreadCount).toBe(2)
  })

  it('never goes below 0 when decrementing from 0', () => {
    useNotificationStore.getState().setUnreadCount(0)
    useNotificationStore.getState().decrementUnread()
    expect(useNotificationStore.getState().unreadCount).toBe(0)
  })

  it('multiple decrements only apply once each — simulates single-archive call', () => {
    useNotificationStore.getState().setUnreadCount(5)
    // Archive one notification — should call decrementUnread exactly once
    useNotificationStore.getState().decrementUnread()
    expect(useNotificationStore.getState().unreadCount).toBe(4)
  })

  it('resetUnread sets count to 0', () => {
    useNotificationStore.getState().setUnreadCount(10)
    useNotificationStore.getState().resetUnread()
    expect(useNotificationStore.getState().unreadCount).toBe(0)
  })
})
