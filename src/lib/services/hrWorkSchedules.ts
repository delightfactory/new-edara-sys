import { supabase } from '@/lib/supabase/client'
import type { HRDayOfWeek } from '@/lib/types/hr'
import {
  HR_WORK_WEEK_DAYS,
  type HRCompanyWorkScheduleDefaults,
  type HREmployeeWorkSchedule,
  type HREmployeeWorkScheduleDay,
  type HREmployeeWorkScheduleInput,
  type HRSaveWorkScheduleResult,
  type HRUpdateFutureWorkScheduleResult,
  type HRWorkScheduleFeatureState,
} from '@/lib/types/hrWorkSchedules'
import {
  normalizeScheduleTime,
  timeToMinutes,
  validateEmployeeWorkSchedule,
  validateWorkScheduleDays,
} from '@/lib/validations/hrWorkSchedules'

const FEATURE_SETTING_KEY = 'hr.employee_work_schedules_enabled'
const COMPANY_SETTING_KEYS = [
  'hr.work_start_time',
  'hr.work_end_time',
  'hr.work_hours_per_day',
  'hr.weekly_off_day',
] as const

const truthyValues = new Set(['true', '1', 'on', 'yes'])

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

export async function getWorkScheduleFeatureState(): Promise<HRWorkScheduleFeatureState> {
  const { data, error } = await supabase
    .from('company_settings')
    .select('key, value')
    .eq('key', FEATURE_SETTING_KEY)
    .maybeSingle()

  if (error) throw error

  if (!data) {
    return { installed: false, enabled: false }
  }

  return {
    installed: true,
    enabled: truthyValues.has(String(data.value).trim().toLowerCase()),
  }
}

export async function getCompanyWorkScheduleDefaults(): Promise<HRCompanyWorkScheduleDefaults> {
  const { data, error } = await supabase
    .from('company_settings')
    .select('key, value')
    .in('key', [...COMPANY_SETTING_KEYS])

  if (error) throw error

  const settings = new Map((data ?? []).map(item => [item.key, String(item.value)]))
  const startTime = normalizeScheduleTime(settings.get('hr.work_start_time'))
  const endTime = normalizeScheduleTime(settings.get('hr.work_end_time'))
  const workHours = Number(settings.get('hr.work_hours_per_day'))
  const weeklyOff = settings.get('hr.weekly_off_day')?.trim().toLowerCase() as HRDayOfWeek | undefined

  if (!startTime || !endTime || !Number.isFinite(workHours) || workHours <= 0) {
    throw new Error('إعدادات مواعيد الشركة غير مكتملة أو غير صالحة')
  }

  if (!weeklyOff || !HR_WORK_WEEK_DAYS.includes(weeklyOff)) {
    throw new Error('إعداد يوم الإجازة الأسبوعية للشركة غير صالح')
  }

  const windowMinutes = timeToMinutes(endTime) - timeToMinutes(startTime)
  if (windowMinutes <= 0 || windowMinutes !== workHours * 60) {
    throw new Error('عدد ساعات العمل في إعدادات الشركة لا يطابق وقت البداية والنهاية')
  }

  return {
    start_time: startTime,
    end_time: endTime,
    work_hours_per_day: workHours,
    weekly_off_day: weeklyOff,
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
