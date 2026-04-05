import { useState, useEffect, useCallback, useRef } from 'react'

export interface GeoCoords {
  lat: number
  lng: number
  accuracy: number
}

export type GeoPermissionStatus = 'checking' | 'granted' | 'prompt' | 'denied' | 'unavailable'

/** نتيجة طلب الموقع — إما إحداثيات أو خطأ مفصّل */
export type GeoRequestResult =
  | { ok: true;  coords: GeoCoords }
  | { ok: false; reason: 'denied' | 'unavailable' | 'timeout' | 'unknown'; message: string }

/** خطوات إرشادية مرئية لإصلاح حالة الحظر — مُهيكلة للعرض بصرياً */
export interface BrowserGuideStep {
  step: number
  icon: string
  text: string
}

export interface UseGeoPermissionReturn {
  /** حالة الصلاحية الحالية */
  status: GeoPermissionStatus
  /** الإحداثيات المحدّدة (إذا نجح الطلب) */
  coords: GeoCoords | null
  /** رسالة الخطأ المختصرة */
  error: string | null
  /** طلب تحديد الموقع — يُرجع الإحداثيات أو نتيجة الفشل */
  requestLocation: () => Promise<GeoRequestResult>
  /** هل تم حظر الصلاحية نهائياً؟ */
  isBlocked: boolean
  /** إعادة فحص حالة الصلاحية (بعد تعديل المستخدم للإعدادات) */
  recheckPermission: () => void
  /** هل الطلب جارٍ؟ */
  isLoading: boolean
  /** نوع المتصفح المكتشف */
  browserType: 'chrome' | 'safari' | 'firefox' | 'samsung' | 'edge' | 'other'
  /** خطوات إرشادية مرئية لهذا المتصفح في حالة الحظر */
  browserGuideSteps: BrowserGuideStep[]
  /** رسالة خطأ الحظر المختصرة */
  blockedMessage: string
}

// ─── Browser Detection ──────────────────────────────────────────────────────

type BrowserType = 'chrome' | 'safari' | 'firefox' | 'samsung' | 'edge' | 'other'

function detectBrowser(): BrowserType {
  const ua = navigator.userAgent.toLowerCase()

  // Samsung Internet Browser
  if (ua.includes('samsungbrowser')) return 'samsung'
  // Edge
  if (ua.includes('edg/') || ua.includes('edge/')) return 'edge'
  // Firefox
  if (ua.includes('firefox') || ua.includes('fxios')) return 'firefox'
  // Chrome iOS (CriOS)
  if (ua.includes('crios')) return 'chrome'
  // Safari (must check after Chrome since Chrome UA includes "safari")
  if (ua.includes('safari') && !ua.includes('chrome') && !ua.includes('chromium')) return 'safari'
  // Chrome/Chromium (includes Android Chrome)
  if (ua.includes('chrome') || ua.includes('chromium')) return 'chrome'

  return 'other'
}

// ─── Guide Steps per Browser ─────────────────────────────────────────────────

