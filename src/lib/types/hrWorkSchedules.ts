import type { HRDayOfWeek } from '@/lib/types/hr'

export type HRWorkScheduleStatus = 'draft' | 'active' | 'retired'
export type HRCompanyWorkScheduleStatus = 'active' | 'retired'
export type HRWorkScheduleSource = 'employee' | 'company' | 'public_holiday'
export type HRWorkScheduleDayKind = 'work_day' | 'weekly_off' | 'public_holiday'

export const HR_WORK_WEEK_DAYS: readonly HRDayOfWeek[] = [
  'saturday',
  'sunday',
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
] as const

export const HR_WORK_WEEK_DAY_LABELS: Record<HRDayOfWeek, string> = {
  saturday: 'السبت',
  sunday: 'الأحد',
  monday: 'الاثنين',
  tuesday: 'الثلاثاء',
  wednesday: 'الأربعاء',
  thursday: 'الخميس',
  friday: 'الجمعة',
}

export interface HREmployeeWorkScheduleDay {
  id?: string
  schedule_id?: string
  day_of_week: HRDayOfWeek
  is_working_day: boolean
  start_time: string | null
  end_time: string | null
  scheduled_minutes: number
  created_at?: string
  updated_at?: string
}

export interface HREmployeeWorkSchedule {
  id: string
  employee_id: string
  effective_from: string
  effective_to: string | null
  status: HRWorkScheduleStatus
  notes: string | null
  activated_by?: string | null
  activated_at?: string | null
  retired_by?: string | null
  retired_at?: string | null
  created_by?: string | null
  created_at?: string
  updated_by?: string | null
  updated_at?: string
  days: HREmployeeWorkScheduleDay[]
}

export interface HREmployeeWorkScheduleDayInput {
  day_of_week: HRDayOfWeek
  is_working_day: boolean
  start_time: string | null
  end_time: string | null
}

export interface HREmployeeWorkScheduleInput {
  employee_id: string
  effective_from: string
  days: HREmployeeWorkScheduleDayInput[]
  notes?: string | null
}

export interface HRWorkScheduleFeatureState {
  installed: boolean
  enabled: boolean
}

export interface HRCompanyWorkScheduleDefaults {
  start_time: string
  end_time: string
  work_hours_per_day: number
  weekly_off_day: HRDayOfWeek
}

export interface HRCompanyWorkScheduleVersion extends HRCompanyWorkScheduleDefaults {
  id: string
  effective_from: string
  effective_to: string | null
  status: HRCompanyWorkScheduleStatus
  scheduled_minutes: number
  notes: string | null
  is_system_baseline: boolean
}

export interface HRCompanyWorkScheduleVersionInput {
  effective_from: string
  start_time: string
  end_time: string
  weekly_off_day: HRDayOfWeek
  notes?: string | null
}

export interface HRSaveWorkScheduleResult {
  success: boolean
  schedule: HREmployeeWorkSchedule
  previous_schedule_retired?: boolean
  feature_enabled: boolean
}

export interface HRUpdateFutureWorkScheduleResult {
  success: boolean
  schedule: HREmployeeWorkSchedule
  feature_enabled: boolean
}

export interface HRSaveCompanyWorkScheduleResult {
  success: boolean
  schedule: HRCompanyWorkScheduleVersion
  previous_schedule_id?: string | null
  feature_enabled: boolean
}

export interface HRUpdateFutureCompanyWorkScheduleResult {
  success: boolean
  schedule: HRCompanyWorkScheduleVersion
  feature_enabled: boolean
}
