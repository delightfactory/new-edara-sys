/**
 * Global Realtime Manager — EDARA v2
 * ─────────────────────────────────────────────
 * مكوّن واحد عالمي يُركَّب مرة واحدة في App.tsx
 * يستمع لتغييرات الجداول الحرجة عبر Supabase Realtime
 * ويُبطل React Query cache تلقائياً.
 *
 * المبدأ: قناة واحدة → عشرات الجداول → cache invalidation فوري
 *
 * Best Practices المُطبقة:
 * 1. قناة واحدة (singleton) بدلاً من قناة لكل صفحة → توفير WebSocket connections
 * 2. Broad invalidation بالـ queryKey prefix → يُبطل كل الـ queries ذات الصلة
 * 3. Debounce لتجنُّب سيل الـ invalidations عند bulk operations
 * 4. يعمل فقط عند وجود مستخدم مُسجّل دخول
 */

import { useEffect, useRef, useCallback } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase/client'
import { useAuthStore } from '@/stores/auth-store'

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

  // ─── المخزون ───
  stock:               ['stock', 'stock-movements'],
  stock_transfers:     ['transfers'],
  stock_transfer_items:['transfers'],
  stock_adjustments:   ['adjustments'],

  // ─── البيانات الأساسية ───
  customers:           ['customers'],
  products:            ['products'],
  warehouses:          ['warehouses', 'my-warehouses'],
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

    channel.subscribe()

    return () => {
      if (timerRef.current) clearTimeout(timerRef.current)
      supabase.removeChannel(channel)
    }
  }, [profile, queryClient, scheduleInvalidation])

  // هذا المكوّن لا يعرض شيئاً — فقط يدير الاشتراكات
  return null
}
