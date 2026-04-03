/**
 * Global Realtime Manager — EDARA v2
 * ─────────────────────────────────────────────
 * مكوّن واحد عالمي يُركَّب مرة واحدة في App.tsx
 * يستمع لتغييرات الجداول الحرجة عبر Supabase Realtime
 * ويُبطل React Query cache تلقائياً.
 *
 * المبدأ: قناتان منفصلتان:
 *   1. global-realtime  → عشرات الجداول → cache invalidation فوري (debounced)
 *   2. notifications:<userId> → إشعارات المستخدم فقط → store + toast
 *
 * Best Practices المُطبقة:
 * 1. قناة واحدة للبيانات العامة (singleton) → توفير WebSocket connections
 * 2. قناة منفصلة للإشعارات مع filter → لا تُستقبل إشعارات مستخدمين آخرين
 * 3. Debounce لتجنُّب سيل الـ invalidations عند bulk operations
 * 4. يعمل فقط عند وجود مستخدم مُسجّل دخول
 */

import { useEffect, useRef, useCallback } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { supabase } from '@/lib/supabase/client'
import { useAuthStore } from '@/stores/auth-store'
import { useNotificationStore } from '@/stores/notification-store'
import { notificationKeys } from '@/lib/notifications/query-keys'
import { updateAppBadge } from '@/lib/notifications/push-utils'
import { resolveNotificationUrlFromRow } from '@/lib/notifications/navigation'
import type { NotificationRow } from '@/lib/notifications/types'

/**
 * خريطة الجدول → مفاتيح الـ cache المُبطلة
 * كل تغيير في الجدول يُبطل كل الـ queries التي تبدأ بهذه المفاتيح
 */
const TABLE_QUERY_MAP: Record<string, string[]> = {
  // ─── المالية ───
  expenses:             ['expenses'],
  payment_receipts:     ['payment-receipts'],
  vaults:               ['vaults'],
  vault_transactions:   ['vault-transactions', 'vaults'],
  custody_accounts:     ['custody-accounts'],
  custody_transactions: ['custody-transactions', 'custody-accounts'],
  journal_entries:      ['journal-entries'],
  journal_entry_lines:  ['journal-entries'],
  customer_ledger:      ['customer-ledger'],
  supplier_ledger:      ['supplier-ledger'],

  // ─── المخزون ───
  stock:               ['stock', 'stock-movements'],
  stock_transfers:     ['transfers'],
  stock_transfer_items:['transfers'],
  stock_adjustments:   ['adjustments'],

  // ─── البيانات الأساسية ───
  customers:           ['customers'],
  products:            ['products'],
  suppliers:           ['suppliers'],
  warehouses:          ['warehouses', 'my-warehouses'],
  profiles:            ['profiles-active', 'users'],
  product_categories:  ['product-categories'],
  brands:              ['brands'],
  user_roles:          ['users', 'profiles-active'],

  // ─── المبيعات ───
  sales_orders:        ['sales-orders', 'sales-stats'],
  sales_order_items:   ['sales-orders'],
  sale_returns:        ['sales-returns'],

  // ─── المشتريات ───
  purchase_orders:     ['purchase-orders'],
  purchase_order_items:['purchase-orders'],

  // ─── الأنشطة الميدانية ───
  visit_plans:         ['visit-plans'],
  visit_plan_items:    ['visit-plans', 'visit-plan-items'],
  call_plans:          ['call-plans'],
  call_plan_items:     ['call-plans', 'call-plan-items'],
  activities:          ['activities', 'rep-performance', 'plan-daily-summary'],

  // ─── الموارد البشرية ───
  hr_employees:        ['hr-employees', 'hr-current-employee'],
  hr_attendance:       ['hr-attendance-days', 'hr-attendance-alerts',
                        'hr-attendance-review-summary', 'hr-attendance-summary'],
  hr_leave_requests:   ['hr-leave-requests', 'hr-leave-balances'],
  hr_advances:         ['hr-advances'],
  hr_payroll_runs:     ['hr-payroll-runs'],
  hr_payroll_lines:    ['hr-payroll-runs', 'hr-payroll-lines'],
}

