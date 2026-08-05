import type { HRDayOfWeek } from '@/lib/types/hr'
import {
  HR_WORK_WEEK_DAYS,
  type HREmployeeWorkScheduleDayInput,
  type HREmployeeWorkScheduleInput,
} from '@/lib/types/hrWorkSchedules'

export interface HRWorkScheduleValidationResult {
  valid: boolean
  errors: Record<string, string>
}

const TIME_PATTERN = /^(?:[01]\d|2[0-3]):[0-5]\d$/

export function getCairoDateISO(date = new Date()): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Africa/Cairo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date)

  const values = Object.fromEntries(parts.map(part => [part.type, part.value]))
  return `${values.year}-${values.month}-${values.day}`
}

export function addDaysToISODate(dateISO: string, days: number): string {
  const [year, month, day] = dateISO.split('-').map(Number)
  const value = new Date(Date.UTC(year, month - 1, day + days))
  return value.toISOString().slice(0, 10)
}

export function getNextCairoDateISO(date = new Date()): string {
  return addDaysToISODate(getCairoDateISO(date), 1)
}

export function normalizeScheduleTime(value: string | null | undefined): string | null {
  if (!value) return null
  const trimmed = value.trim()
  const match = trimmed.match(/^(\d{2}):(\d{2})/)
  return match ? `${match[1]}:${match[2]}` : trimmed
}

export function timeToMinutes(value: string): number {
  const [hours, minutes] = value.split(':').map(Number)
  return hours * 60 + minutes
}

export function minutesToTime(value: number): string | null {
  if (!Number.isInteger(value) || value < 0 || value >= 24 * 60) return null
  const hours = Math.floor(value / 60).toString().padStart(2, '0')
  const minutes = (value % 60).toString().padStart(2, '0')
  return `${hours}:${minutes}`
}

export function addMinutesToTime(value: string, minutes: number): string | null {
  if (!TIME_PATTERN.test(value) || !Number.isInteger(minutes) || minutes <= 0) return null
  return minutesToTime(timeToMinutes(value) + minutes)
}

export function calculateScheduledMinutes(day: HREmployeeWorkScheduleDayInput): number {
  if (!day.is_working_day || !day.start_time || !day.end_time) return 0
  return timeToMinutes(day.end_time) - timeToMinutes(day.start_time)
}

export function getUniformWorkingDayMinutes(
  days: HREmployeeWorkScheduleDayInput[]
): number | null {
  const durations = days
    .filter(day => day.is_working_day)
    .map(calculateScheduledMinutes)
    .filter(minutes => minutes > 0)

  if (durations.length === 0) return null
  const first = durations[0]
  return durations.every(minutes => minutes === first) ? first : null
}

export function isFirstDayOfMonthISO(value: string): boolean {
  return /^\d{4}-\d{2}-01$/.test(value)
}

export function validateWorkScheduleDays(
  days: HREmployeeWorkScheduleDayInput[]
): HRWorkScheduleValidationResult {
  const errors: Record<string, string> = {}

  if (days.length !== 7) {
    errors.days = 'يجب إدخال الأيام السبعة كاملة'
    return { valid: false, errors }
  }

  const dayNames = days.map(day => day.day_of_week)
  const uniqueDays = new Set(dayNames)

  if (uniqueDays.size !== 7 || HR_WORK_WEEK_DAYS.some(day => !uniqueDays.has(day))) {
    errors.days = 'الأيام السبعة يجب أن تكون فريدة وكاملة'
  }

  if (!days.some(day => day.is_working_day)) {
    errors.days = 'يجب أن يحتوي الجدول على يوم عمل واحد على الأقل'
  }

  days.forEach(day => {
    const key = `days.${day.day_of_week}`

    if (!HR_WORK_WEEK_DAYS.includes(day.day_of_week as HRDayOfWeek)) {
      errors[key] = 'اسم اليوم غير صحيح'
      return
    }

    if (!day.is_working_day) {
      if (day.start_time || day.end_time) {
        errors[key] = 'يوم الإجازة لا يقبل وقت بداية أو نهاية'
      }
      return
    }

    if (!day.start_time || !day.end_time) {
      errors[key] = 'وقت البداية والنهاية مطلوبان في يوم العمل'
      return
    }

    if (!TIME_PATTERN.test(day.start_time) || !TIME_PATTERN.test(day.end_time)) {
      errors[key] = 'استخدم صيغة الوقت HH:MM'
      return
    }

    if (timeToMinutes(day.end_time) <= timeToMinutes(day.start_time)) {
      errors[key] = 'وقت الانصراف يجب أن يكون بعد وقت الحضور في اليوم نفسه'
    }
  })

  if (!Object.keys(errors).some(key => key.startsWith('days.'))) {
    const workingDurations = days
      .filter(day => day.is_working_day)
      .map(calculateScheduledMinutes)

    if (new Set(workingDurations).size > 1) {
      errors.days = 'يجب أن تكون مدة يوم العمل ثابتة داخل نفس نسخة الجدول'
    }
  }

  return { valid: Object.keys(errors).length === 0, errors }
}

export function validateEmployeeWorkSchedule(
  input: HREmployeeWorkScheduleInput,
  cairoToday = getCairoDateISO()
): HRWorkScheduleValidationResult {
  const errors: Record<string, string> = {}

  if (!input.employee_id) {
    errors.employee_id = 'الموظف مطلوب'
  }

  if (!input.effective_from) {
    errors.effective_from = 'تاريخ بدء التطبيق مطلوب'
  } else if (input.effective_from <= cairoToday) {
    errors.effective_from = 'تاريخ بدء التطبيق يجب أن يكون بعد اليوم بتوقيت القاهرة'
  }

  if ((input.notes?.trim().length ?? 0) > 500) {
    errors.notes = 'الملاحظات لا يمكن أن تتجاوز 500 حرف'
  }

  const daysResult = validateWorkScheduleDays(input.days)
  Object.assign(errors, daysResult.errors)

  return { valid: Object.keys(errors).length === 0, errors }
}
