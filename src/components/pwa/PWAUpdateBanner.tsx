/**
 * PWAUpdateManager — نظام تحديث آمن بدون reload تلقائي
 *
 * المبدأ الجوهري (مستوحى من home-care المُثبَت):
 * ─────────────────────────────────────────────
 * window.location.reload() لا تُستدعى أبداً تلقائياً.
 * تُستدعى فقط بعد أن يضغط المستخدم "تحديث الآن" صراحةً.
 *
 * هذا يحل مشكلة إغلاق نموذج رفع الملفات على الموبايل:
 * عند العودة من الكاميرا/الجاليري، لا يوجد أي مسار تحديث
 * يُطلق reload في الخلفية.
 *
 * دورة الحياة:
 * 1. التطبيق يبدأ → نبحث فوراً عن SW منتظر
 * 2. كل 5 دقائق → reg.update() (فحص للتحديثات)
 * 3. تحديث وُجد → toast يظهر للمستخدم
 * 4. مستخدم يضغط "تحديث الآن" → postMessage(SKIP_WAITING) → reload
 * 5. مستخدم يتجاهل → لا شيء يحدث، التطبيق يعمل طبيعياً
 */

import { useEffect, useRef } from 'react'
import { toast } from 'sonner'

export default function PWAUpdateManager() {
  // Flag: هل يجري تحديث بناءً على طلب المستخدم صراحةً؟
  // reload() مسموح فقط عندما يكون هذا true
  const isUpdatingRef = useRef(false)
  const registrationRef = useRef<ServiceWorkerRegistration | null>(null)

  useEffect(() => {
    if (!('serviceWorker' in navigator)) return

    let pollInterval: ReturnType<typeof setInterval>

    const showUpdateToast = () => {
      toast.info('يوجد تحديث جديد للتطبيق', {
        id: 'pwa-update-available',
        duration: Infinity, // يبقى حتى يتخذ المستخدم قراراً
        position: 'bottom-center',
        action: {
          label: 'تحديث الآن',
          onClick: handleUpdate,
        },
        cancel: {
          label: 'لاحقاً',
          onClick: () => toast.dismiss('pwa-update-available'),
        },
      })
    }

    const handleUpdate = async () => {
      const reg = registrationRef.current
      if (!reg) {
        // لا يوجد registration — أعد التحميل مباشرة
        window.location.reload()
        return
      }

      if (!reg.waiting) {
        // لا يوجد SW منتظر — أعد التحميل مباشرة
        window.location.reload()
        return
      }

      // ✅ هذا هو الموضع الوحيد الذي يُسمح فيه بـ reload
      isUpdatingRef.current = true

      // أرسل SKIP_WAITING للـ SW المنتظر
      reg.waiting.postMessage({ type: 'SKIP_WAITING' })

      // انتظر تغيير الـ controller (مع timeout أمان 3 ثواني)
      await Promise.race([
        new Promise<void>(resolve => {
          const onControllerChange = () => {
            navigator.serviceWorker.removeEventListener('controllerchange', onControllerChange)
            resolve()
          }
          navigator.serviceWorker.addEventListener('controllerchange', onControllerChange)
        }),
        new Promise<void>(resolve => setTimeout(resolve, 3000)),
      ])

      window.location.reload()
    }

    const setup = async () => {
      try {
        const reg = await navigator.serviceWorker.ready
        registrationRef.current = reg

        // ── فحص فوري: هل يوجد SW منتظر من جلسة سابقة؟ ──
        if (reg.waiting) {
          showUpdateToast()
        }

        // ── استمع لتحديثات جديدة ──
        reg.addEventListener('updatefound', () => {
          const newWorker = reg.installing
          if (!newWorker) return

          newWorker.addEventListener('statechange', () => {
            if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
              // SW جديد جاهز ومنتظر — أعلم المستخدم
              showUpdateToast()
            }
          })
        })

        // ── فحص دوري كل 5 دقائق ──
        reg.update().catch(() => {}) // فحص فوري عند mount
        pollInterval = setInterval(() => {
          reg.update().catch(() => {})
        }, 5 * 60 * 1000)
      } catch {
        // SW غير متاح (dev mode أو browser لا يدعمه) — تجاهل بصمت
      }
    }

    // ── عند عودة المستخدم للتطبيق (من الكاميرا / تبديل التطبيقات / ساعات غياب) ──
    const handleVisibilityChange = () => {
      if (document.visibilityState !== 'visible') return
      const reg = registrationRef.current
      if (!reg) return

      // إذا كان SW منتظراً (ربما أغلق المستخدم الـ toast سابقاً) → أعد إظهار الـ toast
      if (reg.waiting) {
        showUpdateToast()
        return
      }

      // وإلا: اطلب فحص تحديث جديد من السيرفر
      reg.update().catch(() => {})
    }

    // ── عند استعادة الاتصال: التحديث قد يكون نزل على السيرفر أثناء الانقطاع ──
    const handleOnline = () => {
      registrationRef.current?.update().catch(() => {})
    }

    // ── حارس controllerchange: reload فقط إذا طلبه المستخدم ──
    const handleControllerChange = () => {
      if (isUpdatingRef.current) {
        window.location.reload()
      }
      // وإلا: تجاهل تماماً — لا reload في الخلفية أبداً
    }

    document.addEventListener('visibilitychange', handleVisibilityChange)
    window.addEventListener('online', handleOnline)
    navigator.serviceWorker.addEventListener('controllerchange', handleControllerChange)

    setup()

    return () => {
      clearInterval(pollInterval)
      document.removeEventListener('visibilitychange', handleVisibilityChange)
      window.removeEventListener('online', handleOnline)
      navigator.serviceWorker.removeEventListener('controllerchange', handleControllerChange)
    }
  }, [])

  return null
}
