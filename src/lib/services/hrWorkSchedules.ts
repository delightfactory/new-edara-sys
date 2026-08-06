import { supabase } from '@/lib/supabase/client'
import type { HRDayOfWeek } from '@/lib/types/hr'
import {
  HR_WORK_WEEK_DAYS,
  type HRCompanyWorkScheduleDefaults,
  type HRCompanyWorkScheduleVersion,
  type HRCompanyWorkScheduleVersionInput,
  type HREmployeeWorkSchedule,
  type HREmployeeWorkScheduleDay,
  type HREmployeeWorkScheduleInput,
  type HRSaveCompanyWorkScheduleResult,
  type HRSaveWorkScheduleResult,
  type HRUpdateFutureCompanyWorkScheduleResult,
  type HRUpdateFutureWorkScheduleResult,
  type HRWorkScheduleFeatureState,
} from '@/lib/types/hrWorkSchedules'
import {
  getCairoDateISO,
  normalizeScheduleTime,
  timeToMinutes,
  validateEmployeeWorkSchedule,
  validateWorkScheduleDays,
} from '@/lib/validations/hrWorkSchedules'

interface WorkScheduleAdminContextResponse {
  installed: boolean
  enabled: boolean
  company_defaults: {
    start_time: string
    end_time: string
    work_hours_per_day: number
    weekly_off_day: HRDayOfWeek
  }
}

const TIME_PATTERN = /^(?:[01]\d|2[0-3]):[0-5]\d$/

function isMissingContextRpc(error: { code?: string; message?: string } | null): boolean {
  if (!error) return false
  return error.code === 'PGRST202'
    || error.message?.includes('get_employee_work_schedule_admin_context') === true
}

async function getWorkScheduleAdminContext(): Promise<WorkScheduleAdminContextResponse | null> {
  const { data, error } = await supabase.rpc('get_employee_work_schedule_admin_context')

  if (error) {
    if (isMissingContextRpc(error)) return null
    throw error
  }

  return data as unknown as WorkScheduleAdminContextResponse
}

function sortDays(days: HREmployeeWorkScheduleDay[]): HREmployeeWorkScheduleDay[] {
  return [...days].sort(
    (a, b) => HR_WORK_WEEK_DAYS.indexOf(a.day_of_week) - HR_WORK_WEEK_DAYS.indexOf(b.day_of_week)
  )
}

function mapSchedule(row: Record<string, unknown>): HREmployeeWorkSchedule {
  const rawDays = Array.isArray(row.days) ? row.days : []
  const days = rawDays.map(raw => {
    const day = raw as Record<string, unknown>
    return {
      id: day.id as string | undefined,
      schedule_id: day.schedule_id as string | undefined,
      day_of_week: day.day_of_week as HRDayOfWeek,
      is_working_day: Boolean(day.is_working_day),
      start_time: normalizeScheduleTime(day.start_time as string | null | undefined),
      end_time: normalizeScheduleTime(day.end_time as string | null | undefined),
      scheduled_minutes: Number(day.scheduled_minutes ?? 0),
      created_at: day.created_at as string | undefined,
      updated_at: day.updated_at as string | undefined,
    } satisfies HREmployeeWorkScheduleDay
  })

  return {
    id: row.id as string,
    employee_id: row.employee_id as string,
    effective_from: row.effective_from as string,
    effective_to: (row.effective_to as string | null) ?? null,
    status: row.status as HREmployeeWorkSchedule['status'],
    notes: (row.notes as string | null) ?? null,
    activated_by: (row.activated_by as string | null) ?? null,
    activated_at: (row.activated_at as string | null) ?? null,
    retired_by: (row.retired_by as string | null) ?? null,
    retired_at: (row.retired_at as string | null) ?? null,
    created_by: (row.created_by as string | null) ?? null,
    created_at: row.created_at as string | undefined,
    updated_by: (row.updated_by as string | null) ?? null,
    updated_at: row.updated_at as string | undefined,
    days: sortDays(days),
  }
}

