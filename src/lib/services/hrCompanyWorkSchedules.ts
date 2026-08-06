import { supabase } from '@/lib/supabase/client'
import type { HRDayOfWeek } from '@/lib/types/hr'
import type { HRCompanyWorkScheduleVersion } from '@/lib/types/hrWorkSchedules'
import { normalizeScheduleTime } from '@/lib/validations/hrWorkSchedules'

export interface HRCompanySettingsAlignmentResult {
  success: boolean
  company_schedule_id: string
  effective_from: string
  settings: Record<string, string>
  company_history_consistent: boolean
  feature_enabled: boolean
}

function mapCompanySchedule(row: Record<string, unknown>): HRCompanyWorkScheduleVersion {
  const startTime = normalizeScheduleTime(row.start_time as string | null | undefined)
  const endTime = normalizeScheduleTime(row.end_time as string | null | undefined)
  const scheduledMinutes = Number(row.scheduled_minutes ?? 0)

  if (!startTime || !endTime || !Number.isFinite(scheduledMinutes) || scheduledMinutes <= 0) {
    throw new Error('نسخة جدول الشركة تحتوي على بيانات وقت غير صالحة')
  }

  return {
    id: row.id as string,
    effective_from: row.effective_from as string,
    effective_to: (row.effective_to as string | null) ?? null,
    status: row.status as HRCompanyWorkScheduleVersion['status'],
    start_time: startTime,
    end_time: endTime,
    work_hours_per_day: scheduledMinutes / 60,
    scheduled_minutes: scheduledMinutes,
    weekly_off_day: row.weekly_off_day as HRDayOfWeek,
    notes: (row.notes as string | null) ?? null,
    is_system_baseline: Boolean(row.is_system_baseline),
  }
}

export async function getCompanyWorkScheduleVersions(): Promise<HRCompanyWorkScheduleVersion[]> {
  const { data, error } = await supabase
    .from('hr_company_work_schedules')
    .select(`
      id,
      effective_from,
      effective_to,
      status,
      start_time,
      end_time,
      scheduled_minutes,
      weekly_off_day,
      notes,
      is_system_baseline
    `)
    .order('effective_from', { ascending: false })

  if (error) throw error
  return (data ?? []).map(row => mapCompanySchedule(row as unknown as Record<string, unknown>))
}

export async function alignLegacyCompanySettingsToCurrentVersion(): Promise<HRCompanySettingsAlignmentResult> {
  const { data, error } = await supabase.rpc('align_legacy_company_settings_to_current_version')
  if (error) throw error
  return data as unknown as HRCompanySettingsAlignmentResult
}