function getBrowserGuideSteps(browser: BrowserType): BrowserGuideStep[] {
  switch (browser) {
    case 'chrome':
      return [
        { step: 1, icon: '🔒', text: 'اضغط على أيقونة القفل 🔒 بجانب شريط العنوان' },
        { step: 2, icon: '📍', text: 'اختر "الموقع الجغرافي" أو "Location"' },
        { step: 3, icon: '✅', text: 'غيّر الإعداد إلى "السماح / Allow"' },
        { step: 4, icon: '🔄', text: 'اضغط "تم التعديل — أعد المحاولة" أدناه' },
      ]
    case 'samsung':
      return [
        { step: 1, icon: '⋮',  text: 'اضغط على قائمة ⋮ في أعلى يمين المتصفح' },
        { step: 2, icon: '⚙️', text: 'اختر "الإعدادات / Settings"' },
        { step: 3, icon: '🌐', text: 'اضغط "إعدادات المواقع / Site settings"' },
        { step: 4, icon: '📍', text: 'اختر "الموقع / Location" ← السماح لهذا الموقع' },
        { step: 5, icon: '🔄', text: 'اضغط "تم التعديل — أعد المحاولة" أدناه' },
      ]
    case 'safari':
      return [
        { step: 1, icon: '⚙️', text: 'افتح "الإعدادات / Settings" في جهازك' },
        { step: 2, icon: '🌐', text: 'اختر "Safari" من القائمة' },
        { step: 3, icon: '📍', text: 'اضغط "الموقع / Location"' },
        { step: 4, icon: '✅', text: 'اختر "السماح أثناء استخدام التطبيق"' },
        { step: 5, icon: '🔄', text: 'ارجع للتطبيق واضغط "أعد المحاولة"' },
      ]
    case 'firefox':
      return [
        { step: 1, icon: '🔒', text: 'اضغط على أيقونة القفل 🔒 في شريط العنوان' },
        { step: 2, icon: '📋', text: 'اضغط "صلاحيات الاتصال / Connection Permissions"' },
        { step: 3, icon: '📍', text: 'ابحث عن "الموقع" وغيّر الإعداد إلى "السماح"' },
        { step: 4, icon: '🔄', text: 'اضغط "تم التعديل — أعد المحاولة" أدناه' },
      ]
    case 'edge':
      return [
        { step: 1, icon: '🔒', text: 'اضغط على أيقونة القفل 🔒 في شريط العنوان' },
        { step: 2, icon: '⚙️', text: 'اضغط "إعدادات الموقع / Site Permissions"' },
        { step: 3, icon: '📍', text: 'اختر "الموقع الجغرافي / Location"' },
        { step: 4, icon: '✅', text: 'غيّر الإعداد إلى "السماح / Allow"' },
        { step: 5, icon: '🔄', text: 'اضغط "تم التعديل — أعد المحاولة" أدناه' },
      ]
    default:
      return [
        { step: 1, icon: '🔒', text: 'ابحث عن أيقونة القفل أو الإعدادات بجانب شريط العنوان' },
        { step: 2, icon: '📍', text: 'ابحث عن إعداد "الموقع الجغرافي" أو "Location"' },
        { step: 3, icon: '✅', text: 'غيّر الإعداد إلى "السماح / Allow"' },
        { step: 4, icon: '🔄', text: 'أعد تحميل الصفحة وحاول مرة أخرى' },
      ]
  }
}

function getBlockedMessage(browser: BrowserType): string {
  switch (browser) {
    case 'samsung':  return 'تم حظر الوصول للموقع في متصفح Samsung — راجع الإرشادات أدناه'
    case 'safari':   return 'تم حظر الوصول للموقع في Safari — راجع إعدادات الجهاز'
    case 'firefox':  return 'تم حظر الوصول للموقع في Firefox — راجع صلاحيات الموقع'
    case 'edge':     return 'تم حظر الوصول للموقع في Edge — راجع إعدادات الموقع'
    case 'chrome':   return 'تم حظر الوصول للموقع في Chrome — راجع الإرشادات أدناه'
    default:         return 'تم حظر الوصول للموقع — راجع إعدادات المتصفح'
  }
}

// ─── Main Hook ───────────────────────────────────────────────────────────────

/**
 * useGeoPermission — إدارة صلاحيات الموقع بأفضل الممارسات الاحترافية
 *
 * يحل مشكلة: "تم رفض الوصول إلى الموقع" على Samsung Galaxy وغيرها
 * حيث المتصفح لا يُعيد السؤال بعد الرفض الأول.
 *
 * Pattern: Permissions API → getCurrentPosition → onchange listener
 *
 * maximumAge: 0 — دائماً نطلب موقعاً طازجاً (مهم لتسجيل الحضور)
 */
