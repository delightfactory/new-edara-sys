/**
 * visitPlanFormTypes.ts
 * الأنواع المحلية المشتركة بين VisitPlanForm ومكوناته الفرعية.
 * لا تحتوي على أنواع عامة تخص النظام — تلك تبقى في lib/types.
 */
import type { PlanItemPurposeType, PlanPriority } from '@/lib/types/activities'

export type { PlanItemPurposeType, PlanPriority }

/** حالة بند الزيارة المحدد داخل معالج الإنشاء */
export interface SelectedCustomer {
  customerId: string
  customerName: string
  customerCode: string
  phone: string | null
  /** إحداثيات الموقع الرئيسي للعميل — للعرض فقط، لا تُرسل للـRPC */
  latitude: number | null
  longitude: number | null
  governorate: string | null
  city: string | null
  currentBalance: number
  creditLimit: number
  sequence: number
  plannedTime: string
  estimatedDuration: number
  priority: PlanPriority
  purposeType: PlanItemPurposeType | ''
  purpose: string
  /** معرف الفرع المختار — القيمة الوحيدة التي تدخل الحمولة */
  customerBranchId: string | null
  /** اسم الفرع للعرض فقط — ممنوع إرساله للـRPC */
  customerBranchName: string | null
  /** هل تم التحقق من الفرع وحله محلياً؟ */
  customerBranchResolved: boolean
  /** هل للفرع المختار (أو الرئيسي) إحداثيات موقع صالحة؟ */
  customerBranchHasCoordinates: boolean | null
}

/** خيارات الأولوية مع التسميات */
export const PRIORITY_OPTIONS: { value: PlanPriority; label: string }[] = [
  { value: 'high', label: 'عالية' },
  { value: 'normal', label: 'عادية' },
  { value: 'low', label: 'منخفضة' },
]

/** خيارات الغرض مع التسميات */
export const PURPOSE_OPTIONS: { value: PlanItemPurposeType; label: string }[] = [
  { value: 'sales', label: 'مبيعات' },
  { value: 'collection', label: 'تحصيل' },
  { value: 'activation', label: 'تنشيط' },
  { value: 'promotion', label: 'ترويج' },
  { value: 'followup', label: 'متابعة' },
  { value: 'service', label: 'خدمة' },
]
