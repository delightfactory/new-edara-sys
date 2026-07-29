import { supabase } from '@/lib/supabase/client'

export interface VisitReportFilters {
  dateFrom: string
  dateTo: string
  employeeId?: string
  branchId?: string
  purposeType?: string
  visitStatus?: string
  recordingQuality?: string
  contactResult?: string
}

export interface VisitReportMetrics {
  planned: number
  completed: number
  field_recorded: number
  administrative: number
  effective_contacts: number
  survey_completed: number
  gps_passed: number
  gps_pending_review: number
  quality_exceptions: number
  open_visits: number
  average_duration_minutes: number | null
  opportunity_value: number
  sales_created?: number
  sales_expected?: number
  sales_lost?: number
  activation_followup?: number
  at_risk_visits?: number
  very_short_visits?: number
  unlinked_order_claims?: number
  actionable_visits?: number
}

export interface VisitReportBreakdown {
  label: string
  count: number
}

export interface VisitPurposeResult {
  purpose_type: string
  planned: number
  completed: number
  effective_contacts: number
}

export interface VisitEmployeeResult {
  employee_id: string
  employee_name: string
  planned: number
  completed: number
  field_recorded: number
  effective_contacts: number
  quality_exceptions: number
}

export interface VisitDailyResult {
  date: string
  planned: number
  completed: number
  effective_contacts: number
}

export interface VisitReportSummary {
  metrics: VisitReportMetrics
  contact_results: VisitReportBreakdown[]
  customer_states: VisitReportBreakdown[]
  sales_outcomes?: VisitReportBreakdown[]
  activation_outcomes?: VisitReportBreakdown[]
  daily_results?: VisitDailyResult[]
  purpose_results: VisitPurposeResult[]
  employee_results: VisitEmployeeResult[]
}

export interface VisitReportRow {
  visit_item_id: string
  plan_id: string
  plan_date: string
  plan_status: string
  branch_id: string | null
  branch_name: string | null
  employee_id: string
  employee_name: string
  sequence: number
  customer_id: string
  customer_code: string
  customer_name: string
  purpose_type: string | null
  purpose: string | null
  priority: string
  visit_status: string
  activity_id: string | null
  started_at: string | null
  completed_at: string | null
  duration_minutes: number | null
  gps_validation_status: string | null
  gps_review_status: string | null
  is_administrative_completion: boolean
  recording_quality: string
  response_count: number | null
  contact_result: string | null
  contact_person_name: string | null
  customer_state: string | null
  visit_summary: string | null
  sales_order_outcome: string | null
  sales_no_order_reason: string | null
  sales_opportunity_value: number | null
  activation_response: string | null
  followup_status: string | null
  has_core_survey: boolean
  business_outcome: string | null
  is_effective_contact: boolean
  needs_gps_review: boolean
  has_quality_exception: boolean
}

export interface VisitSurveyReportAnswer {
  plan_date: string
  branch_id: string | null
  branch_name: string | null
  employee_id: string
  employee_name: string
  visit_item_id: string
  plan_id: string
  customer_id: string
  customer_code: string
  customer_name: string
  purpose_type: string | null
  activity_id: string
  response_id: string
  template_code: string
  template_name: string
  template_version: number
  question_code: string
  question_text: string
  question_type: string
  answer_value: string | null
  answer_json: unknown
  created_at: string
}

function applyRowFilters(query: any, filters: VisitReportFilters) {
  let next = query
    .gte('plan_date', filters.dateFrom)
    .lte('plan_date', filters.dateTo)

  if (filters.employeeId) next = next.eq('employee_id', filters.employeeId)
  if (filters.branchId) next = next.eq('branch_id', filters.branchId)
  if (filters.purposeType) next = next.eq('purpose_type', filters.purposeType)
  if (filters.visitStatus) next = next.eq('visit_status', filters.visitStatus)
  if (filters.recordingQuality) next = next.eq('recording_quality', filters.recordingQuality)
  if (filters.contactResult) next = next.eq('contact_result', filters.contactResult)

  return next
}

function applySurveyFilters(query: any, filters: VisitReportFilters) {
  let next = query
    .gte('plan_date', filters.dateFrom)
    .lte('plan_date', filters.dateTo)

  if (filters.employeeId) next = next.eq('employee_id', filters.employeeId)
  if (filters.branchId) next = next.eq('branch_id', filters.branchId)
  if (filters.purposeType) next = next.eq('purpose_type', filters.purposeType)

  return next
}

export async function getVisitReportSummary(filters: VisitReportFilters): Promise<VisitReportSummary> {
  const { data, error } = await supabase.rpc('get_visit_report_summary', {
    p_date_from: filters.dateFrom,
    p_date_to: filters.dateTo,
    p_employee_id: filters.employeeId || null,
    p_branch_id: filters.branchId || null,
    p_purpose_type: filters.purposeType || null,
  })
  if (error) throw error
  return data as VisitReportSummary
}

export async function getVisitReportRows(
  filters: VisitReportFilters,
  options: { page?: number; pageSize?: number; exceptionsOnly?: boolean } = {},
) {
  const page = options.page ?? 1
  const pageSize = options.pageSize ?? 25
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  let query = supabase
    .from('v_visit_report_rows')
    .select('*', { count: 'exact' })

  query = applyRowFilters(query, filters)
  if (options.exceptionsOnly) query = query.eq('has_quality_exception', true)

  const { data, error, count } = await query
    .order('plan_date', { ascending: false })
    .order('sequence', { ascending: true })
    .range(from, to)

  if (error) throw error
  return {
    data: (data ?? []) as VisitReportRow[],
    count: count ?? 0,
    totalPages: Math.max(1, Math.ceil((count ?? 0) / pageSize)),
  }
}

export async function getVisitReportExportRows(filters: VisitReportFilters) {
  let query = supabase.from('v_visit_report_rows').select('*')
  query = applyRowFilters(query, filters)

  const { data, error } = await query
    .order('plan_date', { ascending: false })
    .order('sequence', { ascending: true })
    .limit(5000)

  if (error) throw error
  return (data ?? []) as VisitReportRow[]
}

export async function getVisitSurveyReportAnswers(filters: VisitReportFilters) {
  let query = supabase.from('v_visit_survey_report_answers').select('*')
  query = applySurveyFilters(query, filters)

  const { data, error } = await query
    .order('plan_date', { ascending: false })
    .order('created_at', { ascending: false })
    .limit(10000)

  if (error) throw error
  return (data ?? []) as VisitSurveyReportAnswer[]
}