function mapCompanySchedule(row: Record<string, unknown>): HRCompanyWorkScheduleVersion {
  const startTime = normalizeScheduleTime(row.start_time as string | null | undefined)
  const endTime = normalizeScheduleTime(row.end_time as string | null | undefined)

  if (!startTime || !endTime) {
    throw new Error('نسخة جدول الشركة لا تحتوي على وقت بداية ونهاية صالحين')
  }

  const scheduledMinutes = Number(row.scheduled_minutes ?? 0)
  const workHours = Number(row.work_hours_per_day ?? scheduledMinutes / 60)

  if (!Number.isFinite(scheduledMinutes) || scheduledMinutes <= 0 || !Number.isFinite(workHours)) {
    throw new Error('مدة نسخة جدول الشركة غير صالحة')
  }

  return {
    id: row.id as string,
    effective_from: row.effective_from as string,
    effective_to: (row.effective_to as string | null) ?? null,
    status: row.status as HRCompanyWorkScheduleVersion['status'],
    start_time: startTime,
    end_time: endTime,
    work_hours_per_day: workHours,
    scheduled_minutes: scheduledMinutes,
    weekly_off_day: row.weekly_off_day as HRDayOfWeek,
    notes: (row.notes as string | null) ?? null,
    is_system_baseline: Boolean(row.is_system_baseline),
  }
}

function validateCompanyScheduleInput(input: HRCompanyWorkScheduleVersionInput): void {
  const startTime = normalizeScheduleTime(input.start_time)
  const endTime = normalizeScheduleTime(input.end_time)

  if (!input.effective_from || input.effective_from <= getCairoDateISO()) {
    throw new Error('تاريخ بدء جدول الشركة يجب أن يكون بعد اليوم بتوقيت القاهرة')
  }

  if (!startTime || !endTime || !TIME_PATTERN.test(startTime) || !TIME_PATTERN.test(endTime)) {
    throw new Error('مواعيد الشركة يجب أن تكون بصيغة HH:MM')
  }

  if (timeToMinutes(endTime) <= timeToMinutes(startTime)) {
    throw new Error('وقت نهاية دوام الشركة يجب أن يكون بعد وقت البداية')
  }

  if (!HR_WORK_WEEK_DAYS.includes(input.weekly_off_day)) {
    throw new Error('يوم الإجازة الأسبوعية للشركة غير صالح')
  }

  if ((input.notes?.trim().length ?? 0) > 500) {
    throw new Error('ملاحظات جدول الشركة لا يمكن أن تتجاوز 500 حرف')
  }
}

export async function getWorkScheduleFeatureState(): Promise<HRWorkScheduleFeatureState> {
  const context = await getWorkScheduleAdminContext()
  if (!context) return { installed: false, enabled: false }

  return {
    installed: context.installed === true,
    enabled: context.enabled === true,
  }
}

export async function getCompanyWorkScheduleDefaults(): Promise<HRCompanyWorkScheduleDefaults> {
  const context = await getWorkScheduleAdminContext()
  if (!context) {
    throw new Error('ميزة جداول العمل الفردية غير مركبة على قاعدة البيانات')
  }

  const defaults = context.company_defaults
  const startTime = normalizeScheduleTime(defaults.start_time)
  const endTime = normalizeScheduleTime(defaults.end_time)
  const workHours = Number(defaults.work_hours_per_day)
  const weeklyOff = defaults.weekly_off_day

  if (!startTime || !endTime || !Number.isFinite(workHours) || workHours <= 0) {
    throw new Error('إعدادات مواعيد الشركة غير مكتملة أو غير صالحة')
  }

  if (!weeklyOff || !HR_WORK_WEEK_DAYS.includes(weeklyOff)) {
    throw new Error('إعداد يوم الإجازة الأسبوعية للشركة غير صالح')
  }

  return {
    start_time: startTime,
    end_time: endTime,
    work_hours_per_day: workHours,
    weekly_off_day: weeklyOff,
  }
}

export async function getCompanyWorkScheduleForDate(
  targetDate: string
): Promise<HRCompanyWorkScheduleVersion> {
  const { data, error } = await supabase.rpc('get_company_work_schedule_for_date', {
    p_target_date: targetDate,
  })

  if (error) throw error
  return mapCompanySchedule(data as unknown as Record<string, unknown>)
}

