// src/hooks/usePushNotifications.ts
// ─────────────────────────────────────────────────────────────
// Manages the full Push Subscription lifecycle.
// IMPORTANT: never requests permission automatically on mount —
// only on explicit user action via requestAndSubscribe().
// ─────────────────────────────────────────────────────────────

import { useEffect, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { NotificationsAPI } from '@/lib/notifications/api'
import { notificationKeys } from '@/lib/notifications/query-keys'
import { useNotificationStore } from '@/stores/notification-store'
import {
  isPushSupported,
  urlBase64ToUint8Array,
  buildDeviceName,
  detectDeviceType,
  detectBrowser,
} from '@/lib/notifications/push-utils'

// ── Types ─────────────────────────────────────────────────────

type PushPermissionState = NotificationPermission | 'unsupported' | 'loading'

interface RequestResult {
  success: boolean
  error?: string
}

export interface UsePushNotificationsReturn {
  permission: PushPermissionState
  isSubscribing: boolean
  isUnsubscribing: boolean
  currentSubscription: PushSubscription | null
  error: string | null
  requestAndSubscribe: () => Promise<RequestResult>
  unsubscribe: (endpoint: string) => Promise<void>
}

// ── Hook ──────────────────────────────────────────────────────

export function usePushNotifications(): UsePushNotificationsReturn {
  const queryClient = useQueryClient()

  const [permission, setPermission] = useState<PushPermissionState>('loading')
  const [isSubscribing, setIsSubscribing]     = useState(false)
  const [isUnsubscribing, setIsUnsubscribing] = useState(false)
  const [currentSubscription, setCurrentSubscription] = useState<PushSubscription | null>(null)
  const [error, setError] = useState<string | null>(null)

  // ── On mount: detect support and current permission state ──
  useEffect(() => {
    if (!isPushSupported()) {
      setPermission('unsupported')
      useNotificationStore.getState().setPushPermission('unsupported')
      return
    }

    const perm = Notification.permission
    setPermission(perm)
    useNotificationStore.getState().setPushPermission(perm)

    // If already granted, fetch the existing subscription silently
    if (perm === 'granted') {
      navigator.serviceWorker.ready
        .then(reg => reg.pushManager.getSubscription())
        .then(existing => setCurrentSubscription(existing))
        .catch(() => {
          // Non-critical — existing subscription may be null
        })
    }
  }, [])

  // ── requestAndSubscribe ───────────────────────────────────────
  // Called only on explicit user action (button click in Preferences).
  const requestAndSubscribe = async (): Promise<RequestResult> => {
    setError(null)

    if (!isPushSupported()) {
      return { success: false, error: 'المتصفح لا يدعم Push Notifications' }
    }

    setIsSubscribing(true)

    try {
      // 1. Request browser permission
      const result = await Notification.requestPermission()
      setPermission(result)
      useNotificationStore.getState().setPushPermission(result)

      if (result !== 'granted') {
        setIsSubscribing(false)
        return { success: false, error: 'لم يتم منح الإذن لإرسال الإشعارات' }
      }

      // 2. Get VAPID public key
      const publicKey = import.meta.env.VITE_VAPID_PUBLIC_KEY as string | undefined
      if (!publicKey) {
        throw new Error('VITE_VAPID_PUBLIC_KEY غير مضبوط في البيئة')
      }

      // 3. Get the registered service worker — with a 10s timeout guard.
      //    navigator.serviceWorker.ready can hang indefinitely if the SW
      //    failed to install (e.g. dev server without devOptions.enabled).
      const swReadyWithTimeout = (): Promise<ServiceWorkerRegistration> =>
        Promise.race([
          navigator.serviceWorker.ready,
          new Promise<never>((_, reject) =>
            setTimeout(() =>
              reject(new Error(
                'Service Worker غير جاهز — تأكد من تشغيل التطبيق في بيئة HTTPS أو أعد تحميل الصفحة'
              )),
              10_000
            )
          ),
        ])

      const reg = await swReadyWithTimeout()

      // 4. Subscribe to Push API
      const subscription = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        // Cast required: Uint8Array<ArrayBufferLike> vs ArrayBufferView<ArrayBuffer> strictness
        applicationServerKey: urlBase64ToUint8Array(publicKey) as unknown as ArrayBuffer,
      })

      setCurrentSubscription(subscription)

      // 5. Persist subscription to Supabase
      await NotificationsAPI.savePushSubscription(subscription, {
        deviceName: buildDeviceName(),
        deviceType: detectDeviceType(),
        browser: detectBrowser(),
        userAgent: navigator.userAgent,
      })

      // 6. Refresh devices list immediately so UI reflects the new device (BUG-06)
      await queryClient.invalidateQueries({ queryKey: notificationKeys.pushDevices() })

      setIsSubscribing(false)
      return { success: true }

    } catch (err: unknown) {
      setIsSubscribing(false)

      let message = 'حدث خطأ أثناء تفعيل إشعارات Push'

      if (err instanceof DOMException) {
        if (err.name === 'NotAllowedError') {
          message = 'رُفض إذن Push من المتصفح — تحقق من إعدادات المتصفح'
        } else if (err.name === 'AbortError') {
          message = 'تم إلغاء العملية — حاول مجدداً'
        }
      } else if (err instanceof Error) {
        message = err.message
      }

      setError(message)
      return { success: false, error: message }
    }
  }

  // ── unsubscribe ───────────────────────────────────────────────
  // Unregisters the subscription from both the browser and Supabase.
  const unsubscribe = async (endpoint: string): Promise<void> => {
    setIsUnsubscribing(true)
    setError(null)

    try {
      const reg = await navigator.serviceWorker.ready
      const sub = await reg.pushManager.getSubscription()

      // Unsubscribe from browser PushManager if it matches the requested endpoint
      if (sub?.endpoint === endpoint) {
        await sub.unsubscribe()
      }

      // Remove from Supabase regardless (endpoint may belong to another device)
      await NotificationsAPI.removePushSubscription(endpoint)

      // Clear local state only if the unsubscribed endpoint matches current device
      if (currentSubscription?.endpoint === endpoint) {
        setCurrentSubscription(null)
      }
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'خطأ أثناء إلغاء الاشتراك'
      setError(message)
    } finally {
      // Refresh devices list regardless of success/failure (BUG-07)
      // If DB delete succeeded but browser unsubscribe failed, list should still update
      await queryClient.invalidateQueries({ queryKey: notificationKeys.pushDevices() })

      setIsUnsubscribing(false)
    }
  }

  return {
    permission,
    isSubscribing,
    isUnsubscribing,
    currentSubscription,
    error,
    requestAndSubscribe,
    unsubscribe,
  }
}
