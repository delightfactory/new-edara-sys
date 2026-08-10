import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260810220126_employee_weekly_work_schedules.sql',
), 'utf8')
const hrService = readFileSync(resolve(process.cwd(), 'src/lib/services/hr.ts'), 'utf8')
const employeeForm = readFileSync(resolve(
  process.cwd(),
  'src/pages/hr/employees/EmployeeForm.tsx',
), 'utf8')

describe('employee weekly schedules migration contract', () => {
  it('keeps company settings as the fallback when no dated override applies', () => {
    expect(migration).toContain('effective_from')
    expect(migration).toContain('s.effective_from <= p_date')
    expect(migration).toContain("WHERE key = 'hr.work_start_time'")
    expect(migration).toContain("WHERE key = 'hr.work_end_time'")
    expect(migration).toContain("WHERE key = 'hr.weekly_off_day'")
  })

  it('only accepts future effective dates, preserves history and keeps one visible pending change', () => {
    expect(migration).toContain('p_effective_from < v_tomorrow')
    expect(migration).toContain('FOR UPDATE')
    expect(migration).toContain('effective_from >= v_tomorrow')
    expect(migration).not.toMatch(
      /DELETE FROM public\.hr_employee_work_schedules\s+WHERE employee_id = p_employee_id\s*;/,
    )
  })

  it('saves exactly seven days atomically and routes writes through the RPC', () => {
    expect(migration).toContain('jsonb_array_length(p_schedule) <> 7')
    expect(migration).toContain("COUNT(DISTINCT item->>'day_of_week')")
    expect(migration).toMatch(
      /REVOKE ALL ON public\.hr_employee_work_schedules\s+FROM anon, authenticated, service_role/,
    )
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.set_employee_weekly_schedule')
    expect(migration).toContain('FROM PUBLIC, anon, authenticated, service_role')
  })

  it('keeps historical/started snapshots immutable and safely refreshes untouched future placeholders', () => {
    expect(migration).toContain('scheduled_start_at TIMESTAMPTZ')
    expect(migration).toContain('scheduled_end_at TIMESTAMPTZ')
    expect(migration).toContain('scheduled_minutes INTEGER')
    expect(migration).toContain('trg_sync_attendance_day_schedule')
    expect(migration).toContain('refresh_future_attendance_schedule_snapshots')
    expect(migration).toContain('OLD.punch_in_time IS NULL AND OLD.punch_out_time IS NULL')
    expect(migration).toContain("pr.status IN ('approved', 'paid')")
    expect(migration).not.toContain('NEW.late_minutes :=')
    expect(migration).not.toContain('NEW.early_leave_minutes :=')
    expect(migration).not.toContain('NEW.overtime_minutes :=')
  })

  it('preserves GPS and manual calculation semantics while replacing only schedule assignments', () => {
    expect(migration).toContain("'record_attendance_gps'")
    expect(migration).toContain("'record_attendance_gps_v2'")
    expect(migration).toContain("'upsert_attendance_and_reprocess'")
    expect(migration).toContain('schedule assignment count changed')
    expect(migration).toContain('schedule assignments were not replaced')
  })

  it('uses employee cutoffs for absence, checkout, review alerts and absence notifications', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.mark_daily_absences')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.run_auto_checkout')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.scan_attendance_daily_review_alerts')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.notify_absent_employees')
    expect(migration).toContain("schedule := '*/15 * * * *'")
    expect(migration).toContain('ON CONFLICT (alert_key) DO NOTHING')
  })

  it('does not expose security-definer attendance operations to anonymous users', () => {
    expect(migration).toMatch(
      /REVOKE ALL ON FUNCTION public\.is_employee_work_day\(UUID, DATE\)[\s\S]*FROM PUBLIC, anon, authenticated, service_role/,
    )
    expect(migration).toMatch(
      /REVOKE ALL ON FUNCTION public\.mark_daily_absences\(DATE\)[\s\S]*GRANT EXECUTE ON FUNCTION public\.mark_daily_absences\(DATE\)[\s\S]*TO authenticated, service_role/,
    )
    expect(migration).toMatch(
      /REVOKE ALL ON FUNCTION public\.run_auto_checkout\(DATE\)[\s\S]*GRANT EXECUTE ON FUNCTION public\.run_auto_checkout\(DATE\)[\s\S]*TO authenticated, service_role/,
    )
    expect(migration).toMatch(
      /REVOKE ALL ON FUNCTION public\.notify_absent_employees\(\)[\s\S]*TO service_role/,
    )
  })

  it('keeps the early-leave notification trigger observable during auto checkout', () => {
    expect(migration).toMatch(
      /UPDATE public\.hr_attendance_days[\s\S]*early_leave_minutes = v_early_leave_minutes/,
    )
  })

  it('patches leave settlement, penalties and payroll and fails closed on schema drift', () => {
    expect(migration).toContain("pg_get_functiondef('public.settle_attendance_day_against_leave(uuid,boolean)'::regprocedure)")
    expect(migration).toContain("pg_get_functiondef('public.process_attendance_penalties(uuid)'::regprocedure)")
    expect(migration).toContain("pg_get_functiondef('public.calculate_employee_payroll(uuid,uuid)'::regprocedure)")
    expect(migration).toContain('settle_attendance_day_against_leave work-hours lookup was not found')
    expect(migration).toContain('process_attendance_penalties scheduled end lookup was not found')
    expect(migration).toContain('calculate_employee_payroll partial-month loops were not found')
    expect(migration).toContain('partial-month loop count changed')
    expect(migration).toContain('v_partial_matches <> 3')
  })

  it('preserves the production auto-checkout metric calculations exactly', () => {
    expect(migration).toContain('v_early_leave_minutes := 0;')
    expect(migration).toContain('v_overtime_minutes := 0;')
    expect(migration).toContain('IF v_auto_checkout_time < v_scheduled_end THEN')
    expect(migration).not.toContain('LEAST(24.00')
  })

  it('keeps rest-day attendance on the existing company-time calculation path', () => {
    expect(migration).toMatch(
      /IF NOT v_row\.is_working_day THEN[\s\S]*p_date \+ v_company_start[\s\S]*p_date \+ v_company_end[\s\S]*0/,
    )
  })

  it('keeps the service RPC names and payload keys aligned with the migration', () => {
    expect(hrService).toContain("supabase.rpc('get_employee_weekly_schedule_for_editor'")
    expect(hrService).toContain("supabase.rpc('set_employee_weekly_schedule'")
    expect(hrService).toContain('p_employee_id: employeeId')
    expect(hrService).toContain('p_schedule: payload')
    expect(hrService).toContain('p_effective_from: effectiveFrom')
  })

  it('loads real defaults before save and uses Cairo for the minimum effective date', () => {
    expect(employeeForm).toContain('getEmployeeWeeklySchedule(employee?.id)')
    expect(employeeForm).toContain("timeZone: 'Africa/Cairo'")
    expect(employeeForm).toContain('scheduleDirty')
    expect(employeeForm).toContain('scheduleLoadError')
    expect(employeeForm).toContain('setEmployeeWeeklySchedule(')
  })
})
