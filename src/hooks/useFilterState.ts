import { useCallback, useMemo } from 'react'
import { useSearchParams } from 'react-router-dom'

/**
 * useFilterState — Hook موحد لإدارة حالة الفلاتر مع URL Sync اختياري
 *
 * ─── وضعان من التخزين ────────────────────────────────────────────────
 *
 * 1. URL Sync (urlSync: true) — الافتراضي للصفحات الرئيسية:
 *    ✅ الفلاتر تُحفظ في URL كـ query params (?status=confirmed&rep=...)
 *    ✅ الضغط على "عودة" من صفحة التفاصيل → تستعيد الفلاتر تلقائياً (browser history)
 *    ✅ مشاركة الرابط مع فلاتر محددة
 *    ✅ replace:true → لا يُضيف إدخالاً في browser history بكل تغيير
 *    ✅ عند مغادرة الصفحة بالكامل والعودة → يُقرأ URL الحالي (قد يكون نظيفاً)
 *
 * 2. State محلي (urlSync: false):
 *    ✅ للأدوات الداخلية (modals, nested components)
 *    ✅ لا يُلوّث URL
 *
 * ─── أداء ────────────────────────────────────────────────────────────
 * - URL reads: synchronous، لا network calls
 * - setSearchParams + replace:true: O(1)، لا إعادة رسم غير ضرورية
 * - useMemo على filterKey و activeCount
 * - setFilter مُستقر بـ useCallback
 *
 * ─── سلوك ذكي ────────────────────────────────────────────────────────
 * - الفلاتر افتراضية لا تُضاف للـ URL (يبقى نظيفاً)
 * - الفلاتر الفارغة '' تُحذف من URL تلقائياً
 * - reset → يُزيل كل params من URL دفعة واحدة
 *
 * ─── استخدام ─────────────────────────────────────────────────────────
 * ```tsx
 * // صفحة رئيسية — URL Sync
 * const { filters, setFilter, reset, activeCount, filterKey } = useFilterState({
 *   defaults: { search: '', status: '', repId: '' },
 *   urlSync: true,
 * })
 *
 * // مكون داخلي — State محلي
 * const { filters, setFilter, reset } = useFilterState({
 *   defaults: { q: '', type: '' },
 *   urlSync: false,
 * })
 * ```
 */

type Primitive = string | boolean | number

interface UseFilterStateOptions<T extends Record<string, Primitive>> {
  defaults: T
  /** حقيقي = تخزين في URL params (الافتراضي للصفحات الرئيسية) */
  urlSync?: boolean
  /** الحقول التي تُحسب في activeCount (افتراضياً: كلها) */
  countFields?: (keyof T)[]
}

interface UseFilterStateReturn<T extends Record<string, Primitive>> {
  filters:     T
  /** تحديث حقل واحد */
  setFilter:   <K extends keyof T>(key: K, value: T[K]) => void
  /** تحديث حقول متعددة في setSearchParams واحد — يمنع مشكلة React 18 batching */
  setFilters:  (updates: Partial<T>) => void
  reset:       () => void
  activeCount: number
  filterKey:   string
}

// ─────────────────────────────────────────────────────────────────────────────
// Implementation
// ─────────────────────────────────────────────────────────────────────────────

export function useFilterState<T extends Record<string, Primitive>>(
  options: UseFilterStateOptions<T>,
): UseFilterStateReturn<T> {
  const { defaults, urlSync = true, countFields } = options

  // ── URL-based storage ─────────────────────────────────────────────────────
  const [searchParams, setSearchParams] = useSearchParams()

  // قراءة الفلاتر من URL
  const filters = useMemo<T>(() => {
    if (!urlSync) return defaults
    const result = { ...defaults }
    for (const key of Object.keys(defaults) as (keyof T)[]) {
      const raw = searchParams.get(key as string)
      if (raw === null) continue
      const def = defaults[key]
      if (typeof def === 'boolean') {
        result[key] = (raw === 'true') as T[keyof T]
      } else if (typeof def === 'number') {
        const n = Number(raw)
        result[key] = (isNaN(n) ? def : n) as T[keyof T]
      } else {
        result[key] = raw as T[keyof T]
      }
    }
    return result
  }, [searchParams, defaults, urlSync])

  // ── helper: تطبيق مجموعة تحديثات على URLSearchParams ─────────────────────
  const applyUpdates = useCallback(
    (next: URLSearchParams, updates: Partial<T>) => {
      for (const [k, v] of Object.entries(updates)) {
        const strVal = String(v)
        const strDef = String(defaults[k as keyof T])
        if (strVal === '' || strVal === strDef) {
          next.delete(k)
        } else {
          next.set(k, strVal)
        }
      }
    },
    [defaults],
  )

  // تحديث حقل واحد
  const setFilter = useCallback(<K extends keyof T>(key: K, value: T[K]) => {
    if (!urlSync) return
    setSearchParams(
      prev => {
        const next = new URLSearchParams(prev)
        applyUpdates(next, { [key]: value } as unknown as Partial<T>)
        return next
      },
      { replace: true },
    )
  }, [setSearchParams, applyUpdates, urlSync])

  // ── تحديث متعدد دفعة واحدة (الحل الجوهري لـ React 18 batching) ───────────
  //
  // لماذا؟ عند استدعاء setFilter مرتين متتاليتين:
  //   setFilter('governorateId', govId)  → setSearchParams call 1
  //   setFilter('cityId', '')            → setSearchParams call 2
  //
  // React 18 يُجمّعهما في batch، وكلاهما يقرأ نفس الـ prev القديم.
  // النتيجة: call 2 يمحو ما أضافه call 1 → URL يبقى فارغاً.
  //
  // setFilters يدمجهما في setSearchParams واحد → مشكلة لا تنشأ.
  const setFilters = useCallback((updates: Partial<T>) => {
    if (!urlSync) return
    setSearchParams(
      prev => {
        const next = new URLSearchParams(prev)
        applyUpdates(next, updates)
        return next
      },
      { replace: true },
    )
  }, [setSearchParams, applyUpdates, urlSync])

  // إعادة تعيين كل الفلاتر
  const reset = useCallback(() => {
    if (!urlSync) return
    setSearchParams(
      prev => {
        const next = new URLSearchParams(prev)
        for (const key of Object.keys(defaults)) {
          next.delete(key)
        }
        return next
      },
      { replace: true },
    )
  }, [setSearchParams, defaults, urlSync])

  // عدد الفلاتر النشطة
  const activeCount = useMemo(() => {
    const fields = countFields ?? (Object.keys(defaults) as (keyof T)[])
    return fields.reduce((count, key) => {
      const val = filters[key]
      const def = defaults[key]
      if (typeof val === 'boolean') return count + (val !== def ? 1 : 0)
      if (typeof val === 'string')  return count + (val !== '' && val !== def ? 1 : 0)
      if (typeof val === 'number')  return count + (val !== def ? 1 : 0)
      return count
    }, 0)
  }, [filters, defaults, countFields])

  // مفتاح فريد للـ Infinite Scroll reset
  const filterKey = useMemo(() => JSON.stringify(filters), [filters])

  return { filters, setFilter, setFilters, reset, activeCount, filterKey }
}
