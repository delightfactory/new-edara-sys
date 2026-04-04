import { useEffect, useRef, useCallback, useState } from 'react'

/**
 * useIntersectionObserver — Callback Ref Pattern
 *
 * يستخدم Callback Ref لضمان أن الـ IntersectionObserver
 * يُهيَّأ بالضبط لحظة ارتباط العنصر بالـ DOM.
 */
export function useIntersectionObserver(options: {
  rootMargin?: string
  threshold?: number
  onIntersect: () => void
  enabled?: boolean
}) {
  const {
    rootMargin = '400px',
    threshold  = 0,
    onIntersect,
    enabled    = true,
  } = options

  const callbackRef = useRef(onIntersect)
  useEffect(() => { callbackRef.current = onIntersect }, [onIntersect])

  const observerRef = useRef<IntersectionObserver | null>(null)

  useEffect(() => {
    return () => {
      observerRef.current?.disconnect()
      observerRef.current = null
    }
  }, [])

  const sentinelRef = useCallback(
    (node: HTMLDivElement | null) => {
      if (observerRef.current) {
        observerRef.current.disconnect()
        observerRef.current = null
      }
      if (!enabled || !node) return

      observerRef.current = new IntersectionObserver(
        (entries) => {
          if (entries[0]?.isIntersecting) callbackRef.current()
        },
        { rootMargin, threshold }
      )
      observerRef.current.observe(node)
    },
    [enabled, rootMargin, threshold]
  )

  return sentinelRef
}

// ─────────────────────────────────────────────────────────────────────────────

interface InfiniteState<T> {
  /** المفتاح الخاص بمجموعة الفلاتر الحالية — يتغير عند تغيير البحث */
  key:   string
  items: T[]
}

/**
 * useMobileInfiniteList
 *
 * يُدير تراكم النتائج للـ Infinite Scroll على الموبايل.
 *
 * ─── كيف يعمل ───────────────────────────────────────────────────────────────
 * الـ state يحمل (key, items) معاً:
 *   - عند تغيير resetKey: state.key !== resetKey → نبدأ من جديد بالبيانات الجديدة
 *   - عند تحميل صفحة إضافية: state.key === resetKey → نُضيف بدون تكرار
 *
 * هذا النمط يحل مشكلة الـ Race Condition التي كانت تُظهر بيانات قديمة
 * عند تغيير البحث قبل وصول البيانات الجديدة.
 */
export function useMobileInfiniteList<T extends { id: string }>(params: {
  data:       T[]
  pageSize:   number
  loading:    boolean
  resetKey:   string
  hasMore:    boolean
  onLoadMore: () => void
}) {
  const { data, loading, resetKey, hasMore, onLoadMore } = params

  const [state, setState] = useState<InfiniteState<T>>({
    key:   resetKey,
    items: [],
  })

  useEffect(() => {
    // لا نُحدّث الـ state أثناء التحميل
    if (loading) return

    setState(prev => {
      // ── تغيّر الـ resetKey (بحث/فلتر جديد) ───────────────────────────
      if (prev.key !== resetKey) {
        // ابدأ من الصفر مع البيانات الجديدة فوراً (بدون flash للقديمة)
        return { key: resetKey, items: data.length > 0 ? [...data] : [] }
      }

      // ── نفس الفلاتر، صفحة جديدة ──────────────────────────────────────
      if (!data.length) return prev

      const existingIds = new Set(prev.items.map(item => item.id))
      const freshItems  = data.filter(item => !existingIds.has(item.id))

      return freshItems.length > 0
        ? { key: resetKey, items: [...prev.items, ...freshItems] }
        : prev
    })
  }, [data, loading, resetKey])

  // ── Sentinel ref للـ IntersectionObserver ────────────────────────────
  const loadCallback = useCallback(() => {
    if (!loading && hasMore) onLoadMore()
  }, [loading, hasMore, onLoadMore])

  const sentinelRef = useIntersectionObserver({
    onIntersect: loadCallback,
    enabled:     hasMore && !loading,
    rootMargin:  '400px',
  })

  return {
    accumulated: state.items,
    sentinelRef,
  }
}