export function useGeoPermission(): UseGeoPermissionReturn {
  const [status,    setStatus]    = useState<GeoPermissionStatus>('checking')
  const [coords,    setCoords]    = useState<GeoCoords | null>(null)
  const [error,     setError]     = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(false)

  const permissionRef = useRef<PermissionStatus | null>(null)
  const browserType   = useRef<BrowserType>(detectBrowser())

  // ── فحص حالة الصلاحية عند التحميل ──────────────────────────────────────
  const checkPermission = useCallback(async () => {
    // 1. هل الجهاز يدعم تحديد الموقع؟
    if (!navigator.geolocation) {
      setStatus('unavailable')
      setError('جهازك أو متصفحك لا يدعم خدمات تحديد الموقع')
      return
    }

    // 2. هل المتصفح يدعم Permissions API?
    if (!navigator.permissions?.query) {
      // المتصفحات القديمة — نفترض prompt وننتظر طلب المستخدم
      setStatus('prompt')
      return
    }

    try {
      const result = await navigator.permissions.query({ name: 'geolocation' })
      permissionRef.current = result

      const mapState = (state: PermissionState): GeoPermissionStatus => {
        switch (state) {
          case 'granted': return 'granted'
          case 'denied':  return 'denied'
          default:        return 'prompt'
        }
      }

      setStatus(mapState(result.state))

      if (result.state === 'denied') {
        setError(getBlockedMessage(browserType.current))
      }

      // مراقبة تغيير الإعدادات يدوياً من المستخدم
      result.onchange = () => {
        const newStatus = mapState(result.state)
        setStatus(newStatus)
        if (result.state === 'denied') {
          setError(getBlockedMessage(browserType.current))
        } else {
          setError(null)
        }
        // إذا منح المستخدم الصلاحية يدوياً → نجلب الموقع تلقائياً
        if (result.state === 'granted') {
          setStatus('granted')
        }
      }
    } catch {
      // Safari لا يدعم query('geolocation') في بعض الإصدارات
      setStatus('prompt')
    }
  }, [])

  useEffect(() => {
    checkPermission()
    return () => {
      if (permissionRef.current) {
        permissionRef.current.onchange = null
      }
    }
  }, [checkPermission])

  // ── طلب الموقع الفعلي ────────────────────────────────────────────────────
  const requestLocation = useCallback(async (): Promise<GeoRequestResult> => {
    if (!navigator.geolocation) {
      setStatus('unavailable')
      setError('جهازك لا يدعم خدمات تحديد الموقع')
      return { ok: false, reason: 'unavailable', message: 'جهازك لا يدعم خدمات تحديد الموقع' }
    }

    setIsLoading(true)
    setError(null)

    return new Promise<GeoRequestResult>((resolve) => {

      // Strategy: نحاول أولاً بدقة عالية، ثم بدقة عادية عند الفشل
      const tryGetPosition = (highAccuracy: boolean) => {
        navigator.geolocation.getCurrentPosition(
          (position) => {
            const result: GeoCoords = {
              lat:      position.coords.latitude,
              lng:      position.coords.longitude,
              accuracy: position.coords.accuracy,
            }
            setCoords(result)
            setStatus('granted')
            setError(null)
            setIsLoading(false)
            resolve({ ok: true, coords: result })
          },
          (err) => {
            if (err.code === err.PERMISSION_DENIED) {
              const msg = getBlockedMessage(browserType.current)
              // رُفضت الصلاحية — لا نعيد المحاولة
              setStatus('denied')
              setError(msg)
              setIsLoading(false)
              resolve({ ok: false, reason: 'denied', message: msg })

            } else if (err.code === err.TIMEOUT && highAccuracy) {
              // انتهت المهلة بدقة عالية → نحاول بدقة عادية (أسرع داخل المباني)
              tryGetPosition(false)

            } else if (err.code === err.POSITION_UNAVAILABLE) {
              const msg = 'تعذّر تحديد الموقع — تأكد من تفعيل GPS في الجهاز ووجودك في مكان مفتوح'
              setError(msg)
              setIsLoading(false)
              resolve({ ok: false, reason: 'unavailable', message: msg })

            } else {
              const msg = err.code === err.TIMEOUT
                ? 'انتهت مهلة تحديد الموقع — تأكد من تفعيل GPS وحاول مرة أخرى'
                : 'حدث خطأ أثناء تحديد الموقع — حاول مرة أخرى'
              setError(msg)
              setIsLoading(false)
              resolve({ ok: false, reason: 'timeout', message: msg })
            }
          },
          {
            enableHighAccuracy: highAccuracy,
            timeout:            highAccuracy ? 15_000 : 10_000,
            maximumAge:         0,   // دائماً موقع طازج (لا cached positions)
          }
        )
      }

      tryGetPosition(true)
    })
  }, [])

  return {
    status,
    coords,
    error,
    requestLocation,
    isBlocked:        status === 'denied',
    recheckPermission: checkPermission,
    isLoading,
    browserType:      browserType.current,
    browserGuideSteps: getBrowserGuideSteps(browserType.current),
    blockedMessage:   getBlockedMessage(browserType.current),
  }
}

export default useGeoPermission
