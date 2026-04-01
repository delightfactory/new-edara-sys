import { useState, useEffect, useCallback, useRef } from 'react'

export interface GeoCoords {
  lat: number
  lng: number
  accuracy: number
}

export type GeoPermissionStatus = 'checking' | 'granted' | 'prompt' | 'denied' | 'unavailable'

export interface UseGeoPermissionReturn {
  /** حالة الصلاحية الحالية */
  status: GeoPermissionStatus
  /** الإحداثيات المحدّدة (إذا نجح الطلب) */
  coords: GeoCoords | null
  /** رسالة الخطأ (بالعربية) */
  error: string | null
  /** طلب تحديد الموقع — يُرجع الإحداثيات أو null */
  requestLocation: () => Promise<GeoCoords | null>
  /** هل تم حظر الصلاحية نهائياً؟ */
  isBlocked: boolean
  /** إعادة فحص حالة الصلاحية (بعد تعديل المستخدم للإعدادات) */
  recheckPermission: () => void
  /** هل الطلب جاري? */
  isLoading: boolean
  /** نوع المتصفح المكتشف */
  browserType: 'chrome' | 'safari' | 'firefox' | 'samsung' | 'other'
}

/**
 * Detection: نوع المتصفح لعرض التعليمات الصحيحة
 */
function detectBrowser(): 'chrome' | 'safari' | 'firefox' | 'samsung' | 'other' {
  const ua = navigator.userAgent.toLowerCase()
  if (ua.includes('samsungbrowser')) return 'samsung'
  if (ua.includes('firefox')) return 'firefox'
  if (ua.includes('safari') && !ua.includes('chrome')) return 'safari'
  if (ua.includes('chrome') || ua.includes('chromium') || ua.includes('crios')) return 'chrome'
  return 'other'
}

/**
 * useGeoPermission — إدارة صلاحيات الموقع بشكل احترافي
 *
 * يحل مشكلة: "تم رفض الوصول إلى الموقع" على Samsung Galaxy والأجهزة الحديثة
 * حيث المتصفح لا يُعيد السؤال بعد الرفض الأول.
 *
 * يستخدم:
 * 1. navigator.permissions.query() — لفحص الحالة قبل الطلب
 * 2. navigator.geolocation.getCurrentPosition() — لطلب الموقع فعلياً
 * 3. permissionStatus.onchange — لمراقبة تغيير الإعدادات
 */
export function useGeoPermission(): UseGeoPermissionReturn {
  const [status, setStatus] = useState<GeoPermissionStatus>('checking')
  const [coords, setCoords] = useState<GeoCoords | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(false)
  const permissionRef = useRef<PermissionStatus | null>(null)
  const browserType = useRef(detectBrowser())

  // ── فحص حالة الصلاحية عند التحميل ──
  const checkPermission = useCallback(async () => {
    // 1. هل الجهاز يدعم تحديد الموقع؟
    if (!navigator.geolocation) {
      setStatus('unavailable')
      setError('جهازك لا يدعم خدمات تحديد الموقع')
      return
    }

    // 2. هل المتصفح يدعم Permissions API؟
    if (!navigator.permissions?.query) {
      // المتصفحات القديمة — نفترض prompt
      setStatus('prompt')
      return
    }

    try {
      const result = await navigator.permissions.query({ name: 'geolocation' })
      permissionRef.current = result

      // تحديث الحالة
      const mapState = (state: PermissionState): GeoPermissionStatus => {
        switch (state) {
          case 'granted': return 'granted'
          case 'denied': return 'denied'
          case 'prompt':
          default: return 'prompt'
        }
      }

      setStatus(mapState(result.state))

      if (result.state === 'denied') {
        setError(getBlockedMessage(browserType.current))
      }

      // مراقبة التغيير — المستخدم قد يعدّل الإعدادات يدوياً
      result.onchange = () => {
        const newStatus = mapState(result.state)
        setStatus(newStatus)
        if (result.state === 'denied') {
          setError(getBlockedMessage(browserType.current))
        } else {
          setError(null)
        }
      }
    } catch {
      // Safari لا يدعم query('geolocation') دائماً
      setStatus('prompt')
    }
  }, [])

  useEffect(() => {
    checkPermission()
    return () => {
      // cleanup listener
      if (permissionRef.current) {
        permissionRef.current.onchange = null
      }
    }
  }, [checkPermission])

  // ── طلب الموقع الفعلي ──
  const requestLocation = useCallback(async (): Promise<GeoCoords | null> => {
    if (!navigator.geolocation) {
      setStatus('unavailable')
      setError('جهازك لا يدعم خدمات تحديد الموقع')
      return null
    }

    setIsLoading(true)
    setError(null)

    return new Promise<GeoCoords | null>((resolve) => {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          const result: GeoCoords = {
            lat: position.coords.latitude,
            lng: position.coords.longitude,
            accuracy: position.coords.accuracy,
          }
          setCoords(result)
          setStatus('granted')
          setError(null)
          setIsLoading(false)
          resolve(result)
        },
        (err) => {
          setIsLoading(false)
          setCoords(null)

          if (err.code === err.PERMISSION_DENIED) {
            setStatus('denied')
            setError(getBlockedMessage(browserType.current))
          } else if (err.code === err.POSITION_UNAVAILABLE) {
            setError('تعذّر تحديد الموقع — تأكد من تفعيل GPS في الجهاز')
          } else if (err.code === err.TIMEOUT) {
            setError('انتهت مهلة تحديد الموقع — حاول مرة أخرى في مكان مفتوح')
          } else {
            setError('حدث خطأ أثناء تحديد الموقع — حاول مرة أخرى')
          }

          resolve(null)
        },
        {
          enableHighAccuracy: true,
          timeout: 15000,
          maximumAge: 30000,
        }
      )
    })
  }, [])

  return {
    status,
    coords,
    error,
    requestLocation,
    isBlocked: status === 'denied',
    recheckPermission: checkPermission,
    isLoading,
    browserType: browserType.current,
  }
}

/**
 * رسائل مخصصة حسب نوع المتصفح — تساعد المستخدم على تعديل الإعدادات
 */
function getBlockedMessage(browser: string): string {
  switch (browser) {
    case 'chrome':
      return 'تم حظر الوصول إلى الموقع. لتفعيله: اضغط على 🔒 بجانب شريط العنوان ← الموقع الجغرافي ← السماح'
    case 'samsung':
      return 'تم حظر الوصول إلى الموقع. لتفعيله: اضغط ⋮ ← الإعدادات ← الموقع ← السماح لهذا الموقع'
    case 'safari':
      return 'تم حظر الوصول إلى الموقع. لتفعيله: الإعدادات ← Safari ← الموقع ← السماح'
    case 'firefox':
      return 'تم حظر الوصول إلى الموقع. لتفعيله: اضغط على 🔒 ← صلاحيات ← الموقع ← السماح'
    default:
      return 'تم حظر الوصول إلى الموقع. يُرجى السماح من إعدادات المتصفح ثم إعادة المحاولة'
  }
}

export default useGeoPermission
