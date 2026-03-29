/**
 * FIX-07: HR Validations — قواعد التحقق لموديول الموارد البشرية
 * مُجمَّعة في ملف واحد بدلاً من التفريق في المكوّنات
 */

import type {
  HREmployeeInput,
  HRLeaveRequestInput,
  HRAdvanceInput,
  HRAttendanceDayInput,
} from '@/lib/types/hr'

// ─── Types ──────────────────────────────────────────────────
interface ValidationResult {
  valid: boolean
  errors: Record<string, string>
}

function ok(): ValidationResult {
  return { valid: true, errors: {} }
}

function fail(errors: Record<string, string>): ValidationResult {
  return { valid: false, errors }
}

// ─── Employee ───────────────────────────────────────────────
export function validateEmployee(input: Partial<HREmployeeInput>): ValidationResult {
  const errors: Record<string, string> = {}

  if (!input.full_name?.trim()) {
    errors.full_name = 'اسم الموظف مطلوب'
  } else if (input.full_name.trim().length < 5) {
    errors.full_name = 'اسم الموظف قصير جداً (5 أحرف على الأقل)'
  }

  if (!input.hire_date) {
    errors.hire_date = 'تاريخ التعيين مطلوب'
  }

  if (input.base_salary != null && input.base_salary < 0) {
    errors.base_salary = 'الراتب الأساسي لا يمكن أن يكون سالباً'
  }

  if (input.transport_allowance != null && input.transport_allowance < 0) {
    errors.transport_allowance = 'بدل المواصلات لا يمكن أن يكون سالباً'
  }

  if (input.housing_allowance != null && input.housing_allowance < 0) {
    errors.housing_allowance = 'بدل السكن لا يمكن أن يكون سالباً'
  }

  if (input.personal_phone && !/^\+?\d{8,15}$/.test(input.personal_phone.replace(/\s/g, ''))) {
    errors.personal_phone = 'رقم الهاتف غير صالح'
  }

  return Object.keys(errors).length ? fail(errors) : ok()
}

// ─── Leave Request ──────────────────────────────────────────
export function validateLeaveRequest(
  input: Partial<HRLeaveRequestInput>,
  availableBalance?: number
): ValidationResult {
  const errors: Record<string, string> = {}

  if (!input.leave_type_id) {
    errors.leave_type_id = 'نوع الإجازة مطلوب'
  }

  if (!input.start_date) {
    errors.start_date = 'تاريخ البداية مطلوب'
  }

  if (!input.end_date) {
    errors.end_date = 'تاريخ النهاية مطلوب'
  }

  if (input.start_date && input.end_date && input.start_date > input.end_date) {
    errors.end_date = 'تاريخ النهاية يجب أن يكون بعد تاريخ البداية'
  }

  // التحقق من الرصيد إذا مُتاح
  if (availableBalance != null && input.days_count != null) {
    if (input.days_count > availableBalance) {
      errors.days_count = `عدد الأيام (${input.days_count}) يتجاوز الرصيد المتاح (${availableBalance})`
    }
  }

  return Object.keys(errors).length ? fail(errors) : ok()
}

// ─── Advance ────────────────────────────────────────────────
export function validateAdvance(
  input: Partial<HRAdvanceInput>,
  grossSalary?: number
): ValidationResult {
  const errors: Record<string, string> = {}

  if (!input.amount || input.amount <= 0) {
    errors.amount = 'مبلغ السلفة مطلوب ويجب أن يكون أكبر من صفر'
  }

  // السلفة لا تتجاوز 30% من الراتب الإجمالي (حماية أولية — الحد الفعلي في الإعدادات)
  if (grossSalary != null && input.amount != null) {
    const maxAllowed = grossSalary * 0.3
    if (input.amount > maxAllowed) {
      errors.amount = `مبلغ السلفة يتجاوز 30% من الراتب الإجمالي (${Math.round(maxAllowed)} ج.م)`
    }
  }

  if (!input.reason?.trim()) {
    errors.reason = 'سبب طلب السلفة مطلوب'
  }

  return Object.keys(errors).length ? fail(errors) : ok()
}

// ─── Attendance Day (manual edit) ───────────────────────────
export function validateAttendanceEdit(
  input: Partial<HRAttendanceDayInput>
): ValidationResult {
  const errors: Record<string, string> = {}

  if (input.effective_hours != null) {
    if (input.effective_hours < 0) {
      errors.effective_hours = 'ساعات العمل لا يمكن أن تكون سالبة'
    }
    if (input.effective_hours > 24) {
      errors.effective_hours = 'ساعات العمل لا يمكن أن تتجاوز 24 ساعة'
    }
  }

  if (input.punch_in_time && input.punch_out_time) {
    const inTime  = new Date(input.punch_in_time).getTime()
    const outTime = new Date(input.punch_out_time).getTime()
    if (outTime <= inTime) {
      errors.punch_out_time = 'وقت الانصراف يجب أن يكون بعد وقت الحضور'
    }
  }

  return Object.keys(errors).length ? fail(errors) : ok()
}