const DEBOUNCE_MS = 500 // تأخير نصف ثانية لتجميع bulk operations

export default function GlobalRealtimeManager() {
  const queryClient = useQueryClient()
  const profile = useAuthStore(s => s.profile)
  const pendingKeys = useRef<Set<string>>(new Set())
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const flushInvalidations = useCallback(() => {
    if (pendingKeys.current.size === 0) return
    const keys = [...pendingKeys.current]
    pendingKeys.current.clear()
    keys.forEach(key => {
      queryClient.invalidateQueries({ queryKey: [key] })
    })
  }, [queryClient])

  const scheduleInvalidation = useCallback((queryKeys: string[]) => {
    queryKeys.forEach(k => pendingKeys.current.add(k))
    if (timerRef.current) clearTimeout(timerRef.current)
    timerRef.current = setTimeout(flushInvalidations, DEBOUNCE_MS)
  }, [flushInvalidations])

  // ── قناة 1: الجداول العامة ─────────────────────────────
  useEffect(() => {
    // لا نشترك إلا عند وجود مستخدم مُسجّل
    if (!profile) return

    const tables = Object.keys(TABLE_QUERY_MAP)

    // إنشاء قناة واحدة مع listener لكل جدول
    let channel = supabase.channel('global-realtime')

    tables.forEach(table => {
      channel = channel.on(
        'postgres_changes',
        { event: '*', schema: 'public', table },
        () => {
          const queryKeys = TABLE_QUERY_MAP[table]
          if (queryKeys) {
            scheduleInvalidation(queryKeys)
          }
        }
      )
    })

    channel.subscribe((status, err) => {
      if (status === 'SUBSCRIBED') {
        console.log('[Realtime] ✅ Connected — listening to', tables.length, 'tables')
      } else if (status === 'TIMED_OUT') {
        console.warn('[Realtime] ⏱ Connection timed out — will retry')
      } else if (status === 'CHANNEL_ERROR') {
        console.error('[Realtime] ❌ Channel error:', err)
      } else if (status === 'CLOSED') {
        console.warn('[Realtime] 🔌 Connection closed')
      }
    })

    return () => {
      if (timerRef.current) clearTimeout(timerRef.current)
      supabase.removeChannel(channel)
    }
  }, [profile, queryClient, scheduleInvalidation])

  // ── قناة 2: إشعارات المستخدم الحالي ───────────────────
  useEffect(() => {
    if (!profile) return

    // profile.id هو الـ auth.users.id المرتبط بالمستخدم الحالي
    const userId = profile.id

    const notificationChannel = supabase
      .channel(`notifications:${userId}`)
      .on(
        'postgres_changes',
        {
          event:  'INSERT',
          schema: 'public',
          table:  'notifications',
          filter: `user_id=eq.${userId}`,
        },
        (payload) => {
          const notification = payload.new as NotificationRow

          // 1. تحديث unread count في الـ store فوراً
          //    نقرأ القيمة الحالية أولاً ثم نُضيف 1 للـ badge — Zustand's set() متزامن
          //    لكن قراءة count قبل increment ثم إضافة 1 تضمن الدقة دون أي التباس
          const prevCount = useNotificationStore.getState().unreadCount
          useNotificationStore.getState().incrementUnread()

          // 2. تحديث App Badge على مستوى نظام التشغيل (Chrome/Edge فقط)
          updateAppBadge(prevCount + 1).catch(() => {})

          // 3. إبطال caches ذات الصلة
          queryClient.invalidateQueries({ queryKey: notificationKeys.unreadCount() })
          // Use prefix match to invalidate all recent(X) queries regardless of limit param
          queryClient.invalidateQueries({ queryKey: [...notificationKeys.all, 'recent'] })
          queryClient.invalidateQueries({ queryKey: notificationKeys.lists() })

          // 4. Rich toast for high/critical priority notifications
          // (low/medium appear only in the notification panel when opened)
          if (notification.priority === 'critical' || notification.priority === 'high') {
            const isCritical = notification.priority === 'critical'
            const categoryColors: Record<string, string> = {
              hr_attendance: '#6366f1', hr_leaves: '#8b5cf6', hr_payroll: '#10b981',
              finance_expenses: '#f59e0b', finance_approvals: '#3b82f6',
              inventory: '#06b6d4', sales: '#ec4899', system: '#6b7280',
              alerts: '#ef4444', procurement: '#0891b2', tasks: '#059669',
            }
            const accentColor = isCritical
              ? '#dc2626'
              : categoryColors[notification.category] || '#3b82f6'

            toast.custom(
              (t) => {
                const handleToastClick = () => {
                  toast.dismiss(t)
                  const actionUrl = resolveNotificationUrlFromRow(notification)
                  if (actionUrl) {
                    // Navigate using location (GlobalRealtimeManager is outside BrowserRouter)
                    window.location.href = actionUrl
                  } else {
                    useNotificationStore.getState().setPanelOpen(true)
                  }
                }

                return (
                  <div
                    onClick={handleToastClick}
                    style={{
                      display: 'flex',
                      alignItems: 'flex-start',
                      gap: '12px',
                      padding: '14px 16px',
                      background: 'var(--bg-surface, #fff)',
                      border: '1px solid var(--border-primary, #e2e8f0)',
                      borderRadius: '14px',
                      boxShadow: '0 8px 30px rgba(0,0,0,0.12), 0 2px 8px rgba(0,0,0,0.06)',
                      cursor: 'pointer',
                      maxWidth: '380px',
                      width: '100%',
                      position: 'relative',
                      overflow: 'hidden',
                      direction: 'rtl',
                      fontFamily: 'var(--font-sans)',
                      animation: 'notif-toast-slide 0.4s cubic-bezier(0.16,1,0.3,1)',
                    }}
                  >
                    {/* Priority accent stripe */}
                    <div style={{
                      position: 'absolute',
                      top: 0,
                      right: 0,
                      bottom: 0,
                      width: '4px',
                      background: accentColor,
                      borderRadius: '0 14px 14px 0',
                    }} />

                    {/* Category icon */}
                    <div style={{
                      width: '40px',
                      height: '40px',
                      borderRadius: '12px',
                      background: `${accentColor}14`,
                      color: accentColor,
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      flexShrink: 0,
                      fontSize: '18px',
                    }}>
                      🔔
                    </div>

                    {/* Text content */}
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{
                        fontSize: '14px',
                        fontWeight: 600,
                        color: 'var(--text-primary, #0f172a)',
                        marginBottom: '3px',
                        lineHeight: '1.4',
                      }}>
                        {notification.title}
                      </div>
                      <div style={{
                        fontSize: '12px',
                        color: 'var(--text-secondary, #64748b)',
                        lineHeight: '1.5',
                        display: '-webkit-box',
                        WebkitLineClamp: 2,
                        WebkitBoxOrient: 'vertical',
                        overflow: 'hidden',
                      }}>
                        {notification.body}
                      </div>
                      <div style={{
                        fontSize: '11px',
                        color: accentColor,
                        fontWeight: 500,
                        marginTop: '6px',
                      }}>
                        اضغط للعرض ←
                      </div>
                    </div>
                  </div>
                )
              },
              {
                duration: isCritical ? 10_000 : 6_000,
                position: 'top-center',
              }
            )
          }
        }
      )
      .subscribe((status) => {
        const notifStore = useNotificationStore.getState()
        if (status === 'SUBSCRIBED') {
          notifStore.setRealtimeStatus('connected')
          console.log('[Notifications Realtime] ✅ Subscribed for user:', userId)
        } else if (status === 'CHANNEL_ERROR') {
          notifStore.setRealtimeStatus('error')
          console.error('[Notifications Realtime] ❌ Channel error')
        } else if (status === 'CLOSED') {
          notifStore.setRealtimeStatus('disconnected')
        } else {
          notifStore.setRealtimeStatus('connecting')
        }
      })

    return () => {
      supabase.removeChannel(notificationChannel)
      useNotificationStore.getState().setRealtimeStatus('disconnected')
    }
  }, [profile, queryClient])

  // هذا المكوّن لا يعرض شيئاً — فقط يدير الاشتراكات
  return null
}
