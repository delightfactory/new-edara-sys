import { describe, expect, it } from 'vitest'
import type { HREmployeeWorkScheduleDayInput } from '@/lib/types/hrWorkSchedules'
import {
  addMinutesToTime,
  calculateScheduledMinutes,
  getUniformWorkingDayMinutes,
  isFirstDayOfMonthISO,
  normalizeScheduleTime,
  validateEmployeeWorkSchedule,
  validateWorkScheduleDays,
} from '@/lib/validations/hrWorkSchedules'

const standardDays = (): HREmployeeWorkScheduleDayInput[] => [
  { day_of_week: 'saturday', is_working_day: true, start_time: '11:00', end_time: '19:00' },
  { day_of_week: 'sunday', is_working_day: true, start_time: '11:00', end_time: '19:00' },
  { day_of_week: 'monday', is_working_day: true, start_time: '11:00', end_time: '19:00' },
  { day_of_week: 'tuesday', is_working_day: true, start_time: '11:00', end_time: '19:00' },
  { day_of_week: 'wednesday', is_working_day: true, start_time: '11:00', end_time: '19:00' },
  { day_of_week: 'thursday', is_working_day: true, start_time: '11:00', end_time: '19:00' },
  { day_of_week: 'friday', is_working_day: false, start_time: null, end_time: null },
]

describe('employee work schedule validation', () => {
  it('accepts the current six-day company schedule', () => {
    expect(validateWorkScheduleDays(standardDays())).toEqual({ valid: true, errors: {} })
  })

  it('accepts Ahmed Neamatallah mixed weekly times without a separate part-time mode', () => {
    const days: HREmployeeWorkScheduleDayInput[] = [
      { day_of_week: 'saturday', is_working_day: true, start_time: '15:00', end_time: '21:00' },
      { day_of_week: 'sunday', is_working_day: true, start_time: '10:00', end_time: '16:00' },
      { day_of_week: 'monday', is_working_day: true, start_time: '15:00', end_time: '21:00' },
      { day_of_week: 'tuesday', is_working_day: true, start_time: '15:00', end_time: '21:00' },
      { day_of_week: 'wednesday', is_working_day: true, start_time: '10:00', end_time: '16:00' },
      { day_of_week: 'thursday', is_working_day: true, start_time: '10:00', end_time: '16:00' },
      { day_of_week: 'friday', is_working_day: false, start_time: null, end_time: null },
    ]

    const result = validateWorkScheduleDays(days)
    expect(result.valid).toBe(true)
    expect(days.filter(day => day.is_working_day).map(calculateScheduledMinutes)).toEqual([
      360, 360, 360, 360, 360, 360,
    ])
    expect(getUniformWorkingDayMinutes(days)).toBe(360)
  })

  it('accepts nine official working hours for sales', () => {
    const days = standardDays().map(day =>
      day.is_working_day ? { ...day, start_time: '09:00', end_time: '18:00' } : day
    )

    expect(validateWorkScheduleDays(days).valid).toBe(true)
    expect(calculateScheduledMinutes(days[0])).toBe(540)
    expect(getUniformWorkingDayMinutes(days)).toBe(540)
  })

  it('rejects mixed daily durations inside one schedule version', () => {
    const days = standardDays()
    days[0] = { ...days[0], start_time: '10:00', end_time: '16:00' }

    const result = validateWorkScheduleDays(days)
    expect(result.valid).toBe(false)
    expect(result.errors.days).toContain('مدة يوم العمل ثابتة')
    expect(getUniformWorkingDayMinutes(days)).toBeNull()
  })

  it('rejects a schedule where every day is off', () => {
    const days = standardDays().map(day => ({
      ...day,
      is_working_day: false,
      start_time: null,
      end_time: null,
    }))

    expect(validateWorkScheduleDays(days).errors.days).toContain('يوم عمل واحد')
  })

  it('rejects duplicate or missing weekdays', () => {
    const days = standardDays()
    days[6] = { ...days[6], day_of_week: 'thursday' }

    expect(validateWorkScheduleDays(days).errors.days).toContain('فريدة وكاملة')
  })

  it('rejects overnight or non-positive windows in v1', () => {
    const days = standardDays()
    days[0] = { ...days[0], start_time: '21:00', end_time: '03:00' }

    expect(validateWorkScheduleDays(days).errors['days.saturday']).toContain('بعد وقت الحضور')
  })

  it('rejects times on non-working days', () => {
    const days = standardDays()
    days[6] = { ...days[6], start_time: '11:00' }

    expect(validateWorkScheduleDays(days).errors['days.friday']).toContain('لا يقبل وقت')
  })

  it('requires a future Cairo effective date', () => {
    const today = '2026-08-05'
    const base = {
      employee_id: 'employee-1',
      days: standardDays(),
      notes: null,
    }

    expect(validateEmployeeWorkSchedule({ ...base, effective_from: today }, today).valid).toBe(false)
    expect(validateEmployeeWorkSchedule({ ...base, effective_from: '2026-08-06' }, today).valid).toBe(true)
  })

  it('recognizes month boundaries and preserves a requested daily duration', () => {
    expect(isFirstDayOfMonthISO('2026-09-01')).toBe(true)
    expect(isFirstDayOfMonthISO('2026-09-02')).toBe(false)
    expect(addMinutesToTime('10:00', 360)).toBe('16:00')
    expect(addMinutesToTime('15:00', 360)).toBe('21:00')
    expect(addMinutesToTime('20:00', 540)).toBeNull()
  })

  it('normalizes database and compact time values for the editor', () => {
    expect(normalizeScheduleTime('15:00:00')).toBe('15:00')
    expect(normalizeScheduleTime('09:30')).toBe('09:30')
    expect(normalizeScheduleTime('1100')).toBe('11:00')
    expect(normalizeScheduleTime('1930')).toBe('19:30')
    expect(normalizeScheduleTime(null)).toBeNull()
  })
})
