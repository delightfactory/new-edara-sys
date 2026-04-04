import { useState, useMemo, useCallback, useRef, useEffect } from 'react'
import { useQuery } from '@tanstack/react-query'
import { searchCustomers } from '@/lib/services/customers'
import type { Customer } from '@/lib/types/master-data'

export interface CustomerSearchResult {
  id: string
  name: string
  code: string
  phone: string | null
  mobile: string | null
  type: string | null
  governorate_name: string | null
  city_name: string | null
  current_balance: number
  credit_limit: number
  latitude: number | null
  longitude: number | null
  address: string | null
  is_active: boolean
  assigned_rep_id: string | null
  /** الكائن الأصلي الكامل */
  _raw: Customer
}

interface UseCustomerSearchReturn {
  /** نتائج البحث المتراكمة */
  results: CustomerSearchResult[]
  /** حالة التحميل */
  isLoading: boolean
  /** هل يوجد المزيد للتحميل؟ */
  hasMore: boolean
  /** نص البحث الحالي */
  search: string
  /** تعيين نص البحث */
  setSearch: (s: string) => void
  /** تحميل الصفحة التالية عبر Keyset cursor */
  loadMore: () => void
  /** إعادة تحميل من البداية */
  refresh: () => void
}

function mapToSearchResult(c: Customer): CustomerSearchResult {
  const raw = c as any
  return {
    id: raw.id,
    name: raw.name ?? '',
    code: raw.code ?? '',
    phone: raw.phone ?? null,
    mobile: raw.mobile ?? null,
    type: raw.type ?? null,
    governorate_name: raw.governorate?.name ?? null,
    city_name: raw.city?.name ?? null,
    current_balance: raw.current_balance ?? 0,
    credit_limit: raw.credit_limit ?? 0,
    latitude: raw.latitude ?? null,
    longitude: raw.longitude ?? null,
    address: raw.address ?? null,
    is_active: raw.is_active ?? true,
    assigned_rep_id: raw.assigned_rep_id ?? null,
    _raw: c,
  }
}

/**
 * useCustomerSearch — بحث Server-side بـ Keyset Pagination
 *
 * المميزات:
 * - Debounced search (300ms) — لا يرسل طلب عند كل حرف
 * - Keyset cursor — أداء O(log N) ثابت، لا OFFSET، لا COUNT(*)
 * - RLS تلقائي — المندوب يرى عملاءه فقط (من DB)
 * - React Query cache لكل صفحة منفصلة
 * - Infinite scroll بدون تكرارات
 */
export function useCustomerSearch(options?: {
  /** حجم الصفحة (افتراضي: 30) */
  pageSize?: number
  /** فلترة — المحافظة */
  governorateId?: string
  /** فلترة — النوع */
  type?: string
  /** تعطيل البحث مؤقتاً */
  enabled?: boolean
  /**
   * فلترة حسب الحالة — undefined = الكل، true = فعال فقط، false = موقوف فقط
   * الافتراضي: true (للاستخدام في نماذج إنشاء الطلبات)
   */
  isActive?: boolean
}): UseCustomerSearchReturn {
  const pageSize = options?.pageSize ?? 30
  const enabled  = options?.enabled !== false
  const isActive = options?.isActive !== undefined ? options.isActive : true

  // نص البحث (raw + debounced)
  const [search,          setSearchRaw]       = useState('')
  const [debouncedSearch, setDebouncedSearch]  = useState('')
  const debounceRef = useRef<ReturnType<typeof setTimeout>>()

  // Keyset cursor للصفحة الحالية
  const [cursorTs,  setCursorTs]  = useState<string | null>(null)
  const [cursorId,  setCursorId]  = useState<string | null>(null)

  // النتائج المتراكمة
  const [allResults, setAllResults] = useState<CustomerSearchResult[]>([])
  const [canLoadMore, setCanLoadMore] = useState(false)

  // ─── Debounce: 300ms ─────────────────────────────────────
  const setSearch = useCallback((value: string) => {
    setSearchRaw(value)
    if (debounceRef.current) clearTimeout(debounceRef.current)
    debounceRef.current = setTimeout(() => {
      setDebouncedSearch(value)
      // إعادة ضبط الـ cursor عند تغيير البحث
      setCursorTs(null)
      setCursorId(null)
      setAllResults([])
      setCanLoadMore(false)
    }, 300)
  }, [])

  useEffect(() => () => {
    if (debounceRef.current) clearTimeout(debounceRef.current)
  }, [])

  // ─── Query key فريد لكل مجموعة فلاتر + cursor ─────────────
  const queryKey = useMemo(() => [
    'customers-keyset',
    debouncedSearch,
    isActive,
    options?.type,
    options?.governorateId,
    pageSize,
    cursorTs,
    cursorId,
  ], [debouncedSearch, isActive, options?.type, options?.governorateId, pageSize, cursorTs, cursorId])

  const { data: currentPage, isLoading, refetch } = useQuery({
    queryKey,
    queryFn: () => searchCustomers({
      search:        debouncedSearch || undefined,
      isActive,
      type:          options?.type,
      governorateId: options?.governorateId,
      cursor:        cursorTs,
      cursorId:      cursorId,
      pageSize,
    }),
    enabled,
    staleTime: 30_000, // 30 ثانية
  })

  // ─── تراكم النتائج عند استلام صفحة جديدة ─────────────────
  useEffect(() => {
    if (!currentPage?.data) return

    const mapped = currentPage.data.map(mapToSearchResult)

    if (cursorTs === null && cursorId === null) {
      // الصفحة الأولى — استبدل كل النتائج
      setAllResults(mapped)
    } else {
      // صفحة لاحقة — أضف مع إزالة التكرارات
      setAllResults(prev => {
        const existingIds = new Set(prev.map(r => r.id))
        return [...prev, ...mapped.filter(m => !existingIds.has(m.id))]
      })
    }

    setCanLoadMore(currentPage.hasMore)
  }, [currentPage]) // eslint-disable-line react-hooks/exhaustive-deps

  // ─── تحميل المزيد: ادفع cursor الجديد ───────────────────
  const loadMore = useCallback(() => {
    if (!canLoadMore || isLoading || !currentPage?.nextCursor) return
    setCursorTs(currentPage.nextCursor)
    setCursorId(currentPage.nextCursorId)
  }, [canLoadMore, isLoading, currentPage])

  // ─── إعادة التحميل من الصفحة الأولى ─────────────────────
  const refresh = useCallback(() => {
    setCursorTs(null)
    setCursorId(null)
    setAllResults([])
    setCanLoadMore(false)
    refetch()
  }, [refetch])

  return {
    results: allResults,
    isLoading,
    hasMore: canLoadMore,
    search,
    setSearch,
    loadMore,
    refresh,
  }
}

export default useCustomerSearch
