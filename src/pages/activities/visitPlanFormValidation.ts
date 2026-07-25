export const isUuid = (val: unknown): val is string =>
  typeof val === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(val)

export interface ValidationItem {
  customerId: string
  customerName: string
  customerBranchId: string | null | undefined
  sequence: number
  estimatedDuration: number
  plannedTime: string
  purposeType: string
}

export interface ValidationResult {
  isValid: boolean
  error?: string
}

export function validateVisitPlanItems(items: ValidationItem[]): ValidationResult {
  if (items.length === 0) {
    return { isValid: false, error: 'يجب إضافة عميل واحد على الأقل' }
  }
  if (items.length > 100) {
    return { isValid: false, error: 'لا يمكن إضافة أكثر من 100 عميل في الخطة' }
  }

  // Duplicate customer_id check
  const custIds = items.map(c => c.customerId)
  if (new Set(custIds).size !== custIds.length) {
    return { isValid: false, error: 'يوجد تكرار في العملاء المحددين' }
  }

  // Sequence check (1 to N consecutive and unique)
  const sortedSeqs = [...items].map(c => c.sequence).sort((a, b) => a - b)
  const isConsecutive = sortedSeqs.every((seq, idx) => seq === idx + 1)
  if (!isConsecutive) {
    return { isValid: false, error: 'ترتيب البنود غير متتابع أو غير صالح' }
  }

  // Item validations
  for (const cust of items) {
    if (!isUuid(cust.customerId)) {
      return { isValid: false, error: `معرف العميل ${cust.customerName} غير صالح. يجب أن يكون UUID.` }
    }
    if (cust.customerBranchId !== null && cust.customerBranchId !== undefined && !isUuid(cust.customerBranchId)) {
      return { isValid: false, error: `معرف فرع العميل ${cust.customerName} غير صالح. يجب أن يكون UUID.` }
    }
    if (typeof cust.estimatedDuration !== 'number' || cust.estimatedDuration < 5 || cust.estimatedDuration > 480 || !Number.isInteger(cust.estimatedDuration)) {
      return { isValid: false, error: `المدة الزمنية للعميل ${cust.customerName} غير صالحة (يجب أن تكون بين 5 و 480 دقيقة)` }
    }
    if (cust.plannedTime) {
      const timeRegex = /^(?:[01]\d|2[0-3]):[0-5]\d$/
      if (!timeRegex.test(cust.plannedTime)) {
        return { isValid: false, error: `الوقت المخطط للعميل ${cust.customerName} غير صالح (يجب أن يكون بصيغة HH:MM)` }
      }
    }
    if (cust.purposeType && !['sales', 'collection', 'activation', 'promotion', 'followup', 'service'].includes(cust.purposeType)) {
      return { isValid: false, error: `غرض الزيارة للعميل ${cust.customerName} غير صالح` }
    }
  }

  return { isValid: true }
}
