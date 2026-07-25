/**
 * useCustomerBranches — Hook ضيق لقراءة فروع عميل محدد.
 *
 * - لا يُجلب حتى يصبح enabled=true (تحميل كسول عند فتح البطاقة).
 * - يعيد branches (جميع الفروع) فقط.
 * - لا يعدّل customers.ts ولا يُجلب فروع جميع العملاء دفعة واحدة.
 * - لا يُستخدم لاتخاذ قرارات صلاحيات — RLS والخادم هما المرجع.
 */
import { useQuery } from '@tanstack/react-query'
import { getCustomerBranches } from '@/lib/services/customers'
import type { CustomerBranch } from '@/lib/types/master-data'

interface UseCustomerBranchesOptions {
  customerId: string
  enabled?: boolean
}

interface UseCustomerBranchesResult {
  /** جميع الفروع كما يعيدها الخادم */
  branches: CustomerBranch[]
  isLoading: boolean
  isError: boolean
}

export function useCustomerBranches({
  customerId,
  enabled = true,
}: UseCustomerBranchesOptions): UseCustomerBranchesResult {
  const { data = [], isLoading, isError } = useQuery({
    queryKey: ['customer-branches', customerId],
    queryFn: () => getCustomerBranches(customerId),
    enabled: enabled && !!customerId,
    staleTime: 5 * 60 * 1000, // 5 دقائق — بيانات مرجعية نادرة التغيير
    gcTime: 10 * 60 * 1000,
  })

  return { branches: data, isLoading, isError }
}
