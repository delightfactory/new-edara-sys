import { useState, useMemo, useCallback, useRef, useEffect } from 'react'
import { useCustomers } from '@/hooks/useQueryHooks'
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
  /** نتائج البحث */
  results: CustomerSearchResult[]
  /** حالة التحميل */
  isLoading: boolean
  /** هل يوجد المزيد للتحميل؟ */
  hasMore: boolean
  /** نص البحث الحالي */
  search: string
  /** تعيين نص البحث */
  setSearch: (s: string) => void
  /** تحميل المزيد */
  loadMore: () => void
  /** العدد الإجمالي */
  totalCount: number
  /** الصفحة الحالية */
  page: number
  /** إعادة تحميل */
  refresh: () => void
}

/**
 * useCustomerSearch — بحث Server-side ذكي عن العملاء
 *
 * المميزات:
 * - Debounced search (300ms) — لا يرسل طلب عند كل حرف
 * - Pagination — pageSize: 30 مع "تحميل المزيد"
 * - RLS تلقائي — المندوب يرى عملاءه فقط (من DB)
 * - Cache — React Query يُخزّن نتائج البحث
 * - تحويل النتائج إلى format موحّد مع المعلومات المالية والجغرافية
 */
export function useCustomerSearch(options?: {
  /** حجم الصفحة (افتراضي: 30) */
  pageSize?: number
  /** فلترة إضافية — المحافظة */
  governorateId?: string
  /** فلترة إضافية — النوع */
  type?: string
  /** تعطيل البحث مؤقتاً */
  enabled?: boolean
}): UseCustomerSearchReturn {
  const pageSize = options?.pageSize ?? 30
  const enabled = options?.enabled !== false

  const [search, setSearchRaw] = useState('')
  const [debouncedSearch, setDebouncedSearch] = useState('')
  const [page, setPage] = useState(1)
  const [allResults, setAllResults] = useState<CustomerSearchResult[]>([])
  const debounceRef = useRef<ReturnType<typeof setTimeout>>()

  // Debounce: 300ms
  const setSearch = useCallback((value: string) => {
    setSearchRaw(value)

    if (debounceRef.current) clearTimeout(debounceRef.current)
    debounceRef.current = setTimeout(() => {
      setDebouncedSearch(value)
      setPage(1)
      setAllResults([])
    }, 300)
  }, [])

  // Cleanup debounce
  useEffect(() => {
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current)
    }
  }, [])

  // Query params
  const queryParams = useMemo(() => ({
    search: debouncedSearch || undefined,
    page,
    pageSize,
    governorateId: options?.governorateId,
    type: options?.type,
    isActive: true,
  }), [debouncedSearch, page, pageSize, options?.governorateId, options?.type])

  const { data: customersResult, isLoading, refetch } = useCustomers(
    enabled ? queryParams : undefined
  )

  // تحويل إلى CustomerSearchResult وتراكم النتائج
  useEffect(() => {
    if (!customersResult?.data) return

    const mapped: CustomerSearchResult[] = customersResult.data.map((c: any) => ({
      id: c.id,
      name: c.name ?? '',
      code: c.code ?? '',
      phone: c.phone ?? null,
      mobile: c.mobile ?? null,
      type: c.type ?? null,
      governorate_name: c.governorate?.name ?? null,
      city_name: c.city?.name ?? null,
      current_balance: c.current_balance ?? 0,
      credit_limit: c.credit_limit ?? 0,
      latitude: c.latitude ?? null,
      longitude: c.longitude ?? null,
      address: c.address ?? null,
      is_active: c.is_active ?? true,
      assigned_rep_id: c.assigned_rep_id ?? null,
      _raw: c,
    }))

    // إذا page > 1 نضيف للنتائج السابقة (تحميل المزيد)
    if (page === 1) {
      setAllResults(mapped)
    } else {
      setAllResults(prev => {
        // إزالة التكرارات
        const existingIds = new Set(prev.map(r => r.id))
        const newItems = mapped.filter(m => !existingIds.has(m.id))
        return [...prev, ...newItems]
      })
    }
  }, [customersResult?.data, page])

  // حساب hasMore
  const totalCount = customersResult?.count ?? 0
  const hasMore = totalCount > page * pageSize

  const loadMore = useCallback(() => {
    if (hasMore && !isLoading) {
      setPage(p => p + 1)
    }
  }, [hasMore, isLoading])

  const refresh = useCallback(() => {
    setPage(1)
    setAllResults([])
    refetch()
  }, [refetch])

  return {
    results: allResults,
    isLoading,
    hasMore,
    search,
    setSearch,
    loadMore,
    totalCount,
    page,
    refresh,
  }
}

export default useCustomerSearch