export async function saveCompanyWorkScheduleVersion(
  input: HRCompanyWorkScheduleVersionInput
): Promise<HRSaveCompanyWorkScheduleResult> {
  validateCompanyScheduleInput(input)

  const { data, error } = await supabase.rpc('save_company_work_schedule_version', {
    p_effective_from: input.effective_from,
    p_start_time: normalizeScheduleTime(input.start_time),
    p_end_time: normalizeScheduleTime(input.end_time),
    p_weekly_off_day: input.weekly_off_day,
    p_notes: input.notes?.trim() || null,
  })

  if (error) throw error

  const result = data as unknown as HRSaveCompanyWorkScheduleResult
  return {
    ...result,
    schedule: mapCompanySchedule(result.schedule as unknown as Record<string, unknown>),
  }
}

export async function updateFutureCompanyWorkScheduleVersion(
  scheduleId: string,
  input: Omit<HRCompanyWorkScheduleVersionInput, 'effective_from'> & { effective_from: string }
): Promise<HRUpdateFutureCompanyWorkScheduleResult> {
  validateCompanyScheduleInput(input)

  const { data, error } = await supabase.rpc('update_future_company_work_schedule_version', {
    p_schedule_id: scheduleId,
    p_start_time: normalizeScheduleTime(input.start_time),
    p_end_time: normalizeScheduleTime(input.end_time),
    p_weekly_off_day: input.weekly_off_day,
    p_notes: input.notes?.trim() || null,
  })

  if (error) throw error

  const result = data as unknown as HRUpdateFutureCompanyWorkScheduleResult
  return {
    ...result,
    schedule: mapCompanySchedule(result.schedule as unknown as Record<string, unknown>),
  }
}

export async function getEmployeeWorkSchedules(
  employeeId: string
): Promise<HREmployeeWorkSchedule[]> {
  const { data, error } = await supabase
    .from('hr_employee_work_schedules')
    .select(`
      id,
      employee_id,
      effective_from,
      effective_to,
      status,
      notes,
      activated_by,
      activated_at,
      retired_by,
      retired_at,
      created_by,
      created_at,
      updated_by,
      updated_at,
      days:hr_employee_work_schedule_days(
        id,
        schedule_id,
        day_of_week,
        is_working_day,
        start_time,
        end_time,
        scheduled_minutes,
        created_at,
        updated_at
      )
    `)
    .eq('employee_id', employeeId)
    .order('effective_from', { ascending: false })

  if (error) throw error
  return (data ?? []).map(row => mapSchedule(row as unknown as Record<string, unknown>))
}

export async function saveEmployeeWorkSchedule(
  input: HREmployeeWorkScheduleInput
): Promise<HRSaveWorkScheduleResult> {
  const validation = validateEmployeeWorkSchedule(input)
  if (!validation.valid) {
    throw new Error(Object.values(validation.errors)[0] ?? 'بيانات جدول العمل غير صالحة')
  }

  const { data, error } = await supabase.rpc('save_employee_work_schedule', {
    p_employee_id: input.employee_id,
    p_effective_from: input.effective_from,
    p_days: input.days,
    p_notes: input.notes?.trim() || null,
  })

  if (error) throw error

  const result = data as unknown as HRSaveWorkScheduleResult
  return {
    ...result,
    schedule: mapSchedule(result.schedule as unknown as Record<string, unknown>),
  }
}

export async function updateFutureEmployeeWorkSchedule(
  scheduleId: string,
  days: HREmployeeWorkScheduleInput['days'],
  notes?: string | null
): Promise<HRUpdateFutureWorkScheduleResult> {
  const validation = validateWorkScheduleDays(days)
  if (!validation.valid) {
    throw new Error(Object.values(validation.errors)[0] ?? 'بيانات جدول العمل غير صالحة')
  }

  const { data, error } = await supabase.rpc('update_future_employee_work_schedule', {
    p_schedule_id: scheduleId,
    p_days: days,
    p_notes: notes?.trim() || null,
  })

  if (error) throw error

  const result = data as unknown as HRUpdateFutureWorkScheduleResult
  return {
    ...result,
    schedule: mapSchedule(result.schedule as unknown as Record<string, unknown>),
  }
}
