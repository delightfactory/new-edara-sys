/**
 * useGeoOnboarding — طلب إذن الموقع الاحترافي عند فتح التطبيق
 *
 * Best Practice: "Explain before Ask" — نشرح السبب أولاً ثم نطلب الإذن
 *
 * السلوك:
 * - يُطلق الـ dialog مرة واحدة فقط عند أول دخول للتطبيق بعد تسجيل الدخول
 * - إذا كانت الصلاحية ممنوحة مسبقاً → لا dialog
 * - إذا كانت الصلاحية محظورة → لا dialog (البانر في الصفحات المعنية يتولى الإرشاد)
 * - يُخزّن حالة "تم العرض" في localStorage لعدم الإزعاج مجدداً في نفس الجلسة
 * - تأخير 2.5s بعد mount لمنح المستخدم وقت للاستقرار قبل الطلب
 */
import { useState, useEffect, useCallback, useRef } from 'react'

const ONBOARDING_KEY = 'edara_geo_onboarding_shown_v1'

export interface UseGeoOnboardingReturn {
  /** هل Dialog يجب أن يُعرض الآن */
  showDialog: boolean
  /** عند موافقة المستخدم → يطلب الإذن الفعلي */
  handleAllow: () => void
  /** عند رفض المستخدم → يُغلق ولا يُعرض لاحقاً */
  handleDismiss: () => void
}

/** هل تم تخزين "تم العرض" مسبقاً */
function wasAlreadyShown(): boolean {
  try {
    return localStorage.getItem(ONBOARDING_KEY) === '1'
  } catch {
    return false
  }
}

function markAsShown(): void {
  try {
    localStorage.setItem(ONBOARDING_KEY, '1')
  } catch {
    // silent — localStorage might be blocked
  }
}

export function useGeoOnboarding(): UseGeoOnboardingReturn {
  const [showDialog, setShowDialog] = useState(false)
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    // لا نعيد العرض لو تم من قبل
    if (wasAlreadyShown()) return

    // لا نعرض إذا الجهاز لا يدعم Geolocation
    if (!navigator.geolocation) return

    // نفحص الوضع الحالي أولاً بدون طلب فعلي
    const checkAndShow = async () => {
      try {
        if (navigator.permissions?.query) {
          const result = await navigator.permissions.query({ name: 'geolocation' })

          // ✅ ممنوح مسبقاً → لا حاجة للـ dialog، فقط نسجّل ذلك
          if (result.state === 'granted') {
            markAsShown()
            return
          }

          // 🚫 محظور → المستخدم رفض من قبل → لا نزعجه بالـ dialog
          // (البانر في كل صفحة سيُرشده عند الحاجة)
          if (result.state === 'denied') {
            markAsShown()
            return
          }

          // ❓ prompt → فرصة مثالية للشرح الاحترافي
          // نؤخر 2.5 ثانية لمنح المستخدم وقت للاستقرار
          timerRef.current = setTimeout(() => {
            setShowDialog(true)
          }, 2500)
        } else {
          // Safari القديم لا يدعم permissions.query
          // نكتشف الحالة بطلب صامت جداً (timeout: 200ms) — إذا كان مسموحاً سيُجيب فوراً
          navigator.geolocation.getCurrentPosition(
            () => {
              // ✅ الإذن ممنوح — نسجّل ذلك ولا نزعج المستخدم
              markAsShown()
            },
            (err) => {
              if (err.code === err.PERMISSION_DENIED) {
                // 🚫 محظور — نسجّل ولا نعرض dialog
                markAsShown()
              } else {
                // ❓ TIMEOUT أو POSITION_UNAVAILABLE = لم يُجب بعد → prompt state
                // نعرض dialog بعد تأخير قصير
                timerRef.current = setTimeout(() => {
                  setShowDialog(true)
                }, 2500)
              }
            },
            { enableHighAccuracy: false, timeout: 200, maximumAge: Infinity }
          )
        }
      } catch {
        // في حالة الخطأ → نؤخر وعرضه بشكل احتياطي
        timerRef.current = setTimeout(() => {
          setShowDialog(true)
        }, 2500)
      }
    }

    void checkAndShow()

    return () => {
      if (timerRef.current) {
        clearTimeout(timerRef.current)
        timerRef.current = null
      }
    }
  }, [])

  /**
   * عند الموافقة: نُغلق الـ dialog ونطلب الإذن الفعلي من المتصفح
   * المتصفح سيعرض نافذته الرسمية الآن — لكن بعد أن شرحنا السبب
   */
  const handleAllow = useCallback(() => {
    setShowDialog(false)
    markAsShown()

    // طلب الإذن الفعلي من المتصفح بعد إغلاق الـ modal
    if (!navigator.geolocation) return

    // نطلب موقعاً واحداً فقط لاستدراج نافذة الإذن
    // لسنا بحاجة للنتيجة هنا — الهدف فقط طلب الإذن
    navigator.geolocation.getCurrentPosition(
      () => { /* تم منح الإذن — سيعمل كل شيء تلقائياً */ },
      () => { /* رُفض الإذن — البانر في الصفحات سيرشد المستخدم */ },
      { enableHighAccuracy: false, timeout: 10_000, maximumAge: 60_000 },
    )
  }, [])

  /**
   * عند الرفض: نُغلق ونسجّل ذلك — لن نُزعجه مجدداً
   */
  const handleDismiss = useCallback(() => {
    setShowDialog(false)
    markAsShown()
  }, [])

  return { showDialog, handleAllow, handleDismiss }
}

export default useGeoOnboarding
